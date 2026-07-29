#!/usr/bin/env bash
# render-dashboard.sh — Terminal ASCII dashboard for chaos experiments
# Usage: watch -n 5 -c bash scripts/render-dashboard.sh
# Or:    while true; do clear; bash scripts/render-dashboard.sh; sleep 5; done

set -euo pipefail

OUTPUT_DIR="${OUTPUT_DIR:-./output}"
STATE_FILE="$OUTPUT_DIR/state.json"
MONITOR_FILE="$OUTPUT_DIR/monitoring/monitor-status.json"
RUNNER_FILE="$OUTPUT_DIR/checkpoints/step5-experiment.json"
METRICS_FILE="$OUTPUT_DIR/monitoring/step5-metrics.jsonl"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color
BOLD='\033[1m'

# Read state (snapshot to avoid partial reads; mktemp avoids predictable names)
if [[ -f "$STATE_FILE" ]]; then
    TMPF=$(mktemp "${TMPDIR:-/tmp}/render-state.XXXXXX")
    STATE=$(cp "$STATE_FILE" "$TMPF" 2>/dev/null && cat "$TMPF" || echo '{}')
    rm -f "$TMPF"
else
    STATE='{}'
fi

# Header
echo -e "${BOLD}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}║  🔬  Chaos Engineering Dashboard                            ║${NC}"
echo -e "${BOLD}║  $(date '+%Y-%m-%d %H:%M:%S %Z')                                      ║${NC}"
echo -e "${BOLD}╠══════════════════════════════════════════════════════════════╣${NC}"

# Progress
STEP=$(echo "$STATE" | jq -r '.workflow.current_step // 0')
STATUS=$(echo "$STATE" | jq -r '.workflow.status // "unknown"')
TOTAL=6
PCT=$((STEP * 100 / TOTAL))
FILLED=$((PCT / 5))

PROG=""
for ((i=1; i<=20; i++)); do
    if ((i <= FILLED)); then PROG+="█"; else PROG+="░"; fi
done

echo -e "║  ${BOLD}Progress:${NC} [${GREEN}${PROG}${NC}] ${PCT}%  Step ${STEP}/${TOTAL}  (${STATUS})"
echo -e "╠══════════════════════════════════════════════════════════════╣"

# Experiments table
echo -e "║  ${BOLD}#     Experiment                Status     Duration  Result${NC}"
echo -e "║  ─── ─────────────────────── ────────── ────────  ──────"

echo "$STATE" | jq -r '.experiments[]? | @json' 2>/dev/null | while read -r exp_json; do
    ID=$(echo "$exp_json" | jq -r '.id')
    NAME=$(echo "$exp_json" | jq -r '.name' | cut -c1-25)
    EXP_STATUS=$(echo "$exp_json" | jq -r '.status')
    ELAPSED=$(echo "$exp_json" | jq -r '.elapsed_seconds // "—"')
    RESULT=$(echo "$exp_json" | jq -r '.result // "—"')

    # Color status
    case "$EXP_STATUS" in
        completed) STATUS_FMT="${GREEN}✅ done${NC}" ;;
        running)   STATUS_FMT="${BLUE}🔄 run ${NC}" ;;
        failed)    STATUS_FMT="${RED}❌ fail${NC}" ;;
        queued)    STATUS_FMT="${YELLOW}⏳ wait${NC}" ;;
        *)         STATUS_FMT="$EXP_STATUS" ;;
    esac

    # Color result
    case "$RESULT" in
        PASSED) RESULT_FMT="${GREEN}PASS${NC}" ;;
        FAILED) RESULT_FMT="${RED}FAIL${NC}" ;;
        *)      RESULT_FMT="$RESULT" ;;
    esac

    printf "║  %-5s %-27s %b  %-8s  %b\n" "$ID" "$NAME" "$STATUS_FMT" "${ELAPSED}s" "$RESULT_FMT"
done

echo -e "╠══════════════════════════════════════════════════════════════╣"

# Monitor heartbeat
if [[ -f "$MONITOR_FILE" ]]; then
    LAST=$(jq -r '.last_collect // "—"' "$MONITOR_FILE" 2>/dev/null)
    SAMPLES=$(jq -r '.samples // 0' "$MONITOR_FILE" 2>/dev/null)
    EXP_ST=$(jq -r '.status // "—"' "$MONITOR_FILE" 2>/dev/null)
    echo -e "║  ${BOLD}Monitor:${NC} ✅ Active  samples=${SAMPLES}  last=${LAST}"
    echo -e "║  ${BOLD}FIS Status:${NC} ${EXP_ST}"
else
    echo -e "║  ${BOLD}Monitor:${NC} ${YELLOW}⚠️  Not running${NC}"
fi

# Latest metric snapshot
if [[ -f "$METRICS_FILE" ]]; then
    LAST_LINE=$(tail -1 "$METRICS_FILE" 2>/dev/null || echo '{}')
    METRIC_TS=$(echo "$LAST_LINE" | jq -r '.timestamp // "—"' 2>/dev/null)
    METRIC_COUNT=$(echo "$LAST_LINE" | jq '.metrics | length' 2>/dev/null || echo 0)
    echo -e "╠══════════════════════════════════════════════════════════════╣"
    echo -e "║  ${BOLD}Metrics:${NC} ${METRIC_COUNT} data points  at ${METRIC_TS}"

    # Show first 3 metrics with values
    echo "$LAST_LINE" | jq -r '.metrics[]? | "║    \(.Id): \(.Values[0] // "no data")"' 2>/dev/null | head -5
fi

# Runner status
if [[ -f "$RUNNER_FILE" ]]; then
    R_STATUS=$(jq -r '.status // "—"' "$RUNNER_FILE" 2>/dev/null)
    R_ID=$(jq -r '.experiment_id // "—"' "$RUNNER_FILE" 2>/dev/null)
    echo -e "╠══════════════════════════════════════════════════════════════╣"
    echo -e "║  ${BOLD}Runner:${NC} ${R_ID}  status=${R_STATUS}"
fi

echo -e "${BOLD}╚══════════════════════════════════════════════════════════════╝${NC}"
echo -e "  ${CYAN}Refresh: watch -n 5 -c bash scripts/render-dashboard.sh${NC}"
