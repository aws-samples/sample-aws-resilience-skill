#!/usr/bin/env bash
# monitor.sh — Chaos engineering experiment metric collection script
# Auto-generated and executed by chaos-engineering-on-aws Skill Step 5
# Usage: nohup ./monitor.sh &
#
# Variables to replace (filled in by Agent at generation time):
#   EXPERIMENT_ID  — FIS experiment ID
#   NAMESPACE      — CloudWatch metric namespace
#   METRIC_NAMES   — List of metrics to collect
#   DIMENSIONS     — Metric dimensions
#   REGION         — AWS region
#   OUTPUT_FILE    — Output file path
#   INTERVAL       — Collection interval (seconds)

set -euo pipefail

EXPERIMENT_ID="${EXPERIMENT_ID:?'EXPERIMENT_ID not set'}"
NAMESPACE="${NAMESPACE:?'NAMESPACE not set'}"
REGION="${REGION:?'REGION not set — pass AWS_DEFAULT_REGION or set REGION env var'}"
OUTPUT_FILE="${OUTPUT_FILE:-output/step5-metrics.jsonl}"
INTERVAL="${INTERVAL:-30}"

# Custom metrics support
CUSTOM_METRICS_FILE="${CUSTOM_METRICS_FILE:-}"

if [[ -n "$CUSTOM_METRICS_FILE" && -f "$CUSTOM_METRICS_FILE" ]]; then
  echo "[monitor] Loading custom metrics from $CUSTOM_METRICS_FILE" >&2
fi

# Ensure output directory exists
mkdir -p "$(dirname "$OUTPUT_FILE")"

echo "[monitor] Started at $(date -u +%FT%TZ), interval=${INTERVAL}s" >&2
echo "[monitor] Experiment: $EXPERIMENT_ID" >&2
echo "[monitor] Output: $OUTPUT_FILE" >&2

while true; do
    TIMESTAMP=$(date -u +%FT%TZ)

    # Check FIS experiment status
    EXP_STATUS=$(aws fis get-experiment \
        --id "$EXPERIMENT_ID" \
        --region "$REGION" \
        --query 'experiment.state.status' \
        --output text 2>/dev/null || echo "UNKNOWN")

    # Collect CloudWatch metrics
    END_TIME=$(date -u +%FT%TZ)
    START_TIME=$(date -u -d "-${INTERVAL} seconds" +%FT%TZ 2>/dev/null || date -u -v-${INTERVAL}S +%FT%TZ)

    # Agent fills in specific metric queries at generation time
    if [[ ! -f "metric-queries.json" ]]; then
        echo "{\"ts\":\"$TIMESTAMP\",\"type\":\"warning\",\"message\":\"metric-queries.json not found — skipping CloudWatch metric collection for this interval\"}" >> "$OUTPUT_FILE"
        METRICS_JSON='{"MetricDataResults":[]}'
    else
        METRICS_JSON=$(aws cloudwatch get-metric-data \
            --region "$REGION" \
            --start-time "$START_TIME" \
            --end-time "$END_TIME" \
            --metric-data-queries file://metric-queries.json \
            --output json 2>/dev/null || echo '{"MetricDataResults":[]}')
    fi

    # Write to JSONL
    jq -cn \
        --arg ts "$TIMESTAMP" \
        --arg status "$EXP_STATUS" \
        --argjson metrics "$METRICS_JSON" \
        '{timestamp: $ts, experiment_status: $status, metrics: $metrics.MetricDataResults}' \
        >> "$OUTPUT_FILE"

    # Collect custom metrics if configured
    if [[ -n "$CUSTOM_METRICS_FILE" && -f "$CUSTOM_METRICS_FILE" ]]; then
      while IFS='|' read -r ns mn dn dv st; do
        [[ "$ns" == "#"* || -z "$ns" ]] && continue
        CUSTOM_RESULT=$(aws cloudwatch get-metric-statistics \
          --namespace "$ns" \
          --metric-name "$mn" \
          --dimensions "Name=$dn,Value=$dv" \
          --statistics "$st" \
          --start-time "$START_TIME" \
          --end-time "$END_TIME" \
          --period "$INTERVAL" \
          --region "$REGION" \
          --output json 2>/dev/null || echo '{}')
        echo "{\"ts\":\"$TIMESTAMP\",\"type\":\"custom\",\"namespace\":\"$ns\",\"metric\":\"$mn\",\"data\":$CUSTOM_RESULT}" >> "$OUTPUT_FILE"
      done < "$CUSTOM_METRICS_FILE"
    fi

    echo "[monitor] $TIMESTAMP status=$EXP_STATUS" >&2

    # Exit if experiment ended
    case "$EXP_STATUS" in
        completed|failed|stopped|cancelled)
            echo "[monitor] Experiment $EXP_STATUS, stopping monitor." >&2
            break
            ;;
    esac

    sleep "$INTERVAL"
done

echo "[monitor] Finished at $(date -u +%FT%TZ)" >&2
