#!/usr/bin/env bash
# Offline test for log-collector.sh with a stubbed kubectl: the classic
# --namespace path and the --app-map path (several namespaces, two clusters,
# non-Deployment kinds, unverified entries skipped).
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$HERE/../log-collector.sh"
WORK=$(mktemp -d "${TMPDIR:-/tmp}/test-logcol-XXXXXX")
trap 'rm -rf "$WORK"' EXIT
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  ✅ $1"; }
bad() { FAIL=$((FAIL+1)); echo "  ❌ $1"; }
check() { if [[ "$(jq -r -s "$2" "$3" 2>/dev/null)" == "true" ]]; then ok "$1"; else bad "$1  [filter: $2]"; fi; }

BIN="$WORK/bin"; mkdir -p "$BIN"
# Stub: records every call; answers per (kubeconfig, namespace, kind).
cat > "$BIN/kubectl" <<'EOF'
#!/usr/bin/env bash
echo "$*" >> "$STUB_LOG"
kc="none"; ns=""; args=("$@")
for ((i=0; i<${#args[@]}; i++)); do
  [[ "${args[$i]}" == "--kubeconfig" ]] && kc="$(basename "${args[$((i+1))]}")"
  [[ "${args[$i]}" == "-n" ]] && ns="${args[$((i+1))]}"
done
case "$*" in
  *"get deployments -n shop"*)                echo -n "cart web" ;;
  *"get pods -l app=cart -n shop"*)           echo -n "cart-1" ;;
  *"get pods -l app=web -n shop"*)            echo -n "" ;;
  *"get deployment web -n shop"*)             echo -n '{"tier":"web"}' ;;
  *"get pods -l tier=web -n shop"*)           echo -n "web-1" ;;
  *"get pods -l app=payment-api -n payments"*) [[ "$kc" == "eks-a.kubeconfig" ]] && echo -n "pay-1" ;;
  *"get statefulset queue-worker -n jobs"*)   [[ "$kc" == "eks-b.kubeconfig" ]] && echo -n '{"app.kubernetes.io/name":"qw"}' ;;
  *"get pods -l app.kubernetes.io/name=qw -n jobs"*) echo -n "queue-worker-0" ;;
  *"logs --since-time="*)
      pod="${args[$((${#args[@]}-3))]}"
      echo "2026-11-09T08:00:01Z INFO started $pod ns=$ns kc=$kc"
      echo "2026-11-09T08:00:05Z ERROR connection refused to db ($pod)" ;;
  *) : ;;
esac
EOF
chmod +x "$BIN/kubectl"
export STUB_LOG="$WORK/calls.log"

echo "【log-collector】classic --namespace path"
: > "$STUB_LOG"
PATH="$BIN:$PATH" bash "$SCRIPT" --namespace shop --mode post --since 2026-11-09T08:00:00Z --output-dir "$WORK/o1" 2>"$WORK/e1"
L1="$WORK/o1/monitoring/step5-logs.jsonl"
check "both deployments collected (label app= and selector fallback)" '[.[].pod] | unique == ["cart-1","web-1"]' "$L1"
check "namespace field present" 'all(.[]; .namespace == "shop")' "$L1"
check "no cluster field without app-map" 'all(.[]; has("cluster") | not)' "$L1"
grep -q -- '--kubeconfig' "$STUB_LOG" && bad "classic path must not pass --kubeconfig" || ok "classic path uses the current context"
check "summary counts the connection error" '.[0].error_counts.connection == 2' "$WORK/o1/monitoring/step5-log-summary.json"

echo "【log-collector】--app-map path"
cat > "$WORK/app-map.json" <<EOF
[
 {"cluster":"eks-a","kubeconfig":"$WORK/kc/eks-a.kubeconfig","namespace":"payments","kind":"Deployment","workload":"payment-api","resources":["orders-aurora"],"status":"verified"},
 {"cluster":"eks-b","kubeconfig":"$WORK/kc/eks-b.kubeconfig","namespace":"jobs","kind":"StatefulSet","workload":"queue-worker","resources":["sessions-rg"],"status":"confirmed"},
 {"cluster":"","kubeconfig":"","namespace":"legacy","kind":"Pod","workload":"batch","resources":["i-0abc"],"status":"verified"},
 {"cluster":"eks-a","kubeconfig":"$WORK/kc/eks-a.kubeconfig","namespace":"billing","kind":"Deployment","workload":"billing-api","resources":["orders-aurora"],"status":"unverified"}
]
EOF
: > "$STUB_LOG"
PATH="$BIN:$PATH" bash "$SCRIPT" --app-map "$WORK/app-map.json" --mode post --since 2026-11-09T08:00:00Z --output-dir "$WORK/o2" 2>"$WORK/e2"
rc=$?
L2="$WORK/o2/monitoring/step5-logs.jsonl"
[[ $rc -eq 0 ]] && ok "exit code 0" || { bad "exit code $rc"; tail -5 "$WORK/e2"; }
check "verified + confirmed entries collected, unverified skipped" '[.[].service] | unique == ["batch","payment-api","queue-worker"]' "$L2"
check "each line tagged with its own namespace" \
      '([.[] | select(.service=="payment-api") | .namespace] | unique) == ["payments"] and ([.[] | select(.service=="queue-worker") | .namespace] | unique) == ["jobs"]' "$L2"
check "cluster field set where the map has one" \
      '([.[] | select(.service=="queue-worker") | .cluster] | unique) == ["eks-b"] and all(.[] | select(.service=="batch"); has("cluster") | not)' "$L2"
check "logs fetched through each workload's own kubeconfig" \
      'any(.[]; .service=="payment-api" and (.message|test("kc=eks-a.kubeconfig"))) and any(.[]; .service=="queue-worker" and (.message|test("kc=eks-b.kubeconfig"))) and any(.[]; .service=="batch" and (.message|test("kc=none")))' "$L2"
grep -q 'billing' "$STUB_LOG" && bad "unverified entry must not be queried" || ok "unverified entry never queried"
grep -q 'unverified app-map entr' "$WORK/e2" && ok "skipped unverified entry is announced" || bad "no notice for skipped entry"
check "summary namespace lists all namespaces" '.[0].namespace == "jobs,legacy,payments"' "$WORK/o2/monitoring/step5-log-summary.json"

echo "【log-collector】argument checks"
PATH="$BIN:$PATH" bash "$SCRIPT" --mode post --since x --output-dir "$WORK/o3" 2>/dev/null && bad "no --namespace/--app-map must fail" || ok "missing --namespace and --app-map rejected"
PATH="$BIN:$PATH" bash "$SCRIPT" --app-map "$WORK/nope.json" --output-dir "$WORK/o3" 2>/dev/null && bad "missing app-map file must fail" || ok "missing app-map file rejected"

echo "  结果: $PASS passed, $FAIL failed"
exit $FAIL
