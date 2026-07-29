#!/usr/bin/env bash
# experiment-runner.sh — Orchestrate FIS/Chaos Mesh experiment execution with timeout
# Replaces agent-side polling to avoid context window exhaustion and hangs.
#
# Usage:
#   # FIS experiment:
#   ./experiment-runner.sh --mode fis --template-id <id> --region <region> \
#     --timeout 600 --poll-interval 15 --output-dir output/
#
#   # Chaos Mesh experiment:
#   ./experiment-runner.sh --mode chaosmesh --manifest chaos-experiment.yaml \
#     --namespace <ns> --timeout 600 --output-dir output/
#
#   # Monitor-only (experiment already running):
#   ./experiment-runner.sh --mode fis --experiment-id <id> --region <region> \
#     --timeout 600 --output-dir output/

set -euo pipefail

# ---------------------------------------------------------------------------
# Defaults
# ---------------------------------------------------------------------------
MODE=""                    # fis | chaosmesh
TEMPLATE_ID=""             # FIS template ID (to start new experiment)
EXPERIMENT_ID=""           # FIS experiment ID (to monitor existing)
MANIFEST=""                # Chaos Mesh YAML file
NAMESPACE=""               # K8s namespace for Chaos Mesh
REGION="${AWS_DEFAULT_REGION:-}"
TIMEOUT=600                # Max wait time in seconds (default: 10 min)
POLL_INTERVAL=15           # Seconds between status checks
OUTPUT_DIR="./output"
STATE_EXP_ID=""            # Custom experiment ID in state.json (e.g., EXP-001)
ONE_SHOT=false             # One-shot injection mode (pod-kill): complete on AllInjected + Pods Ready
POD_LABEL=""               # Pod label selector for --one-shot completion check
DEPLOYMENT=""              # Deployment name for --one-shot replica count (optional)
QUIET=false

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------
usage() {
    cat >&2 <<'EOF'
Usage: experiment-runner.sh --mode fis|chaosmesh [OPTIONS]

FIS Options:
  --template-id ID       FIS template ID (starts new experiment)
  --experiment-id ID     Existing FIS experiment ID (monitor only)
  --region REGION        AWS region

Chaos Mesh Options:
  --manifest FILE        Chaos Mesh YAML manifest
  --namespace NS         K8s namespace

Common Options:
  --state-exp-id ID      Experiment ID in state.json for dashboard/recovery updates
  --one-shot             One-shot injection mode (pod-kill, pod-failure with fixed count).
                         Completes when AllInjected=True AND target pods are Ready.
  --pod-label LABEL      Pod label selector for --one-shot completion check (e.g. "app=petsite")
  --deployment NAME      Deployment name for --one-shot replica count (e.g. "petsite-deployment").
                         If omitted, auto-discovers deployment by matching spec.selector.matchLabels.
  --timeout SECONDS      Max wait time (default: 600)
  --poll-interval SECS   Poll interval (default: 15)
  --output-dir DIR       Output directory (default: ./output)
  --quiet                Minimal output (for background use)
  -h, --help             Show this help
EOF
    exit 1
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --mode)           MODE="$2";           shift 2 ;;
        --template-id)    TEMPLATE_ID="$2";    shift 2 ;;
        --experiment-id)  EXPERIMENT_ID="$2";  shift 2 ;;
        --manifest)       MANIFEST="$2";       shift 2 ;;
        --namespace)      NAMESPACE="$2";      shift 2 ;;
        --region)         REGION="$2";         shift 2 ;;
        --timeout)        TIMEOUT="$2";        shift 2 ;;
        --poll-interval)  POLL_INTERVAL="$2";  shift 2 ;;
        --output-dir)     OUTPUT_DIR="$2";     shift 2 ;;
        --state-exp-id)   STATE_EXP_ID="$2";  shift 2 ;;
        --one-shot)       ONE_SHOT=true;       shift ;;
        --pod-label)      POD_LABEL="$2";      shift 2 ;;
        --deployment)     DEPLOYMENT="$2";     shift 2 ;;
        --quiet)          QUIET=true;          shift ;;
        -h|--help)        usage ;;
        *)                echo "Unknown option: $1" >&2; usage ;;
    esac
done

[[ -z "$MODE" ]] && { echo "ERROR: --mode is required (fis|chaosmesh)" >&2; exit 1; }

# --one-shot silently degrades to waiting for AllRecovered (i.e. until timeout
# for fixed-count pod-kill) without --pod-label, so fail fast instead.
if [[ "$ONE_SHOT" == "true" && -z "$POD_LABEL" ]]; then
    echo "ERROR: --one-shot requires --pod-label (e.g. --pod-label app=petsite)" >&2
    exit 1
fi

mkdir -p "$OUTPUT_DIR" "$OUTPUT_DIR/checkpoints" "$OUTPUT_DIR/monitoring"
STATE_FILE="$OUTPUT_DIR/checkpoints/step5-experiment.json"
LOG_FILE="$OUTPUT_DIR/experiment-runner.log"

log() {
    local msg="[experiment-runner] $(date -u +%FT%TZ) $*"
    echo "$msg" >> "$LOG_FILE"
    $QUIET || echo "$msg" >&2
}

# ---------------------------------------------------------------------------
# State management (state.json v2 — shared with monitor.sh via flock)
# ---------------------------------------------------------------------------
STATE_JSON="$OUTPUT_DIR/state.json"

# flock(1) is unavailable on macOS; fall back to a mkdir-based spinlock.
HAVE_FLOCK=false
command -v flock >/dev/null 2>&1 && HAVE_FLOCK=true

# jq filter: numeric-looking values are stored as numbers, others as strings
JQ_SET_FIELD='(.experiments[]? | select(.id == $id)) |= . + {($f): ($v | tonumber? // $v)}'

_state_jq_update() {
    local exp_id="$1" field="$2" value="$3"
    jq --arg id "$exp_id" --arg f "$field" --arg v "$value" \
        "$JQ_SET_FIELD" \
        "$STATE_JSON" > "$STATE_JSON.tmp" \
        && mv "$STATE_JSON.tmp" "$STATE_JSON"
}

update_state() {
    local exp_id="$1" field="$2" value="$3"
    [[ ! -f "$STATE_JSON" ]] && return 0
    if $HAVE_FLOCK; then
        (
            flock -w 5 200 || { log "WARN: state lock timeout"; exit 1; }
            _state_jq_update "$exp_id" "$field" "$value"
        ) 200>"$STATE_JSON.lock"
    else
        # mkdir is atomic — poor man's lock with ~5s timeout
        local tries=0
        until mkdir "$STATE_JSON.lockdir" 2>/dev/null; do
            ((tries++))
            if (( tries >= 50 )); then
                log "WARN: state lock timeout (mkdir fallback)"
                return 1
            fi
            sleep 0.1
        done
        _state_jq_update "$exp_id" "$field" "$value"
        rmdir "$STATE_JSON.lockdir" 2>/dev/null || true
    fi
}

# ---------------------------------------------------------------------------
# FIS Mode
# ---------------------------------------------------------------------------
run_fis() {
    [[ -z "$REGION" ]] && { echo "ERROR: --region is required for FIS mode" >&2; exit 1; }

    # Start new experiment if template-id provided
    if [[ -n "$TEMPLATE_ID" && -z "$EXPERIMENT_ID" ]]; then
        log "Starting FIS experiment from template: $TEMPLATE_ID"
        local start_result
        start_result=$(aws fis start-experiment \
            --experiment-template-id "$TEMPLATE_ID" \
            --region "$REGION" \
            --output json 2>&1)

        EXPERIMENT_ID=$(echo "$start_result" | jq -r '.experiment.id // empty' 2>/dev/null || true)
        if [[ -z "$EXPERIMENT_ID" ]]; then
            log "ERROR: Failed to start experiment"
            echo "$start_result" >> "$LOG_FILE"
            jq -n --arg err "$start_result" '{status:"ERROR",message:"Failed to start experiment",detail:$err}' > "$STATE_FILE"
            exit 1
        fi
        log "Experiment started: $EXPERIMENT_ID"

        # Save experiment ID for other scripts (monitor.sh)
        echo "$EXPERIMENT_ID" > "$OUTPUT_DIR/monitoring/experiment_id.txt"

        # Quick initial check — catch immediate failures (e.g., stop condition block)
        sleep 3
        local init_status
        init_status=$(aws fis get-experiment --id "$EXPERIMENT_ID" --region "$REGION" \
            --query 'experiment.state.status' --output text 2>/dev/null || echo "UNKNOWN")
        if [[ "$init_status" == "failed" || "$init_status" == "stopped" ]]; then
            local init_reason
            init_reason=$(aws fis get-experiment --id "$EXPERIMENT_ID" --region "$REGION" \
                --query 'experiment.state.reason' --output text 2>/dev/null || echo "")
            log "IMMEDIATE FAILURE: $init_status — $init_reason"
            jq -n --arg id "$EXPERIMENT_ID" --arg status "$init_status" \
                --arg reason "$init_reason" \
                '{experiment_id:$id, status:$status, reason:$reason, elapsed_seconds:3, immediate_failure:true}' \
                > "$STATE_FILE"
            [[ -n "$STATE_EXP_ID" ]] && {
                update_state "$STATE_EXP_ID" "status" "$init_status"
                update_state "$STATE_EXP_ID" "result" "FAILED"
            }
            exit 1
        fi
    fi

    [[ -z "$EXPERIMENT_ID" ]] && { echo "ERROR: --template-id or --experiment-id required" >&2; exit 1; }

    # Poll loop with timeout
    local start_epoch
    start_epoch=$(date +%s)
    local last_status="UNKNOWN"

    while true; do
        local elapsed=$(( $(date +%s) - start_epoch ))

        # Timeout check
        if (( elapsed >= TIMEOUT )); then
            log "TIMEOUT after ${elapsed}s — stopping experiment"
            aws fis stop-experiment --id "$EXPERIMENT_ID" --region "$REGION" 2>/dev/null || true
            jq -n \
                --arg id "$EXPERIMENT_ID" \
                --arg status "TIMEOUT" \
                --argjson elapsed "$elapsed" \
                --argjson timeout "$TIMEOUT" \
                '{experiment_id:$id, status:$status, elapsed_seconds:$elapsed, timeout_seconds:$timeout, message:"Experiment stopped due to timeout"}' \
                > "$STATE_FILE"
            [[ -n "$STATE_EXP_ID" ]] && {
                update_state "$STATE_EXP_ID" "status" "timeout"
                update_state "$STATE_EXP_ID" "result" "TIMEOUT"
            }
            log "State written to $STATE_FILE"
            exit 2
        fi

        # Get experiment status
        local exp_json
        exp_json=$(aws fis get-experiment \
            --id "$EXPERIMENT_ID" \
            --region "$REGION" \
            --output json 2>/dev/null || echo '{}')

        local status
        status=$(echo "$exp_json" | jq -r '.experiment.state.status // "UNKNOWN"')
        local reason
        reason=$(echo "$exp_json" | jq -r '.experiment.state.reason // ""')

        if [[ "$status" != "$last_status" ]]; then
            log "Status: $status (was: $last_status) ${reason:+reason=$reason}"
            last_status="$status"
        else
            log "Status: $status (${elapsed}s elapsed)"
        fi

        # Terminal states
        case "$status" in
            completed)
                log "Experiment COMPLETED successfully"
                jq -n \
                    --arg id "$EXPERIMENT_ID" \
                    --arg status "completed" \
                    --argjson elapsed "$elapsed" \
                    --arg end "$(date -u +%FT%TZ)" \
                    '{experiment_id:$id, status:$status, elapsed_seconds:$elapsed, ended_at:$end}' \
                    > "$STATE_FILE"
                [[ -n "$STATE_EXP_ID" ]] && {
                    update_state "$STATE_EXP_ID" "status" "completed"
                    update_state "$STATE_EXP_ID" "elapsed_seconds" "$elapsed"
                }
                exit 0
                ;;
            failed)
                log "Experiment FAILED: $reason"
                jq -n \
                    --arg id "$EXPERIMENT_ID" \
                    --arg status "failed" \
                    --arg reason "$reason" \
                    --argjson elapsed "$elapsed" \
                    '{experiment_id:$id, status:$status, reason:$reason, elapsed_seconds:$elapsed}' \
                    > "$STATE_FILE"
                [[ -n "$STATE_EXP_ID" ]] && {
                    update_state "$STATE_EXP_ID" "status" "failed"
                    update_state "$STATE_EXP_ID" "result" "FAILED"
                }
                exit 1
                ;;
            stopped|cancelled)
                log "Experiment $status: $reason"
                jq -n \
                    --arg id "$EXPERIMENT_ID" \
                    --arg status "$status" \
                    --arg reason "$reason" \
                    --argjson elapsed "$elapsed" \
                    '{experiment_id:$id, status:$status, reason:$reason, elapsed_seconds:$elapsed}' \
                    > "$STATE_FILE"
                [[ -n "$STATE_EXP_ID" ]] && {
                    update_state "$STATE_EXP_ID" "status" "$status"
                    update_state "$STATE_EXP_ID" "result" "ABORTED"
                }
                exit 1
                ;;
        esac

        sleep "$POLL_INTERVAL"
    done
}

# ---------------------------------------------------------------------------
# Chaos Mesh Mode
# ---------------------------------------------------------------------------
run_chaosmesh() {
    [[ -z "$MANIFEST" ]] && { echo "ERROR: --manifest is required for chaosmesh mode" >&2; exit 1; }
    [[ ! -f "$MANIFEST" ]] && { echo "ERROR: Manifest not found: $MANIFEST" >&2; exit 1; }

    local exp_ns="${NAMESPACE:-default}"

    log "Applying Chaos Mesh manifest: $MANIFEST"
    # `-o name` returns "<kind>.<group>/<name>" — more reliable than grepping
    # the YAML (metadata.name is not always the first `name:` in the file).
    local apply_out
    if ! apply_out=$(kubectl apply -f "$MANIFEST" -o name 2>&1); then
        log "ERROR: kubectl apply failed: $apply_out"
        jq -n --arg err "$apply_out" \
            '{status:"ERROR", message:"kubectl apply failed", detail:$err}' > "$STATE_FILE"
        [[ -n "$STATE_EXP_ID" ]] && {
            update_state "$STATE_EXP_ID" "status" "failed"
            update_state "$STATE_EXP_ID" "result" "FAILED"
        }
        exit 1
    fi
    echo "$apply_out" >> "$LOG_FILE"

    # apply_out example: "podchaos.chaos-mesh.org/pod-kill-test"
    local kind exp_name
    kind="${apply_out%%/*}"      # full resource name incl. group works with kubectl get
    exp_name="${apply_out##*/}"
    log "Applied: kind=$kind name=$exp_name ns=$exp_ns"

    local start_epoch
    start_epoch=$(date +%s)

    while true; do
        local elapsed=$(( $(date +%s) - start_epoch ))

        # Timeout check
        if (( elapsed >= TIMEOUT )); then
            log "TIMEOUT after ${elapsed}s — deleting experiment"
            kubectl delete -f "$MANIFEST" 2>/dev/null || true
            jq -n \
                --arg name "$exp_name" \
                --arg status "TIMEOUT" \
                --argjson elapsed "$elapsed" \
                '{experiment_name:$name, status:$status, elapsed_seconds:$elapsed, message:"Experiment deleted due to timeout"}' \
                > "$STATE_FILE"
            [[ -n "$STATE_EXP_ID" ]] && {
                update_state "$STATE_EXP_ID" "status" "timeout"
                update_state "$STATE_EXP_ID" "result" "TIMEOUT"
            }
            exit 2
        fi

        # Check Chaos Mesh experiment status
        local cm_status
        if [[ -n "$kind" ]]; then
            # Check if CR still exists (may have been deleted during abort)
            if ! kubectl get "$kind" "$exp_name" -n "$exp_ns" &>/dev/null; then
                log "Experiment CR not found — likely deleted or cleaned up"
                jq -n \
                    --arg name "$exp_name" \
                    --arg status "ABORTED" \
                    --argjson elapsed "$elapsed" \
                    '{experiment_name:$name, status:$status, elapsed_seconds:$elapsed, message:"Experiment CR not found (deleted or cleaned up)"}' \
                    > "$STATE_FILE"
                [[ -n "$STATE_EXP_ID" ]] && {
                    update_state "$STATE_EXP_ID" "status" "aborted"
                    update_state "$STATE_EXP_ID" "result" "ABORTED"
                }
                log "State written to $STATE_FILE"
                exit 1
            fi
            cm_status=$(kubectl get "$kind" "$exp_name" -n "$exp_ns" \
                -o jsonpath='{.status.conditions[?(@.type=="AllRecovered")].status}' 2>/dev/null || echo "")
        else
            cm_status=""
        fi

        local phase
        phase=$(kubectl get "$kind" "$exp_name" -n "$exp_ns" \
            -o jsonpath='{.status.conditions[?(@.type=="AllInjected")].status}' 2>/dev/null || echo "Unknown")

        log "Phase: injected=$phase recovered=${cm_status:-pending} (${elapsed}s elapsed)"

        # One-shot completion: AllInjected=True + target pods are Ready
        if [[ "$ONE_SHOT" == "true" && "$phase" == "True" && -n "$POD_LABEL" ]]; then
            local ready_pods=0 desired_pods=0
            # Count Ready pods by label
            ready_pods=$(kubectl get pods -n "$exp_ns" -l "$POD_LABEL" \
                --field-selector status.phase=Running \
                -o jsonpath='{range .items[*]}{.status.conditions[?(@.type=="Ready")].status}{"\n"}{end}' \
                2>/dev/null | grep -c "True" || echo "0")
            # Get desired replicas: use --deployment if given, else find by selector
            if [[ -n "$DEPLOYMENT" ]]; then
                desired_pods=$(kubectl get deployment "$DEPLOYMENT" -n "$exp_ns" \
                    -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "0")
            else
                # Fallback: find deployment whose selector matches POD_LABEL
                local lbl_key lbl_val
                lbl_key="${POD_LABEL%%=*}"
                lbl_val="${POD_LABEL#*=}"
                desired_pods=$(kubectl get deployments -n "$exp_ns" -o json 2>/dev/null \
                    | jq -r --arg k "$lbl_key" --arg v "$lbl_val" \
                      '.items[] | select(.spec.selector.matchLabels[$k]==$v) | .spec.replicas' \
                    2>/dev/null | head -1 || echo "0")
            fi
            # Sanitize to integer
            ready_pods=$((ready_pods + 0))
            desired_pods=$((desired_pods + 0))
            if (( ready_pods >= desired_pods && desired_pods > 0 )); then
                log "One-shot COMPLETED: AllInjected=True + $ready_pods/$desired_pods pods Ready"
                jq -n \
                    --arg name "$exp_name" \
                    --arg status "completed" \
                    --argjson elapsed "$elapsed" \
                    --arg end "$(date -u +%FT%TZ)" \
                    '{experiment_name:$name, status:$status, elapsed_seconds:$elapsed, ended_at:$end, one_shot:true}' \
                    > "$STATE_FILE"
                [[ -n "$STATE_EXP_ID" ]] && {
                    update_state "$STATE_EXP_ID" "status" "completed"
                    update_state "$STATE_EXP_ID" "elapsed_seconds" "$elapsed"
                }
                # Clean up CR
                kubectl delete "$kind" "$exp_name" -n "$exp_ns" 2>/dev/null || true
                exit 0
            fi
        fi

        # Chaos Mesh experiment completed when AllRecovered=True
        if [[ "$cm_status" == "True" ]]; then
            log "Experiment COMPLETED (AllRecovered)"
            jq -n \
                --arg name "$exp_name" \
                --arg status "completed" \
                --argjson elapsed "$elapsed" \
                --arg end "$(date -u +%FT%TZ)" \
                '{experiment_name:$name, status:$status, elapsed_seconds:$elapsed, ended_at:$end}' \
                > "$STATE_FILE"
            [[ -n "$STATE_EXP_ID" ]] && {
                update_state "$STATE_EXP_ID" "status" "completed"
                update_state "$STATE_EXP_ID" "elapsed_seconds" "$elapsed"
            }
            exit 0
        fi

        sleep "$POLL_INTERVAL"
    done
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
log "Starting experiment-runner mode=$MODE timeout=${TIMEOUT}s poll=${POLL_INTERVAL}s"

case "$MODE" in
    fis)       run_fis ;;
    chaosmesh) run_chaosmesh ;;
    *)         echo "ERROR: Unknown mode: $MODE (use fis|chaosmesh)" >&2; exit 1 ;;
esac
