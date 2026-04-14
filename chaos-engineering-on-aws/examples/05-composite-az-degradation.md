# Example 05: Composite AZ Degradation — Multi-Action FIS Experiment

> This example demonstrates how to use **FIS native multi-action templates** to simulate compound AZ-level failures without any external orchestration code.

## Scenario

Simulate degradation in a single Availability Zone by simultaneously:
1. **Stopping EC2 instances** in the target AZ
2. **Pausing EBS volume IO** in the target AZ
3. **Triggering RDS Aurora failover**

EC2 stop and EBS pause start immediately (parallel). RDS failover starts 30 seconds later (serial dependency via `startAfter`).

## Architecture

```
          AZ-a (target)              AZ-c (healthy)
  ┌──────────────────────┐    ┌──────────────────────┐
  │  EC2: stopped ❌      │    │  EC2: running ✅      │
  │  EBS: IO paused ❌    │    │  EBS: normal ✅       │
  │  RDS Writer → fails   │───►│  RDS Reader → Writer  │
  └──────────────────────┘    └──────────────────────┘
```

## Hypothesis

**Statement**: When EC2 instances in AZ-a are stopped, EBS IO is paused, and RDS fails over, the application should:
- Continue serving requests via healthy AZ-c instances
- Complete RDS failover within 30 seconds
- Maintain request success rate ≥ 95% during the event
- Fully recover within 120 seconds after fault injection stops

## Prerequisites

- [ ] Multi-AZ deployment with instances in at least 2 AZs
- [ ] Target EC2 instances and EBS volumes tagged with `AzImpairmentPower: IceQualified`
- [ ] RDS Aurora cluster with reader instance in another AZ
- [ ] FIS IAM Role with required permissions (see below)
- [ ] CloudWatch Alarm for stop condition
- [ ] Sufficient capacity in remaining AZs

## FIS Template (Multi-Action with `startAfter`)

> Full JSON template: [references/templates/az-power-interruption.json](../references/templates/az-power-interruption.json)

The key `actions` section (showing orchestration logic):

```json
{
  "actions": {
    "stop-ec2-az-a": {
      "actionId": "aws:ec2:stop-instances",
      "parameters": { "startInstancesAfterDuration": "PT5M" },
      "targets": { "Instances": "ec2-instances-az-a" }
    },
    "pause-ebs-az-a": {
      "actionId": "aws:ebs:pause-volume-io",
      "parameters": { "duration": "PT5M" },
      "targets": { "Volumes": "ebs-volumes-az-a" }
    },
    "failover-rds": {
      "actionId": "aws:rds:failover-db-cluster",
      "targets": { "Clusters": "rds-cluster" },
      "startAfter": ["stop-ec2-az-a"]
    },
    "wait-before-rds": {
      "actionId": "aws:fis:wait",
      "parameters": { "duration": "PT30S" },
      "startAfter": ["stop-ec2-az-a"]
    }
  }
}
```

### Key Design Points

| Aspect | Implementation |
|--------|---------------|
| **Parallel actions** | `stop-ec2-az-a` and `pause-ebs-az-a` have no `startAfter` → FIS runs them simultaneously |
| **Serial dependency** | `failover-rds` has `"startAfter": ["stop-ec2-az-a"]` → waits for EC2 stop to begin |
| **Timed delay** | `wait-before-rds` uses `aws:fis:wait` with `PT30S` to insert a 30s gap |
| **Auto-recovery** | `startInstancesAfterDuration: PT5M` auto-restarts EC2 after 5 minutes |
| **Stop condition** | CloudWatch Alarm triggers abort of ALL actions atomically |

### FIS `startAfter` Reference

| Pattern | `startAfter` | Effect |
|---------|-------------|--------|
| Parallel (default) | _(not set)_ | All actions start simultaneously |
| Sequential | `["action-A"]` | Starts after action-A **begins** |
| Chain | `["action-A", "action-B"]` | Starts after **both** A and B begin |
| Delayed | Use `aws:fis:wait` action | Insert a timed gap between actions |

## Execution

```bash
# 1. Create the multi-action template
TEMPLATE_ID=$(aws fis create-experiment-template \
  --cli-input-json file://output/templates/composite-az-degradation.json \
  --region ap-northeast-1 \
  --query 'experimentTemplate.id' --output text)
echo "Template created: $TEMPLATE_ID"

# 2. Run via experiment-runner.sh (same as single-action — no changes needed)
nohup bash scripts/experiment-runner.sh \
  --mode fis \
  --template-id "$TEMPLATE_ID" \
  --region ap-northeast-1 \
  --timeout 720 \
  --poll-interval 15 \
  --output-dir output/ &
RUNNER_PID=$!

# 3. Start monitoring
nohup bash scripts/monitor.sh &

# 4. Start log collection
nohup bash scripts/log-collector.sh \
  --namespace petadoptions \
  --services "petsite,petsearch,payforadoption" \
  --duration 720 \
  --output-dir output/ \
  --mode live &

# 5. Wait
wait $RUNNER_PID
echo "Runner exit code: $?"
```

## Stop Condition Alarm

```bash
aws cloudwatch put-metric-alarm \
  --alarm-name "chaos-stop-high-5xx" \
  --namespace "AWS/ApplicationELB" \
  --metric-name "HTTPCode_Target_5XX_Count" \
  --statistic Sum \
  --period 60 \
  --threshold 100 \
  --comparison-operator GreaterThanThreshold \
  --evaluation-periods 2 \
  --treat-missing-data notBreaching \
  --dimensions Name=LoadBalancer,Value=app/my-alb/1234567890 \
  --region ap-northeast-1
```

## FIS IAM Role Permissions

The FIS role needs permissions for all actions in the template:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ec2:StopInstances",
        "ec2:StartInstances",
        "ec2:DescribeInstances",
        "ebs:PauseVolumeIO",
        "ebs:DescribeVolumes",
        "rds:FailoverDBCluster",
        "rds:DescribeDBClusters"
      ],
      "Resource": "*"
    }
  ]
}
```

## Expected Results

### PASSED ✅ Scenario
- EC2 instances in AZ-a stopped → traffic shifts to AZ-c
- EBS IO paused → no cascading failure (data layer isolated)
- RDS failover completes within 30s
- Success rate stays ≥ 95% throughout
- Full recovery within 120s after faults end

### FAILED ❌ Scenarios
- Success rate drops below 95% → application not AZ-resilient
- RDS failover takes > 30s → database HA needs tuning
- Recovery time exceeds 120s → auto-scaling or health checks too slow
- Cascading failure to AZ-c → single points of failure exist

## Duration Override

To run a shorter version for quick validation:

```bash
# Modify all action durations to 2 minutes
jq '
  .actions["stop-ec2-az-a"].parameters.startInstancesAfterDuration = "PT2M" |
  .actions["pause-ebs-az-a"].parameters.duration = "PT2M"
' output/templates/composite-az-degradation.json > output/templates/composite-az-degradation-short.json
```

## Cost Estimate

| Action | Duration | Action-Minutes | Cost |
|--------|----------|---------------|------|
| EC2 Stop | 5 min | 5 | $0.50 |
| EBS Pause IO | 5 min | 5 | $0.50 |
| RDS Failover | ~30s | 0.5 | $0.05 |
| FIS Wait | 30s | 0.5 | $0.05 |
| **Total** | | **11** | **$1.10** |
