# Example 13: AZ Power Interruption — Multi-Service AZ Failure Simulation

> This example demonstrates how to use the **FIS Scenario Library** to simulate a full Availability Zone power failure across multiple AWS services simultaneously.

## Scenario

Simulate power interruption in a single Availability Zone by simultaneously:
1. **Stopping EC2 instances** in the target AZ
2. **Stopping ASG-managed instances** and blocking replacement launches
3. **Disrupting network connectivity** for subnets in the target AZ
4. **Failing over RDS Aurora** if the writer is in the target AZ
5. **Interrupting ElastiCache power** for replication groups with nodes in the target AZ
6. **Pausing EBS volume IO** for volumes in the target AZ
7. **Disrupting S3 Express One Zone** directory buckets in the target AZ
8. **Triggering ARC Zonal Autoshift** to simulate traffic shift response

All actions run in parallel with a default duration of PT10M (10 minutes).

## Architecture

```
          AZ-a (target — power interrupted)           AZ-b / AZ-c (healthy)
  ┌─────────────────────────────────────┐    ┌─────────────────────────────────┐
  │  EC2: stopped ❌                     │    │  EC2: running ✅                 │
  │  ASG: instances stopped, no replace  │    │  ASG: scaling to compensate ✅   │
  │  Network: connectivity disrupted ❌  │    │  Network: normal ✅              │
  │  RDS Writer → fails                 │───►│  RDS Reader → promoted Writer   │
  │  ElastiCache: power interrupted ❌   │    │  ElastiCache: failover ✅        │
  │  EBS: IO paused ❌                   │    │  EBS: normal ✅                  │
  │  S3 Express: disrupted ❌            │    │                                 │
  └─────────────────────────────────────┘    └─────────────────────────────────┘
```

## Hypothesis

**Statement**: When a full AZ power interruption is simulated, the application should:
- Continue serving requests via healthy AZs
- Complete all service failovers (RDS, ElastiCache) within 60 seconds
- Maintain request success rate >= 95% during the event
- Fully recover within 5 minutes after the experiment ends
- ARC Zonal Autoshift should redirect traffic away from the impaired AZ

### What does this enable you to verify?

- True multi-AZ resilience across all infrastructure layers simultaneously
- Coordinated multi-service failure behavior (EC2 + Network + RDS + ElastiCache + EBS)
- Cross-AZ capacity planning — remaining AZs handle full production load
- ARC Zonal Autoshift integration and traffic shift timing
- Tag-based resource targeting with Lambda Custom Resource
- Blast radius containment — only target AZ resources are affected

## Prerequisites

- [ ] Multi-AZ deployment with instances in at least 2 AZs
- [ ] Target resources tagged with `AzImpairmentPower` key (see Tagging Strategy)
- [ ] RDS Aurora cluster with reader in another AZ
- [ ] ElastiCache replication group with Multi-AZ enabled
- [ ] FIS IAM Role with required managed policies + inline policy
- [ ] CloudWatch Alarm for stop condition
- [ ] Sufficient capacity in remaining AZs to handle full load

## Sub-Action Reference

| Sub-Action | Action ID | Target Type | Tag Value |
|-----------|-----------|-------------|-----------|
| Stop-Instances | `aws:ec2:stop-instances` | EC2 Instance | `StopInstances` |
| Stop-ASG-Instances | `aws:ec2:stop-instances` | EC2 Instance (ASG) | `IceAsg` |
| Pause-ASG-Scaling | `aws:ec2:asg-insufficient-instance-capacity-error` | Auto Scaling Group | `IceAsg` |
| Pause-Network-Connectivity | `aws:network:disrupt-connectivity` | Subnet | `DisruptSubnet` |
| Failover-RDS | `aws:rds:failover-db-cluster` | RDS Cluster | `DisruptRds` |
| Pause-ElastiCache | `aws:elasticache:replicationgroup-interrupt-az-power` | ElastiCache RG | `ElasticacheImpact` |
| Pause-EBS-IO | `aws:ebs:pause-volume-io` | EBS Volume | `ApiPauseVolume` |
| Disrupt-S3-Express | `aws:network:disrupt-connectivity` | Subnet (S3 Express) | `DisruptSubnet` |
| Start-ARC-Autoshift | `aws:arc:start-zonal-autoshift` | — | `RecoverAutoshiftResources` |

**Blast radius control**: When testing specific services only, prune sub-actions to include only relevant services plus `Pause-Network-Connectivity` (mandatory for realistic AZ simulation).

## Tagging Strategy

All sub-actions share the tag key `AzImpairmentPower`. Tags do NOT distinguish AZ — the experiment template's internal AZ filters handle AZ selection.

Tags are applied via a **Lambda-backed CFN Custom Resource** within the same CloudFormation stack:

```python
import json
import boto3
import cfnresponse

def handler(event, context):
    try:
        # Tagging logic for Create/Update/Delete events
        # Apply AzImpairmentPower tags to target resources
        cfnresponse.send(event, context, cfnresponse.SUCCESS, {})
    except Exception as e:
        print(f"ERROR: {e}")
        cfnresponse.send(event, context, cfnresponse.FAILED, {"Error": str(e)})
```

**ASG tagging is two-step** (critical):
1. Tag the ASG with `PropagateAtLaunch: true` (future instances get tagged)
2. Tag existing EC2 instances in the ASG directly (current instances need the tag immediately)

## FIS IAM Role Permissions

Use AWS managed policies for well-covered areas plus an inline policy:

| Managed Policy | Covers |
|---------------|--------|
| `AWSFaultInjectionSimulatorEC2Access` | EC2 stop/start, KMS grants, SSM |
| `AWSFaultInjectionSimulatorNetworkAccess` | Network ACL for connectivity disruption |
| `AWSFaultInjectionSimulatorRDSAccess` | RDS cluster failover |

Inline policy for remaining permissions:
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "elasticache:InterruptClusterAzPower",
        "elasticache:DescribeReplicationGroups",
        "ebs:PauseVolumeIO",
        "ebs:DescribeVolumes",
        "ec2:DescribeVolumes",
        "autoscaling:DescribeAutoScalingGroups",
        "tag:GetResources"
      ],
      "Resource": "*"
    }
  ]
}
```

## Execution

```bash
# 1. Deploy the CloudFormation stack (includes experiment template + tagging)
aws cloudformation deploy \
  --template-file az-power-interruption.yaml \
  --stack-name fis-az-power-int-2a-$(openssl rand -hex 3) \
  --parameter-overrides \
    TargetAZ=us-east-1a \
    ExperimentName=az-power-test \
  --capabilities CAPABILITY_NAMED_IAM

# 2. Get the experiment template ID
TEMPLATE_ID=$(aws cloudformation describe-stacks \
  --stack-name {STACK_NAME} \
  --query "Stacks[0].Outputs[?OutputKey=='ExperimentTemplateId'].OutputValue" \
  --output text)

# 3. Start the experiment
aws fis start-experiment --experiment-template-id $TEMPLATE_ID

# 4. Monitor experiment status
watch -n 15 'aws fis get-experiment \
  --id {EXPERIMENT_ID} \
  --query "experiment.{State:state.status,Actions:actions}"'
```

## Stop Condition Alarm

```bash
aws cloudwatch put-metric-alarm \
  --alarm-name "chaos-stop-az-power" \
  --namespace "AWS/ApplicationELB" \
  --metric-name "HTTPCode_Target_5XX_Count" \
  --statistic Sum \
  --period 60 \
  --threshold 100 \
  --comparison-operator GreaterThanThreshold \
  --evaluation-periods 2 \
  --treat-missing-data notBreaching \
  --dimensions Name=LoadBalancer,Value=app/my-alb/1234567890
```

## Observation Metrics

| Metric | Source | Expected Behavior |
|--------|--------|-------------------|
| EC2 instance state | EC2 API | running → stopped → running (after experiment ends) |
| ALB healthy host count | CloudWatch (AWS/ApplicationELB) | Drops for target AZ, stable for healthy AZs |
| RDS failover events | RDS Events | Failover triggered, writer switches AZ |
| ElastiCache IsPrimary | CloudWatch (AWS/ElastiCache) | Role swap if primary was in target AZ |
| EBS volume IO | CloudWatch (AWS/EBS) | Paused for target AZ volumes |
| Network connectivity | VPC Flow Logs | Blocked for target AZ subnets |
| ARC Zonal Autoshift | ARC API | Traffic shifted away from impaired AZ |

## Expected Results

### PASSED
- All services in target AZ impaired as expected
- Traffic automatically shifts to healthy AZs
- Service failovers (RDS, ElastiCache) complete within 60 seconds
- Application success rate >= 95% throughout experiment
- Full recovery within 5 minutes after experiment ends

### FAILED
- Application success rate drops below 95% — not truly AZ-resilient
- RDS or ElastiCache failover exceeds 60 seconds — HA configuration needs tuning
- Recovery time exceeds 5 minutes — auto-scaling or health checks too slow
- Cascading failure to healthy AZs — single points of failure exist
- ASG cannot scale in healthy AZs — capacity or limits issue

## Duration Override

To run a shorter version:

```bash
# Default: PT10M (10 minutes), override to PT5M
# Update all action durations in the experiment template
```

## Cleanup

```bash
# Delete the CloudFormation stack (removes experiment template + tags)
aws cloudformation delete-stack --stack-name {STACK_NAME}

# Verify stack deletion
aws cloudformation wait stack-delete-complete --stack-name {STACK_NAME}
```

The Lambda Custom Resource automatically removes all `AzImpairmentPower` tags during stack deletion.

## Design Notes

- **One stack per AZ**: Target AZ is hardcoded in the experiment template. To test a different AZ, delete and redeploy.
- **Pause-Instance-Launches removed by default**: The `aws:ec2:api-insufficient-instance-capacity-error` action is excluded because `Pause-ASG-Scaling` already blocks ASG launches, and FIS does not accept service-linked roles as targets.
- **Tag-based targeting**: AZ filtering is done by the experiment template, not by tags. Resources in all AZs can carry the same tags simultaneously.
