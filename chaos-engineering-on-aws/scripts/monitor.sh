#!/usr/bin/env bash
# monitor.sh — 混沌工程实验指标采集脚本
# 由 chaos-engineering-on-aws Skill Step 5 自动生成并执行
# 用法：nohup ./monitor.sh &
#
# 需要替换的变量（Agent 生成时填入）：
#   EXPERIMENT_ID  — FIS 实验 ID
#   NAMESPACE      — CloudWatch 指标命名空间
#   METRIC_NAMES   — 要采集的指标名列表
#   DIMENSIONS     — 指标维度
#   REGION         — AWS 区域
#   OUTPUT_FILE    — 输出文件路径
#   INTERVAL       — 采集间隔（秒）

set -euo pipefail

EXPERIMENT_ID="${EXPERIMENT_ID:?'EXPERIMENT_ID not set'}"
NAMESPACE="${NAMESPACE:?'NAMESPACE not set'}"
REGION="${REGION:-ap-northeast-1}"
OUTPUT_FILE="${OUTPUT_FILE:-output/step5-metrics.jsonl}"
INTERVAL="${INTERVAL:-30}"

# 确保输出目录存在
mkdir -p "$(dirname "$OUTPUT_FILE")"

echo "[monitor] Started at $(date -u +%FT%TZ), interval=${INTERVAL}s" >&2
echo "[monitor] Experiment: $EXPERIMENT_ID" >&2
echo "[monitor] Output: $OUTPUT_FILE" >&2

while true; do
    TIMESTAMP=$(date -u +%FT%TZ)

    # 检查 FIS 实验状态
    EXP_STATUS=$(aws fis get-experiment \
        --id "$EXPERIMENT_ID" \
        --region "$REGION" \
        --query 'experiment.state.status' \
        --output text 2>/dev/null || echo "UNKNOWN")

    # 采集 CloudWatch 指标
    END_TIME=$(date -u +%FT%TZ)
    START_TIME=$(date -u -d "-${INTERVAL} seconds" +%FT%TZ 2>/dev/null || date -u -v-${INTERVAL}S +%FT%TZ)

    # Agent 生成时会填入具体的 metric queries
    METRICS_JSON=$(aws cloudwatch get-metric-data \
        --region "$REGION" \
        --start-time "$START_TIME" \
        --end-time "$END_TIME" \
        --metric-data-queries file://metric-queries.json \
        --output json 2>/dev/null || echo '{"MetricDataResults":[]}')

    # 写入 JSONL
    jq -cn \
        --arg ts "$TIMESTAMP" \
        --arg status "$EXP_STATUS" \
        --argjson metrics "$METRICS_JSON" \
        '{timestamp: $ts, experiment_status: $status, metrics: $metrics.MetricDataResults}' \
        >> "$OUTPUT_FILE"

    echo "[monitor] $TIMESTAMP status=$EXP_STATUS" >&2

    # 实验结束则退出
    case "$EXP_STATUS" in
        completed|failed|stopped|cancelled)
            echo "[monitor] Experiment $EXP_STATUS, stopping monitor." >&2
            break
            ;;
    esac

    sleep "$INTERVAL"
done

echo "[monitor] Finished at $(date -u +%FT%TZ)" >&2
