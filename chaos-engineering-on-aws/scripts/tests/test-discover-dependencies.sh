#!/usr/bin/env bash
# Offline regression test for discover-dependencies.sh (needs bash + jq only).
# Builds a three-cluster fixture covering every discovery route and every
# false-positive trap the matcher is meant to reject, then asserts the result.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$HERE/../discover-dependencies.sh"
WORK=$(mktemp -d "${TMPDIR:-/tmp}/test-discover-XXXXXX")
trap 'rm -rf "$WORK"' EXIT
FX="$WORK/fx"; OUT="$WORK/out"
mkdir -p "$FX/clusters/eks-prod" "$FX/clusters/eks-staging" "$FX/clusters/eks-private"

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  ✅ $1"; }
bad() { FAIL=$((FAIL+1)); echo "  ❌ $1"; }
check() { # description, jq filter that must output true, file
    if [[ "$(jq -r "$2" "$3" 2>/dev/null)" == "true" ]]; then ok "$1"; else bad "$1  [filter: $2]"; fi
}

cat > "$FX/resources.json" <<'EOF'
[
 {"type":"rds-cluster","id":"orders-aurora","loose":"orders-aurora","patterns":[
   {"kind":"host","value":"orders-aurora.cluster-abc123.us-east-1.rds.amazonaws.com"},
   {"kind":"host","value":"orders-aurora.cluster-ro-abc123.us-east-1.rds.amazonaws.com"},
   {"kind":"host","value":"orders-aurora-instance-1.abc123.us-east-1.rds.amazonaws.com"},
   {"kind":"id","value":"orders-aurora"}]},
 {"type":"elasticache","id":"sessions-rg","loose":"sessions-rg","patterns":[
   {"kind":"host","value":"master.sessions-rg.xyz789.use1.cache.amazonaws.com"},
   {"kind":"host","value":"replica.sessions-rg.xyz789.use1.cache.amazonaws.com"},
   {"kind":"id","value":"sessions-rg"}]},
 {"type":"ec2","id":"i-0abc1234","loose":null,"patterns":[
   {"kind":"host","value":"ip-10-0-1-25.ec2.internal"},
   {"kind":"ip","value":"10.0.1.25"}]}
]
EOF

# --- eks-prod: every route ----------------------------------------------------
cat > "$FX/clusters/eks-prod/replicasets.json" <<'EOF'
[
 {"metadata":{"namespace":"payments","name":"payment-api-7d9f","ownerReferences":[{"kind":"Deployment","name":"payment-api"}]}},
 {"metadata":{"namespace":"orders","name":"order-service-55c","ownerReferences":[{"kind":"Deployment","name":"order-service"}]}},
 {"metadata":{"namespace":"users","name":"user-service-1a2","ownerReferences":[{"kind":"Deployment","name":"user-service"}]}},
 {"metadata":{"namespace":"billing","name":"billing-api-9f8","ownerReferences":[{"kind":"Deployment","name":"billing-api"}]}},
 {"metadata":{"namespace":"sessions","name":"session-mgr-3b4","ownerReferences":[{"kind":"Deployment","name":"session-mgr"}]}}
]
EOF
cat > "$FX/clusters/eks-prod/pods.json" <<'EOF'
[
 {"metadata":{"namespace":"payments","name":"payment-api-7d9f-x1","ownerReferences":[{"kind":"ReplicaSet","name":"payment-api-7d9f"}]},
  "spec":{"containers":[{"name":"app","env":[
     {"name":"DB_HOST","value":"orders-aurora.cluster-abc123.us-east-1.rds.amazonaws.com"},
     {"name":"REDIS_URL","value":"redis://:p4ssw0rd@master.sessions-rg.xyz789.use1.cache.amazonaws.com:6379/0"}],"envFrom":[]}],"volumes":[]}},
 {"metadata":{"namespace":"payments","name":"payment-api-7d9f-x2","ownerReferences":[{"kind":"ReplicaSet","name":"payment-api-7d9f"}]},
  "spec":{"containers":[{"name":"app","env":[
     {"name":"DB_HOST","value":"orders-aurora.cluster-abc123.us-east-1.rds.amazonaws.com"}],"envFrom":[]}],"volumes":[]}},
 {"metadata":{"namespace":"orders","name":"order-service-55c-a","ownerReferences":[{"kind":"ReplicaSet","name":"order-service-55c"}]},
  "spec":{"containers":[{"name":"app","env":[],"envFrom":[{"configMapRef":{"name":"app-config"}}]}],"volumes":[]}},
 {"metadata":{"namespace":"users","name":"user-service-1a2-b","ownerReferences":[{"kind":"ReplicaSet","name":"user-service-1a2"}]},
  "spec":{"containers":[{"name":"app","env":[
     {"name":"DB_HOST","value":"orders-aurora-replica.cluster-abc123.us-east-1.rds.amazonaws.com"},
     {"name":"SHADOW_DB","value":"shadow-orders-aurora.cluster-abc123.us-east-1.rds.amazonaws.com"}],"envFrom":[]}],"volumes":[]}},
 {"metadata":{"namespace":"billing","name":"billing-api-9f8-c","ownerReferences":[{"kind":"ReplicaSet","name":"billing-api-9f8"}]},
  "spec":{"containers":[{"name":"app","env":[
     {"name":"DB_PASSWORD","valueFrom":{"secretKeyRef":{"name":"billing-db","key":"password"}}}],
     "envFrom":[{"secretRef":{"name":"billing-db"}}]}],"volumes":[]}},
 {"metadata":{"namespace":"sessions","name":"session-mgr-3b4-d","ownerReferences":[{"kind":"ReplicaSet","name":"session-mgr-3b4"}]},
  "spec":{"containers":[{"name":"app","env":[{"name":"REDIS_HOST","value":"redis-primary"}],"envFrom":[]}],"volumes":[]}},
 {"metadata":{"namespace":"other","name":"local-redis-client","ownerReferences":[]},
  "spec":{"containers":[{"name":"app","env":[{"name":"REDIS_HOST","value":"redis-primary"}],"envFrom":[]}],"volumes":[]}},
 {"metadata":{"namespace":"jobs","name":"queue-worker-0","ownerReferences":[{"kind":"StatefulSet","name":"queue-worker"}]},
  "spec":{"containers":[{"name":"worker","env":[
     {"name":"CACHE","value":"redis-primary.sessions.svc.cluster.local:6379"},
     {"name":"REGION_TAG","valueFrom":{"configMapKeyRef":{"name":"worker-cfg","key":"tag"}}}],"envFrom":[]}],"volumes":[]}},
 {"metadata":{"namespace":"legacy","name":"batch","ownerReferences":[]},
  "spec":{"containers":[{"name":"batch","env":[{"name":"OTHER_HOST","value":"10.0.1.250"}],"envFrom":[]}],
          "volumes":[{"name":"cfg","configMap":{"name":"legacy-cfg"},"secret":null,"projected":null},
                     {"name":"proj","configMap":null,"secret":null,"projected":{"sources":[{"configMap":{"name":"legacy-extra"}}]}}]}}
]
EOF
cat > "$FX/clusters/eks-prod/configmaps.json" <<'EOF'
[
 {"metadata":{"namespace":"orders","name":"app-config"},"data":{
   "DATABASE_URL":"jdbc:mysql://orders-aurora.cluster-ro-abc123.us-east-1.rds.amazonaws.com:3306/orders?user=app&password=hunter2",
   "LOG_LEVEL":"info"}},
 {"metadata":{"namespace":"jobs","name":"worker-cfg"},"data":{"tag":"blue","unused":"orders-aurora.cluster-abc123.us-east-1.rds.amazonaws.com"}},
 {"metadata":{"namespace":"legacy","name":"legacy-cfg"},"data":{"app.yml":"server:\n  name: batch\nupstream:\n  host: 10.0.1.25\n  port: 8080\n"}},
 {"metadata":{"namespace":"legacy","name":"legacy-extra"},"data":{"x":"nothing here"}},
 {"metadata":{"namespace":"default","name":"old-config"},"data":{"DB":"orders-aurora.cluster-abc123.us-east-1.rds.amazonaws.com"}}
]
EOF
cat > "$FX/clusters/eks-prod/services.json" <<'EOF'
[ {"namespace":"sessions","name":"redis-primary","externalName":"master.sessions-rg.xyz789.use1.cache.amazonaws.com"} ]
EOF
cat > "$FX/clusters/eks-prod/secret-keys.json" <<'EOF'
[ {"namespace":"billing","name":"billing-db","keys":["DB_HOST","password"]} ]
EOF

# --- eks-staging: accessible, nothing depends ----------------------------------
cat > "$FX/clusters/eks-staging/pods.json" <<'EOF'
[ {"metadata":{"namespace":"web","name":"web-0","ownerReferences":[]},
   "spec":{"containers":[{"name":"web","env":[{"name":"DB_HOST","value":"staging-db.cluster-zzz.us-east-1.rds.amazonaws.com"}],"envFrom":[]}],"volumes":[]}} ]
EOF

# --- eks-private: not reachable -------------------------------------------------
echo '{"name":"eks-private","accessible":false,"reason":"API not reachable or not authorized: i/o timeout"}' > "$FX/clusters/eks-private/status.json"

echo "【discover-dependencies】fixture run"
bash "$SCRIPT" --fixtures "$FX" --output-dir "$OUT" 2> "$WORK/stderr.txt"
rc=$?
D="$OUT/checkpoints/step2-dependencies.json"; M="$OUT/monitoring/app-map.json"
[[ $rc -eq 0 ]] && ok "exit code 0" || { bad "exit code $rc"; cat "$WORK/stderr.txt"; }
[[ -s "$D" && -s "$M" ]] && ok "both output files written" || bad "output files missing"

dep() { echo "[.dependencies[] | select(.cluster==\"eks-prod\" and .namespace==\"$1\" and .kind==\"$2\" and .workload==\"$3\" and .resource==\"$4\")] | length == 1 and .[0].status == \"$5\""; }
check "env value -> Deployment via ReplicaSet (2 pods, 1 entry)"  "$(dep payments Deployment payment-api orders-aurora verified)" "$D"
check "envFrom ConfigMap -> verified"                              "$(dep orders Deployment order-service orders-aurora verified)" "$D"
check "Secret key name only -> unverified"                         "$(dep billing Deployment billing-api orders-aurora unverified)" "$D"
check "URL with credentials -> verified for ElastiCache"           "$(dep payments Deployment payment-api sessions-rg verified)" "$D"
check "ExternalName Service itself is listed"                      "$(dep sessions Service redis-primary sessions-rg verified)" "$D"
check "FQDN of ExternalName from another namespace -> verified"    "$(dep jobs StatefulSet queue-worker sessions-rg verified)" "$D"
check "bare ExternalName name in its namespace -> unverified"      "$(dep sessions Deployment session-mgr sessions-rg unverified)" "$D"
check "ConfigMap volume, multi-line file, IP -> bare Pod"          "$(dep legacy Pod batch i-0abc1234 verified)" "$D"
check "exactly 8 dependencies"                                     '.dependencies | length == 8' "$D"

check "trap: orders-aurora-replica / shadow-orders-aurora.* are near misses, not dependencies" \
      '([.dependencies[] | select(.workload=="user-service")] | length == 0) and ([.near_misses[] | select(.workload=="user-service" and .resource=="orders-aurora")] | length == 2)' "$D"
check "trap: 10.0.1.250 does not match 10.0.1.25" \
      '[.dependencies[] | select(.workload=="batch") | .sources[] | select(.source | test("OTHER_HOST"))] | length == 0' "$D"
check "trap: configMapKeyRef to an unrelated key is not followed" \
      '[.dependencies[] | select(.workload=="queue-worker" and .resource=="orders-aurora")] | length == 0' "$D"
check "trap: bare Service name in a different namespace is not matched" \
      '[.dependencies[] | select(.namespace=="other")] | length == 0' "$D"
check "trap: staging-db in eks-staging matches nothing" \
      '[.dependencies[] | select(.cluster=="eks-staging")] | length == 0' "$D"
check "ConfigMap with a match but no consumer is reported" \
      '[.unreferenced_configmaps[] | select(.configmap=="default/old-config")] | length == 1' "$D"
check "inaccessible cluster recorded with reason" \
      '[.clusters[] | select(.name=="eks-private" and .accessible==false and (.reason|test("timeout")))] | length == 1' "$D"

check "redaction: URL password removed" \
      '[.. | strings | select(test("p4ssw0rd"))] | length == 0' "$D"
check "redaction: query-string password removed" \
      '[.. | strings | select(test("hunter2"))] | length == 0' "$D"
check "evidence keeps only the matching line of a multi-line file" \
      '[.dependencies[] | select(.workload=="batch") | .sources[0].evidence] | .[0] | (test("10.0.1.25") and (test("server:") | not))' "$D"

check "app-map: 6 workloads, Services excluded" 'length == 6 and ([.[] | select(.kind=="Service")] | length == 0)' "$M"
check "app-map: payment-api carries both resources" \
      '[.[] | select(.workload=="payment-api") | .resources] == [["orders-aurora","sessions-rg"]]' "$M"
check "app-map: unverified entries keep status unverified" \
      '[.[] | select(.status=="unverified") | .workload] | sort == ["billing-api","session-mgr"]' "$M"

echo "【discover-dependencies】live plumbing with stubbed aws/kubectl"
# Exercises endpoint resolution, isolated kubeconfig, raw-List slimming and the
# keys-only Secret listing — the code paths fixture mode skips.
BIN="$WORK/bin"; mkdir -p "$BIN"
cat > "$BIN/aws" <<'EOF'
#!/usr/bin/env bash
case "$1 $2" in
  "eks list-clusters")        echo '{"clusters":["eks-a","eks-down"]}' ;;
  "eks update-kubeconfig")    while [[ $# -gt 0 ]]; do [[ "$1" == "--kubeconfig" ]] && : > "$2"; [[ "$1" == "--name" ]] && n="$2"; shift; done
                              [[ "$n" == "eks-down" ]] && { echo "AccessDenied" >&2; exit 254; }; exit 0 ;;
  "rds describe-db-clusters") echo '{"DBClusters":[{"Endpoint":"orders-aurora.cluster-abc123.us-east-1.rds.amazonaws.com","ReaderEndpoint":"orders-aurora.cluster-ro-abc123.us-east-1.rds.amazonaws.com","CustomEndpoints":[]}]}' ;;
  "rds describe-db-instances") echo '{"DBInstances":[{"Endpoint":{"Address":"orders-aurora-instance-1.abc123.us-east-1.rds.amazonaws.com"}}]}' ;;
  "elasticache describe-replication-groups") echo '{"ReplicationGroups":[{"NodeGroups":[{"PrimaryEndpoint":{"Address":"master.sessions-rg.xyz789.use1.cache.amazonaws.com"},"ReaderEndpoint":{"Address":"replica.sessions-rg.xyz789.use1.cache.amazonaws.com"},"NodeGroupMembers":[{"ReadEndpoint":{"Address":"sessions-rg-001.sessions-rg.xyz789.use1.cache.amazonaws.com"}}]}]}]}' ;;
  *) echo "stub aws: unexpected $*" >&2; exit 1 ;;
esac
EOF
cat > "$BIN/kubectl" <<'EOF'
#!/usr/bin/env bash
args="$*"
[[ "$args" == *"~/.kube/config"* || "$args" != *"--kubeconfig"* ]] && { echo "stub kubectl: missing --kubeconfig" >&2; exit 9; }
case "$args" in
  *"get namespaces"*) echo "namespace/default" ;;
  *"get nodes"*)      printf 'node/a\nnode/b\n' ;;
  *"get pods"*)       echo '{"kind":"List","items":[{"metadata":{"namespace":"shop","name":"cart-6f-a","uid":"u1","ownerReferences":[{"kind":"ReplicaSet","name":"cart-6f","uid":"r1"}]},"spec":{"nodeName":"n1","containers":[{"name":"cart","image":"x","env":[{"name":"DB","valueFrom":{"secretKeyRef":{"name":"cart-db","key":"DB_HOST"}}}],"resources":{}}],"initContainers":[{"name":"migrate","image":"y","env":[{"name":"DB_URL","value":"postgres://u:pw@orders-aurora.cluster-abc123.us-east-1.rds.amazonaws.com:5432/x"}]}],"volumes":[{"name":"kube-api-access","projected":{"sources":[{"serviceAccountToken":{"path":"token"}}]}}]},"status":{"phase":"Running"}}]}' ;;
  *"get replicasets"*) echo '{"items":[{"metadata":{"namespace":"shop","name":"cart-6f","ownerReferences":[{"kind":"Deployment","name":"cart"}]}}]}' ;;
  *"get configmaps"*) echo '{"items":[{"metadata":{"namespace":"kube-system","name":"aws-auth"},"data":{"mapRoles":"- rolearn: x"}}]}' ;;
  *"get services"*)   echo '{"items":[{"metadata":{"namespace":"shop","name":"cache"},"spec":{"type":"ExternalName","externalName":"master.sessions-rg.xyz789.use1.cache.amazonaws.com"}},{"metadata":{"namespace":"shop","name":"web"},"spec":{"type":"ClusterIP"}}]}' ;;
  *"get secrets"*)    [[ "$args" == *"go-template"* ]] || { echo "stub kubectl: secrets must be listed with go-template (keys only)" >&2; exit 9; }
                      printf 'shop\tcart-db\tDB_HOST,DB_PASSWORD,\n' ;;
  *) echo "stub kubectl: unexpected $args" >&2; exit 1 ;;
esac
EOF
chmod +x "$BIN/aws" "$BIN/kubectl"
PATH="$BIN:$PATH" bash "$SCRIPT" --region us-east-1 --resource rds-cluster:orders-aurora --resource elasticache:sessions-rg \
    --scan-secret-keys --output-dir "$WORK/live" 2> "$WORK/live.stderr"
rc=$?; L="$WORK/live/checkpoints/step2-dependencies.json"
[[ $rc -eq 0 ]] && ok "live: exit code 0" || { bad "live: exit code $rc"; tail -5 "$WORK/live.stderr"; }
check "live: endpoints resolved from AWS (3 rds hosts + id, 3 cache hosts + id)" \
      '([.resources[] | select(.id=="orders-aurora") | .patterns | length] == [4]) and ([.resources[] | select(.id=="sessions-rg") | .patterns | length] == [4])' "$L"
check "live: initContainer env found, ReplicaSet resolved to Deployment" \
      '[.dependencies[] | select(.workload=="cart" and .kind=="Deployment" and .resource=="orders-aurora" and .status=="verified")] | length == 1' "$L"
check "live: Secret key names read (unverified), no value captured" \
      '([.dependencies[] | select(.workload=="cart") | .sources[] | select(.source|test("secret cart-db:DB_HOST"))] | length == 1) and ([.. | strings | select(test(":pw@"))] | length == 0)' "$L"
check "live: ExternalName picked out of mixed Service list" \
      '[.dependencies[] | select(.kind=="Service" and .workload=="cache")] | length == 1' "$L"
check "live: cluster failing update-kubeconfig is reported, scan continues" \
      '[.clusters[] | select(.name=="eks-down" and .accessible==false and (.reason|test("AccessDenied")))] | length == 1' "$L"
[[ -f "$WORK/live/kubeconfigs/eks-a.kubeconfig" ]] && ok "live: isolated kubeconfig written under output dir" || bad "live: kubeconfig file missing"
check "live: app-map carries the kubeconfig path" \
      '[.[] | select(.workload=="cart") | .kubeconfig | test("kubeconfigs/eks-a.kubeconfig$")] == [true]' "$WORK/live/monitoring/app-map.json"

echo "【discover-dependencies】no reachable cluster -> exit 2"
rm -rf "$FX/clusters/eks-prod" "$FX/clusters/eks-staging"
bash "$SCRIPT" --fixtures "$FX" --output-dir "$WORK/out2" 2>/dev/null
rc=$?
[[ $rc -eq 2 ]] && ok "exit 2 when nothing could be scanned" || bad "expected exit 2, got $rc"

echo "  结果: $PASS passed, $FAIL failed"
exit $FAIL
