#!/usr/bin/env bash
#
# selfhosted-stack-analyzer — Phase 1 collector
#
# Collects a comprehensive, READ-ONLY evidence bundle of self-hosted stateful
# middleware (MySQL / TiDB / TiKV / PD / Redis / Kafka / ZooKeeper) running on an
# Amazon EKS cluster, so that Phase 2 analysis can run fully offline.
#
# Design goals:
#   - Grab as much as possible in a single pass (Phase 1 = online, one shot).
#   - READ-ONLY: only get/list/describe. Never create/apply/delete/exec.
#   - Never dump Secret/ConfigMap VALUES (only names/keys) to avoid leaking creds.
#   - Fault-tolerant: one failed collection never aborts the whole run.
#
# Usage:
#   bash collect.sh --cluster <NAME> --region <REGION> \
#       --namespaces <ns1,ns2,...> [--output ./evidence-bundle] [--no-aws] [--metrics]
#
set -uo pipefail

# ----------------------------------------------------------------------------
# Args
# ----------------------------------------------------------------------------
CLUSTER=""
REGION=""
NAMESPACES=""
OUTPUT="./evidence-bundle"
COLLECT_AWS=1
COLLECT_METRICS=0

usage() {
  grep '^#' "$0" | sed 's/^# \{0,1\}//' | head -n 22
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --cluster)    CLUSTER="${2:-}"; shift 2 ;;
    --region)     REGION="${2:-}"; shift 2 ;;
    --namespaces) NAMESPACES="${2:-}"; shift 2 ;;
    --output)     OUTPUT="${2:-}"; shift 2 ;;
    --no-aws)     COLLECT_AWS=0; shift ;;
    --metrics)    COLLECT_METRICS=1; shift ;;
    -h|--help)    usage ;;
    *) echo "Unknown arg: $1"; usage ;;
  esac
done

[[ -z "$CLUSTER" ]] && { echo "ERROR: --cluster is required"; usage; }

TS="$(date +%Y-%m-%d)"
BUNDLE="${OUTPUT}/${CLUSTER}-${TS}"
mkdir -p "$BUNDLE"/{cluster,aws,k8s,components,operators,metrics,events}

# System namespaces excluded from workload scans.
SYS_NS_RE='^(kube-system|kube-public|kube-node-lease|amazon-cloudwatch|cert-manager|ingress-nginx)$'

# manifest bookkeeping
MANIFEST="${BUNDLE}/manifest.json"
declare -a COLLECTED=()
declare -a FAILED=()

log()  { echo "[collect] $*" >&2; }
ok()   { COLLECTED+=("$1"); log "  ✓ $1"; }
fail() { FAILED+=("$1"); log "  ✗ $1 ($2)"; }

# run <label> <outfile> <command...>  — capture stdout to file, record status
run() {
  local label="$1"; local out="$2"; shift 2
  if "$@" >"$out" 2>"${out}.err"; then
    # treat empty output as collected-but-empty, still success
    rm -f "${out}.err"
    ok "$label"
  else
    fail "$label" "$(head -c 200 "${out}.err" 2>/dev/null | tr '\n' ' ')"
    rm -f "${out}.err"
  fi
}

# kubectl get all namespaces in TARGET into JSON for a resource type
kubectl_ns() {
  # $1 = resource, $2 = outfile
  local res="$1"; local out="$2"
  if [[ -n "$NAMESPACES" ]]; then
    local combined="[]"
    IFS=',' read -ra NS <<< "$NAMESPACES"
    : > "${out}.tmp"
    local first=1
    echo "{\"items\":[" > "$out"
    for ns in "${NS[@]}"; do
      kubectl get "$res" -n "$ns" -o json 2>/dev/null \
        | jq -c '.items[]?' 2>/dev/null >> "${out}.tmp" || true
    done
    # join items into a single json doc
    jq -s '{items: .}' "${out}.tmp" > "$out" 2>/dev/null || echo '{"items":[]}' > "$out"
    rm -f "${out}.tmp"
  else
    kubectl get "$res" --all-namespaces -o json > "$out" 2>/dev/null || echo '{"items":[]}' > "$out"
  fi
}

# ----------------------------------------------------------------------------
# 0. Preflight
# ----------------------------------------------------------------------------
log "Preflight checks..."
command -v kubectl >/dev/null || { echo "ERROR: kubectl not found"; exit 2; }
command -v jq >/dev/null      || { echo "ERROR: jq not found"; exit 2; }
if ! kubectl version --client >/dev/null 2>&1; then
  echo "ERROR: kubectl not working"; exit 2
fi
if [[ $COLLECT_AWS -eq 1 ]] && ! command -v aws >/dev/null; then
  log "WARN: aws CLI not found → skipping AWS layer (--no-aws implied)"
  COLLECT_AWS=0
fi

log "Bundle: $BUNDLE"
log "Namespaces: ${NAMESPACES:-<all>}"

# ----------------------------------------------------------------------------
# 1. Cluster / platform layer
# ----------------------------------------------------------------------------
log "[1/6] Cluster & platform..."
run "cluster/version"        "$BUNDLE/cluster/version.json"        kubectl version -o json
run "cluster/nodes"          "$BUNDLE/cluster/nodes.json"          kubectl get nodes -o json
run "cluster/namespaces"     "$BUNDLE/cluster/namespaces.json"     kubectl get namespaces -o json
run "cluster/storageclasses" "$BUNDLE/cluster/storageclasses.json" kubectl get storageclasses -o json
run "cluster/pv"             "$BUNDLE/cluster/persistentvolumes.json" kubectl get pv -o json
run "cluster/crds"           "$BUNDLE/cluster/crds.json"           kubectl get crds -o json
run "cluster/priorityclasses" "$BUNDLE/cluster/priorityclasses.json" kubectl get priorityclasses -o json

# ----------------------------------------------------------------------------
# 2. AWS layer (EKS / EC2 / EBS)  — read-only Describe
# ----------------------------------------------------------------------------
if [[ $COLLECT_AWS -eq 1 && -n "$REGION" ]]; then
  log "[2/6] AWS layer..."
  run "aws/caller-identity" "$BUNDLE/aws/caller-identity.json" \
      aws sts get-caller-identity --output json
  run "aws/eks-cluster" "$BUNDLE/aws/eks-cluster.json" \
      aws eks describe-cluster --name "$CLUSTER" --region "$REGION" --output json
  run "aws/eks-nodegroups" "$BUNDLE/aws/eks-nodegroups.json" \
      aws eks list-nodegroups --cluster-name "$CLUSTER" --region "$REGION" --output json
  run "aws/eks-addons" "$BUNDLE/aws/eks-addons.json" \
      aws eks list-addons --cluster-name "$CLUSTER" --region "$REGION" --output json
  run "aws/eks-fargate-profiles" "$BUNDLE/aws/eks-fargate-profiles.json" \
      aws eks list-fargate-profiles --cluster-name "$CLUSTER" --region "$REGION" --output json
  # EBS volumes tagged for this cluster (persistent storage for stateful sets)
  run "aws/ebs-volumes" "$BUNDLE/aws/ebs-volumes.json" \
      aws ec2 describe-volumes --region "$REGION" \
      --filters "Name=tag:kubernetes.io/cluster/${CLUSTER},Values=owned,shared" --output json
  # EC2 instances (node → AZ mapping cross-check).
  # IMPORTANT: the customer distinguishes self-hosted components by the EC2 host
  # Name tag. We collect the full instance set AND derive a clean Name-tag map so
  # Phase 2 can identify which component a node/pod belongs to via the Name tag.
  run "aws/ec2-instances" "$BUNDLE/aws/ec2-instances.json" \
      aws ec2 describe-instances --region "$REGION" \
      --filters "Name=tag-key,Values=kubernetes.io/cluster/${CLUSTER}" --output json

  # Derive: instanceId → Name tag → private DNS/IP → AZ  (★ component identification key)
  if [[ -s "$BUNDLE/aws/ec2-instances.json" ]]; then
    jq '{
      instances: [ .Reservations[]?.Instances[]? | {
        instanceId: .InstanceId,
        nameTag: ((.Tags // []) | map(select(.Key=="Name")) | (.[0].Value // null)),
        privateDnsName: .PrivateDnsName,
        privateIp: .PrivateIpAddress,
        az: .Placement.AvailabilityZone,
        instanceType: .InstanceType,
        state: .State.Name,
        allTags: ((.Tags // []) | map({(.Key): .Value}) | add)
      } ]
    }' "$BUNDLE/aws/ec2-instances.json" > "$BUNDLE/aws/node-nametag-map.json" 2>/dev/null \
      && ok "aws/node-nametag-map (EC2 Name tag → node identification key)" \
      || fail "aws/node-nametag-map" "jq derive failed"
  fi
else
  log "[2/6] AWS layer skipped"
fi

# ----------------------------------------------------------------------------
# 3. Kubernetes workload layer (target namespaces)
# ----------------------------------------------------------------------------
log "[3/6] K8s workloads..."
for res in pods statefulsets deployments daemonsets replicasets services endpoints \
           persistentvolumeclaims poddisruptionbudgets horizontalpodautoscalers \
           configmaps serviceaccounts networkpolicies; do
  kubectl_ns "$res" "$BUNDLE/k8s/${res}.json"
  ok "k8s/${res}"
done
# NOTE: configmaps.json is post-processed below to strip values (keep keys only).
if [[ -f "$BUNDLE/k8s/configmaps.json" ]]; then
  jq '{items: [.items[]? | {metadata: {name: .metadata.name, namespace: .metadata.namespace,
      labels: .metadata.labels}, dataKeys: (.data // {} | keys)}]}' \
      "$BUNDLE/k8s/configmaps.json" > "$BUNDLE/k8s/configmaps.json.tmp" 2>/dev/null \
      && mv "$BUNDLE/k8s/configmaps.json.tmp" "$BUNDLE/k8s/configmaps.json"
  log "  · configmaps sanitized (values stripped, keys only)"
fi
# Secrets: names + types ONLY, never data.
kubectl_ns secrets "$BUNDLE/k8s/secrets-index.json.raw"
jq '{items: [.items[]? | {name: .metadata.name, namespace: .metadata.namespace,
    type: .type, keys: (.data // {} | keys)}]}' \
    "$BUNDLE/k8s/secrets-index.json.raw" > "$BUNDLE/k8s/secrets-index.json" 2>/dev/null \
    || echo '{"items":[]}' > "$BUNDLE/k8s/secrets-index.json"
rm -f "$BUNDLE/k8s/secrets-index.json.raw"
ok "k8s/secrets-index (names/types/keys only)"

# ----------------------------------------------------------------------------
# 4. Component detection + component-specific CR/CRD dumps
# ----------------------------------------------------------------------------
log "[4/6] Component-specific resources..."

CRD_NAMES="$(jq -r '.items[]?.metadata.name' "$BUNDLE/cluster/crds.json" 2>/dev/null)"

# helper: dump a namespaced CR type if its CRD exists
dump_cr() {
  local crd="$1"; local label="$2"
  if echo "$CRD_NAMES" | grep -q "^${crd}$"; then
    kubectl_ns "$crd" "$BUNDLE/components/${label}.json"
    ok "components/${label} (CRD $crd)"
  fi
}

# TiDB (pingcap tidb-operator)
dump_cr "tidbclusters.pingcap.com"        "tidb-tidbclusters"
dump_cr "tidbmonitors.pingcap.com"        "tidb-tidbmonitors"
dump_cr "backups.pingcap.com"             "tidb-backups"
dump_cr "backupschedules.pingcap.com"     "tidb-backupschedules"
dump_cr "restores.pingcap.com"            "tidb-restores"

# Kafka (Strimzi)
dump_cr "kafkas.kafka.strimzi.io"                 "kafka-kafkas"
dump_cr "kafkatopics.kafka.strimzi.io"            "kafka-topics"
dump_cr "kafkanodepools.kafka.strimzi.io"         "kafka-nodepools"
dump_cr "kafkarebalances.kafka.strimzi.io"        "kafka-rebalances"

# Redis (common operators)
dump_cr "redisfailovers.databases.spotahome.com"  "redis-failovers-spotahome"
dump_cr "redis.redis.redis.opstreelabs.in"        "redis-opstree"
dump_cr "redisclusters.redis.redis.opstreelabs.in" "redis-cluster-opstree"
dump_cr "redisreplications.redis.redis.opstreelabs.in" "redis-replication-opstree"

# MySQL (common operators)
dump_cr "innodbclusters.mysql.oracle.com"         "mysql-innodbclusters-oracle"
dump_cr "mysqlclusters.moco.cybozu.com"           "mysql-moco"
dump_cr "perconaxtradbclusters.pxc.percona.com"   "mysql-pxc-percona"

# Prometheus / monitoring CRs (coverage check)
dump_cr "servicemonitors.monitoring.coreos.com"   "mon-servicemonitors"
dump_cr "prometheusrules.monitoring.coreos.com"   "mon-prometheusrules"

# ----------------------------------------------------------------------------
# 5. Operators (helm releases + operator deployments)
# ----------------------------------------------------------------------------
log "[5/6] Operators..."
if command -v helm >/dev/null 2>&1; then
  run "operators/helm-releases" "$BUNDLE/operators/helm-releases.json" \
      helm list --all-namespaces -o json
fi
# operator pods often carry app.kubernetes.io/name in operator namespaces
run "operators/all-deployments" "$BUNDLE/operators/all-deployments.json" \
    kubectl get deployments --all-namespaces -o json

# ----------------------------------------------------------------------------
# 6. Events + optional metrics
# ----------------------------------------------------------------------------
log "[6/6] Events & metrics..."
kubectl_ns events "$BUNDLE/events/events.json"
ok "events/events"

if [[ $COLLECT_METRICS -eq 1 ]]; then
  run "metrics/top-nodes" "$BUNDLE/metrics/top-nodes.txt" kubectl top nodes
  if [[ -n "$NAMESPACES" ]]; then
    IFS=',' read -ra NS <<< "$NAMESPACES"
    for ns in "${NS[@]}"; do
      kubectl top pods -n "$ns" > "$BUNDLE/metrics/top-pods-${ns}.txt" 2>/dev/null || true
    done
    ok "metrics/top-pods"
  fi
fi

# ----------------------------------------------------------------------------
# Manifest + self-check
# ----------------------------------------------------------------------------
log "Writing manifest..."

# quick component inventory hints for the analyst
count_json_items() { jq '.items | length' "$1" 2>/dev/null || echo 0; }

STS_COUNT=$(count_json_items "$BUNDLE/k8s/statefulsets.json")
POD_COUNT=$(count_json_items "$BUNDLE/k8s/pods.json")
NODE_COUNT=$(count_json_items "$BUNDLE/cluster/nodes.json")
PVC_COUNT=$(count_json_items "$BUNDLE/k8s/persistentvolumeclaims.json")

# detected middleware families (by CR files present + by well-known labels in sts)
detect_hint() {
  local pat="$1"
  jq -r --arg p "$pat" \
    '[.items[]? | (.metadata.name // "") + " " + ((.metadata.labels // {}) | tostring)]
      | map(select(ascii_downcase | test($p))) | length' \
    "$BUNDLE/k8s/statefulsets.json" 2>/dev/null || echo 0
}

COLLECTED_JSON=$(printf '%s\n' "${COLLECTED[@]}" | jq -R . | jq -s .)
FAILED_JSON=$(printf '%s\n' "${FAILED[@]:-}" | jq -R . | jq -s '[.[] | select(. != "")]')

cat > "$MANIFEST" <<EOF
{
  "schemaVersion": "1.0",
  "generator": "selfhosted-stack-analyzer/collect.sh",
  "cluster": "$CLUSTER",
  "region": "$REGION",
  "collectedAt": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "targetNamespaces": "${NAMESPACES:-<all>}",
  "awsLayerCollected": $( [[ $COLLECT_AWS -eq 1 ]] && echo true || echo false ),
  "metricsCollected": $( [[ $COLLECT_METRICS -eq 1 ]] && echo true || echo false ),
  "counts": {
    "nodes": ${NODE_COUNT:-0},
    "pods": ${POD_COUNT:-0},
    "statefulsets": ${STS_COUNT:-0},
    "pvcs": ${PVC_COUNT:-0}
  },
  "detectionHints": {
    "ec2_nametag_map": $( [[ -f "$BUNDLE/aws/node-nametag-map.json" ]] && echo true || echo false ),
    "tidb_crd": $( [[ -f "$BUNDLE/components/tidb-tidbclusters.json" ]] && echo true || echo false ),
    "kafka_strimzi_crd": $( [[ -f "$BUNDLE/components/kafka-kafkas.json" ]] && echo true || echo false ),
    "redis_operator_crd": $( ls "$BUNDLE"/components/redis-*.json >/dev/null 2>&1 && echo true || echo false ),
    "mysql_operator_crd": $( ls "$BUNDLE"/components/mysql-*.json >/dev/null 2>&1 && echo true || echo false ),
    "sts_name_mysql": $(detect_hint "mysql|mariadb|percona"),
    "sts_name_redis": $(detect_hint "redis"),
    "sts_name_kafka": $(detect_hint "kafka"),
    "sts_name_zookeeper": $(detect_hint "zookeeper|zk"),
    "sts_name_tikv_pd": $(detect_hint "tikv|pd-|placement")
  },
  "collected": $COLLECTED_JSON,
  "failed": $FAILED_JSON
}
EOF

# ----------------------------------------------------------------------------
# Package
# ----------------------------------------------------------------------------
ARCHIVE="${OUTPUT}/evidence-bundle-${CLUSTER}-${TS}.tar.gz"
if command -v tar >/dev/null 2>&1; then
  tar -czf "$ARCHIVE" -C "$OUTPUT" "$(basename "$BUNDLE")" 2>/dev/null \
    && log "Archive: $ARCHIVE"
fi

echo ""
echo "=========================================================="
echo " Phase 1 collection complete"
echo "=========================================================="
echo " Bundle dir : $BUNDLE"
echo " Archive    : ${ARCHIVE:-<tar unavailable>}"
echo " Collected  : ${#COLLECTED[@]} resource groups"
echo " Failed     : ${#FAILED[@]} (see manifest.json .failed)"
echo ""
echo " Detection hints:"
jq -r '.detectionHints | to_entries[] | "   \(.key): \(.value)"' "$MANIFEST" 2>/dev/null
echo ""
echo " Next: run Phase 2 (offline) analysis on this bundle."
echo "=========================================================="
