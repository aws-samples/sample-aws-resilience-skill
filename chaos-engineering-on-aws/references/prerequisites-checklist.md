# Chaos Engineering Prerequisites Checklist

This document lists all prerequisites for chaos engineering experiments, organized by architecture pattern. Use it to prepare your environment before running experiments.

> **Tip**: Run `scripts/setup-prerequisites.sh` to automate common setup tasks.

---

## Common Prerequisites (All Architectures)

### IAM Permissions

#### FIS Experiment Role

An IAM role that FIS assumes to execute experiments. Required for all FIS-based experiments.

```
Role name: FISExperimentRole (recommended)
Trust policy: fis.amazonaws.com
```

**Minimum permissions by experiment type:**

| Experiment Type | Required Permissions |
|----------------|---------------------|
| EC2 terminate/stop/reboot | `ec2:TerminateInstances`, `ec2:StopInstances`, `ec2:StartInstances`, `ec2:RebootInstances`, `ec2:DescribeInstances` |
| EKS node termination | `ec2:TerminateInstances`, `eks:DescribeNodegroup`, `autoscaling:*` |
| RDS failover/reboot | `rds:FailoverDBCluster`, `rds:RebootDBInstance`, `rds:DescribeDBClusters` |
| Network disruption | `ec2:CreateNetworkAcl`, `ec2:CreateNetworkAclEntry`, `ec2:DeleteNetworkAcl`, `ec2:DeleteNetworkAclEntry`, `ec2:DescribeNetworkAcls`, `ec2:ReplaceNetworkAclAssociation`, `ec2:DescribeSubnets`, `ec2:DescribeVpcs` |
| EBS volume IO pause | `ec2:PauseVolumeIO`, `ec2:DescribeVolumes` |
| Lambda fault injection | `lambda:InvokeFunction`, `lambda:GetFunction` (FIS extension permissions) |
| API error injection | `fis:InjectApiInternalError`, `fis:InjectApiThrottleError` |
| ElastiCache AZ power | `elasticache:InterruptClusterAzPower`, `elasticache:DescribeReplicationGroups` |
| S3 replication pause | `s3:PutReplicationConfiguration`, `s3:GetReplicationConfiguration` |
| DynamoDB replication pause | `dynamodb:DescribeTable`, `dynamodb:UpdateTable` |

**FIS also needs:**
- `logs:CreateLogDelivery` (if logging to CloudWatch Logs)
- `cloudwatch:DescribeAlarms` (for stop conditions)

#### Tiered FIS IAM Policies

Instead of assembling permissions manually, use one of these ready-to-use policy templates. Attach the appropriate tier to your `FISExperimentRole`.

> **Recommendation**: Add a [Permission Boundary](https://docs.aws.amazon.com/IAM/latest/UserGuide/access_policies_boundaries.html) to `FISExperimentRole` to prevent privilege escalation. Set the boundary to limit scope to only the services you experiment on.

**Tier 1 — EC2 Only** (safe starting point for EC2 experiments):

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "FISTier1EC2",
      "Effect": "Allow",
      "Action": [
        "ec2:DescribeInstances",
        "ec2:TerminateInstances",
        "ec2:StopInstances",
        "ec2:StartInstances",
        "ec2:RebootInstances",
        "ec2:SendSpotInstanceInterruptions",
        "ec2:CreateNetworkAcl",
        "ec2:CreateNetworkAclEntry",
        "ec2:DeleteNetworkAcl",
        "ec2:DeleteNetworkAclEntry",
        "ec2:DescribeNetworkAcls",
        "ec2:ReplaceNetworkAclAssociation",
        "ec2:DescribeSubnets",
        "ec2:DescribeVpcs",
        "ec2:PauseVolumeIO",
        "ec2:DescribeVolumes",
        "logs:CreateLogDelivery",
        "cloudwatch:DescribeAlarms"
      ],
      "Resource": "*"
    }
  ]
}
```

**Tier 2 — EC2 + RDS** (adds database failover for RDS experiments):

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "FISTier2EC2RDS",
      "Effect": "Allow",
      "Action": [
        "ec2:DescribeInstances",
        "ec2:TerminateInstances",
        "ec2:StopInstances",
        "ec2:StartInstances",
        "ec2:RebootInstances",
        "ec2:SendSpotInstanceInterruptions",
        "ec2:CreateNetworkAcl",
        "ec2:CreateNetworkAclEntry",
        "ec2:DeleteNetworkAcl",
        "ec2:DeleteNetworkAclEntry",
        "ec2:DescribeNetworkAcls",
        "ec2:ReplaceNetworkAclAssociation",
        "ec2:DescribeSubnets",
        "ec2:DescribeVpcs",
        "ec2:PauseVolumeIO",
        "ec2:DescribeVolumes",
        "rds:FailoverDBCluster",
        "rds:RebootDBInstance",
        "rds:DescribeDBClusters",
        "logs:CreateLogDelivery",
        "cloudwatch:DescribeAlarms"
      ],
      "Resource": "*"
    }
  ]
}
```

**Tier 3 — Full** (all supported FIS actions including EKS, Lambda, ECS, DynamoDB, ElastiCache, S3):

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "FISTier3Full",
      "Effect": "Allow",
      "Action": [
        "ec2:DescribeInstances",
        "ec2:TerminateInstances",
        "ec2:StopInstances",
        "ec2:StartInstances",
        "ec2:RebootInstances",
        "ec2:SendSpotInstanceInterruptions",
        "ec2:CreateNetworkAcl",
        "ec2:CreateNetworkAclEntry",
        "ec2:DeleteNetworkAcl",
        "ec2:DeleteNetworkAclEntry",
        "ec2:DescribeNetworkAcls",
        "ec2:ReplaceNetworkAclAssociation",
        "ec2:DescribeSubnets",
        "ec2:DescribeVpcs",
        "ec2:PauseVolumeIO",
        "ec2:DescribeVolumes",
        "ec2:CreateRoute",
        "ec2:DeleteRoute",
        "ec2:ReplaceRoute",
        "ec2:DescribeRouteTables",
        "ec2:DescribeTransitGateways",
        "eks:DescribeNodegroup",
        "eks:ListNodegroups",
        "autoscaling:DescribeAutoScalingGroups",
        "autoscaling:TerminateInstanceInAutoScalingGroup",
        "rds:FailoverDBCluster",
        "rds:RebootDBInstance",
        "rds:DescribeDBClusters",
        "lambda:InvokeFunction",
        "lambda:GetFunction",
        "ecs:StopTask",
        "ecs:UpdateContainerInstancesState",
        "ecs:DescribeTasks",
        "ecs:ListTasks",
        "dynamodb:DescribeTable",
        "dynamodb:UpdateTable",
        "elasticache:InterruptClusterAzPower",
        "elasticache:DescribeReplicationGroups",
        "s3:PutReplicationConfiguration",
        "s3:GetReplicationConfiguration",
        "ssm:SendCommand",
        "ssm:GetCommandInvocation",
        "fis:InjectApiInternalError",
        "fis:InjectApiThrottleError",
        "logs:CreateLogDelivery",
        "cloudwatch:DescribeAlarms"
      ],
      "Resource": "*"
    }
  ]
}
```

> **Permission Boundary example** — create a boundary policy that limits the blast radius of the FIS Role:
>
> ```json
> {
>   "Version": "2012-10-17",
>   "Statement": [
>     {
>       "Effect": "Allow",
>       "Action": [
>         "ec2:*", "rds:*", "eks:*", "ecs:*", "lambda:*",
>         "elasticache:*", "dynamodb:*", "s3:GetReplicationConfiguration",
>         "s3:PutReplicationConfiguration", "autoscaling:*", "ssm:SendCommand",
>         "ssm:GetCommandInvocation", "fis:InjectApi*",
>         "logs:CreateLogDelivery", "cloudwatch:DescribeAlarms"
>       ],
>       "Resource": "*"
>     }
>   ]
> }
> ```
>
> Attach boundary when creating the role:
> ```bash
> aws iam create-role \
>   --role-name FISExperimentRole \
>   --assume-role-policy-document file://fis-trust-policy.json \
>   --permissions-boundary arn:aws:iam::<ACCOUNT_ID>:policy/FISPermissionBoundary
> ```

#### Operator Permissions

The human/CI user running the experiment needs:

```
fis:CreateExperimentTemplate
fis:StartExperiment
fis:StopExperiment
fis:GetExperiment
fis:ListExperiments
fis:ListExperimentTemplates
fis:DeleteExperimentTemplate
cloudwatch:PutMetricAlarm
cloudwatch:DescribeAlarms
cloudwatch:GetMetricData
iam:PassRole (to pass FIS Role)
```

### CloudWatch Monitoring

- At least one CloudWatch Alarm configured as a stop condition
- Key metrics collectible (latency, error rate, success rate)
- Alarm evaluation period ≤ 60s for fast reaction

### Network

- VPC with proper security group rules (allow monitoring traffic)
- Outbound internet access or VPC endpoints for AWS API calls

---

## Architecture-Specific Prerequisites

### EKS Microservices

#### Kubernetes Access

- `kubectl` configured with cluster access
- EKS authentication mode supports current credentials (ConfigMap or API)
- RBAC permissions for experiment namespace

#### Chaos Mesh (Optional but Recommended for Pod-level faults)

```bash
# Check if installed
kubectl get crd | grep chaos-mesh

# Install if needed (Helm)
helm repo add chaos-mesh https://charts.chaos-mesh.org
helm install chaos-mesh chaos-mesh/chaos-mesh \
  --namespace chaos-mesh --create-namespace \
  --set chaosDaemon.runtime=containerd \
  --set chaosDaemon.socketPath=/run/containerd/containerd.sock
```

**Chaos Mesh requirements:**
- Cluster version >= 1.24
- containerd or Docker runtime
- Sufficient RBAC for Chaos Mesh controller
- Target namespaces not excluded from Chaos Mesh scope

#### EKS-Specific

| Requirement | Check Command | Notes |
|------------|---------------|-------|
| Managed node group or ASG | `aws eks list-nodegroups --cluster-name <name>` | For node termination experiments |
| Multiple replicas | `kubectl get deploy -n <ns>` | Replicas >= 2 for resilience |
| Resource limits set | `kubectl describe pod <pod>` | Required for StressChaos |
| Pod Disruption Budget | `kubectl get pdb -n <ns>` | Recommended for controlled disruption |
| Health checks configured | `kubectl get deploy -o yaml` | Liveness + readiness probes |

### Serverless (Lambda + API Gateway + DynamoDB)

| Requirement | Check Command | Notes |
|------------|---------------|-------|
| Lambda function ARN | `aws lambda get-function --function-name <name>` | Target function exists and is active |
| Reserved concurrency | `aws lambda get-function-concurrency` | Avoid throttling unrelated functions |
| DynamoDB Global Table | `aws dynamodb describe-table` | For replication pause experiments |
| API Gateway stage | `aws apigateway get-stages` | For end-to-end latency monitoring |
| CloudWatch Logs | Check log group exists | For post-experiment log analysis |
| X-Ray tracing enabled | `aws lambda get-function-configuration` | Recommended for latency analysis |

### EC2 Traditional (ALB + ASG + RDS)

| Requirement | Check Command | Notes |
|------------|---------------|-------|
| ASG configured | `aws autoscaling describe-auto-scaling-groups` | For instance replacement |
| ALB health checks | `aws elbv2 describe-target-health` | Detect unhealthy instances |
| Multi-AZ RDS | `aws rds describe-db-clusters` | For failover experiments |
| EBS snapshots | `aws ec2 describe-snapshots` | Backup before IO pause |
| SSM Agent installed | `aws ssm describe-instance-information` | For SSM-based experiments |
| CloudWatch Agent | Check metrics namespace | For instance-level metrics |

### Multi-Region

| Requirement | Check Command | Notes |
|------------|---------------|-------|
| Multi-region deployment | Verify resources in both regions | Architecture must span regions |
| Route 53 health checks | `aws route53 list-health-checks` | DNS-based failover |
| Global Accelerator | `aws globalaccelerator list-accelerators` | Network-layer failover |
| Cross-region VPC Peering or TGW | `aws ec2 describe-vpc-peering-connections` | For route disruption experiments |
| S3 CRR configured | `aws s3api get-bucket-replication` | For replication pause |
| DynamoDB Global Table | `aws dynamodb describe-table` | For replication pause |
| Cross-region monitoring | CloudWatch cross-account/region | Monitor both regions simultaneously |

---

## FIS Scenario Library Additional Prerequisites

When using FIS Scenario Library (composite scenarios), additional requirements apply:

### Resource Tagging

Scenario Library uses **mandatory tags** to identify target resources. Apply tags **before** creating the experiment:

```bash
# For AZ Power Interruption / AZ Application Slowdown / Cross-AZ Traffic
aws ec2 create-tags --resources <instance-id> <volume-id> \
  --tags Key=AzImpairmentPower,Value=IceQualified

# Verify tags
aws ec2 describe-instances --instance-ids <id> \
  --query "Reservations[].Instances[].Tags[?Key=='AzImpairmentPower']"
```

### Expanded FIS Role Permissions

Scenario Library experiments touch multiple services. The FIS Role needs combined permissions for all sub-actions:

| Scenario | Additional Permissions Beyond Single Actions |
|----------|---------------------------------------------|
| AZ Power Interruption | All of: EC2 stop/start + EBS IO pause + RDS failover + ElastiCache interrupt |
| AZ Application Slowdown | All of: Network NACL + Lambda invoke |
| Cross-AZ Traffic | Network NACL (same as single network:disrupt-connectivity) |
| Cross-Region | Route table + TGW modification permissions in both regions |

### Capacity Validation

Before AZ-level experiments, verify remaining AZs can handle full traffic:

```bash
# Check ASG distribution across AZs
aws autoscaling describe-auto-scaling-groups \
  --query "AutoScalingGroups[].{Name:AutoScalingGroupName,AZs:AvailabilityZones,Desired:DesiredCapacity}"

# Check target group health per AZ
aws elbv2 describe-target-health --target-group-arn <arn>
```

---

## Pre-flight Quick Reference

Run these checks before any experiment:

```bash
# 1. AWS credentials valid
aws sts get-caller-identity

# 2. FIS Role exists
aws iam get-role --role-name FISExperimentRole

# 3. Target resources healthy
aws ec2 describe-instance-status --instance-ids <ids>
aws rds describe-db-clusters --db-cluster-identifier <id>
aws eks describe-cluster --name <name>

# 4. Stop condition alarm exists
aws cloudwatch describe-alarms --alarm-names <alarm-name>

# 5. Chaos Mesh installed (if EKS Pod experiments)
kubectl get crd | grep chaos-mesh
kubectl get pods -n chaos-mesh

# 6. Monitoring working
aws cloudwatch get-metric-data --metric-data-queries '[...]' \
  --start-time $(date -u -d '5 minutes ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S)
```
