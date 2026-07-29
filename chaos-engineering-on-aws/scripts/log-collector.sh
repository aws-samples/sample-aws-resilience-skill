#!/usr/bin/env bash
# log-collector.sh — Collect Pod logs during chaos experiments
# Runs alongside monitor.sh for dual-channel observability (metrics + logs)
#
# Usage:
#   Live mode:  ./log-collector.sh --namespace {NAMESPACE} --duration 300
#   Post mode:  ./log-collector.sh --namespace {NAMESPACE} --mode post --since 2026-04-04T02:30:00Z

set -euo pipefail

# ---------------------------------------------------------------------------
# Defaults
# ---------------------------------------------------------------------------
NAMESPACE=""
SERVICES=""
DURATION=300
OUTPUT_DIR="./output"
MODE="live"
SINCE=""
SUMMARY_INTERVAL=30

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------
usage() {
    cat >&2 <<'EOF'
Usage: log-collector.sh --namespace NS [OPTIONS]

Options:
  --namespace NS            Target namespace (required)
  --services "svc1,svc2"    Comma-separated services (default: all deployments)
  --duration SECONDS        Collection duration (default: 300)
  --output-dir DIR          Output directory (default: ./output)
  --mode live|post          Collection mode (default: live)
  --since TIME              ISO8601 start time (required for post mode)
  -h, --help                Show this help
EOF
    exit 1
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --namespace)   NAMESPACE="$2";   shift 2 ;;
        --services)    SERVICES="$2";    shift 2 ;;
        --duration)    DURATION="$2";    shift 2 ;;
        --output-dir)  OUTPUT_DIR="$2";  shift 2 ;;
        --mode)        MODE="$2";        shift 2 ;;
        --since)       SINCE="$2";       shift 2 ;;
        -h|--help)     usage ;;
        *)             echo "[log-collector] Unknown option: $1" >&2; usage ;;
    esac
done

if [[ -z "$NAMESPACE" ]]; then
    echo "[log-collector] ERROR: --namespace is required" >&2
    usage
fi

if [[ "$MODE" != "live" && "$MODE" != "post" ]]; then
    echo "[log-collector] ERROR: --mode must be 'live' or 'post'" >&2
    exit 1
fi

if [[ "$MODE" == "post" && -z "$SINCE" ]]; then
    echo "[log-collector] ERROR: --since is required for post mode" >&2
    exit 1
fi

# ---------------------------------------------------------------------------
# Output setup
# ---------------------------------------------------------------------------
mkdir -p "$OUTPUT_DIR" "$OUTPUT_DIR/monitoring"
LOGS_FILE="$OUTPUT_DIR/monitoring/step5-logs.jsonl"
SUMMARY_FILE="$OUTPUT_DIR/monitoring/step5-log-summary.json"
INTERNAL_FILE=$(mktemp "${OUTPUT_DIR}/.log-collector-XXXXXX.jsonl")
: > "$LOGS_FILE"
: > "$INTERNAL_FILE"

# ---------------------------------------------------------------------------
# Discover services
# ---------------------------------------------------------------------------
discover_services() {
    if [[ -n "$SERVICES" ]]; then
        echo "$SERVICES" | tr ',' '\n'
    else
        kubectl get deployments -n "$NAMESPACE" -o jsonpath='{.items[*].metadata.name}' \
            | tr ' ' '\n'
    fi
}

SVC_LIST=()
while IFS= read -r svc; do
    [[ -n "$svc" ]] && SVC_LIST+=("$svc")
done < <(discover_services)

if [[ ${#SVC_LIST[@]} -eq 0 ]]; then
    echo "[log-collector] ERROR: no services found in namespace $NAMESPACE" >&2
    exit 1
fi

echo "[log-collector] Started at $(date -u +%FT%TZ), mode=$MODE, duration=${DURATION}s" >&2
echo "[log-collector] Namespace: $NAMESPACE" >&2
echo "[log-collector] Services: ${SVC_LIST[*]}" >&2
echo "[log-collector] Output: $LOGS_FILE" >&2

START_EPOCH=$(date +%s)

# ---------------------------------------------------------------------------
# Error classification
# Uses bash regex with nocasematch (bash 3.1+, works on macOS's bash 3.2) —
# no subprocess forks. The previous grep-based version forked up to 5
# processes per log line, which silently dropped logs on high-volume services.
# ---------------------------------------------------------------------------
classify_line() {
    local line="$1" result="other"
    shopt -s nocasematch
    if [[ "$line" =~ timeout|timed.out|deadline.exceeded|context.deadline ]]; then
        result="timeout"
    elif [[ "$line" =~ connection.refused|connection.reset|ECONNREFUSED|ECONNRESET|no.route.to.host|connect.failed ]]; then
        result="connection"
    elif [[ "$line" =~ HTTP\ 5[0-9][0-9]|status.?=.?5[0-9][0-9]|Internal.Server.Error|Bad.Gateway|Service.Unavailable|Gateway.Timeout ]]; then
        result="5xx"
    elif [[ "$line" =~ OOMKilled|out.of.memory|Cannot.allocate.memory|memory.cgroup|killed.process ]]; then
        result="oom"
    fi
    shopt -u nocasematch
    echo "$result"
}

detect_level() {
    local line="$1" result="INFO"
    shopt -s nocasematch
    if [[ "$line" =~ ERROR|FATAL|PANIC|CRITICAL ]]; then
        result="ERROR"
    elif [[ "$line" =~ WARN ]]; then
        result="WARN"
    fi
    shopt -u nocasematch
    echo "$result"
}

# ---------------------------------------------------------------------------
# Process a single log line and append JSONL (safe for subshells)
# ---------------------------------------------------------------------------
process_line() {
    local raw_line="$1"
    local pod_name="$2"
    local service="$3"

    # Extract timestamp if present (kubectl --timestamps prefixes ISO8601)
    local ts=""
    local msg="$raw_line"
    if [[ "$raw_line" =~ ^([0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}[^ ]*) ]]; then
        ts="${BASH_REMATCH[1]}"
        msg="${raw_line#"$ts" }"
    else
        ts=$(date -u +%FT%TZ)
    fi

    local level
    level=$(detect_level "$msg")

    local category
    category=$(classify_line "$msg")

    # Compute elapsed minute for timeline bucketing
    local now_epoch
    now_epoch=$(date +%s)
    local minute=$(( (now_epoch - START_EPOCH) / 60 ))

    # Write clean JSONL for user output
    jq -cn \
        --arg ts "$ts" \
        --arg pod "$pod_name" \
        --arg svc "$service" \
        --arg level "$level" \
        --arg cat "$category" \
        --arg msg "$msg" \
        '{timestamp:$ts, pod:$pod, service:$svc, level:$level, category:$cat, message:$msg}' \
        >> "$LOGS_FILE"

    # Write minute-tagged copy for summary timeline.
    # printf instead of jq: level/category/minute are generated values and ts
    # is sanitized below, so JSON-escaping via jq (one fork per line) is
    # unnecessary overhead here.
    local safe_ts="${ts//[\"\\\\]/}"
    printf '{"timestamp":"%s","level":"%s","category":"%s","_minute":%d}\n' \
        "$safe_ts" "$level" "$category" "$minute" >> "$INTERNAL_FILE"
}

# ---------------------------------------------------------------------------
# Background process management
# ---------------------------------------------------------------------------
BG_PIDS=()

cleanup() {
    echo "" >&2
    echo "[log-collector] Shutting down..." >&2
    
    # Step 1: Write summary FIRST (use whatever data we have now).
    # This ensures summary is written even if subsequent kill/wait hangs.
    write_summary
    
    # Step 2: Stop background kubectl processes with timeout
    for pid in "${BG_PIDS[@]}"; do
        kill "$pid" 2>/dev/null || true
    done
    local wait_start
    wait_start=$(date +%s)
    while true; do
        local any_alive=false
        for pid in "${BG_PIDS[@]}"; do
            kill -0 "$pid" 2>/dev/null && any_alive=true && break
        done
        [[ "$any_alive" == "false" ]] && break
        if (( $(date +%s) - wait_start > 5 )); then
            echo "[log-collector] Force killing remaining processes" >&2
            for pid in "${BG_PIDS[@]}"; do
                kill -9 "$pid" 2>/dev/null || true
            done
            break
        fi
        sleep 0.5
    done
    
    rm -f "$INTERNAL_FILE"
    echo "[log-collector] Finished at $(date -u +%FT%TZ)" >&2
    exit 0
}

trap cleanup SIGTERM SIGINT
# Also remove the temp file on abnormal exits (e.g. set -e aborts) where the
# SIGTERM/SIGINT cleanup path never runs.
trap 'rm -f "$INTERNAL_FILE"' EXIT

# ---------------------------------------------------------------------------
# Write summary JSON (built from the JSONL file)
# ---------------------------------------------------------------------------
write_summary() {
    # Build services JSON array
    local svc_json="[]"
    for svc in "${SVC_LIST[@]}"; do
        svc_json=$(echo "$svc_json" | jq -c --arg s "$svc" '. + [$s]')
    done

    local actual_duration=$(( $(date +%s) - START_EPOCH ))
    local max_minute=$(( actual_duration / 60 ))

    # Handle empty log file
    if [[ ! -s "$INTERNAL_FILE" ]]; then
        jq -n \
            --arg mode "$MODE" \
            --argjson dur "$DURATION" \
            --arg ns "$NAMESPACE" \
            --argjson svcs "$svc_json" \
            '{
                collection_mode: $mode,
                duration_seconds: $dur,
                namespace: $ns,
                services: $svcs,
                total_lines: 0,
                error_counts: {timeout:0, connection:0, "5xx":0, oom:0, other:0},
                total_errors: 0,
                error_timeline: [],
                first_error_at: null,
                recovery_detected_at: null
            }' > "$SUMMARY_FILE"
        echo "[log-collector] Summary written to $SUMMARY_FILE" >&2
        echo "[log-collector] total_lines=0 total_errors=0" >&2
        return
    fi

    # Build summary from the internal (minute-tagged) file
    jq -s --arg mode "$MODE" \
        --argjson dur "$DURATION" \
        --arg ns "$NAMESPACE" \
        --argjson svcs "$svc_json" \
        --argjson max_min "$max_minute" \
    '
    . as $all |
    length as $total |

    # Errors: lines with a recognized error category, or "other" with ERROR level
    [.[] | select(.category != "other" or .level == "ERROR")] as $errors |

    # Per-category counts
    {
        timeout:    [$errors[] | select(.category == "timeout")]    | length,
        connection: [$errors[] | select(.category == "connection")] | length,
        "5xx":      [$errors[] | select(.category == "5xx")]        | length,
        oom:        [$errors[] | select(.category == "oom")]        | length,
        other:      [$errors[] | select(.category == "other")]      | length
    } as $counts |

    ($counts | to_entries | map(.value) | add // 0) as $total_errors |

    # First error timestamp
    ([$errors[] | .timestamp] | sort | first // null) as $first_err |

    # Recovery: first non-error line after the last error
    (if ($errors | length) > 0 then
        ([$errors[] | .timestamp] | sort | last) as $last_err_ts |
        [$all[] | select(
            .timestamp > $last_err_ts and
            .category == "other" and
            .level != "ERROR"
        ) | .timestamp] | sort | first // null
    else null end) as $recovery |

    # Error timeline: group errors by _minute bucket
    ([range(0; $max_min + 1)] | map(. as $m | {
        minute: $m,
        timeout:    [$errors[] | select(._minute == $m and .category == "timeout")]    | length,
        connection: [$errors[] | select(._minute == $m and .category == "connection")] | length,
        "5xx":      [$errors[] | select(._minute == $m and .category == "5xx")]        | length,
        oom:        [$errors[] | select(._minute == $m and .category == "oom")]        | length
    })) as $timeline |

    {
        collection_mode: $mode,
        duration_seconds: $dur,
        namespace: $ns,
        services: $svcs,
        total_lines: $total,
        error_counts: $counts,
        total_errors: $total_errors,
        error_timeline: $timeline,
        first_error_at: $first_err,
        recovery_detected_at: $recovery
    }
    ' "$INTERNAL_FILE" > "$SUMMARY_FILE"

    local total_lines total_errors
    total_lines=$(jq '.total_lines' "$SUMMARY_FILE")
    total_errors=$(jq '.total_errors' "$SUMMARY_FILE")
    echo "[log-collector] Summary written to $SUMMARY_FILE" >&2
    echo "[log-collector] total_lines=$total_lines total_errors=$total_errors" >&2
}

# ---------------------------------------------------------------------------
# Print periodic status (reads counts from JSONL file)
# ---------------------------------------------------------------------------
print_status() {
    local elapsed=$1
    local counts
    counts=$(jq -s '
        [.[] | select(.category != "other" or .level == "ERROR")] |
        group_by(.category) | map({key: .[0].category, value: length}) | from_entries |
        {timeout: (.timeout // 0), connection: (.connection // 0),
         "5xx": (."5xx" // 0), oom: (.oom // 0), other: (.other // 0)}
    ' "$LOGS_FILE" 2>/dev/null || echo '{"timeout":0,"connection":0,"5xx":0,"oom":0,"other":0}')

    local t c x o oth
    t=$(echo "$counts" | jq -r '.timeout')
    c=$(echo "$counts" | jq -r '.connection')
    x=$(echo "$counts" | jq -r '."5xx"')
    o=$(echo "$counts" | jq -r '.oom')
    oth=$(echo "$counts" | jq -r '.other')

    echo "[log-collector] ${elapsed}s elapsed | errors: timeout=$t connection=$c 5xx=$x oom=$o other=$oth" >&2
}

# ---------------------------------------------------------------------------
# Live mode: stream logs in background with periodic pod re-discovery.
# Chaos experiments kill pods; their replacements get new names, so a
# one-time discovery at startup would miss all post-injection logs.
# ---------------------------------------------------------------------------
TRACKED_PODS=" "   # space-delimited set (portable to bash 3.2, no assoc arrays)

is_tracked() { [[ "$TRACKED_PODS" == *" $1 "* ]]; }

resolve_pods_for_service() {
    local svc="$1" pods selector
    # Try label app=$svc first
    pods=$(kubectl get pods -l "app=$svc" -n "$NAMESPACE" \
        -o jsonpath='{.items[*].metadata.name}' 2>/dev/null || true)
    # Fallback: resolve deployment's actual selector labels
    if [[ -z "$pods" ]]; then
        selector=$(kubectl get deployment "$svc" -n "$NAMESPACE" \
            -o jsonpath='{.spec.selector.matchLabels}' 2>/dev/null | \
            jq -r 'to_entries | map("\(.key)=\(.value)") | join(",")' 2>/dev/null || true)
        if [[ -n "$selector" ]]; then
            pods=$(kubectl get pods -l "$selector" -n "$NAMESPACE" \
                -o jsonpath='{.items[*].metadata.name}' 2>/dev/null || true)
        fi
    fi
    echo "$pods"
}

start_stream() {
    local pod="$1" svc="$2"
    (
        # Per-pod stream: pod name is known, no --prefix parsing needed
        kubectl logs -f --timestamps "$pod" -n "$NAMESPACE" 2>/dev/null \
        | while IFS= read -r line; do
            process_line "$line" "$pod" "$svc"
        done
    ) &
    BG_PIDS+=($!)
    echo "[log-collector] Streaming pod=$pod service=$svc (PID=$!)" >&2
}

discover_streams() {
    local svc pod pods
    for svc in "${SVC_LIST[@]}"; do
        pods=$(resolve_pods_for_service "$svc")
        if [[ -z "$pods" ]]; then
            echo "[log-collector] WARN: no pods found for service=$svc" >&2
            continue
        fi
        for pod in $pods; do
            is_tracked "$pod" && continue
            TRACKED_PODS="${TRACKED_PODS}${pod} "
            start_stream "$pod" "$svc"
        done
    done
}

run_live() {
    discover_streams

    # Wait for duration, printing status every SUMMARY_INTERVAL seconds.
    # Use "sleep N & wait $!" pattern so SIGTERM can interrupt the sleep.
    local elapsed=0
    while (( elapsed < DURATION )); do
        sleep "$SUMMARY_INTERVAL" &
        wait $! || true  # interrupted by SIGTERM → trap fires immediately
        elapsed=$(( $(date +%s) - START_EPOCH ))
        # Re-discover: pick up replacement pods created after chaos injection
        discover_streams
        print_status "$elapsed"
    done

    cleanup
}

# ---------------------------------------------------------------------------
# Post mode: collect logs since a timestamp.
# Iterates every pod of each service — `kubectl logs deployment/x` would only
# return logs from one arbitrary pod, losing data for multi-replica services.
# ---------------------------------------------------------------------------
run_post() {
    for svc in "${SVC_LIST[@]}"; do
        echo "[log-collector] Collecting post-experiment logs for service=$svc since=$SINCE" >&2

        local pods
        pods=$(resolve_pods_for_service "$svc")
        if [[ -z "$pods" ]]; then
            echo "[log-collector] WARN: no pods found for service=$svc" >&2
            continue
        fi

        local pod log_output
        for pod in $pods; do
            log_output=$(kubectl logs --since-time="$SINCE" --timestamps \
                "$pod" -n "$NAMESPACE" 2>/dev/null || true)

            if [[ -z "$log_output" ]]; then
                echo "[log-collector] WARN: no logs for pod=$pod service=$svc" >&2
                continue
            fi

            while IFS= read -r line; do
                [[ -z "$line" ]] && continue
                process_line "$line" "$pod" "$svc"
            done <<< "$log_output"
        done
    done

    write_summary
    rm -f "$INTERNAL_FILE"
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
case "$MODE" in
    live) run_live ;;
    post) run_post ;;
esac
