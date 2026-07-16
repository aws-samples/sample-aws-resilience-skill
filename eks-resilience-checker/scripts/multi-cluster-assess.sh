#!/usr/bin/env bash
set -euo pipefail

###############################################################################
# multi-cluster-assess.sh
#
# Orchestrates scripts/assess.sh across many EKS clusters in the same account.
#
# Why this exists: running assess.sh concurrently against 20-30 clusters can
# trip account-level EKS control-plane API throttling (aws eks describe-cluster /
# list-access-entries / describe-addon share a per-account rate limit, not a
# per-cluster one). assess.sh silently swallows those errors (falls back to
# "unknown"/empty results) instead of failing loudly, so throttled clusters
# would otherwise produce misleading PASS/INFO results.
#
# This wrapper:
#   1. Discovers clusters (via --discover) or takes an explicit --clusters list
#   2. Runs assess.sh against each cluster SEQUENTIALLY by default (or with a
#      small bounded concurrency), switching kubeconfig context per cluster
#   3. Adds inter-cluster delay + adaptive AWS SDK retries to absorb throttling
#   4. Aggregates all assessment.json summaries into one rollup report,
#      sorted by compliance score, so the customer can prioritize which
#      cluster to fix first
###############################################################################

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ASSESS_SH="$SCRIPT_DIR/assess.sh"

CLUSTERS=""
REGION=""
DISCOVER=0
NAMESPACES=""
OUTPUT_DIR="./output"
CONCURRENCY=2
DELAY_SECONDS=5
SKIP_KUBECONFIG_UPDATE=0

usage() {
  cat <<'USAGE'
Usage: multi-cluster-assess.sh [OPTIONS]

Options:
  --clusters "c1,c2,c3"   Comma-separated list of EKS cluster names
  --discover              Auto-discover all clusters via `aws eks list-clusters` (requires --region)
  --region REGION         AWS region (required for --discover; also passed to assess.sh)
  --namespaces "a,b,c"    Comma-separated namespaces passed through to assess.sh (default: all non-system)
  --output-dir DIR        Base output directory; each cluster gets its own subfolder (default: ./output)
  --concurrency N         Max clusters to assess in parallel (default: 2)
  --delay SECONDS         Delay between cluster runs, or between batches if concurrency>1 (default: 5)
  --skip-kubeconfig-update  Do not run `aws eks update-kubeconfig` per cluster (use if kubeconfig is pre-provisioned)
  -h, --help              Show this help

Examples:
  # Explicit list, fully sequential (safest, recommended for 10+ clusters)
  ./multi-cluster-assess.sh --clusters "prod-a,prod-b,staging-a" --region us-west-2

  # Auto-discover every cluster in the account/region
  ./multi-cluster-assess.sh --discover --region us-west-2

  # Small bounded concurrency (use with caution — watch for EKS API throttling)
  ./multi-cluster-assess.sh --discover --region us-west-2 --concurrency 3 --delay 10
USAGE
  exit 0
}

log()  { echo "[multi-cluster] $*" >&2; }
die()  { echo "[multi-cluster] ERROR: $*" >&2; exit 1; }

check_deps() {
  for cmd in kubectl aws jq "$ASSESS_SH"; do
    command -v "$cmd" >/dev/null 2>&1 || [[ -x "$cmd" ]] || die "Required command/file not found: $cmd"
  done
}

discover_clusters() {
  [[ -n "$REGION" ]] || die "--discover requires --region"
  log "Discovering clusters in region $REGION ..."
  local list
  list=$(aws eks list-clusters --region "$REGION" --output json 2>/dev/null | jq -r '.clusters[]?')
  [[ -n "$list" ]] || die "No clusters found in region $REGION (or list-clusters call failed/was throttled)"
  CLUSTER_ARR=()
  while IFS= read -r c; do
    [[ -n "$c" ]] && CLUSTER_ARR+=("$c")
  done <<< "$list"
  log "Discovered ${#CLUSTER_ARR[@]} cluster(s): ${CLUSTER_ARR[*]}"
}

run_one_cluster() {
  local cluster="$1"
  local cluster_out="$OUTPUT_DIR/$cluster"
  mkdir -p "$cluster_out"

  log "=== [$cluster] starting assessment ==="

  if [[ "$SKIP_KUBECONFIG_UPDATE" -eq 0 ]]; then
    if ! aws eks update-kubeconfig --name "$cluster" --region "$REGION" >"$cluster_out/kubeconfig-update.log" 2>&1; then
      log "=== [$cluster] FAILED: could not update kubeconfig — see $cluster_out/kubeconfig-update.log ==="
      echo '{"cluster_name":"'"$cluster"'","error":"kubeconfig_update_failed"}' > "$cluster_out/assessment.json"
      return 1
    fi
  fi

  local args=(--cluster "$cluster" --region "$REGION" --output-dir "$cluster_out")
  [[ -n "$NAMESPACES" ]] && args+=(--namespaces "$NAMESPACES")

  # Adaptive retry absorbs transient EKS API throttling instead of failing silently
  local rc=0
  AWS_RETRY_MODE=adaptive AWS_MAX_ATTEMPTS=10 "$ASSESS_SH" "${args[@]}" >"$cluster_out/assess.log" 2>&1 || rc=$?

  if [[ $rc -eq 2 ]]; then
    log "=== [$cluster] SCRIPT ERROR (exit 2) — see $cluster_out/assess.log ==="
  elif [[ $rc -eq 1 ]]; then
    log "=== [$cluster] completed — one or more checks FAILED ==="
  else
    log "=== [$cluster] completed — all checks PASSED ==="
  fi
  return 0
}

run_all_sequential() {
  local i=0
  local total=${#CLUSTER_ARR[@]}
  for cluster in "${CLUSTER_ARR[@]}"; do
    i=$((i + 1))
    run_one_cluster "$cluster" || true
    if [[ $i -lt $total ]]; then
      log "Sleeping ${DELAY_SECONDS}s before next cluster to avoid EKS API throttling ..."
      sleep "$DELAY_SECONDS"
    fi
  done
}

run_all_bounded_parallel() {
  local total=${#CLUSTER_ARR[@]}
  local i=0
  while [[ $i -lt $total ]]; do
    local batch=("${CLUSTER_ARR[@]:$i:$CONCURRENCY}")
    log "Starting batch: ${batch[*]}"
    local pids=()
    for cluster in "${batch[@]}"; do
      run_one_cluster "$cluster" &
      pids+=($!)
    done
    for pid in "${pids[@]}"; do
      wait "$pid" || true
    done
    i=$((i + CONCURRENCY))
    if [[ $i -lt $total ]]; then
      log "Batch done. Sleeping ${DELAY_SECONDS}s before next batch to avoid EKS API throttling ..."
      sleep "$DELAY_SECONDS"
    fi
  done
}

generate_rollup() {
  local rollup_json="$OUTPUT_DIR/rollup-summary.json"
  local rollup_md="$OUTPUT_DIR/rollup-summary.md"

  log "Generating rollup summary across ${#CLUSTER_ARR[@]} cluster(s) ..."

  local entries="["
  local first=1
  for cluster in "${CLUSTER_ARR[@]}"; do
    local aj="$OUTPUT_DIR/$cluster/assessment.json"
    local entry
    if [[ -f "$aj" ]] && jq -e '.summary' "$aj" >/dev/null 2>&1; then
      entry=$(jq -c --arg c "$cluster" '{
        cluster_name: $c,
        compliance_score: (.summary.compliance_score // 0),
        total_checks: (.summary.total_checks // 0),
        passed: (.summary.passed // 0),
        failed: (.summary.failed // 0),
        critical_failures: (.summary.critical_failures // 0),
        status: "OK"
      }' "$aj")
    else
      entry=$(jq -nc --arg c "$cluster" '{
        cluster_name: $c, compliance_score: null, total_checks: null,
        passed: null, failed: null, critical_failures: null, status: "ERROR_OR_INCOMPLETE"
      }')
    fi
    [[ $first -eq 0 ]] && entries+=","
    entries+="$entry"
    first=0
  done
  entries+="]"

  echo "$entries" | jq 'sort_by(.compliance_score // 0)' > "$rollup_json"
  log "Wrote $rollup_json"

  {
    echo "# Multi-Cluster EKS Resilience Rollup"
    echo ""
    echo "Generated: $(date -u +"%Y-%m-%dT%H:%M:%SZ")"
    echo "Clusters assessed: ${#CLUSTER_ARR[@]}"
    echo ""
    echo "Sorted by compliance score ascending — fix the top of this list first."
    echo ""
    echo "| Cluster | Compliance Score | Critical Failures | Failed / Total | Status |"
    echo "|---------|-------------------|--------------------|-----------------|--------|"
    jq -r '.[] | "| \(.cluster_name) | \(.compliance_score // "N/A") | \(.critical_failures // "N/A") | \(.failed // "N/A")/\(.total_checks // "N/A") | \(.status) |"' "$rollup_json"
    echo ""
    local error_count
    error_count=$(jq '[.[] | select(.status == "ERROR_OR_INCOMPLETE")] | length' "$rollup_json")
    if [[ "$error_count" -gt 0 ]]; then
      echo "> ⚠️  $error_count cluster(s) had no valid assessment.json — check their assess.log / kubeconfig-update.log for throttling or auth errors, and re-run those individually."
    fi
  } > "$rollup_md"
  log "Wrote $rollup_md"
}

print_final_summary() {
  echo ""
  echo "=============================================="
  echo " Multi-Cluster EKS Resilience Assessment Done"
  echo "=============================================="
  echo " Clusters: ${#CLUSTER_ARR[@]}"
  echo " Output:   $OUTPUT_DIR/<cluster-name>/assessment.json (+ reports)"
  echo "           $OUTPUT_DIR/rollup-summary.md"
  echo "           $OUTPUT_DIR/rollup-summary.json"
  echo "=============================================="
}

main() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --clusters)      CLUSTERS="$2"; shift 2 ;;
      --discover)      DISCOVER=1; shift ;;
      --region)        REGION="$2"; shift 2 ;;
      --namespaces)    NAMESPACES="$2"; shift 2 ;;
      --output-dir)    OUTPUT_DIR="$2"; shift 2 ;;
      --concurrency)   CONCURRENCY="$2"; shift 2 ;;
      --delay)         DELAY_SECONDS="$2"; shift 2 ;;
      --skip-kubeconfig-update) SKIP_KUBECONFIG_UPDATE=1; shift ;;
      -h|--help)       usage ;;
      *)               die "Unknown option: $1" ;;
    esac
  done

  check_deps

  if [[ "$DISCOVER" -eq 1 ]]; then
    discover_clusters
  elif [[ -n "$CLUSTERS" ]]; then
    CLUSTER_ARR=()
    IFS=',' read -ra CLUSTER_ARR <<< "$CLUSTERS"
    [[ -n "$REGION" ]] || die "--region is required alongside --clusters"
  else
    die "Must specify either --clusters \"c1,c2\" or --discover (with --region)"
  fi

  if [[ "$CONCURRENCY" -gt 5 ]]; then
    log "WARN: concurrency=$CONCURRENCY is high. EKS control-plane APIs share an account-level rate limit;"
    log "WARN: values above ~5 risk throttling that assess.sh will NOT surface as an error (results silently degrade)."
  fi

  mkdir -p "$OUTPUT_DIR"

  if [[ "$CONCURRENCY" -le 1 ]]; then
    run_all_sequential
  else
    run_all_bounded_parallel
  fi

  generate_rollup
  print_final_summary
}

main "$@"
