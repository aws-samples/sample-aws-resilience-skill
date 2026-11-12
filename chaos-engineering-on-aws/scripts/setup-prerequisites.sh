#!/usr/bin/env bash
# setup-prerequisites.sh — Chaos Engineering Environment Preparation Script
#
# Prepares common prerequisites for chaos engineering experiments.
# Designed for customers to run in their own change management process before experiments.
#
# Usage:
#   ./setup-prerequisites.sh --region <region> [options]
#
# Options:
#   --region <region>           AWS region (required)
#   --create-fis-role           Create FIS experiment IAM role
#   --create-stop-alarm         Create a basic stop condition CloudWatch alarm
#   --alb-name <name>           ALB dimension for the stop alarm, format: app/<name>/<id>
#                               (required with --create-stop-alarm; without a
#                               LoadBalancer dimension the alarm never fires)
#   --alarm-topic-arn <arn>     SNS topic ARN for alarm notifications
#   --tag-resources <ids>       Tag resources for Scenario Library (comma-separated)
#   --check-chaos-mesh          Check Chaos Mesh installation in EKS cluster
#   --install-chaos-mesh        Install Chaos Mesh via Helm (requires kubectl + helm)
#   --cluster-name <name>       EKS cluster name (for Chaos Mesh operations)
#   --dry-run                   Print actions without executing
#   --help                      Show this help message
#
# Examples:
#   # Create FIS role and basic stop alarm
#   ./setup-prerequisites.sh --region us-east-1 --create-fis-role --create-stop-alarm
#
#   # Tag resources for Scenario Library
#   ./setup-prerequisites.sh --region us-east-1 --tag-resources i-0abc123,vol-0def456
#
#   # Check and install Chaos Mesh
#   ./setup-prerequisites.sh --region us-east-1 --cluster-name my-cluster --install-chaos-mesh
#
#   # Dry-run to preview all actions
#   ./setup-prerequisites.sh --region us-east-1 --create-fis-role --dry-run

set -euo pipefail

# ── Defaults ─────────────────────────────────────────────────────────────────
REGION=""
CREATE_FIS_ROLE=false
CREATE_STOP_ALARM=false
ALB_NAME=""
ALARM_TOPIC_ARN=""
TAG_RESOURCES=""
CHECK_CHAOS_MESH=false
INSTALL_CHAOS_MESH=false
CLUSTER_NAME=""
DRY_RUN=false
FIS_ROLE_NAME="FISExperimentRole"

# ── Colors ───────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info()  { echo -e "${GREEN}[INFO]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }
dry()   { echo -e "${YELLOW}[DRY-RUN]${NC} $*"; }

# ── Argument Parsing ─────────────────────────────────────────────────────────
usage() {
  sed -n '/^# Usage:/,/^$/p' "$0" | sed 's/^# //' | sed 's/^#//'
  exit 0
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --region)            REGION="$2"; shift 2 ;;
    --create-fis-role)   CREATE_FIS_ROLE=true; shift ;;
    --create-stop-alarm) CREATE_STOP_ALARM=true; shift ;;
    --alb-name)          ALB_NAME="$2"; shift 2 ;;
    --alarm-topic-arn)   ALARM_TOPIC_ARN="$2"; shift 2 ;;
    --tag-resources)     TAG_RESOURCES="$2"; shift 2 ;;
    --check-chaos-mesh)  CHECK_CHAOS_MESH=true; shift ;;
    --install-chaos-mesh) INSTALL_CHAOS_MESH=true; shift ;;
    --cluster-name)      CLUSTER_NAME="$2"; shift 2 ;;
    --dry-run)           DRY_RUN=true; shift ;;
    --help|-h)           usage ;;
    *) error "Unknown option: $1"; usage ;;
  esac
done

if [[ -z "$REGION" ]]; then
  error "--region is required"
  exit 1
fi

# ── Preflight ────────────────────────────────────────────────────────────────
info "Verifying AWS credentials..."
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text --region "$REGION" 2>/dev/null) || {
  error "AWS credentials not configured or expired. Run 'aws configure' or set AWS_PROFILE."
  exit 1
}
info "Account: $ACCOUNT_ID, Region: $REGION"

# ── Create FIS IAM Role ─────────────────────────────────────────────────────
if $CREATE_FIS_ROLE; then
  info "=== Creating FIS Experiment Role ==="

  # Check if role already exists
  if aws iam get-role --role-name "$FIS_ROLE_NAME" &>/dev/null; then
    warn "Role '$FIS_ROLE_NAME' already exists. Skipping creation."
  else
    TRUST_POLICY=$(cat <<'TRUST_EOF'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": { "Service": "fis.amazonaws.com" },
      "Action": "sts:AssumeRole",
      "Condition": {
        "StringEquals": { "aws:SourceAccount": "ACCOUNT_PLACEHOLDER" }
      }
    }
  ]
}
TRUST_EOF
)
    TRUST_POLICY="${TRUST_POLICY//ACCOUNT_PLACEHOLDER/$ACCOUNT_ID}"

    FIS_POLICY=$(cat <<'POLICY_EOF'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "EC2DestructiveActions",
      "Effect": "Allow",
      "Action": [
        "ec2:TerminateInstances",
        "ec2:StopInstances",
        "ec2:StartInstances",
        "ec2:RebootInstances"
      ],
      "Resource": "*",
      "Condition": {
        "StringEquals": { "aws:ResourceTag/AzImpairmentPower": ["StopInstances", "IceAsg"] }
      }
    },
    {
      "Sid": "EKSNodeTermination",
      "Effect": "Allow",
      "Action": "ec2:TerminateInstances",
      "Resource": "*",
      "Condition": {
        "Null": { "aws:ResourceTag/eks:nodegroup-name": "false" }
      }
    },
    {
      "Sid": "EC2DescribeActions",
      "Effect": "Allow",
      "Action": [
        "ec2:DescribeInstances",
        "ec2:DescribeInstanceStatus"
      ],
      "Resource": "*"
    },
    {
      "Sid": "NetworkActions",
      "Effect": "Allow",
      "Action": [
        "ec2:CreateNetworkAcl",
        "ec2:CreateNetworkAclEntry",
        "ec2:DeleteNetworkAcl",
        "ec2:DeleteNetworkAclEntry",
        "ec2:DescribeNetworkAcls",
        "ec2:ReplaceNetworkAclAssociation",
        "ec2:DescribeSubnets",
        "ec2:DescribeVpcs",
        "ec2:CreateRoute",
        "ec2:DeleteRoute",
        "ec2:ReplaceRoute",
        "ec2:DescribeRouteTables"
      ],
      "Resource": "*"
    },
    {
      "Sid": "EBSPauseActions",
      "Effect": "Allow",
      "Action": [
        "ec2:PauseVolumeIO"
      ],
      "Resource": "*",
      "Condition": {
        "StringEquals": { "aws:ResourceTag/AzImpairmentPower": "ApiPauseVolume" }
      }
    },
    {
      "Sid": "EBSDescribeActions",
      "Effect": "Allow",
      "Action": [
        "ec2:DescribeVolumes"
      ],
      "Resource": "*"
    },
    {
      "Sid": "EKSActions",
      "Effect": "Allow",
      "Action": [
        "eks:DescribeNodegroup",
        "eks:DescribeCluster"
      ],
      "Resource": "*"
    },
    {
      "Sid": "RDSActions",
      "Effect": "Allow",
      "Action": [
        "rds:FailoverDBCluster",
        "rds:RebootDBInstance",
        "rds:DescribeDBClusters",
        "rds:DescribeDBInstances"
      ],
      "Resource": "*"
    },
    {
      "Sid": "LambdaActions",
      "Effect": "Allow",
      "Action": [
        "lambda:InvokeFunction",
        "lambda:GetFunction"
      ],
      "Resource": "*"
    },
    {
      "Sid": "ElastiCacheActions",
      "Effect": "Allow",
      "Action": [
        "elasticache:InterruptClusterAzPower",
        "elasticache:DescribeReplicationGroups"
      ],
      "Resource": "*"
    },
    {
      "Sid": "AutoScalingActions",
      "Effect": "Allow",
      "Action": [
        "autoscaling:DescribeAutoScalingGroups"
      ],
      "Resource": "*"
    },
    {
      "Sid": "Monitoring",
      "Effect": "Allow",
      "Action": [
        "cloudwatch:DescribeAlarms",
        "logs:CreateLogDelivery",
        "logs:GetLogDelivery",
        "logs:UpdateLogDelivery",
        "logs:DeleteLogDelivery",
        "logs:ListLogDeliveries"
      ],
      "Resource": "*"
    }
  ]
}
POLICY_EOF
)

    if $DRY_RUN; then
      dry "Would create IAM Role: $FIS_ROLE_NAME"
      dry "Trust policy: fis.amazonaws.com with account condition $ACCOUNT_ID"
      dry "Would attach inline policy with EC2, EKS, RDS, Lambda, Network, EBS, ElastiCache, CloudWatch permissions"
      dry "Destructive EC2/EBS actions are scoped to AzImpairmentPower-tagged resources (EKS managed nodes: terminate only)"
    else
      info "Creating IAM Role: $FIS_ROLE_NAME"
      # IAM is a global service — no --region needed
      aws iam create-role \
        --role-name "$FIS_ROLE_NAME" \
        --assume-role-policy-document "$TRUST_POLICY" \
        --tags Key=Project,Value=ChaosEngineering Key=ManagedBy,Value=setup-prerequisites

      info "Attaching inline policy..."
      aws iam put-role-policy \
        --role-name "$FIS_ROLE_NAME" \
        --policy-name FISExperimentPolicy \
        --policy-document "$FIS_POLICY"

      info "FIS Role created: arn:aws:iam::${ACCOUNT_ID}:role/${FIS_ROLE_NAME}"
      info "⚠️  Destructive EC2/EBS actions require target resources to be tagged"
      info "    with AzImpairmentPower (use --tag-resources). Review and"
      info "    narrow down other permissions based on your specific experiments."
    fi
  fi
fi

# ── Create Stop Condition Alarm ──────────────────────────────────────────────
if $CREATE_STOP_ALARM; then
  info "=== Creating Stop Condition CloudWatch Alarm ==="
  ALARM_NAME="chaos-experiment-stop-condition"

  # Without a LoadBalancer dimension this metric matches no data, and with
  # treat-missing-data=notBreaching the alarm would NEVER fire — a silently
  # broken safety guardrail is worse than none, so refuse to create it.
  if [[ -z "$ALB_NAME" ]]; then
    error "--create-stop-alarm requires --alb-name (format: app/<alb-name>/<id>)."
    error "Find it with: aws elbv2 describe-load-balancers --region $REGION \\"
    error "  --query 'LoadBalancers[].{name:LoadBalancerName,arn:LoadBalancerArn}'"
    error "The dimension value is the ARN part after ':loadbalancer/'."
    exit 1
  fi

  if aws cloudwatch describe-alarms --alarm-names "$ALARM_NAME" --region "$REGION" \
      --query "MetricAlarms[0].AlarmName" --output text 2>/dev/null | grep -q "$ALARM_NAME"; then
    warn "Alarm '$ALARM_NAME' already exists. Skipping creation."
  else
    ALARM_ACTIONS=""
    if [[ -n "$ALARM_TOPIC_ARN" ]]; then
      ALARM_ACTIONS="--alarm-actions $ALARM_TOPIC_ARN"
    fi

    if $DRY_RUN; then
      dry "Would create CloudWatch Alarm: $ALARM_NAME"
      dry "Metric: AWS/ApplicationELB HTTPCode_Target_5XX_Count > 100 for 1 min"
      dry "Dimension: LoadBalancer=$ALB_NAME"
      if [[ -n "$ALARM_TOPIC_ARN" ]]; then
        dry "Notification: $ALARM_TOPIC_ARN"
      fi
    else
      info "Creating alarm: $ALARM_NAME (LoadBalancer=$ALB_NAME)"
      # shellcheck disable=SC2086
      aws cloudwatch put-metric-alarm \
        --alarm-name "$ALARM_NAME" \
        --alarm-description "Stop chaos experiment when 5xx errors exceed threshold" \
        --metric-name HTTPCode_Target_5XX_Count \
        --namespace AWS/ApplicationELB \
        --dimensions "Name=LoadBalancer,Value=$ALB_NAME" \
        --statistic Sum \
        --period 60 \
        --threshold 100 \
        --comparison-operator GreaterThanThreshold \
        --evaluation-periods 1 \
        --treat-missing-data notBreaching \
        --tags Key=Project,Value=ChaosEngineering \
        --region "$REGION" \
        $ALARM_ACTIONS

      info "Alarm created: $ALARM_NAME"
      info "⚠️  Adjust threshold (default: >100 5xx/min) to your traffic profile."
    fi
  fi
fi

# ── Tag Resources for Scenario Library ───────────────────────────────────────
if [[ -n "$TAG_RESOURCES" ]]; then
  info "=== Tagging Resources for FIS Scenario Library ==="
  IFS=',' read -ra RESOURCE_IDS <<< "$TAG_RESOURCES"

  for RESOURCE_ID in "${RESOURCE_IDS[@]}"; do
    RESOURCE_ID=$(echo "$RESOURCE_ID" | xargs)  # trim whitespace
    # Tag values follow the official AZ Power Interruption scenario (one per target type)
    case "$RESOURCE_ID" in
      i-*)      TAG_VALUE="StopInstances" ;;
      vol-*)    TAG_VALUE="ApiPauseVolume" ;;
      subnet-*) TAG_VALUE="DisruptSubnet" ;;
      *)
        warn "Skipping $RESOURCE_ID: only instance (i-), volume (vol-) and subnet (subnet-) IDs are supported"
        continue ;;
    esac
    if $DRY_RUN; then
      dry "Would tag $RESOURCE_ID with AzImpairmentPower=$TAG_VALUE"
    else
      info "Tagging $RESOURCE_ID with AzImpairmentPower=$TAG_VALUE"
      aws ec2 create-tags \
        --resources "$RESOURCE_ID" \
        --tags "Key=AzImpairmentPower,Value=$TAG_VALUE" \
        --region "$REGION"
    fi
  done
  info "Resource tagging complete."
fi

# ── Check / Install Chaos Mesh ───────────────────────────────────────────────
if $CHECK_CHAOS_MESH || $INSTALL_CHAOS_MESH; then
  if [[ -n "$CLUSTER_NAME" ]]; then
    info "Updating kubeconfig for cluster: $CLUSTER_NAME"
    if ! $DRY_RUN; then
      aws eks update-kubeconfig --name "$CLUSTER_NAME" --region "$REGION" 2>/dev/null || {
        error "Failed to update kubeconfig for cluster: $CLUSTER_NAME"
        exit 1
      }
    fi
  else
    # No cluster specified — make the implicit target explicit to the user
    CURRENT_CTX=$(kubectl config current-context 2>/dev/null || echo "none")
    warn "No --cluster-name given. Using current kubectl context: $CURRENT_CTX"
  fi

  if $CHECK_CHAOS_MESH; then
    info "=== Checking Chaos Mesh Installation ==="
    if kubectl get crd 2>/dev/null | grep -q chaos-mesh; then
      CM_VERSION=$(kubectl get deploy chaos-controller-manager -n chaos-mesh -o jsonpath='{.spec.template.spec.containers[0].image}' 2>/dev/null | awk -F: '{print $2}')
      info "✅ Chaos Mesh is installed (version: ${CM_VERSION:-unknown})"
      kubectl get pods -n chaos-mesh --no-headers 2>/dev/null | while read -r line; do
        info "  Pod: $line"
      done
    else
      warn "❌ Chaos Mesh is NOT installed in this cluster."
      info "Run with --install-chaos-mesh to install."
    fi
  fi

  if $INSTALL_CHAOS_MESH; then
    info "=== Installing Chaos Mesh ==="

    if ! command -v helm &>/dev/null; then
      error "Helm is required but not installed. Install from https://helm.sh/docs/intro/install/"
      exit 1
    fi

    if kubectl get crd 2>/dev/null | grep -q chaos-mesh; then
      warn "Chaos Mesh is already installed. Skipping."
    else
      if $DRY_RUN; then
        dry "Would install Chaos Mesh via Helm into namespace chaos-mesh"
        dry "Runtime: containerd, Socket: /run/containerd/containerd.sock"
      else
        info "Adding Chaos Mesh Helm repository..."
        helm repo add chaos-mesh https://charts.chaos-mesh.org
        helm repo update

        info "Installing Chaos Mesh..."
        helm install chaos-mesh chaos-mesh/chaos-mesh \
          --namespace chaos-mesh \
          --create-namespace \
          --set chaosDaemon.runtime=containerd \
          --set chaosDaemon.socketPath=/run/containerd/containerd.sock \
          --wait --timeout 5m

        info "✅ Chaos Mesh installed successfully."
        kubectl get pods -n chaos-mesh
      fi
    fi
  fi
fi

# ── Summary ──────────────────────────────────────────────────────────────────
echo ""
info "=== Setup Summary ==="
$CREATE_FIS_ROLE && info "FIS Role: $($DRY_RUN && echo 'would create' || echo 'created/exists') $FIS_ROLE_NAME"
$CREATE_STOP_ALARM && info "Stop Alarm: $($DRY_RUN && echo 'would create' || echo 'created/exists') chaos-experiment-stop-condition"
[[ -n "$TAG_RESOURCES" ]] && info "Tagged resources: $TAG_RESOURCES"
$CHECK_CHAOS_MESH && info "Chaos Mesh check: complete"
$INSTALL_CHAOS_MESH && info "Chaos Mesh install: $($DRY_RUN && echo 'would install' || echo 'complete')"

if $DRY_RUN; then
  echo ""
  warn "This was a dry run. No changes were made. Remove --dry-run to execute."
fi
