#!/usr/bin/env bash
#
# selfhosted-stack-analyzer — Phase 1 collector (RAW EC2 substrate)
#
# Many customers run self-hosted stateful middleware (MySQL / TiDB / TiKV / PD /
# Redis / Kafka / ZooKeeper) directly on dedicated EC2 instances — NOT as pods on
# EKS. Those hosts are distinguished by their EC2 `Name` tag (e.g. tikv-source-1,
# tidb-target-1). This collector gathers a READ-ONLY evidence bundle for that
# substrate and groups instances into component clusters by Name tag.
#
# Design goals:
#   - Grab as much as possible in one pass (Phase 1 = online, one shot).
#   - READ-ONLY: only Describe*. Never create/modify/terminate.
#   - Group by EC2 Name tag → component clusters (the customer's identification key).
#
# Usage:
#   bash collect-ec2.sh --region <REGION> --vpcs <vpc-id1,vpc-id2,...> \
#       [--vpc-names <name1,name2>] [--output ./evidence-bundle]
#   # If neither --vpcs nor --vpc-names is given, collects all non-default VPCs.
#
set -uo pipefail

REGION=""
VPCS=""
VPC_NAMES=""
OUTPUT="./evidence-bundle"

usage() { grep '^#' "$0" | sed 's/^# \{0,1\}//' | head -n 20; exit 1; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --region)    REGION="${2:-}"; shift 2 ;;
    --vpcs)      VPCS="${2:-}"; shift 2 ;;
    --vpc-names) VPC_NAMES="${2:-}"; shift 2 ;;
    --output)    OUTPUT="${2:-}"; shift 2 ;;
    -h|--help)   usage ;;
    *) echo "Unknown arg: $1"; usage ;;
  esac
done

[[ -z "$REGION" ]] && { echo "ERROR: --region is required"; usage; }
command -v aws >/dev/null || { echo "ERROR: aws CLI not found"; exit 2; }
command -v jq  >/dev/null || { echo "ERROR: jq not found"; exit 2; }

TS="$(date +%Y-%m-%d)"
BUNDLE="${OUTPUT}/ec2-${REGION}-${TS}"
mkdir -p "$BUNDLE"/{ec2,network,manifest_tmp}

log()  { echo "[collect-ec2] $*" >&2; }
declare -a API_ERRORS=()

# run_describe <label> <outfile> <empty-json-fallback> <aws-cmd...>
# Captures stderr; on failure, logs a visible warning AND records it in
# API_ERRORS (surfaced in manifest.json) instead of silently writing an
# empty-looking result that could be misread as "confirmed: nothing found".
run_describe() {
  local label="$1" out="$2" fallback="$3"; shift 3
  local errfile="${out}.err"
  if "$@" >"$out" 2>"$errfile"; then
    rm -f "$errfile"
  else
    local msg
    msg="$(tr '\n' ' ' < "$errfile" | head -c 300)"
    log "  ⚠ $label FAILED (not 'no data' — an API call error): $msg"
    API_ERRORS+=("$label: $msg")
    echo "$fallback" > "$out"
    rm -f "$errfile"
  fi
}

# ----------------------------------------------------------------------------
# Resolve target VPCs
# ----------------------------------------------------------------------------
if [[ -z "$VPCS" && -n "$VPC_NAMES" ]]; then
  log "Resolving VPC names → ids..."
  IFS=',' read -ra NAMES <<< "$VPC_NAMES"
  ids=()
  for nm in "${NAMES[@]}"; do
    vid=$(aws ec2 describe-vpcs --region "$REGION" \
      --filters "Name=tag:Name,Values=${nm}" \
      --query 'Vpcs[0].VpcId' --output text 2>/dev/null)
    [[ -n "$vid" && "$vid" != "None" ]] && ids+=("$vid")
  done
  VPCS=$(IFS=','; echo "${ids[*]}")
fi
if [[ -z "$VPCS" ]]; then
  log "No VPC specified → collecting all non-default VPCs"
  VPCS=$(aws ec2 describe-vpcs --region "$REGION" \
    --filters "Name=isDefault,Values=false" \
    --query 'Vpcs[].VpcId' --output text 2>/dev/null | tr '\t' ',')
fi
log "Target VPCs: $VPCS"
IFS=',' read -ra VPC_ARR <<< "$VPCS"

# build a describe-instances filter argument
FILTER_ARG=("Name=vpc-id,Values=${VPCS}")

# ----------------------------------------------------------------------------
# 1. Instances (raw)
# ----------------------------------------------------------------------------
log "[1/5] EC2 instances..."
run_describe "describe-instances" "$BUNDLE/ec2/instances-raw.json" '{"Reservations":[]}' \
  aws ec2 describe-instances --region "$REGION" --filters "${FILTER_ARG[@]}" --output json

# normalize each instance
jq '{
  instances: [ .Reservations[]?.Instances[]? | {
    instanceId: .InstanceId,
    nameTag: ((.Tags // []) | map(select(.Key=="Name")) | (.[0].Value // null)),
    state: .State.Name,
    az: .Placement.AvailabilityZone,
    vpcId: .VpcId,
    subnetId: .SubnetId,
    privateIp: .PrivateIpAddress,
    instanceType: .InstanceType,
    imageId: .ImageId,
    launchTime: .LaunchTime,
    ebsOptimized: .EbsOptimized,
    securityGroups: [ .SecurityGroups[]? | {id: .GroupId, name: .GroupName} ],
    blockDevices: [ .BlockDeviceMappings[]? | {device: .DeviceName, volumeId: .Ebs.VolumeId} ],
    allTags: ((.Tags // []) | map({(.Key): .Value}) | add)
  } ]
}' "$BUNDLE/ec2/instances-raw.json" > "$BUNDLE/ec2/instances.json"
INST_COUNT=$(jq '.instances | length' "$BUNDLE/ec2/instances.json")
log "  ✓ $INST_COUNT instances"

# ----------------------------------------------------------------------------
# 2. Group instances into component clusters by Name tag  (★ identification key)
# ----------------------------------------------------------------------------
log "[2/5] Grouping by Name tag → component clusters..."
# clusterKey  = Name with a trailing "-<number>" stripped (tikv-source-1 → tikv-source)
# component   = leading token normalized to a known middleware type
# nodeIndex   = trailing number (if any)
jq '
  def comp(name):
    (name // "" | ascii_downcase) as $n |
    if   ($n|test("tikv"))               then "tikv"
    elif ($n|test("^pd-|(-|^)pd(-|$)|placement")) then "pd"
    elif ($n|test("tidb"))               then "tidb"
    elif ($n|test("tiflash"))            then "tiflash"
    elif ($n|test("mysql|mariadb|percona")) then "mysql"
    elif ($n|test("redis"))              then "redis"
    elif ($n|test("zookeeper|(-|^)zk(-|$)")) then "zookeeper"
    elif ($n|test("kafka"))              then "kafka"
    elif ($n|test("cdc|ticdc|dm-|drainer|pump")) then "replication/cdc"
    elif ($n|test("mon|grafana|prometheus|deepflow")) then "monitoring"
    elif ($n|test("ops|bastion|jump|bridge|agent")) then "ops/tooling"
    else "other" end;
  {
    groups: (
      [ .instances[] | . + {
          component: comp(.nameTag),
          clusterKey: ((.nameTag // "unknown") | gsub("-[0-9]+$"; "")),
          nodeIndex: ((.nameTag // "") | (capture("-(?<i>[0-9]+)$").i // null))
        }
      ]
      | group_by(.clusterKey)
      | map({
          clusterKey: .[0].clusterKey,
          component: .[0].component,
          count: length,
          running: ([.[] | select(.state=="running")] | length),
          stopped: ([.[] | select(.state=="stopped")] | length),
          azSpread: (group_by(.az) | map({(.[0].az): length}) | add),
          instanceTypes: ([.[].instanceType] | unique),
          members: [.[] | {nameTag, instanceId, state, az, instanceType}]
        })
      | sort_by(.component, .clusterKey)
    )
  }
' "$BUNDLE/ec2/instances.json" > "$BUNDLE/ec2/nametag-groups.json"
GROUP_COUNT=$(jq '.groups | length' "$BUNDLE/ec2/nametag-groups.json")
log "  ✓ $GROUP_COUNT component clusters"

# ----------------------------------------------------------------------------
# 3. EBS volumes (persistent storage: AZ / type / size / iops / encryption)
# ----------------------------------------------------------------------------
log "[3/5] EBS volumes..."
VOL_IDS=$(jq -r '.instances[].blockDevices[]?.volumeId // empty' "$BUNDLE/ec2/instances.json" | sort -u | tr '\n' ' ')
if [[ -n "${VOL_IDS// }" ]]; then
  # shellcheck disable=SC2086
  run_describe "describe-volumes" "$BUNDLE/ec2/volumes-raw.json" '{"Volumes":[]}' \
    aws ec2 describe-volumes --region "$REGION" --volume-ids $VOL_IDS --output json
  jq '{volumes: [ .Volumes[]? | {
    volumeId: .VolumeId, az: .AvailabilityZone, type: .VolumeType,
    sizeGiB: .Size, iops: .Iops, throughput: .Throughput,
    encrypted: .Encrypted, state: .State,
    attachedTo: [ .Attachments[]? | {instanceId: .InstanceId, device: .Device} ]
  } ]}' "$BUNDLE/ec2/volumes-raw.json" > "$BUNDLE/ec2/volumes.json"
else
  echo '{"volumes":[]}' > "$BUNDLE/ec2/volumes.json"
fi
log "  ✓ $(jq '.volumes | length' "$BUNDLE/ec2/volumes.json") volumes"

# ----------------------------------------------------------------------------
# 3b. EBS snapshots for those volumes (backup-existence evidence — CONFIRMED tier)
# ----------------------------------------------------------------------------
log "[3b/5] EBS snapshots (backup evidence)..."
if [[ -n "${VOL_IDS// }" ]]; then
  # Build a clean comma-separated list (VOL_IDS is space-separated with a
  # trailing space from `tr '\n' ' '` — a naive ${VOL_IDS// /,} substitution
  # leaves a trailing comma that AWS CLI's filter parser rejects, causing a
  # silent false-negative "no snapshots" result). Use an array + IFS join instead.
  read -ra _VOL_ARR <<< "$VOL_IDS"
  VOL_CSV=$(IFS=','; echo "${_VOL_ARR[*]}")
  run_describe "describe-snapshots" "$BUNDLE/ec2/snapshots-raw.json" '{"Snapshots":[]}' \
    aws ec2 describe-snapshots --region "$REGION" --owner-ids self \
    --filters "Name=volume-id,Values=${VOL_CSV}" --output json
  jq '{snapshots: [ .Snapshots[]? | {
    snapshotId: .SnapshotId, volumeId: .VolumeId, state: .State,
    startTime: .StartTime, sizeGiB: .VolumeSize, encrypted: .Encrypted,
    description: .Description
  } ]}' "$BUNDLE/ec2/snapshots-raw.json" > "$BUNDLE/ec2/snapshots.json"
else
  echo '{"snapshots":[]}' > "$BUNDLE/ec2/snapshots.json"
fi
SNAP_COUNT=$(jq '.snapshots | length' "$BUNDLE/ec2/snapshots.json")
log "  ✓ $SNAP_COUNT snapshots found"

# per-volume backup coverage: which of the discovered volumes have >=1 snapshot, which have none
jq -n --slurpfile vols "$BUNDLE/ec2/volumes.json" --slurpfile snaps "$BUNDLE/ec2/snapshots.json" '
  ($vols[0].volumes // []) as $v |
  ($snaps[0].snapshots // []) as $s |
  {
    volumesWithBackup: [ $v[] | select(.volumeId as $id | $s | any(.volumeId == $id)) | .volumeId ],
    volumesWithoutBackup: [ $v[] | select(.volumeId as $id | ($s | any(.volumeId == $id)) | not) | .volumeId ],
    latestSnapshotPerVolume: (
      $s | group_by(.volumeId) | map({ (.[0].volumeId): (sort_by(.startTime) | last | .startTime) }) | add // {}
    )
  }
' > "$BUNDLE/ec2/backup-coverage.json"
NO_BACKUP_COUNT=$(jq '.volumesWithoutBackup | length' "$BUNDLE/ec2/backup-coverage.json")
log "  ✓ backup-coverage.json: $NO_BACKUP_COUNT / $(jq '.volumes|length' "$BUNDLE/ec2/volumes.json") volumes have NO snapshot"

# ----------------------------------------------------------------------------
# 4. Network: subnets (→ AZ), security groups
# ----------------------------------------------------------------------------
log "[4/5] Network (subnets, security groups)..."
run_describe "describe-subnets" "$BUNDLE/network/subnets-raw.json" '{"Subnets":[]}' \
  aws ec2 describe-subnets --region "$REGION" --filters "${FILTER_ARG[@]}" --output json
jq '{subnets: [ .Subnets[]? | {
  subnetId: .SubnetId, az: .AvailabilityZone, cidr: .CidrBlock, vpcId: .VpcId,
  name: ((.Tags // []) | map(select(.Key=="Name")) | (.[0].Value // null))
} ]}' "$BUNDLE/network/subnets-raw.json" > "$BUNDLE/network/subnets.json"

run_describe "describe-security-groups" "$BUNDLE/network/security-groups-raw.json" '{"SecurityGroups":[]}' \
  aws ec2 describe-security-groups --region "$REGION" --filters "${FILTER_ARG[@]}" --output json
# keep rule shape but not full descriptions
jq '{securityGroups: [ .SecurityGroups[]? | {
  id: .GroupId, name: .GroupName, vpcId: .VpcId,
  ingress: [ .IpPermissions[]? | {proto: .IpProtocol, from: .FromPort, to: .ToPort,
             cidrs: [.IpRanges[]?.CidrIp], sgRefs: [.UserIdGroupPairs[]?.GroupId]} ]
} ]}' "$BUNDLE/network/security-groups-raw.json" > "$BUNDLE/network/security-groups.json"
log "  ✓ subnets + security groups"

# ----------------------------------------------------------------------------
# 4b. Network: gateways, routing, endpoints, EIP, ENI, NACL, peering/TGW
#     ("所有的网络信息都要采集" — full network evidence layer)
# ----------------------------------------------------------------------------
log "[4b/5] Network (gateways, routing, endpoints, EIP, ENI, NACL, peering/TGW)..."

# NAT Gateways — single-NAT-per-VPC is a common AZ-outage-blast-radius SPOF
run_describe "describe-nat-gateways" "$BUNDLE/network/nat-gateways-raw.json" '{"NatGateways":[]}' \
  aws ec2 describe-nat-gateways --region "$REGION" --filter "Name=vpc-id,Values=${VPCS}" --output json
jq --slurpfile subs "$BUNDLE/network/subnets.json" '
  ($subs[0].subnets // []) as $sn |
  {natGateways: [ .NatGateways[]? | . as $nat | {
    natGatewayId: $nat.NatGatewayId, vpcId: $nat.VpcId, subnetId: $nat.SubnetId, state: $nat.State,
    az: ( ($sn[]? | select(.subnetId == $nat.SubnetId) | .az) // null ),
    publicIp: ([$nat.NatGatewayAddresses[]?.PublicIp] | first // null)
  } ]}' "$BUNDLE/network/nat-gateways-raw.json" > "$BUNDLE/network/nat-gateways.json"

# Internet Gateways — attached IGW per VPC (public reachability precondition)
run_describe "describe-internet-gateways" "$BUNDLE/network/internet-gateways-raw.json" '{"InternetGateways":[]}' \
  aws ec2 describe-internet-gateways --region "$REGION" \
  --filters "Name=attachment.vpc-id,Values=${VPCS}" --output json
jq '{internetGateways: [ .InternetGateways[]? | {
  igwId: .InternetGatewayId,
  vpcIds: [.Attachments[]?.VpcId], state: [.Attachments[]?.State]
} ]}' "$BUNDLE/network/internet-gateways-raw.json" > "$BUNDLE/network/internet-gateways.json"

# Route tables — reveals which subnet routes via NAT/IGW/blackhole/peering/TGW
run_describe "describe-route-tables" "$BUNDLE/network/route-tables-raw.json" '{"RouteTables":[]}' \
  aws ec2 describe-route-tables --region "$REGION" --filters "${FILTER_ARG[@]}" --output json
jq '{routeTables: [ .RouteTables[]? | {
  routeTableId: .RouteTableId, vpcId: .VpcId,
  associatedSubnets: [.Associations[]?.SubnetId // empty],
  isMainForVpc: ([.Associations[]?.Main // false] | any),
  routes: [ .Routes[]? | {
    destination: (.DestinationCidrBlock // .DestinationPrefixListId // "?"),
    target: (.GatewayId // .NatGatewayId // .TransitGatewayId // .VpcPeeringConnectionId // .NetworkInterfaceId // "?"),
    state: .State
  } ]
} ]}' "$BUNDLE/network/route-tables-raw.json" > "$BUNDLE/network/route-tables.json"

# VPC Endpoints — private paths to AWS services (S3/EC2/SSM etc.), also flags SSM endpoint presence
run_describe "describe-vpc-endpoints" "$BUNDLE/network/vpc-endpoints-raw.json" '{"VpcEndpoints":[]}' \
  aws ec2 describe-vpc-endpoints --region "$REGION" --filters "${FILTER_ARG[@]}" --output json
jq '{vpcEndpoints: [ .VpcEndpoints[]? | {
  endpointId: .VpcEndpointId, vpcId: .VpcId, serviceName: .ServiceName,
  type: .VpcEndpointType, state: .State, subnetIds: (.SubnetIds // [])
} ]}' "$BUNDLE/network/vpc-endpoints-raw.json" > "$BUNDLE/network/vpc-endpoints.json"

# Elastic IPs — which ENIs/instances have a public IP association
run_describe "describe-addresses" "$BUNDLE/network/eips-raw.json" '{"Addresses":[]}' \
  aws ec2 describe-addresses --region "$REGION" --output json
jq --arg vpcs "$VPCS" '
  ($vpcs | split(",")) as $vlist |
  {eips: [ .Addresses[]? | select((.NetworkInterfaceId // "") != "" or (.InstanceId // "") != "") | {
    publicIp: .PublicIp, allocationId: .AllocationId,
    instanceId: (.InstanceId // null), networkInterfaceId: (.NetworkInterfaceId // null),
    associationId: (.AssociationId // null)
  } ]}' "$BUNDLE/network/eips-raw.json" > "$BUNDLE/network/eips.json"

# ENIs — network-interface-level detail (multi-ENI instances, cross-references to LB/NAT)
run_describe "describe-network-interfaces" "$BUNDLE/network/enis-raw.json" '{"NetworkInterfaces":[]}' \
  aws ec2 describe-network-interfaces --region "$REGION" --filters "${FILTER_ARG[@]}" --output json
jq '{networkInterfaces: [ .NetworkInterfaces[]? | {
  eniId: .NetworkInterfaceId, subnetId: .SubnetId, vpcId: .VpcId,
  privateIp: .PrivateIpAddress, publicIp: (.Association.PublicIp // null),
  attachedInstanceId: (.Attachment.InstanceId // null),
  interfaceType: (.InterfaceType // "interface"),
  description: .Description, status: .Status
} ]}' "$BUNDLE/network/enis-raw.json" > "$BUNDLE/network/enis.json"

# Network ACLs — subnet-level access control (complements security groups)
run_describe "describe-network-acls" "$BUNDLE/network/nacls-raw.json" '{"NetworkAcls":[]}' \
  aws ec2 describe-network-acls --region "$REGION" --filters "${FILTER_ARG[@]}" --output json
jq '{networkAcls: [ .NetworkAcls[]? | {
  naclId: .NetworkAclId, vpcId: .VpcId, isDefault: .IsDefault,
  associatedSubnets: [.Associations[]?.SubnetId // empty],
  entries: [ .Entries[]? | {rule: .RuleNumber, proto: .Protocol, action: .RuleAction,
             egress: .Egress, cidr: (.CidrBlock // .Ipv6CidrBlock // "?"),
             portRange: (.PortRange // null)} ]
} ]}' "$BUNDLE/network/nacls-raw.json" > "$BUNDLE/network/nacls.json"

# VPC Peering connections — hidden cross-VPC dependencies
run_describe "describe-vpc-peering-connections" "$BUNDLE/network/vpc-peering-raw.json" '{"VpcPeeringConnections":[]}' \
  aws ec2 describe-vpc-peering-connections --region "$REGION" \
  --filters "Name=requester-vpc-info.vpc-id,Values=${VPCS}" --output json
jq '{vpcPeering: [ .VpcPeeringConnections[]? | {
  id: .VpcPeeringConnectionId, status: .Status.Code,
  requesterVpc: .RequesterVpcInfo.VpcId, accepterVpc: .AccepterVpcInfo.VpcId
} ]}' "$BUNDLE/network/vpc-peering-raw.json" > "$BUNDLE/network/vpc-peering.json"

# Transit Gateway VPC attachments — hidden cross-VPC/cross-account dependencies via TGW
run_describe "describe-transit-gateway-vpc-attachments" "$BUNDLE/network/tgw-attachments-raw.json" '{"TransitGatewayVpcAttachments":[]}' \
  aws ec2 describe-transit-gateway-vpc-attachments --region "$REGION" \
  --filters "Name=vpc-id,Values=${VPCS}" --output json
jq '{tgwAttachments: [ .TransitGatewayVpcAttachments[]? | {
  attachmentId: .TransitGatewayAttachmentId, tgwId: .TransitGatewayId,
  vpcId: .VpcId, state: .State, subnetIds: (.SubnetIds // [])
} ]}' "$BUNDLE/network/tgw-attachments-raw.json" > "$BUNDLE/network/tgw-attachments.json"

log "  ✓ NAT/IGW/route-tables/VPC-endpoints/EIP/ENI/NACL/peering/TGW"

# ----------------------------------------------------------------------------
# 4c. Load balancing: ALB/NLB, target groups, target health
# ----------------------------------------------------------------------------
log "[4c/5] Load balancers (ALB/NLB), target groups, target health..."

run_describe "describe-load-balancers" "$BUNDLE/network/load-balancers-raw.json" '{"LoadBalancers":[]}' \
  aws elbv2 describe-load-balancers --region "$REGION" --output json
jq --arg vpcs "$VPCS" '
  ($vpcs | split(",")) as $vlist |
  {loadBalancers: [ .LoadBalancers[]? | select(.VpcId as $v | $vlist | index($v)) | {
    arn: .LoadBalancerArn, name: .LoadBalancerName, type: .Type, scheme: .Scheme,
    vpcId: .VpcId, dnsName: .DNSName, state: .State.Code,
    azs: [ .AvailabilityZones[]? | {zoneName: .ZoneName, subnetId: .SubnetId} ]
  } ]}' "$BUNDLE/network/load-balancers-raw.json" > "$BUNDLE/network/load-balancers.json"
LB_COUNT=$(jq '.loadBalancers | length' "$BUNDLE/network/load-balancers.json")

run_describe "describe-target-groups" "$BUNDLE/network/target-groups-raw.json" '{"TargetGroups":[]}' \
  aws elbv2 describe-target-groups --region "$REGION" --output json
jq --arg vpcs "$VPCS" '
  ($vpcs | split(",")) as $vlist |
  {targetGroups: [ .TargetGroups[]? | select(.VpcId as $v | $vlist | index($v)) | {
    arn: .TargetGroupArn, name: .TargetGroupName, vpcId: .VpcId,
    port: .Port, protocol: .Protocol, targetType: .TargetType,
    lbArns: (.LoadBalancerArns // [])
  } ]}' "$BUNDLE/network/target-groups-raw.json" > "$BUNDLE/network/target-groups.json"
TG_COUNT=$(jq '.targetGroups | length' "$BUNDLE/network/target-groups.json")

# Target health per target group — reveals whether any tikv/tidb/etc instance is
# actually registered behind a load balancer (CONFIRMED-tier signal for MY5/connection-layer checks)
: > "$BUNDLE/network/target-health-raw.jsonl"
for tg_arn in $(jq -r '.targetGroups[].arn' "$BUNDLE/network/target-groups.json"); do
  aws elbv2 describe-target-health --region "$REGION" --target-group-arn "$tg_arn" --output json 2>>"$BUNDLE/network/target-health.err" \
    | jq --arg tg "$tg_arn" '{tgArn: $tg, targets: [.TargetHealthDescriptions[]? | {id: .Target.Id, port: .Target.Port, health: .TargetHealth.State}]}' \
    >> "$BUNDLE/network/target-health-raw.jsonl" 2>/dev/null
done
if [[ -s "$BUNDLE/network/target-health.err" ]]; then
  API_ERRORS+=("describe-target-health: $(tr '\n' ' ' < "$BUNDLE/network/target-health.err" | head -c 200)")
fi
rm -f "$BUNDLE/network/target-health.err"
jq -s '{targetHealth: .}' "$BUNDLE/network/target-health-raw.jsonl" > "$BUNDLE/network/target-health.json" 2>/dev/null \
  || echo '{"targetHealth":[]}' > "$BUNDLE/network/target-health.json"

log "  ✓ $LB_COUNT load balancers, $TG_COUNT target groups"

# ----------------------------------------------------------------------------
# 5. VPC metadata
# ----------------------------------------------------------------------------
run_describe "describe-vpcs" "$BUNDLE/network/vpcs-raw.json" '{"Vpcs":[]}' \
  aws ec2 describe-vpcs --region "$REGION" --vpc-ids "${VPC_ARR[@]}" --output json
jq '{vpcs: [ .Vpcs[]? | {vpcId: .VpcId, cidr: .CidrBlock,
  name: ((.Tags // []) | map(select(.Key=="Name")) | (.[0].Value // null))} ]}' \
  "$BUNDLE/network/vpcs-raw.json" > "$BUNDLE/network/vpcs.json"

# ----------------------------------------------------------------------------
# Manifest
# ----------------------------------------------------------------------------
rmdir "$BUNDLE/manifest_tmp" 2>/dev/null || true
cat > "$BUNDLE/manifest.json" <<EOF
{
  "schemaVersion": "1.0",
  "generator": "selfhosted-stack-analyzer/collect-ec2.sh",
  "substrate": "raw-ec2",
  "region": "$REGION",
  "vpcs": "$VPCS",
  "collectedAt": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "counts": {
    "instances": ${INST_COUNT:-0},
    "componentClusters": ${GROUP_COUNT:-0},
    "volumes": $(jq '.volumes | length' "$BUNDLE/ec2/volumes.json"),
    "snapshots": ${SNAP_COUNT:-0},
    "volumesWithoutBackup": ${NO_BACKUP_COUNT:-0},
    "natGateways": $(jq '.natGateways | length' "$BUNDLE/network/nat-gateways.json"),
    "internetGateways": $(jq '.internetGateways | length' "$BUNDLE/network/internet-gateways.json"),
    "routeTables": $(jq '.routeTables | length' "$BUNDLE/network/route-tables.json"),
    "vpcEndpoints": $(jq '.vpcEndpoints | length' "$BUNDLE/network/vpc-endpoints.json"),
    "eips": $(jq '.eips | length' "$BUNDLE/network/eips.json"),
    "networkInterfaces": $(jq '.networkInterfaces | length' "$BUNDLE/network/enis.json"),
    "networkAcls": $(jq '.networkAcls | length' "$BUNDLE/network/nacls.json"),
    "vpcPeeringConnections": $(jq '.vpcPeering | length' "$BUNDLE/network/vpc-peering.json"),
    "tgwAttachments": $(jq '.tgwAttachments | length' "$BUNDLE/network/tgw-attachments.json"),
    "loadBalancers": ${LB_COUNT:-0},
    "targetGroups": ${TG_COUNT:-0}
  },
  "natGatewayPerVpc": $(jq '[.natGateways[] | .vpcId] | group_by(.) | map({(.[0]): length}) | add // {}' "$BUNDLE/network/nat-gateways.json"),
  "componentSummary": $(jq '[.groups[] | {clusterKey, component, count, running, azSpread}]' "$BUNDLE/ec2/nametag-groups.json"),
  "apiErrors": $(printf '%s\n' "${API_ERRORS[@]:-}" | jq -R . | jq -s '[.[] | select(. != "")]'),
  "apiErrorsNote": "如果 apiErrors 非空，说明对应资源类型的采集是因为 API 调用失败（权限/参数/限流等）而写入了空占位符，不代表'该资源确实不存在'。分析阶段必须检查此字段，凡列在这里的资源类型都应标记为 UNABLE_TO_ASSESS，不能当作 CONFIRMED 的空结果。"
}
EOF

# package
ARCHIVE="${OUTPUT}/evidence-bundle-ec2-${REGION}-${TS}.tar.gz"
tar -czf "$ARCHIVE" -C "$OUTPUT" "$(basename "$BUNDLE")" 2>/dev/null && log "Archive: $ARCHIVE"

echo ""
echo "=========================================================="
echo " Phase 1 (RAW EC2) collection complete"
echo "=========================================================="
echo " Bundle dir : $BUNDLE"
echo " Archive    : ${ARCHIVE:-<tar unavailable>}"
echo " Instances  : ${INST_COUNT} in ${GROUP_COUNT} component clusters"
echo " Snapshots  : ${SNAP_COUNT} found; ${NO_BACKUP_COUNT} volume(s) have NO snapshot (see ec2/backup-coverage.json)"
echo " Network    : $(jq '.natGateways|length' "$BUNDLE/network/nat-gateways.json") NAT GW, $(jq '.internetGateways|length' "$BUNDLE/network/internet-gateways.json") IGW, $(jq '.routeTables|length' "$BUNDLE/network/route-tables.json") route tables, $(jq '.vpcEndpoints|length' "$BUNDLE/network/vpc-endpoints.json") VPC endpoints, $(jq '.eips|length' "$BUNDLE/network/eips.json") EIP, $(jq '.networkInterfaces|length' "$BUNDLE/network/enis.json") ENI, $(jq '.networkAcls|length' "$BUNDLE/network/nacls.json") NACL, $(jq '.vpcPeering|length' "$BUNDLE/network/vpc-peering.json") peering, $(jq '.tgwAttachments|length' "$BUNDLE/network/tgw-attachments.json") TGW attachments"
echo " Load Bal.  : ${LB_COUNT} ALB/NLB, ${TG_COUNT} target groups"
echo " NAT per VPC: $(jq -c . "$BUNDLE/manifest.json" | jq -r '.natGatewayPerVpc')  ⚠ 单 NAT 的 VPC 是 AZ 故障出网单点"
echo ""
echo " Component clusters (by Name tag):"
jq -r '.groups[] | "   [\(.component)] \(.clusterKey): \(.count) nodes, AZ=\(.azSpread), running=\(.running)"' \
  "$BUNDLE/ec2/nametag-groups.json"
echo "=========================================================="
