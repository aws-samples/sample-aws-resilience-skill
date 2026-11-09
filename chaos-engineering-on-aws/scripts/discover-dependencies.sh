#!/usr/bin/env bash
# discover-dependencies.sh — Find the Kubernetes workloads that depend on the AWS
# resources an experiment will inject faults into (Step 2: Impact Targets).
#
# For each resource it resolves the real endpoints (hostnames / IPs) via the AWS
# API, then scans every reachable EKS cluster in the Region for workloads that
# reference them: container env values, ConfigMaps (via env valueFrom, envFrom,
# volumes, projected volumes), ExternalName Services (and workloads that point at
# those Services), and — opt-in — Secret KEY NAMES (never values).
#
# Matching is anchored, so `orders-db` does not match `orders-db-replica` and a
# hostname does not match a longer hostname it is a suffix of. Substring-only
# hits that fail the anchor are reported as near_misses for transparency and are
# never treated as dependencies.
#
# Usage:
#   ./discover-dependencies.sh --region us-east-1 \
#       --resource rds-cluster:orders-aurora --resource elasticache:sessions-rg \
#       [--match payments-api=pay.internal.example.com] \
#       [--clusters all|eks-a,eks-b] [--scan-secret-keys] [--output-dir output/]
#
#   Offline / test mode (no AWS, no kubectl):
#   ./discover-dependencies.sh --fixtures tests/fixtures/discover --output-dir /tmp/x
#
# Outputs:
#   <output-dir>/checkpoints/step2-dependencies.json  — full evidence (for the report)
#   <output-dir>/monitoring/app-map.json              — workload list for log-collector.sh --app-map
#   <output-dir>/kubeconfigs/<cluster>.kubeconfig     — isolated kubeconfig per cluster
#                                                        (~/.kube/config is never modified)
#
# Exit codes: 0 = scan completed (even with zero findings), 1 = usage error,
#             2 = no cluster could be scanned.

set -euo pipefail

REGION=""
RESOURCES=()
MATCHES=()
CLUSTERS="all"
OUTPUT_DIR="./output"
SCAN_SECRET_KEYS=false
FIXTURES=""
REQUEST_TIMEOUT=15

usage() {
    cat >&2 <<'EOF'
Usage: discover-dependencies.sh --region REGION --resource TYPE:ID [...] [OPTIONS]

Resource types (repeat --resource for several):
  rds-cluster:<db-cluster-identifier>      Aurora / Multi-AZ DB cluster (all endpoints + member instances)
  rds-instance:<db-instance-identifier>    RDS instance
  elasticache:<replication-group-id>       ElastiCache Redis/Valkey replication group (all node endpoints)
  msk:<cluster-arn>                        Amazon MSK cluster (all bootstrap broker hosts)
  opensearch:<domain-name>                 OpenSearch Service domain
  ec2:<instance-id>                        EC2 instance (private IP + private DNS)

Options:
  --match LABEL=STRING      Extra literal string to look for (e.g. a CNAME in front of the resource)
  --clusters all|a,b        EKS clusters to scan (default: all clusters in the Region)
  --scan-secret-keys        Also inspect Secret KEY NAMES (needs RBAC list on secrets; values are never read out)
  --output-dir DIR          Output directory (default: ./output)
  --request-timeout SEC     kubectl request timeout (default: 15)
  --fixtures DIR            Offline mode: read resources.json and clusters/<name>/*.json from DIR
  -h, --help                Show this help
EOF
    exit 1
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --region)           REGION="$2";            shift 2 ;;
        --resource)         RESOURCES+=("$2");      shift 2 ;;
        --match)            MATCHES+=("$2");        shift 2 ;;
        --clusters)         CLUSTERS="$2";          shift 2 ;;
        --scan-secret-keys) SCAN_SECRET_KEYS=true;  shift ;;
        --output-dir)       OUTPUT_DIR="$2";        shift 2 ;;
        --request-timeout)  REQUEST_TIMEOUT="$2";   shift 2 ;;
        --fixtures)         FIXTURES="$2";          shift 2 ;;
        -h|--help)          usage ;;
        *) echo "[discover] Unknown option: $1" >&2; usage ;;
    esac
done

log() { echo "[discover] $*" >&2; }

command -v jq >/dev/null 2>&1 || { log "ERROR: jq is required"; exit 1; }
if [[ -z "$FIXTURES" ]]; then
    [[ -z "$REGION" ]] && { log "ERROR: --region is required"; usage; }
    [[ ${#RESOURCES[@]} -eq 0 && ${#MATCHES[@]} -eq 0 ]] && { log "ERROR: at least one --resource or --match is required"; usage; }
    command -v aws >/dev/null 2>&1 || { log "ERROR: aws CLI is required"; exit 1; }
    command -v kubectl >/dev/null 2>&1 || { log "ERROR: kubectl is required"; exit 1; }
else
    [[ -f "$FIXTURES/resources.json" ]] || { log "ERROR: $FIXTURES/resources.json not found"; exit 1; }
fi

mkdir -p "$OUTPUT_DIR/checkpoints" "$OUTPUT_DIR/monitoring" "$OUTPUT_DIR/kubeconfigs"
WORK=$(mktemp -d "${TMPDIR:-/tmp}/discover-deps-XXXXXX")
trap 'rm -rf "$WORK"' EXIT

# ---------------------------------------------------------------------------
# 1. Resolve resources -> match patterns
#    Pattern kinds: host (full hostname), id (identifier followed by '.'),
#    ip, regex, literal. A 'loose' substring of the identifier is kept only to
#    report near misses.
# ---------------------------------------------------------------------------
awsq() { aws "$@" --region "$REGION" --output json; }

resolve_resource() {
    local spec="$1" type id
    type="${spec%%:*}"; id="${spec#*:}"
    [[ "$type" == "$spec" || -z "$id" ]] && { log "ERROR: --resource must be TYPE:ID (got '$spec')"; exit 1; }
    local hosts="[]" extra="[]" loose="$id"
    case "$type" in
        rds-cluster)
            hosts=$(awsq rds describe-db-clusters --db-cluster-identifier "$id" \
                | jq '[.DBClusters[0] | .Endpoint, .ReaderEndpoint, (.CustomEndpoints // [])[]] | map(select(. != null))')
            local members
            members=$(awsq rds describe-db-instances --filters "Name=db-cluster-id,Values=$id" \
                | jq '[.DBInstances[] | .Endpoint.Address // empty]')
            hosts=$(jq -n --argjson a "$hosts" --argjson b "$members" '$a + $b')
            extra=$(jq -n --arg id "$id" '[{kind:"id", value:$id}]') ;;
        rds-instance)
            hosts=$(awsq rds describe-db-instances --db-instance-identifier "$id" \
                | jq '[.DBInstances[0].Endpoint.Address // empty]')
            extra=$(jq -n --arg id "$id" '[{kind:"id", value:$id}]') ;;
        elasticache)
            hosts=$(awsq elasticache describe-replication-groups --replication-group-id "$id" \
                | jq '[.ReplicationGroups[0] | (.ConfigurationEndpoint.Address // empty),
                       ((.NodeGroups // [])[] | (.PrimaryEndpoint.Address // empty), (.ReaderEndpoint.Address // empty),
                        ((.NodeGroupMembers // [])[] | .ReadEndpoint.Address // empty))] | unique')
            # Node and group endpoints embed the group id as a whole DNS label.
            extra=$(jq -n --arg id "$id" '[{kind:"id", value:$id}]') ;;
        msk)
            hosts=$(awsq kafka get-bootstrap-brokers --cluster-arn "$id" \
                | jq '[to_entries[] | select(.key | startswith("BootstrapBrokerString")) | .value | split(",")[] | sub(":[0-9]+$"; "")] | unique')
            local name
            name=$(awsq kafka describe-cluster-v2 --cluster-arn "$id" | jq -r '.ClusterInfo.ClusterName')
            loose="$name"
            extra=$(jq -n --arg n "$name" '[{kind:"regex", value:("\\." + ($n|ascii_downcase|gsub("(?<c>[.\\-])"; "\\\(.c)")) + "\\.[a-z0-9]+\\.c[0-9]+\\.kafka\\.")}]') ;;
        opensearch)
            hosts=$(awsq opensearch describe-domain --domain-name "$id" \
                | jq '[.DomainStatus | (.Endpoint // empty), (.EndpointV2 // empty), ((.Endpoints // {}) | .[]), ((.DomainEndpointOptions.CustomEndpoint) // empty)] | unique')
            extra=$(jq -n --arg d "$id" '[{kind:"regex", value:("(^|[^a-z0-9-])(search|vpc)-" + ($d|ascii_downcase|gsub("(?<c>[.\\-])"; "\\\(.c)")) + "-[a-z0-9]+\\.")}]') ;;
        ec2)
            local inst
            inst=$(awsq ec2 describe-instances --instance-ids "$id" | jq '.Reservations[0].Instances[0]')
            hosts=$(echo "$inst" | jq '[.PrivateDnsName // empty] | map(select(. != ""))')
            extra=$(echo "$inst" | jq '[.NetworkInterfaces[]?.PrivateIpAddresses[]?.PrivateIpAddress // empty] | unique | map({kind:"ip", value:.})')
            loose="" ;;
        *) log "ERROR: unsupported resource type '$type'"; usage ;;
    esac
    jq -n --arg type "$type" --arg id "$id" --arg loose "$loose" \
        --argjson hosts "$hosts" --argjson extra "$extra" \
        '{type:$type, id:$id,
          patterns: (($hosts | map({kind:"host", value:(.|ascii_downcase)})) + $extra),
          loose: (if $loose == "" then null else ($loose|ascii_downcase) end)}'
}

if [[ -n "$FIXTURES" ]]; then
    cp "$FIXTURES/resources.json" "$WORK/resources.json"
else
    : > "$WORK/resources.jsonl"
    for r in "${RESOURCES[@]+"${RESOURCES[@]}"}"; do
        log "Resolving endpoints for $r"
        resolve_resource "$r" >> "$WORK/resources.jsonl"
    done
    for m in "${MATCHES[@]+"${MATCHES[@]}"}"; do
        label="${m%%=*}"; value="${m#*=}"
        jq -nc --arg id "$label" --arg v "$value" \
            '{type:"literal", id:$id, patterns:[{kind:"literal", value:($v|ascii_downcase)}], loose:null}' >> "$WORK/resources.jsonl"
    done
    jq -s '.' "$WORK/resources.jsonl" > "$WORK/resources.json"
fi

empty_patterns=$(jq -r '.[] | select((.patterns | length) == 0) | "\(.type):\(.id)"' "$WORK/resources.json")
if [[ -n "$empty_patterns" ]]; then
    log "WARN: no endpoint resolved for: $empty_patterns (check the identifier and Region)"
fi

# ---------------------------------------------------------------------------
# 2. Collect cluster objects (slimmed — only the fields the matcher needs)
# ---------------------------------------------------------------------------
SLIM_PODS='[.items[] | {metadata:{namespace:.metadata.namespace, name:.metadata.name, ownerReferences:(.metadata.ownerReferences // [])},
            spec:{containers:[(.spec.containers // [])[], (.spec.initContainers // [])[] | {name, env:(.env // []), envFrom:(.envFrom // [])}],
                  volumes:[(.spec.volumes // [])[] | {name, configMap, secret, projected}]}}]'
SLIM_RS='[.items[] | {metadata:{namespace:.metadata.namespace, name:.metadata.name, ownerReferences:(.metadata.ownerReferences // [])}}]'
SLIM_CM='[.items[] | {metadata:{namespace:.metadata.namespace, name:.metadata.name}, data:(.data // {})}]'
SLIM_SVC='[.items[] | select(.spec.type == "ExternalName") | {namespace:.metadata.namespace, name:.metadata.name, externalName:(.spec.externalName // "")}]'

collect_cluster() {
    # Separate statements: words of one `local` are expanded before any is assigned.
    local name="$1"
    local dir="$WORK/clusters/$name"
    local kcfg="$OUTPUT_DIR/kubeconfigs/$name.kubeconfig"
    mkdir -p "$dir"
    local k=(kubectl --kubeconfig "$kcfg" --request-timeout="${REQUEST_TIMEOUT}s")
    if ! aws eks update-kubeconfig --name "$name" --region "$REGION" --kubeconfig "$kcfg" >/dev/null 2>"$dir/err"; then
        jq -n --arg n "$name" --arg r "update-kubeconfig failed: $(head -c 300 "$dir/err")" '{name:$n, accessible:false, reason:$r}' > "$dir/status.json"
        return 0
    fi
    if ! "${k[@]}" get namespaces -o name >/dev/null 2>"$dir/err"; then
        jq -n --arg n "$name" --arg r "API not reachable or not authorized: $(head -c 300 "$dir/err")" '{name:$n, accessible:false, reason:$r}' > "$dir/status.json"
        return 0
    fi
    local partial=()
    "${k[@]}" get pods -A -o json 2>>"$dir/err" | jq "$SLIM_PODS" > "$dir/pods.json" || { echo '[]' > "$dir/pods.json"; partial+=("pods"); }
    "${k[@]}" get replicasets -A -o json 2>>"$dir/err" | jq "$SLIM_RS" > "$dir/replicasets.json" || { echo '[]' > "$dir/replicasets.json"; partial+=("replicasets"); }
    "${k[@]}" get configmaps -A -o json 2>>"$dir/err" | jq "$SLIM_CM" > "$dir/configmaps.json" || { echo '[]' > "$dir/configmaps.json"; partial+=("configmaps"); }
    "${k[@]}" get services -A -o json 2>>"$dir/err" | jq "$SLIM_SVC" > "$dir/services.json" || { echo '[]' > "$dir/services.json"; partial+=("services"); }
    if [[ "$SCAN_SECRET_KEYS" == "true" ]]; then
        # go-template prints namespace, name and KEY NAMES only; values never leave kubectl.
        "${k[@]}" get secrets -A -o go-template='{{range .items}}{{.metadata.namespace}}{{"\t"}}{{.metadata.name}}{{"\t"}}{{range $k, $v := .data}}{{$k}},{{end}}{{"\n"}}{{end}}' 2>>"$dir/err" \
            | jq -R -s '[split("\n")[] | select(length > 0) | split("\t") | {namespace:.[0], name:.[1], keys:((.[2] // "") | split(",") | map(select(length > 0)))}]' \
            > "$dir/secret-keys.json" || { echo '[]' > "$dir/secret-keys.json"; partial+=("secrets"); }
    else
        echo '[]' > "$dir/secret-keys.json"
    fi
    local nodes
    nodes=$("${k[@]}" get nodes -o name 2>/dev/null | wc -l | tr -d ' ')
    jq -n --arg n "$name" --arg kc "$kcfg" --argjson nodes "${nodes:-0}" \
        --argjson partial "$(printf '%s\n' "${partial[@]+"${partial[@]}"}" | jq -R -s 'split("\n") | map(select(length > 0))')" \
        '{name:$n, accessible:true, kubeconfig:$kc, nodes:$nodes, unreadable:$partial}' > "$dir/status.json"
}

mkdir -p "$WORK/clusters"
if [[ -n "$FIXTURES" ]]; then
    for d in "$FIXTURES"/clusters/*/; do
        name=$(basename "$d")
        mkdir -p "$WORK/clusters/$name"
        for f in pods replicasets configmaps services secret-keys; do
            if [[ -f "$d/$f.json" ]]; then cp "$d/$f.json" "$WORK/clusters/$name/$f.json"; else echo '[]' > "$WORK/clusters/$name/$f.json"; fi
        done
        if [[ -f "$d/status.json" ]]; then cp "$d/status.json" "$WORK/clusters/$name/status.json"
        else jq -n --arg n "$name" '{name:$n, accessible:true, kubeconfig:"", nodes:0, unreadable:[]}' > "$WORK/clusters/$name/status.json"; fi
    done
else
    if [[ "$CLUSTERS" == "all" ]]; then
        CLUSTER_LIST=()   # no mapfile: keep bash 3.2 (macOS) working like the other scripts
        while IFS= read -r c; do [[ -n "$c" ]] && CLUSTER_LIST+=("$c"); done < <(awsq eks list-clusters | jq -r '.clusters[]')
    else
        IFS=',' read -r -a CLUSTER_LIST <<< "$CLUSTERS"
    fi
    [[ ${#CLUSTER_LIST[@]} -eq 0 ]] && { log "ERROR: no EKS clusters found in $REGION"; exit 2; }
    log "Scanning ${#CLUSTER_LIST[@]} cluster(s) in parallel: ${CLUSTER_LIST[*]}"
    pids=()
    for c in "${CLUSTER_LIST[@]}"; do collect_cluster "$c" & pids+=($!); done
    for p in "${pids[@]}"; do wait "$p" || true; done
fi

# ---------------------------------------------------------------------------
# 3. Match (pure jq; identical in live and fixture mode)
# ---------------------------------------------------------------------------
read -r -d '' MATCHER <<'JQ' || true
def esc: gsub("(?<c>[\\\\.^$|?*+()\\[\\]{}/-])"; "\\\(.c)");
def rx:
  if   .kind == "host"    then "(^|[^a-z0-9.-])" + (.value|esc) + "([^a-z0-9-]|$)"
  elif .kind == "id"      then "(^|[^a-z0-9-])"  + (.value|esc) + "\\."
  elif .kind == "ip"      then "(^|[^0-9.])"     + (.value|esc) + "([^0-9]|$)"
  elif .kind == "regex"   then .value
  else (.value|esc) end;
# Keep only the line that matched, strip URL credentials and obvious secrets, cap length.
def evidence($r):
  (split("\n") | map(select(ascii_downcase | test($r))) | first // .)
  | gsub("(?<s>[a-z][a-z0-9+.-]*://)[^/@\\s]+@"; "\(.s)***@"; "i")
  | gsub("(?<k>(password|passwd|pwd|secret|token|apikey|api_key)[\"']?\\s*[:=]\\s*)[^\\s,;&\"']+"; "\(.k)***"; "i")
  | .[0:240];

$resources as $res
| ([$res[] as $r | $r.patterns[] | {res:$r.id, type:$r.type, rx:rx, kind, strength:"strong"}]) as $P0
| ([$res[] | select(.loose != null) | {res:.id, type, rx:(.loose|esc)}]) as $LOOSE

# hits($s; $P): list of {res,type} whose anchored pattern matches string $s
| def hits($s; $P): ($s|ascii_downcase) as $l | [$P[] | select(. as $p | $l | test($p.rx)) | {res, type, rx, strength, via}] | unique_by(.res);
  def loose_only($s; $P):
    ($s|ascii_downcase) as $l | (hits($s; $P) | map(.res)) as $strict
    | [$LOOSE[] | select(.res as $id | ($strict | index($id)) == null) | select(. as $p | $l | test($p.rx)) | {res, type, rx}];

  [$clusters[] | . as $c
   | ($c.pods) as $pods
   | ($c.replicasets | map({key:(.metadata.namespace + "/" + .metadata.name), value:(.metadata.ownerReferences[0] // null)}) | from_entries) as $rs
   | ($c.configmaps | map({key:(.metadata.namespace + "/" + .metadata.name), value:.data}) | from_entries) as $cm

   # ExternalName services that point at a resource -> derived patterns for their in-cluster names
   | ([$c.services[] | . as $s | hits($s.externalName; $P0)[] | {svc:$s, res, type}]) as $ext
   # FQDN form (svc.ns[.svc[.cluster.local]]) is strong evidence from any namespace;
   # the bare service name only counts inside the Service's own namespace and stays unverified.
   | ([$ext[] | {res, type, ns:.svc.namespace, via:("service:" + .svc.namespace + "/" + .svc.name), strength:"strong", scope:"any",
                 rx:("(^|[^a-z0-9.-])" + (.svc.name|esc) + "\\." + (.svc.namespace|esc) + "(\\.svc(\\.cluster\\.local)?)?([^a-z0-9.-]|$)")},
               {res, type, ns:.svc.namespace, via:("service:" + .svc.namespace + "/" + .svc.name), strength:"weak", scope:"ns",
                 rx:("(^|[^a-z0-9.-])" + (.svc.name|esc) + "([^a-z0-9.-]|$)")}]) as $DERIVED

   | def hits_ns($s; $ns):
       ($s|ascii_downcase) as $l
       | (hits($s; $P0) + [ $DERIVED[] | select(.scope == "any" or .ns == $ns) | select(. as $d | $l | test($d.rx)) | {res, type, rx, strength, via} ])
       | sort_by(if .strength == "strong" then 0 else 1 end) | unique_by(.res);

     def workload($p):
       ($p.metadata.ownerReferences[0] // null) as $o
       | if $o == null then {kind:"Pod", name:$p.metadata.name}
         elif $o.kind == "ReplicaSet" then
           ($rs[$p.metadata.namespace + "/" + $o.name]) as $d
           | if $d != null then {kind:$d.kind, name:$d.name} else {kind:"ReplicaSet", name:$o.name} end
         else {kind:$o.kind, name:$o.name} end;

     # Every (string, source-label) a pod can see, with the ConfigMap / Secret it came from
     def sources($p):
       $p.metadata.namespace as $ns
       | ($p.spec.containers[] | . as $ctr
           | ( ($ctr.env[] | select(.value != null) | {v:.value, src:("env " + $ctr.name + "/" + .name)})
             , ($ctr.env[] | select(.valueFrom.configMapKeyRef != null) | .valueFrom.configMapKeyRef as $r
                | {v:($cm[$ns + "/" + $r.name][$r.key] // null), src:("env " + $ctr.name + "/" + .name + " <- configmap " + $r.name + ":" + $r.key)} | select(.v != null))
             , ($ctr.envFrom[] | select(.configMapRef != null) | .configMapRef.name as $n
                | ($cm[$ns + "/" + $n] // {}) | to_entries[] | {v:.value, src:("envFrom configmap " + $n + ":" + .key)})
             ))
       , ($p.spec.volumes[] | . as $vol
           | ([ ($vol.configMap.name // empty), (($vol.projected.sources // [])[] | (.configMap.name // empty)) ][]) as $n
           | ($cm[$ns + "/" + $n] // {}) | to_entries[] | {v:.value, src:("volume " + $vol.name + " <- configmap " + $n + ":" + .key)});

     def secret_refs($p):
       $p.metadata.namespace as $ns
       | ($p.spec.containers[] | . as $ctr
           | ( ($ctr.env[] | select(.valueFrom.secretKeyRef != null) | {name:.valueFrom.secretKeyRef.name, key:.valueFrom.secretKeyRef.key, src:("env " + $ctr.name + "/" + .name)})
             , ($ctr.envFrom[] | select(.secretRef != null) | {name:.secretRef.name, key:null, src:"envFrom"}) ))
       , ($p.spec.volumes[] | . as $vol
           | ([ ($vol.secret.secretName // empty), (($vol.projected.sources // [])[] | (.secret.name // empty)) ][]) | {name:., key:null, src:("volume " + $vol.name)});

     ($c.secrets | map({key:(.namespace + "/" + .name), value:.keys}) | from_entries) as $sk
     | def type_hint($t):
         {"rds-cluster":"db|database|rds|aurora|mysql|postgres|pg|jdbc|sql",
          "rds-instance":"db|database|rds|mysql|postgres|pg|jdbc|sql|oracle|mssql",
          "elasticache":"redis|valkey|cache|memcache",
          "msk":"kafka|msk|broker|bootstrap",
          "opensearch":"opensearch|elastic|search"}[$t] // "^$";
       def conn_key: test("host|endpoint|url|uri|dsn|addr|server|broker|bootstrap|connection"; "i");

     [ $pods[] as $p | workload($p) as $w
       | ( sources($p) as $s
           | ( hits_ns($s.v; $p.metadata.namespace)[] | .rx as $rx
               | {cluster:$c.name, namespace:$p.metadata.namespace, kind:$w.kind, workload:$w.name, resource:.res, type:.type,
                  status:(if .strength == "strong" then "verified" else "unverified" end),
                  source:($s.src + (if .via then " -> " + .via else "" end)), evidence:($s.v | evidence($rx))} )
           , ( loose_only($s.v; $P0)[] | .rx as $rx
               | {cluster:$c.name, namespace:$p.metadata.namespace, kind:$w.kind, workload:$w.name, resource:.res, type:.type,
                  status:"near-miss", source:$s.src, evidence:($s.v | evidence($rx))} ) )
       , ( secret_refs($p) as $r
           | ($sk[$p.metadata.namespace + "/" + $r.name] // []) as $keys
           | ($keys | map(select(($r.key == null) or (. == $r.key)))[]) as $key
           | $res[] | select(.type != "literal") | . as $rr
           | select(($key | conn_key) and ((($key + " " + $r.name) | test(type_hint($rr.type); "i")) or (($key + " " + $r.name) | ascii_downcase | contains($rr.id | ascii_downcase))))
           | {cluster:$c.name, namespace:$p.metadata.namespace, kind:$w.kind, workload:$w.name, resource:$rr.id, type:$rr.type,
              status:"unverified", source:($r.src + " <- secret " + $r.name + ":" + $key), evidence:"secret key name only (value not read)"} )
     ]
     + [ $ext[] | {cluster:$c.name, namespace:.svc.namespace, kind:"Service", workload:.svc.name, resource:.res, type:.type,
                   status:"verified", source:"ExternalName", evidence:.svc.externalName} ]
     | . as $f
     | { findings: $f,
         unreferenced_configmaps:
           ( ([$pods[] | . as $p | $p.metadata.namespace as $ns
               | ([$p.spec.containers[] | (.env[] | .valueFrom.configMapKeyRef.name // empty), (.envFrom[] | .configMapRef.name // empty)]
                  + [$p.spec.volumes[] | (.configMap.name // empty), ((.projected.sources // [])[] | .configMap.name // empty)])[]
               | $ns + "/" + .] | unique) as $used
             | [$c.configmaps[] | (.metadata.namespace + "/" + .metadata.name) as $key | select(($used | index($key)) == null)
                | .data | to_entries[] | . as $e | hits($e.value; $P0)[]
                | {cluster:$c.name, configmap:$key, key:$e.key, resource:.res}] | unique ) }
  ]
| { dependencies: ([.[].findings[] | select(.status != "near-miss")]
                   | group_by([.cluster, .namespace, .kind, .workload, .resource])
                   | map(.[0] as $h | {cluster:$h.cluster, namespace:$h.namespace, kind:$h.kind, workload:$h.workload,
                                       resource:$h.resource, type:$h.type,
                                       status:(if any(.[]; .status == "verified") then "verified" else "unverified" end),
                                       sources:(map({source, evidence, status}) | unique | sort_by(if .status == "verified" then 0 else 1 end))})),
    near_misses: ([.[].findings[] | select(.status == "near-miss")] | unique_by([.cluster, .namespace, .workload, .resource, .source])),
    unreferenced_configmaps: [.[].unreferenced_configmaps[]] }
JQ

CLUSTER_STATUS=$(jq -s '.' "$WORK"/clusters/*/status.json)
ACCESSIBLE=$(echo "$CLUSTER_STATUS" | jq '[.[] | select(.accessible)] | length')

# Assemble per-cluster input only for accessible clusters
: > "$WORK/clusters.jsonl"
for d in "$WORK"/clusters/*/; do
    [[ "$(jq -r '.accessible' "$d/status.json")" == "true" ]] || continue
    jq -nc --arg name "$(basename "$d")" \
        --slurpfile pods "$d/pods.json" --slurpfile rs "$d/replicasets.json" \
        --slurpfile cm "$d/configmaps.json" --slurpfile svc "$d/services.json" --slurpfile sec "$d/secret-keys.json" \
        '{name:$name, pods:$pods[0], replicasets:$rs[0], configmaps:$cm[0], services:$svc[0], secrets:$sec[0]}' >> "$WORK/clusters.jsonl"
done
jq -s '.' "$WORK/clusters.jsonl" > "$WORK/clusters.json"

jq -n --slurpfile resources "$WORK/resources.json" --slurpfile clusters "$WORK/clusters.json" \
    '$resources[0] as $resources | $clusters[0] as $clusters | '"$MATCHER" > "$WORK/result.json"

# ---------------------------------------------------------------------------
# 4. Write outputs
# ---------------------------------------------------------------------------
DEPS_FILE="$OUTPUT_DIR/checkpoints/step2-dependencies.json"
MAP_FILE="$OUTPUT_DIR/monitoring/app-map.json"

jq -n --arg region "${REGION:-fixtures}" --arg mode "$([[ -n "$FIXTURES" ]] && echo fixtures || echo live)" \
    --argjson secrets "$SCAN_SECRET_KEYS" \
    --slurpfile resources "$WORK/resources.json" --argjson clusters "$CLUSTER_STATUS" \
    --slurpfile result "$WORK/result.json" \
    '{generated_at:(now | todate), region:$region, mode:$mode, secret_keys_scanned:$secrets,
      resources:$resources[0], clusters:$clusters} + $result[0]' > "$DEPS_FILE"

# app-map: one entry per workload (Services are not log sources). log-collector.sh
# collects entries whose status is "verified" or "confirmed"; set an "unverified"
# entry to "confirmed" only after the user confirms it.
jq --argjson clusters "$CLUSTER_STATUS" \
    '[.dependencies[] | select(.kind != "Service")]
     | group_by([.cluster, .namespace, .kind, .workload])
     | map(.[0] as $h | ($clusters[] | select(.name == $h.cluster) | .kubeconfig // "") as $kc
           | {cluster:$h.cluster, kubeconfig:$kc, namespace:$h.namespace, kind:$h.kind, workload:$h.workload,
              resources:(map(.resource) | unique),
              status:(if any(.[]; .status == "verified") then "verified" else "unverified" end)})' \
    "$DEPS_FILE" > "$MAP_FILE"

# ---------------------------------------------------------------------------
# 5. Human-readable summary (stderr)
# ---------------------------------------------------------------------------
{
    echo ""
    echo "Dependency discovery ($(jq -r '.mode' "$DEPS_FILE"), region ${REGION:-fixtures})"
    echo "$CLUSTER_STATUS" | jq -r '.[] | if .accessible
        then "  ✅ \(.name): accessible (\(.nodes) nodes)" + (if (.unreadable // []) | length > 0 then " — could not read: \(.unreadable | join(","))" else "" end)
        else "  ❌ \(.name): skipped — \(.reason)" end'
    jq -r '. as $d | $d.resources[] as $r
        | "\n  \($r.type):\($r.id)  [\($r.patterns | length) endpoint pattern(s)]",
          ( [$d.dependencies[] | select(.resource == $r.id)] as $deps
            | if ($deps | length) == 0 then "     (no dependent workload found in the scanned clusters)" else
              ($deps[] | if .status == "verified"
                 then "     ✅ \(.cluster)/\(.namespace)/\(.kind)/\(.workload) — \(.sources[0].source)\n          \(.sources[0].evidence)"
                 else "     ⚠️  \(.cluster)/\(.namespace)/\(.kind)/\(.workload) — \(.sources[0].source)  (unverified: confirm with the user)" end)
              end ),
          ( $d.near_misses[] | select(.resource == $r.id)
            | "     ✖  \(.cluster)/\(.namespace)/\(.workload) — near miss, NOT a dependency: \(.evidence)" )' "$DEPS_FILE"
    jq -r '"\n  Total: \([.dependencies[] | select(.status == "verified")] | length) verified, \([.dependencies[] | select(.status == "unverified")] | length) unverified, \(.near_misses | length) near-miss, \(.unreferenced_configmaps | length) matching ConfigMap key(s) with no consumer"' "$DEPS_FILE"
    echo "  Evidence: $DEPS_FILE"
    echo "  App map:  $MAP_FILE"
} >&2

if [[ "$ACCESSIBLE" -eq 0 ]]; then
    log "ERROR: no cluster could be scanned — the impact list is EMPTY BECAUSE NOTHING WAS READ, not because nothing depends on the resources"
    exit 2
fi
exit 0
