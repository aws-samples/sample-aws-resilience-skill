#!/usr/bin/env bash
set -euo pipefail

# EKS Resilience Assessment — 28 best-practice checks
# Outputs: assessment.json, assessment-report.md, assessment-report.html, remediation-commands.sh

###############################################################################
# Globals
###############################################################################
CLUSTER_NAME=""
REGION=""
NAMESPACES=""
OUTPUT_DIR="./output"
SKIP_NS_REGEX="^(kube-system|kube-public|kube-node-lease)$"
RESULTS=()
TOTAL=0; PASS=0; FAIL=0; INFO=0

###############################################################################
# Helpers
###############################################################################
usage() {
  cat <<'USAGE'
Usage: assess.sh [OPTIONS]

Options:
  --cluster NAME        EKS cluster name (auto-detected if omitted)
  --region REGION        AWS region (default: from AWS_DEFAULT_REGION or aws configure)
  --namespaces "a,b,c"  Comma-separated namespaces to check (default: all non-system)
  --output-dir DIR       Output directory (default: ./output)
  -h, --help             Show this help
USAGE
  exit 0
}

log()  { echo "[assess] $*" >&2; }
die()  { echo "[assess] ERROR: $*" >&2; exit 1; }

check_deps() {
  for cmd in kubectl aws jq; do
    command -v "$cmd" >/dev/null 2>&1 || die "Required command not found: $cmd"
  done
}

discover_cluster() {
  if [[ -z "$CLUSTER_NAME" ]]; then
    CLUSTER_NAME=$(kubectl config current-context 2>/dev/null | sed 's|.*:cluster/||' || true)
    [[ -n "$CLUSTER_NAME" ]] || die "Cannot auto-detect cluster name. Use --cluster."
    log "Auto-detected cluster: $CLUSTER_NAME"
  fi
  if [[ -z "$REGION" ]]; then
    REGION=$(aws configure get region 2>/dev/null || echo "")
    [[ -n "$REGION" ]] || REGION="ap-northeast-1"
    log "Using region: $REGION"
  fi
}

get_namespaces() {
  if [[ -n "$NAMESPACES" ]]; then
    NS_LIST=$(echo "$NAMESPACES" | tr ',' '\n')
  else
    NS_LIST=$(kubectl get namespaces -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' 2>/dev/null)
  fi
  # Filter out system namespaces
  FILTERED_NS=()
  while IFS= read -r ns; do
    [[ -z "$ns" ]] && continue
    if ! echo "$ns" | grep -qE "$SKIP_NS_REGEX"; then
      FILTERED_NS+=("$ns")
    fi
  done <<< "$NS_LIST"
  log "Target namespaces (${#FILTERED_NS[@]}): ${FILTERED_NS[*]}"
}

# emit_result ID NAME CATEGORY SEVERITY STATUS FINDINGS_JSON RESOURCES_JSON REMEDIATION
emit_result() {
  local id="$1" name="$2" category="$3" severity="$4" status="$5"
  local findings="$6" resources="$7" remediation="$8"
  local json
  json=$(jq -nc \
    --arg id "$id" \
    --arg name "$name" \
    --arg category "$category" \
    --arg severity "$severity" \
    --arg status "$status" \
    --argjson findings "$findings" \
    --argjson resources "$resources" \
    --arg remediation "$remediation" \
    '{id:$id, name:$name, category:$category, severity:$severity, status:$status, findings:$findings, resources_affected:$resources, remediation:$remediation}')
  echo "$json"
  RESULTS+=("$json")
  TOTAL=$((TOTAL + 1))
  case "$status" in
    PASS) PASS=$((PASS + 1)) ;;
    FAIL) FAIL=$((FAIL + 1)) ;;
    *)    INFO=$((INFO + 1)) ;;
  esac
}

# Safe kubectl wrapper — returns empty JSON array on failure
kube_json() {
  kubectl "$@" -o json 2>/dev/null || echo '{"items":[]}'
}

###############################################################################
# Application Checks A1–A14
###############################################################################

check_a1() {
  log "A1: Singleton Pods"
  local raw found status
  raw=$(kube_json get pods --all-namespaces)
  found=$(echo "$raw" | jq '[.items[] | select((.metadata.ownerReferences // []) | length == 0) | select(.metadata.namespace | test("^kube-") | not) | {namespace:.metadata.namespace, name:.metadata.name}]')
  if [[ $(echo "$found" | jq 'length') -eq 0 ]]; then status="PASS"; else status="FAIL"; fi
  emit_result "A1" "Avoid Running Singleton Pods" "application" "critical" "$status" \
    "$found" "$found" "Wrap standalone pods in a Deployment, StatefulSet, or Job controller."
}

check_a2() {
  log "A2: Multiple Replicas"
  local deps sts found status
  deps=$(kube_json get deployments --all-namespaces)
  sts=$(kube_json get statefulsets --all-namespaces)
  found=$(jq -nc --argjson d "$deps" --argjson s "$sts" '
    [$d.items[] | select(.metadata.namespace | test("^kube-") | not) | select(.spec.replicas == 1) | {namespace:.metadata.namespace, name:.metadata.name, kind:"Deployment", replicas:.spec.replicas}] +
    [$s.items[] | select(.metadata.namespace | test("^kube-") | not) | select(.spec.replicas == 1) | {namespace:.metadata.namespace, name:.metadata.name, kind:"StatefulSet", replicas:.spec.replicas}]')
  if [[ $(echo "$found" | jq 'length') -eq 0 ]]; then status="PASS"; else status="FAIL"; fi
  emit_result "A2" "Run Multiple Replicas" "application" "critical" "$status" \
    "$found" "$found" "Set spec.replicas > 1 for all production workloads."
}

check_a3() {
  log "A3: Pod Anti-Affinity"
  local deps found status
  deps=$(kube_json get deployments --all-namespaces)
  found=$(echo "$deps" | jq '[.items[] | select(.metadata.namespace | test("^kube-") | not) | select(.spec.replicas > 1) | select(.spec.template.spec.affinity.podAntiAffinity == null) | {namespace:.metadata.namespace, name:.metadata.name, replicas:.spec.replicas}]')
  if [[ $(echo "$found" | jq 'length') -eq 0 ]]; then status="PASS"; else status="FAIL"; fi
  emit_result "A3" "Use Pod Anti-Affinity" "application" "warning" "$status" \
    "$found" "$found" "Add podAntiAffinity to spread replicas across nodes."
}

check_a4() {
  log "A4: Liveness Probes"
  local deps sts ds found status
  deps=$(kube_json get deployments --all-namespaces)
  sts=$(kube_json get statefulsets --all-namespaces)
  ds=$(kube_json get daemonsets --all-namespaces)
  found=$(jq -nc --argjson d "$deps" --argjson s "$sts" --argjson a "$ds" '
    [($d.items[], $s.items[], $a.items[]) | select(.metadata.namespace | test("^kube-") | not) |
     {namespace:.metadata.namespace, name:.metadata.name, containers_missing_probe:
       [.spec.template.spec.containers[] | select(.livenessProbe == null) | .name]}
     | select(.containers_missing_probe | length > 0)]')
  if [[ $(echo "$found" | jq 'length') -eq 0 ]]; then status="PASS"; else status="FAIL"; fi
  emit_result "A4" "Use Liveness Probes" "application" "critical" "$status" \
    "$found" "$found" "Add livenessProbe to every container in your workloads."
}

check_a5() {
  log "A5: Readiness Probes"
  local deps sts ds found status
  deps=$(kube_json get deployments --all-namespaces)
  sts=$(kube_json get statefulsets --all-namespaces)
  ds=$(kube_json get daemonsets --all-namespaces)
  found=$(jq -nc --argjson d "$deps" --argjson s "$sts" --argjson a "$ds" '
    [($d.items[], $s.items[], $a.items[]) | select(.metadata.namespace | test("^kube-") | not) |
     {namespace:.metadata.namespace, name:.metadata.name, containers_missing_probe:
       [.spec.template.spec.containers[] | select(.readinessProbe == null) | .name]}
     | select(.containers_missing_probe | length > 0)]')
  if [[ $(echo "$found" | jq 'length') -eq 0 ]]; then status="PASS"; else status="FAIL"; fi
  emit_result "A5" "Use Readiness Probes" "application" "critical" "$status" \
    "$found" "$found" "Add readinessProbe to every container in your workloads."
}

check_a6() {
  log "A6: Pod Disruption Budgets"
  local deps sts pdbs found status
  deps=$(kube_json get deployments --all-namespaces)
  sts=$(kube_json get statefulsets --all-namespaces)
  pdbs=$(kubectl get pdb --all-namespaces -o json 2>/dev/null | jq '[.items[] | {namespace:.metadata.namespace, selector:.spec.selector.matchLabels}]' || echo '[]')
  found=$(jq -nc --argjson d "$deps" --argjson s "$sts" --argjson p "$pdbs" '
    [$d.items[] | select(.metadata.namespace | test("^kube-") | not) | select(.spec.replicas > 1) |
     {namespace:.metadata.namespace, name:.metadata.name, kind:"Deployment"} |
     select(. as $w | $p | map(select(.namespace == $w.namespace)) | length == 0)] +
    [$s.items[] | select(.metadata.namespace | test("^kube-") | not) |
     {namespace:.metadata.namespace, name:.metadata.name, kind:"StatefulSet"} |
     select(. as $w | $p | map(select(.namespace == $w.namespace)) | length == 0)]')
  if [[ $(echo "$found" | jq 'length') -eq 0 ]]; then status="PASS"; else status="FAIL"; fi
  emit_result "A6" "Use Pod Disruption Budgets" "application" "warning" "$status" \
    "$found" "$found" "Create PodDisruptionBudgets for critical workloads."
}

check_a7() {
  log "A7: Metrics Server"
  local status findings
  local ms_json node_count
  ms_json=$(kubectl get deployment metrics-server -n kube-system -o json 2>/dev/null || echo '{}')
  local avail
  avail=$(echo "$ms_json" | jq '.status.availableReplicas // 0')
  node_count=$(kubectl get --raw "/apis/metrics.k8s.io/v1beta1/nodes" 2>/dev/null | jq '.items | length' || echo "0")
  if [[ "$avail" -ge 1 && "$node_count" -gt 0 ]]; then
    status="PASS"
    findings='["Metrics server running with '"$avail"' replica(s); '"$node_count"' node(s) reporting metrics"]'
  else
    status="FAIL"
    findings='["Metrics server available_replicas='"$avail"', nodes_reporting='"$node_count"'"]'
  fi
  emit_result "A7" "Run Kubernetes Metrics Server" "application" "warning" "$status" \
    "$findings" '[]' "Install metrics-server via EKS managed add-on or Helm."
}

check_a8() {
  log "A8: Horizontal Pod Autoscaler"
  local deps hpas found status
  deps=$(kube_json get deployments --all-namespaces)
  hpas=$(kubectl get hpa --all-namespaces -o json 2>/dev/null | jq '[.items[] | {namespace:.metadata.namespace, target:.spec.scaleTargetRef.name}]' || echo '[]')
  found=$(jq -nc --argjson d "$deps" --argjson h "$hpas" '
    [$d.items[] | select(.metadata.namespace | test("^kube-") | not) | select(.spec.replicas > 1) |
     {namespace:.metadata.namespace, name:.metadata.name} |
     select(. as $w | $h | map(select(.namespace == $w.namespace and .target == $w.name)) | length == 0)]')
  if [[ $(echo "$found" | jq 'length') -eq 0 ]]; then status="PASS"; else status="FAIL"; fi
  emit_result "A8" "Use Horizontal Pod Autoscaler" "application" "warning" "$status" \
    "$found" "$found" "Create HPA resources for multi-replica workloads."
}

check_a9() {
  log "A9: Custom Metrics Scaling"
  local status findings detected=0
  kubectl get --raw "/apis/custom.metrics.k8s.io/v1beta1" >/dev/null 2>&1 && detected=1
  kubectl get --raw "/apis/external.metrics.k8s.io/v1beta1" >/dev/null 2>&1 && detected=1
  kubectl get deployment -n kube-system -l app=prometheus-adapter -o json 2>/dev/null | jq -e '.items | length > 0' >/dev/null 2>&1 && detected=1
  kubectl get crd scaledobjects.keda.sh >/dev/null 2>&1 && detected=1
  local custom_hpas
  custom_hpas=$(kubectl get hpa --all-namespaces -o json 2>/dev/null | jq '[.items[] | select(.spec.metrics[]? | .type == "Pods" or .type == "Object" or .type == "External") | {namespace:.metadata.namespace, name:.metadata.name}]' || echo '[]')
  [[ $(echo "$custom_hpas" | jq 'length') -gt 0 ]] && detected=1
  if [[ $detected -eq 1 ]]; then
    status="PASS"; findings='["Custom/external metrics scaling infrastructure detected"]'
  else
    status="INFO"; findings='["No custom metrics scaling infrastructure found"]'
  fi
  emit_result "A9" "Use Custom Metrics Scaling" "application" "info" "$status" \
    "$findings" '[]' "Install Prometheus Adapter or KEDA for custom metrics scaling."
}

check_a10() {
  log "A10: Vertical Pod Autoscaler"
  local status findings detected=0
  kubectl get crd verticalpodautoscalers.autoscaling.k8s.io >/dev/null 2>&1 && detected=1
  local vpa_count
  vpa_count=$(kubectl get vpa --all-namespaces -o json 2>/dev/null | jq '.items | length' || echo "0")
  [[ "$vpa_count" -gt 0 ]] && detected=$((detected + 1))
  kubectl get deployment -n goldilocks -l app.kubernetes.io/name=goldilocks -o json 2>/dev/null | jq -e '.items | length > 0' >/dev/null 2>&1 && detected=2
  if [[ $detected -ge 2 ]]; then
    status="PASS"; findings='["VPA installed and configured ('"$vpa_count"' VPA resources)"]'
  elif [[ $detected -ge 1 ]]; then
    status="INFO"; findings='["VPA CRD found but no VPA resources configured"]'
  else
    status="INFO"; findings='["VPA not installed"]'
  fi
  emit_result "A10" "Use Vertical Pod Autoscaler" "application" "info" "$status" \
    "$findings" '[]' "Install VPA and create VerticalPodAutoscaler resources for workloads."
}

check_a11() {
  log "A11: PreStop Hooks"
  local deps sts found status
  deps=$(kube_json get deployments --all-namespaces)
  sts=$(kube_json get statefulsets --all-namespaces)
  found=$(jq -nc --argjson d "$deps" --argjson s "$sts" '
    [($d.items[], $s.items[]) | select(.metadata.namespace | test("^kube-") | not) |
     {namespace:.metadata.namespace, name:.metadata.name, containers_missing_hook:
       [.spec.template.spec.containers[] | select(.lifecycle.preStop == null) | .name]}
     | select(.containers_missing_hook | length > 0)]')
  if [[ $(echo "$found" | jq 'length') -eq 0 ]]; then status="PASS"; else status="FAIL"; fi
  emit_result "A11" "Use PreStop Hooks" "application" "warning" "$status" \
    "$found" "$found" "Add lifecycle.preStop hooks for graceful termination."
}

check_a12() {
  log "A12: Service Mesh"
  local status findings detected=0
  kubectl get namespace istio-system >/dev/null 2>&1 && detected=1
  kubectl get crd virtualservices.networking.istio.io >/dev/null 2>&1 && detected=1
  kubectl get namespace linkerd >/dev/null 2>&1 && detected=1
  kubectl get crd serviceprofiles.linkerd.io >/dev/null 2>&1 && detected=1
  kubectl get namespace consul >/dev/null 2>&1 && detected=1
  local sidecar_count
  sidecar_count=$(kubectl get pods --all-namespaces -o json 2>/dev/null | jq '[.items[] | select(.metadata.namespace | test("^kube-") | not) | select(.spec.containers | length > 1) | select(.spec.containers[].name | test("istio-proxy|linkerd-proxy|envoy-sidecar|consul-sidecar"))] | length' || echo "0")
  [[ "$sidecar_count" -gt 0 ]] && detected=1
  if [[ $detected -ge 1 ]]; then
    status="PASS"; findings='["Service mesh detected"]'
  else
    status="INFO"; findings='["No service mesh detected"]'
  fi
  emit_result "A12" "Use a Service Mesh" "application" "info" "$status" \
    "$findings" '[]' "Consider deploying Istio, Linkerd, or Consul for service mesh capabilities."
}

check_a13() {
  log "A13: Application Monitoring"
  local status findings detected=0
  kubectl get deployment -n monitoring -l app.kubernetes.io/name=prometheus -o json 2>/dev/null | jq -e '.items | length > 0' >/dev/null 2>&1 && detected=1
  kubectl get crd prometheuses.monitoring.coreos.com >/dev/null 2>&1 && detected=1
  kubectl get daemonset cloudwatch-agent -n amazon-cloudwatch >/dev/null 2>&1 && detected=1
  kubectl get daemonset fluent-bit -n amazon-cloudwatch >/dev/null 2>&1 && detected=1
  local third_party
  third_party=$(kubectl get pods --all-namespaces -o json 2>/dev/null | jq '[.items[] | select(.metadata.name | test("datadog|newrelic|dynatrace"))] | length' || echo "0")
  [[ "$third_party" -gt 0 ]] && detected=1
  if [[ $detected -ge 1 ]]; then
    status="PASS"; findings='["Monitoring solution detected"]'
  else
    status="FAIL"; findings='["No monitoring solution detected"]'
  fi
  emit_result "A13" "Monitor Your Applications" "application" "warning" "$status" \
    "$findings" '[]' "Deploy Prometheus, CloudWatch Container Insights, or a third-party monitoring agent."
}

check_a14() {
  log "A14: Centralized Logging"
  local status findings detected=0
  local ds_json deploy_json
  ds_json=$(kube_json get daemonset --all-namespaces)
  deploy_json=$(kube_json get deployment --all-namespaces)
  [[ $(echo "$ds_json" | jq '[.items[] | select(.metadata.name | test("fluent-bit|fluentd|fluent"))] | length') -gt 0 ]] && detected=1
  [[ $(echo "$ds_json" | jq '[.items[] | select(.metadata.name | test("cloudwatch"))] | length') -gt 0 ]] && detected=1
  [[ $(echo "$deploy_json" | jq '[.items[] | select(.metadata.name | test("elasticsearch|opensearch|kibana|loki"))] | length') -gt 0 ]] && detected=1
  if [[ $detected -ge 1 ]]; then
    status="PASS"; findings='["Centralized logging solution detected"]'
  else
    status="FAIL"; findings='["No centralized logging solution detected"]'
  fi
  emit_result "A14" "Use Centralized Logging" "application" "warning" "$status" \
    "$findings" '[]' "Deploy Fluent Bit, CloudWatch Logs agent, or EFK/Loki stack."
}

###############################################################################
# Control Plane Checks C1–C5
###############################################################################

check_c1() {
  log "C1: Control Plane Logs"
  local status findings
  local log_types
  log_types=$(aws eks describe-cluster --name "$CLUSTER_NAME" --region "$REGION" \
    --query 'cluster.logging.clusterLogging[?enabled==`true`].types[]' --output json 2>/dev/null || echo '[]')
  if echo "$log_types" | jq -e 'index("api")' >/dev/null 2>&1; then
    status="PASS"; findings=$(jq -nc --argjson t "$log_types" '["Enabled log types: \($t | join(", "))"]')
  else
    status="FAIL"; findings='["API server logging not enabled"]'
  fi
  emit_result "C1" "Monitor Control Plane Logs" "control_plane" "warning" "$status" \
    "$findings" '[]' "Enable at least api log type via aws eks update-cluster-config."
}

check_c2() {
  log "C2: Cluster Authentication"
  local status findings detected=0
  local access_entries
  access_entries=$(aws eks list-access-entries --cluster-name "$CLUSTER_NAME" --region "$REGION" --output json 2>/dev/null || echo '{}')
  if echo "$access_entries" | jq -e '.accessEntries | length > 0' >/dev/null 2>&1; then detected=1; fi
  local auth_cm
  auth_cm=$(kubectl get configmap aws-auth -n kube-system -o json 2>/dev/null || echo '{}')
  if echo "$auth_cm" | jq -e '.data.mapRoles != null or .data.mapUsers != null' >/dev/null 2>&1; then detected=1; fi
  if [[ $detected -ge 1 ]]; then
    status="PASS"; findings='["Cluster authentication configured"]'
  else
    status="FAIL"; findings='["No access entries or aws-auth ConfigMap found"]'
  fi
  emit_result "C2" "Cluster Authentication" "control_plane" "warning" "$status" \
    "$findings" '[]' "Configure EKS Access Entries or aws-auth ConfigMap for cluster access."
}

check_c3() {
  log "C3: Large Cluster Optimizations"
  local status findings
  local svc_count
  svc_count=$(kubectl get services --all-namespaces --no-headers 2>/dev/null | wc -l)
  if [[ "$svc_count" -lt 1000 ]]; then
    status="PASS"
    findings='["Service count '"$svc_count"' < 1000; no large-cluster optimizations needed"]'
  else
    local kp_mode warm_ip optimized=0
    kp_mode=$(kubectl get configmap kube-proxy-config -n kube-system -o json 2>/dev/null | jq -r '.data.config' 2>/dev/null | grep -oP '"mode"\s*:\s*"\K[^"]+' || echo "unknown")
    warm_ip=$(kubectl get daemonset aws-node -n kube-system -o json 2>/dev/null | jq '[.spec.template.spec.containers[0].env[] | select(.name | test("WARM_IP_TARGET|WARM_ENI_TARGET|MINIMUM_IP_TARGET"))]' || echo '[]')
    [[ "$kp_mode" == "ipvs" ]] && optimized=$((optimized + 1))
    [[ $(echo "$warm_ip" | jq 'length') -gt 0 ]] && optimized=$((optimized + 1))
    if [[ $optimized -ge 2 ]]; then
      status="PASS"; findings='["Large cluster ('"$svc_count"' services) with proper optimizations"]'
    else
      status="FAIL"; findings='["Large cluster ('"$svc_count"' services) missing optimizations: kube-proxy mode='"$kp_mode"'"]'
    fi
  fi
  emit_result "C3" "Running Large Clusters" "control_plane" "info" "$status" \
    "$findings" '[]' "For >1000 services, enable IPVS mode and configure WARM_IP_TARGET."
}

check_c4() {
  log "C4: Endpoint Access Control"
  local status findings
  local vpc_cfg
  vpc_cfg=$(aws eks describe-cluster --name "$CLUSTER_NAME" --region "$REGION" \
    --query 'cluster.resourcesVpcConfig.{endpointPublicAccess:endpointPublicAccess,endpointPrivateAccess:endpointPrivateAccess,publicAccessCidrs:publicAccessCidrs}' \
    --output json 2>/dev/null || echo '{}')
  local pub_access cidrs
  pub_access=$(echo "$vpc_cfg" | jq -r '.endpointPublicAccess // "unknown"')
  cidrs=$(echo "$vpc_cfg" | jq -r '.publicAccessCidrs // []')
  if [[ "$pub_access" == "false" ]]; then
    status="PASS"; findings='["Fully private endpoint"]'
  elif echo "$cidrs" | jq -e 'index("0.0.0.0/0")' >/dev/null 2>&1; then
    status="FAIL"; findings='["Public endpoint open to 0.0.0.0/0"]'
  elif [[ "$pub_access" == "true" ]]; then
    status="PASS"; findings=$(jq -nc --argjson c "$cidrs" '["Public endpoint restricted to: \($c | join(", "))"]')
  else
    status="INFO"; findings='["Unable to determine endpoint access configuration"]'
  fi
  emit_result "C4" "EKS Control Plane Endpoint Access Control" "control_plane" "critical" "$status" \
    "$findings" '[]' "Restrict public endpoint access or use a fully private endpoint."
}

check_c5() {
  log "C5: Catch-All Admission Webhooks"
  local mut val found status
  mut=$(kubectl get mutatingwebhookconfigurations -o json 2>/dev/null || echo '{"items":[]}')
  val=$(kubectl get validatingwebhookconfigurations -o json 2>/dev/null || echo '{"items":[]}')
  found=$(jq -nc --argjson m "$mut" --argjson v "$val" '
    [($m.items[], $v.items[]) | {name:.metadata.name, webhooks:[.webhooks[]? |
      select((.namespaceSelector == null) and (.objectSelector == null) and
        (.rules[]? | (.apiGroups[]? == "*") or (.apiVersions[]? == "*") or (.resources[]? == "*"))) |
      {name:.name}]} | select(.webhooks | length > 0)]')
  if [[ $(echo "$found" | jq 'length') -eq 0 ]]; then status="PASS"; else status="FAIL"; fi
  emit_result "C5" "Avoid Catch-All Admission Webhooks" "control_plane" "warning" "$status" \
    "$found" "$found" "Add namespaceSelector or objectSelector to narrow webhook scope."
}

###############################################################################
# Data Plane Checks D1–D7
###############################################################################

check_d1() {
  log "D1: Cluster Autoscaler / Karpenter"
  local status findings detected=0
  local ca_count
  ca_count=$(kubectl get deployment -n kube-system -l app=cluster-autoscaler -o json 2>/dev/null | jq '.items | length' || echo "0")
  [[ "$ca_count" -gt 0 ]] && detected=1
  kubectl get namespace karpenter >/dev/null 2>&1 && detected=1
  kubectl get crd nodepools.karpenter.sh >/dev/null 2>&1 && detected=1
  kubectl get crd ec2nodeclasses.karpenter.k8s.aws >/dev/null 2>&1 && detected=1
  if [[ $detected -ge 1 ]]; then
    status="PASS"; findings='["Node autoscaling solution detected"]'
  else
    status="FAIL"; findings='["No Cluster Autoscaler or Karpenter found"]'
  fi
  emit_result "D1" "Use Cluster Autoscaler or Karpenter" "data_plane" "critical" "$status" \
    "$findings" '[]' "Install Karpenter or Cluster Autoscaler for automatic node scaling."
}

check_d2() {
  log "D2: Multi-AZ Node Spread"
  local status findings
  local nodes_json az_info
  nodes_json=$(kube_json get nodes)
  az_info=$(echo "$nodes_json" | jq '[.items[] | {name:.metadata.name, az:.metadata.labels["topology.kubernetes.io/zone"]}] | group_by(.az) | map({az:.[0].az, count:length})')
  local az_count
  az_count=$(echo "$az_info" | jq 'length')
  if [[ "$az_count" -lt 2 ]]; then
    status="FAIL"
    findings=$(jq -nc --argjson a "$az_info" '["Nodes in only \($a | length) AZ(s): \($a | map(.az) | join(", "))"]')
  else
    local variance
    variance=$(echo "$az_info" | jq '(map(.count) | (max - min) / max * 100) | floor')
    if [[ "$variance" -le 20 ]]; then
      status="PASS"
    else
      status="FAIL"
    fi
    findings=$(jq -nc --argjson a "$az_info" --arg v "$variance" '["AZ distribution: \($a | map("\(.az)=\(.count)") | join(", ")); variance=\($v)%"]')
  fi
  emit_result "D2" "Worker Nodes Spread Across Multiple AZs" "data_plane" "critical" "$status" \
    "$findings" '[]' "Use multiple AZs with balanced node groups for high availability."
}

check_d3() {
  log "D3: Resource Requests/Limits"
  local deps found status
  deps=$(kube_json get deployments --all-namespaces)
  found=$(echo "$deps" | jq '[.items[] | select(.metadata.namespace | test("^kube-") | not) |
    {namespace:.metadata.namespace, name:.metadata.name, containers_missing_resources:
      [.spec.template.spec.containers[] | {name:.name,
        has_cpu_request:(.resources.requests.cpu != null), has_cpu_limit:(.resources.limits.cpu != null),
        has_mem_request:(.resources.requests.memory != null), has_mem_limit:(.resources.limits.memory != null)}
       | select(.has_cpu_request == false or .has_cpu_limit == false or .has_mem_request == false or .has_mem_limit == false)]}
    | select(.containers_missing_resources | length > 0)]')
  if [[ $(echo "$found" | jq 'length') -eq 0 ]]; then status="PASS"; else status="FAIL"; fi
  emit_result "D3" "Configure Resource Requests/Limits" "data_plane" "critical" "$status" \
    "$found" "$found" "Set CPU/memory requests and limits for all containers."
}

check_d4() {
  log "D4: Namespace ResourceQuotas"
  local missing=()
  for ns in "${FILTERED_NS[@]}"; do
    local count
    count=$(kubectl get resourcequota -n "$ns" --no-headers 2>/dev/null | wc -l)
    if [[ "$count" -eq 0 ]]; then missing+=("$ns"); fi
  done
  local found status
  found=$(printf '%s\n' "${missing[@]}" | jq -R . | jq -sc '.')
  if [[ ${#missing[@]} -eq 0 ]]; then status="PASS"; else status="FAIL"; fi
  emit_result "D4" "Namespace ResourceQuotas" "data_plane" "warning" "$status" \
    "$found" "$found" "Create ResourceQuota in each namespace to enforce resource limits."
}

check_d5() {
  log "D5: Namespace LimitRanges"
  local missing=()
  for ns in "${FILTERED_NS[@]}"; do
    local count
    count=$(kubectl get limitrange -n "$ns" --no-headers 2>/dev/null | wc -l)
    if [[ "$count" -eq 0 ]]; then missing+=("$ns"); fi
  done
  local found status
  found=$(printf '%s\n' "${missing[@]}" | jq -R . | jq -sc '.')
  if [[ ${#missing[@]} -eq 0 ]]; then status="PASS"; else status="FAIL"; fi
  emit_result "D5" "Namespace LimitRanges" "data_plane" "warning" "$status" \
    "$found" "$found" "Create LimitRange in each namespace to set default resource constraints."
}

check_d6() {
  log "D6: CoreDNS Metrics Monitoring"
  local status findings detected=0
  local metrics_port
  metrics_port=$(kubectl get deployment coredns -n kube-system -o json 2>/dev/null | jq '[.spec.template.spec.containers[0].ports[] | select(.containerPort == 9153)] | length' || echo "0")
  local svcmon
  svcmon=$(kubectl get servicemonitor -n kube-system -o json 2>/dev/null | jq '[.items[] | select(.spec.selector.matchLabels["k8s-app"] == "kube-dns" or (.metadata.name | test("coredns|dns")))] | length' || echo "0")
  local prom_ann
  prom_ann=$(kubectl get service kube-dns -n kube-system -o json 2>/dev/null | jq '.metadata.annotations | with_entries(select(.key | test("prometheus"))) | length' || echo "0")
  [[ "$metrics_port" -gt 0 ]] && detected=$((detected + 1))
  [[ "$svcmon" -gt 0 || "$prom_ann" -gt 0 ]] && detected=$((detected + 1))
  if [[ $detected -ge 2 ]]; then
    status="PASS"; findings='["CoreDNS metrics port exposed and monitoring configured"]'
  elif [[ "$metrics_port" -gt 0 ]]; then
    status="FAIL"; findings='["CoreDNS metrics port exists but no ServiceMonitor or scrape annotations found"]'
  else
    status="FAIL"; findings='["CoreDNS metrics not properly configured"]'
  fi
  emit_result "D6" "Monitor CoreDNS Metrics" "data_plane" "warning" "$status" \
    "$findings" '[]' "Ensure CoreDNS metrics port 9153 is exposed and monitored by Prometheus."
}

check_d7() {
  log "D7: CoreDNS Configuration"
  local status findings
  local auto_mode
  auto_mode=$(aws eks describe-cluster --name "$CLUSTER_NAME" --region "$REGION" \
    --query 'cluster.computeConfig.enabled' --output text 2>/dev/null || echo "false")
  if [[ "$auto_mode" == "true" || "$auto_mode" == "True" ]]; then
    status="PASS"; findings='["EKS Auto Mode enabled — CoreDNS managed automatically"]'
  else
    local addon_status
    addon_status=$(aws eks describe-addon --cluster-name "$CLUSTER_NAME" --addon-name coredns --region "$REGION" \
      --query 'addon.status' --output text 2>/dev/null || echo "")
    if [[ -n "$addon_status" ]]; then
      status="PASS"; findings='["CoreDNS is an EKS managed add-on (status: '"$addon_status"')"]'
    else
      status="FAIL"; findings='["CoreDNS is self-managed — consider using EKS managed add-on"]'
    fi
  fi
  emit_result "D7" "CoreDNS Configuration" "data_plane" "info" "$status" \
    "$findings" '[]' "Use EKS managed add-on for CoreDNS to get automatic updates."
}

###############################################################################
# Output
###############################################################################

write_json() {
  local out="$OUTPUT_DIR/assessment.json"
  local ts
  ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  {
    echo "{"
    echo "  \"cluster\": \"$CLUSTER_NAME\","
    echo "  \"region\": \"$REGION\","
    echo "  \"timestamp\": \"$ts\","
    echo "  \"summary\": {\"total\": $TOTAL, \"pass\": $PASS, \"fail\": $FAIL, \"info\": $INFO},"
    echo "  \"checks\": ["
    local first=1
    for r in "${RESULTS[@]}"; do
      [[ $first -eq 0 ]] && echo ","
      echo "    $r"
      first=0
    done
    echo ""
    echo "  ]"
    echo "}"
  } | jq '.' > "$out"
  log "Wrote $out"
}

write_report() {
  local out="$OUTPUT_DIR/assessment-report.md"
  local ts
  ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  {
    echo "# EKS Resilience Assessment Report"
    echo ""
    echo "- **Cluster:** $CLUSTER_NAME"
    echo "- **Region:** $REGION"
    echo "- **Date:** $ts"
    echo ""
    echo "## Summary"
    echo ""
    echo "| Total | PASS | FAIL | INFO |"
    echo "|-------|------|------|------|"
    echo "| $TOTAL | $PASS | $FAIL | $INFO |"
    echo ""

    for category in application control_plane data_plane; do
      local title
      case $category in
        application)    title="Application Checks" ;;
        control_plane)  title="Control Plane Checks" ;;
        data_plane)     title="Data Plane Checks" ;;
      esac
      echo "## $title"
      echo ""
      echo "| ID | Check | Severity | Status |"
      echo "|----|-------|----------|--------|"
      for r in "${RESULTS[@]}"; do
        local cat
        cat=$(echo "$r" | jq -r '.category')
        [[ "$cat" != "$category" ]] && continue
        local id name sev st
        id=$(echo "$r" | jq -r '.id')
        name=$(echo "$r" | jq -r '.name')
        sev=$(echo "$r" | jq -r '.severity')
        st=$(echo "$r" | jq -r '.status')
        local icon
        case $st in PASS) icon="✅";; FAIL) icon="❌";; *) icon="ℹ️";; esac
        echo "| $id | $name | $sev | $icon $st |"
      done
      echo ""
    done

    # Details for FAILed checks
    local has_fail=0
    for r in "${RESULTS[@]}"; do
      [[ $(echo "$r" | jq -r '.status') == "FAIL" ]] && has_fail=1 && break
    done
    if [[ $has_fail -eq 1 ]]; then
      echo "## Failed Check Details"
      echo ""
      for r in "${RESULTS[@]}"; do
        [[ $(echo "$r" | jq -r '.status') != "FAIL" ]] && continue
        local id name rem findings
        id=$(echo "$r" | jq -r '.id')
        name=$(echo "$r" | jq -r '.name')
        rem=$(echo "$r" | jq -r '.remediation')
        findings=$(echo "$r" | jq -r '.findings | if type == "array" then map(if type == "string" then . else (. | tostring) end) | join("; ") else tostring end')
        echo "### $id: $name"
        echo ""
        echo "**Findings:** $findings"
        echo ""
        echo "**Remediation:** $rem"
        echo ""
      done
    fi
  } > "$out"
  log "Wrote $out"
}

generate_html_report() {
  local out="$OUTPUT_DIR/assessment-report.html"
  local ts
  ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  local score=0
  [[ $TOTAL -gt 0 ]] && score=$(( (PASS * 100) / TOTAL ))

  cat > "$out" <<'HTMLHEAD'
<!DOCTYPE html>
<html lang="en"><head><meta charset="UTF-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>EKS Resilience Assessment</title>
<style>
*{box-sizing:border-box;margin:0;padding:0}body{font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,sans-serif;background:#f8fafc;color:#1e293b;line-height:1.6;padding:1rem;max-width:960px;margin:auto}
h1{font-size:1.5rem;margin-bottom:.5rem}h2{font-size:1.2rem;margin:1rem 0 .5rem;cursor:pointer}
.summary{background:#fff;border-radius:8px;padding:1rem;margin:1rem 0;box-shadow:0 1px 3px rgba(0,0,0,.1)}
.stats{display:flex;gap:1rem;flex-wrap:wrap;margin:.75rem 0}.stat{text-align:center;padding:.5rem 1rem;border-radius:6px;background:#f1f5f9;min-width:80px}
.stat .num{font-size:1.5rem;font-weight:700}.stat .lbl{font-size:.75rem;color:#64748b}
.bar-bg{background:#e2e8f0;border-radius:99px;height:24px;overflow:hidden;margin:.5rem 0}
.bar-fill{height:100%;border-radius:99px;transition:width .3s;display:flex;align-items:center;justify-content:center;font-size:.75rem;font-weight:600;color:#fff}
.pass{background:#22c55e}.fail{background:#ef4444}.info{background:#3b82f6}
.badge{display:inline-block;padding:2px 8px;border-radius:4px;font-size:.75rem;font-weight:600;color:#fff}
details{background:#fff;border-radius:8px;margin:.5rem 0;box-shadow:0 1px 3px rgba(0,0,0,.1)}
details>summary{padding:.75rem 1rem;cursor:pointer;font-weight:600;list-style:none}
details>summary::before{content:"▶ ";font-size:.8rem}details[open]>summary::before{content:"▼ "}
.check{border-top:1px solid #e2e8f0;padding:.75rem 1rem}.check-header{display:flex;align-items:center;gap:.5rem;flex-wrap:wrap}
.sev{font-size:.7rem;padding:1px 6px;border-radius:3px;background:#e2e8f0;color:#475569}
.findings{margin:.5rem 0;padding-left:1.2rem;font-size:.9rem;color:#475569}.remediation{font-size:.85rem;color:#334155;margin-top:.25rem}
footer{text-align:center;margin-top:2rem;font-size:.75rem;color:#94a3b8}
@media(max-width:600px){.stats{flex-direction:column}.stat{min-width:auto}}
</style></head><body>
HTMLHEAD

  # Header + summary section (written via shell variable expansion)
  cat >> "$out" <<EOF
<h1>EKS Resilience Assessment Report</h1>
<div class="summary">
<div class="stats">
<div class="stat"><div class="num">${TOTAL}</div><div class="lbl">Total</div></div>
<div class="stat"><div class="num" style="color:#22c55e">${PASS}</div><div class="lbl">Passed</div></div>
<div class="stat"><div class="num" style="color:#ef4444">${FAIL}</div><div class="lbl">Failed</div></div>
<div class="stat"><div class="num" style="color:#3b82f6">${INFO}</div><div class="lbl">Info</div></div>
<div class="stat"><div class="num">${score}%</div><div class="lbl">Score</div></div>
</div>
<div class="bar-bg"><div class="bar-fill pass" style="width:${score}%">${score}%</div></div>
</div>
EOF

  # Emit check sections by category
  local cat_id cat_title
  for cat_id in application control_plane data_plane; do
    case $cat_id in
      application)   cat_title="Application (A1–A14)" ;;
      control_plane) cat_title="Control Plane (C1–C5)" ;;
      data_plane)    cat_title="Data Plane (D1–D7)" ;;
    esac
    echo "<details open><summary>${cat_title}</summary>" >> "$out"
    for r in "${RESULTS[@]}"; do
      local rc ri rn rs rv rf rr badge_class
      rc=$(echo "$r" | jq -r '.category')
      [[ "$rc" != "$cat_id" ]] && continue
      ri=$(echo "$r" | jq -r '.id')
      rn=$(echo "$r" | jq -r '.name')
      rs=$(echo "$r" | jq -r '.status')
      rv=$(echo "$r" | jq -r '.severity')
      rf=$(echo "$r" | jq -r '.findings | if type=="array" then map(if type=="string" then . else tostring end) | .[] else tostring end')
      rr=$(echo "$r" | jq -r '.remediation')
      case $rs in PASS) badge_class="pass";; FAIL) badge_class="fail";; *) badge_class="info";; esac
      cat >> "$out" <<EOF
<div class="check"><div class="check-header"><span class="badge ${badge_class}">${rs}</span><strong>${ri}: ${rn}</strong><span class="sev">${rv}</span></div>
<ul class="findings">
EOF
      echo "$r" | jq -r '.findings | if type=="array" then .[] | if type=="string" then . else tostring end else tostring end' | while IFS= read -r line; do
        echo "<li>${line}</li>" >> "$out"
      done
      cat >> "$out" <<EOF
</ul>
<div class="remediation"><strong>Remediation:</strong> ${rr}</div></div>
EOF
    done
    echo "</details>" >> "$out"
  done

  # Footer
  cat >> "$out" <<EOF
<footer>Cluster: ${CLUSTER_NAME} | Date: ${ts} | EKS Resilience Checker v1.0</footer>
</body></html>
EOF
  log "Wrote $out"
}

generate_remediation_script() {
  local out="$OUTPUT_DIR/remediation-commands.sh"
  local ts
  ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

  # Check if there are any FAILed checks
  local has_fail=0
  for r in "${RESULTS[@]}"; do
    [[ $(echo "$r" | jq -r '.status') == "FAIL" ]] && has_fail=1 && break
  done
  if [[ $has_fail -eq 0 ]]; then
    log "No failed checks — skipping remediation script generation"
    return
  fi

  cat > "$out" <<EOF
#!/usr/bin/env bash
# Auto-generated remediation script from EKS Resilience Assessment
# Cluster: ${CLUSTER_NAME} | Date: ${ts}
# WARNING: Review each command before executing!
set -euo pipefail

CLUSTER_NAME="${CLUSTER_NAME}"
REGION="${REGION}"
EOF

  for r in "${RESULTS[@]}"; do
    local st id name
    st=$(echo "$r" | jq -r '.status')
    [[ "$st" != "FAIL" ]] && continue
    id=$(echo "$r" | jq -r '.id')
    name=$(echo "$r" | jq -r '.name')

    echo "" >> "$out"
    echo "echo \"=== ${id}: ${name} ===\"" >> "$out"

    # Emit findings as echo statements
    echo "$r" | jq -r '.findings | if type=="array" then .[] | if type=="string" then . else tostring end else tostring end' | while IFS= read -r finding; do
      echo "echo \"Found: ${finding}\"" >> "$out"
    done

    # Emit remediation commands per check ID
    case "$id" in
      A1)
        echo "$r" | jq -r '.findings // [] | .[] | if type=="object" then "\(.namespace) \(.name)" else empty end' | while read -r ns pod; do
          [[ -z "$ns" || -z "$pod" ]] && continue
          cat >> "$out" <<CMDS
# Convert singleton pod to Deployment:
# kubectl get pod ${pod} -n ${ns} -o json | jq '{apiVersion: "apps/v1", kind: "Deployment", metadata: {name: .metadata.name, namespace: .metadata.namespace}, spec: {replicas: 2, selector: {matchLabels: {app: .metadata.name}}, template: {metadata: {labels: {app: .metadata.name}}, spec: .spec}}}' > /tmp/${pod}-deployment.yaml
# kubectl apply -f /tmp/${pod}-deployment.yaml
# kubectl delete pod ${pod} -n ${ns}
CMDS
        done
        ;;
      A2)
        echo "$r" | jq -r '.findings // [] | .[] | if type=="object" then "\(.namespace) \(.name) \(.kind)" else empty end' | while read -r ns wname kind; do
          [[ -z "$ns" || -z "$wname" ]] && continue
          local klow
          klow=$(echo "${kind:-deployment}" | tr '[:upper:]' '[:lower:]')
          echo "kubectl scale ${klow} ${wname} --replicas=2 -n ${ns}" >> "$out"
        done
        ;;
      A3)
        echo "$r" | jq -r '.findings // [] | .[] | if type=="object" then "\(.namespace) \(.name)" else empty end' | while read -r ns dep; do
          [[ -z "$ns" || -z "$dep" ]] && continue
          cat >> "$out" <<CMDS
kubectl patch deployment ${dep} -n ${ns} --type=strategic -p '{"spec":{"template":{"spec":{"affinity":{"podAntiAffinity":{"preferredDuringSchedulingIgnoredDuringExecution":[{"weight":100,"podAffinityTerm":{"labelSelector":{"matchExpressions":[{"key":"app","operator":"In","values":["${dep}"]}]},"topologyKey":"kubernetes.io/hostname"}}]}}}}}}'
CMDS
        done
        ;;
      A4)
        echo "$r" | jq -r '.findings // [] | .[] | if type=="object" then "\(.namespace) \(.name)" else empty end' | while read -r ns dep; do
          [[ -z "$ns" || -z "$dep" ]] && continue
          cat >> "$out" <<CMDS
# Add liveness probes — adjust path/port for your application:
# kubectl patch deployment ${dep} -n ${ns} --type=strategic -p '{"spec":{"template":{"spec":{"containers":[{"name":"CONTAINER_NAME","livenessProbe":{"httpGet":{"path":"/healthz","port":8080},"initialDelaySeconds":15,"periodSeconds":10,"timeoutSeconds":5,"failureThreshold":3}}]}}}}'
CMDS
        done
        ;;
      A5)
        echo "$r" | jq -r '.findings // [] | .[] | if type=="object" then "\(.namespace) \(.name)" else empty end' | while read -r ns dep; do
          [[ -z "$ns" || -z "$dep" ]] && continue
          cat >> "$out" <<CMDS
# Add readiness probes — adjust path/port for your application:
# kubectl patch deployment ${dep} -n ${ns} --type=strategic -p '{"spec":{"template":{"spec":{"containers":[{"name":"CONTAINER_NAME","readinessProbe":{"httpGet":{"path":"/ready","port":8080},"initialDelaySeconds":5,"periodSeconds":5,"timeoutSeconds":3,"failureThreshold":3}}]}}}}'
CMDS
        done
        ;;
      A6)
        echo "$r" | jq -r '.findings // [] | .[] | if type=="object" then "\(.namespace) \(.name)" else empty end' | while read -r ns wname; do
          [[ -z "$ns" || -z "$wname" ]] && continue
          cat >> "$out" <<CMDS
cat <<PDBEOF | kubectl apply -f -
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: ${wname}-pdb
  namespace: ${ns}
spec:
  minAvailable: 1
  selector:
    matchLabels:
      app: ${wname}
PDBEOF
CMDS
        done
        ;;
      A7)
        cat >> "$out" <<CMDS
# Install metrics-server as EKS managed add-on (recommended):
aws eks create-addon --cluster-name "\$CLUSTER_NAME" --addon-name metrics-server --region "\$REGION"
# Or install via kubectl:
# kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
CMDS
        ;;
      A8)
        echo "$r" | jq -r '.findings // [] | .[] | if type=="object" then "\(.namespace) \(.name)" else empty end' | while read -r ns dep; do
          [[ -z "$ns" || -z "$dep" ]] && continue
          echo "kubectl autoscale deployment ${dep} -n ${ns} --min=2 --max=10 --cpu-percent=70" >> "$out"
        done
        ;;
      A11)
        echo "$r" | jq -r '.findings // [] | .[] | if type=="object" then "\(.namespace) \(.name)" else empty end' | while read -r ns dep; do
          [[ -z "$ns" || -z "$dep" ]] && continue
          cat >> "$out" <<CMDS
# Add preStop hook for graceful termination:
# kubectl patch deployment ${dep} -n ${ns} --type=strategic -p '{"spec":{"template":{"spec":{"containers":[{"name":"CONTAINER_NAME","lifecycle":{"preStop":{"exec":{"command":["/bin/sh","-c","sleep 10"]}}}}]}}}}'
CMDS
        done
        ;;
      A13)
        cat >> "$out" <<CMDS
# Install monitoring — option A: CloudWatch Container Insights
aws eks create-addon --cluster-name "\$CLUSTER_NAME" --addon-name amazon-cloudwatch-observability --region "\$REGION"
# Option B: Prometheus stack via Helm
# helm repo add prometheus-community https://prometheus-community.github.io/helm-charts && helm repo update
# helm install prometheus prometheus-community/kube-prometheus-stack --namespace monitoring --create-namespace
CMDS
        ;;
      A14)
        cat >> "$out" <<CMDS
# Install centralized logging — Fluent Bit as EKS add-on
aws eks create-addon --cluster-name "\$CLUSTER_NAME" --addon-name aws-for-fluent-bit --region "\$REGION"
# Or via Helm:
# helm repo add fluent https://fluent.github.io/helm-charts && helm repo update
# helm install fluent-bit fluent/fluent-bit --namespace logging --create-namespace --set output.cloudwatch.enabled=true --set output.cloudwatch.region="\$REGION"
CMDS
        ;;
      C1)
        cat >> "$out" <<CMDS
aws eks update-cluster-config --name "\$CLUSTER_NAME" --region "\$REGION" \
  --logging '{"clusterLogging":[{"types":["api","audit","authenticator","controllerManager","scheduler"],"enabled":true}]}'
CMDS
        ;;
      C2)
        cat >> "$out" <<CMDS
# Configure EKS Access Entries (replace ACCOUNT_ID and ROLE_NAME):
# aws eks create-access-entry --cluster-name "\$CLUSTER_NAME" --region "\$REGION" --principal-arn "arn:aws:iam::ACCOUNT_ID:role/ROLE_NAME" --type STANDARD
CMDS
        ;;
      C4)
        cat >> "$out" <<CMDS
# Restrict public endpoint — option A: private only
aws eks update-cluster-config --name "\$CLUSTER_NAME" --region "\$REGION" \
  --resources-vpc-config endpointPublicAccess=false,endpointPrivateAccess=true
# Option B: restrict CIDR (replace YOUR_CIDR):
# aws eks update-cluster-config --name "\$CLUSTER_NAME" --region "\$REGION" \
#   --resources-vpc-config endpointPublicAccess=true,endpointPrivateAccess=true,publicAccessCidrs="YOUR_CIDR/32"
CMDS
        ;;
      C5)
        echo "$r" | jq -r '.findings // [] | .[] | if type=="object" then .name else empty end' | while IFS= read -r whname; do
          [[ -z "$whname" ]] && continue
          cat >> "$out" <<CMDS
# Narrow webhook scope for: ${whname}
# kubectl patch mutatingwebhookconfiguration ${whname} --type=json -p '[{"op":"add","path":"/webhooks/0/namespaceSelector","value":{"matchExpressions":[{"key":"kubernetes.io/metadata.name","operator":"NotIn","values":["kube-system","kube-public","kube-node-lease"]}]}}]'
CMDS
        done
        ;;
      D1)
        cat >> "$out" <<CMDS
# Install Karpenter (recommended) — see https://karpenter.sh/docs/getting-started/
# Or install Cluster Autoscaler:
# helm repo add autoscaler https://kubernetes.github.io/autoscaler
# helm install cluster-autoscaler autoscaler/cluster-autoscaler --namespace kube-system --set autoDiscovery.clusterName="\$CLUSTER_NAME" --set awsRegion="\$REGION"
CMDS
        ;;
      D2)
        cat >> "$out" <<CMDS
# Create a multi-AZ node group (replace SUBNET IDs):
# aws eks create-nodegroup --cluster-name "\$CLUSTER_NAME" --region "\$REGION" \
#   --nodegroup-name "multi-az-ng" --subnets "subnet-az-a" "subnet-az-c" "subnet-az-d" \
#   --instance-types "m5.large" --scaling-config minSize=3,maxSize=9,desiredSize=6
CMDS
        ;;
      D3)
        echo "$r" | jq -r '.findings // [] | .[] | if type=="object" then "\(.namespace) \(.name)" else empty end' | while read -r ns dep; do
          [[ -z "$ns" || -z "$dep" ]] && continue
          cat >> "$out" <<CMDS
# Set resource requests/limits — adjust values for your workload:
# kubectl patch deployment ${dep} -n ${ns} --type=strategic -p '{"spec":{"template":{"spec":{"containers":[{"name":"CONTAINER_NAME","resources":{"requests":{"cpu":"100m","memory":"128Mi"},"limits":{"cpu":"500m","memory":"512Mi"}}}]}}}}'
CMDS
        done
        ;;
      D4)
        echo "$r" | jq -r '.findings // [] | if type=="array" then .[] else empty end' | while IFS= read -r ns; do
          [[ -z "$ns" ]] && continue
          cat >> "$out" <<CMDS
cat <<RQEOF | kubectl apply -f -
apiVersion: v1
kind: ResourceQuota
metadata:
  name: default-quota
  namespace: ${ns}
spec:
  hard:
    requests.cpu: "10"
    requests.memory: "20Gi"
    limits.cpu: "20"
    limits.memory: "40Gi"
    pods: "50"
RQEOF
CMDS
        done
        ;;
      D5)
        echo "$r" | jq -r '.findings // [] | if type=="array" then .[] else empty end' | while IFS= read -r ns; do
          [[ -z "$ns" ]] && continue
          cat >> "$out" <<CMDS
cat <<LREOF | kubectl apply -f -
apiVersion: v1
kind: LimitRange
metadata:
  name: default-limits
  namespace: ${ns}
spec:
  limits:
  - type: Container
    default:
      cpu: "500m"
      memory: "256Mi"
    defaultRequest:
      cpu: "100m"
      memory: "128Mi"
LREOF
CMDS
        done
        ;;
      D6)
        cat >> "$out" <<CMDS
# Set up CoreDNS metrics monitoring via ServiceMonitor or annotations:
kubectl annotate service kube-dns -n kube-system prometheus.io/scrape="true" prometheus.io/port="9153" --overwrite
CMDS
        ;;
    esac
  done

  chmod +x "$out"
  log "Wrote $out"
}

print_summary() {
  echo ""
  echo "=========================================="
  echo " EKS Resilience Assessment — $CLUSTER_NAME"
  echo "=========================================="
  echo " PASS: $PASS / $TOTAL"
  echo " FAIL: $FAIL / $TOTAL"
  echo " INFO: $INFO / $TOTAL"
  echo "=========================================="
  echo " Output: $OUTPUT_DIR/assessment.json"
  echo "         $OUTPUT_DIR/assessment-report.md"
  echo "         $OUTPUT_DIR/assessment-report.html"
  [[ -f "$OUTPUT_DIR/remediation-commands.sh" ]] && \
  echo "         $OUTPUT_DIR/remediation-commands.sh"
  echo "=========================================="
}

###############################################################################
# Main
###############################################################################

main() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --cluster)    CLUSTER_NAME="$2"; shift 2 ;;
      --region)     REGION="$2"; shift 2 ;;
      --namespaces) NAMESPACES="$2"; shift 2 ;;
      --output-dir) OUTPUT_DIR="$2"; shift 2 ;;
      -h|--help)    usage ;;
      *)            die "Unknown option: $1" ;;
    esac
  done

  check_deps
  discover_cluster
  get_namespaces
  mkdir -p "$OUTPUT_DIR"

  # Application checks
  check_a1; check_a2; check_a3; check_a4; check_a5
  check_a6; check_a7; check_a8; check_a9; check_a10
  check_a11; check_a12; check_a13; check_a14

  # Control plane checks
  check_c1; check_c2; check_c3; check_c4; check_c5

  # Data plane checks
  check_d1; check_d2; check_d3; check_d4; check_d5
  check_d6; check_d7

  write_json
  write_report
  generate_html_report
  generate_remediation_script
  print_summary
}

main "$@"
