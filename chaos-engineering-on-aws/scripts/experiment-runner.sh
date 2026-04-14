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
        --quiet)          QUIET=true;          shift ;;
        -h|--help)        usage ;;
        *)                echo "Unknown option: $1" >&2; usage ;;
    esac
done

[[ -z "$MODE" ]] && { echo "ERROR: --mode is required (fis|chaosmesh)" >&2; exit 1; }

mkdir -p "$OUTPUT_DIR" "$OUTPUT_DIR/checkpoints" "$OUTPUT_DIR/monitoring"
STATE_FILE="$OUTPUT_DIR/checkpoints/step5-experiment.json"
LOG_FILE="$OUTPUT_DIR/experiment-runner.log"

log() {
    local msg="[experiment-runner] $(date -u +%FT%TZ) $*"
    echo "$msg" >> "$LOG_FILE"
    $QUIET || echo "$msg" >&2
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

    # Extract experiment name and namespace from manifest
    local exp_name
    exp_name=$(grep -m1 'name:' "$MANIFEST" | awk '{print $2}' | tr -d '"' || echo "unknown")
    local exp_ns="${NAMESPACE:-default}"

    log "Applying Chaos Mesh manifest: $MANIFEST"
    kubectl apply -f "$MANIFEST" 2>&1 | tee -a "$LOG_FILE"

    # Detect CRD kind from manifest
    local kind
    kind=$(grep -m1 'kind:' "$MANIFEST" | awk '{print $2}' | tr -d '"' || echo "")

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
