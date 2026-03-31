# Example 4: AZ Network Isolation — Multi-AZ Fault Tolerance Validation

**Architecture pattern**: Multi-AZ deployment (ALB + EC2/EKS + RDS Multi-AZ)
**FIS Action**: `aws:network:disrupt-connectivity`
**Validation target**: After single AZ network disruption, traffic automatically shifts to healthy AZ, service remains available

---

## Steady-State Hypothesis

After isolating the network of 1 AZ:
- ALB request success rate >= 99% (brief drop allowed during switchover)
- P99 latency <= 1000ms (may increase slightly with single AZ bearing full load)
- Recovery time <= 120s
- Database Multi-AZ failover succeeds (if Primary is in the isolated AZ)

## Stop Conditions

```json
{
  "stopConditions": [
    {
      "source": "aws:cloudwatch:alarm",
      "value": "arn:aws:cloudwatch:{region}:{account}:alarm:chaos-stop-availability"
    }
  ]
}
```

Corresponding Alarm:
```bash
aws cloudwatch put-metric-alarm \
  --alarm-name "chaos-stop-availability" \
  --namespace "AWS/ApplicationELB" \
  --metric-name "HTTPCode_ELB_5XX_Count" \
  --statistic Sum \
  --period 60 \
  --threshold 100 \
  --comparison-operator GreaterThanThreshold \
  --evaluation-periods 3 \
  --alarm-actions "arn:aws:sns:{region}:{account}:chaos-alerts"
```

## FIS Experiment Template

```json
{
  "description": "Disrupt network connectivity for one AZ to validate multi-AZ failover",
  "targets": {
    "az-subnets": {
      "resourceType": "aws:ec2:subnet",
      "resourceArns": [
        "arn:aws:ec2:{region}:{account}:subnet/{subnet-az-a-1}",
        "arn:aws:ec2:{region}:{account}:subnet/{subnet-az-a-2}"
      ],
      "selectionMode": "ALL"
    }
  },
  "actions": {
    "disrupt-az-network": {
      "actionId": "aws:network:disrupt-connectivity",
      "parameters": {
        "scope": "all",
        "duration": "PT5M"
      },
      "targets": {
        "Subnets": "az-subnets"
      }
    }
  },
  "stopConditions": [
    {
      "source": "aws:cloudwatch:alarm",
      "value": "arn:aws:cloudwatch:{region}:{account}:alarm:chaos-stop-availability"
    }
  ],
  "roleArn": "arn:aws:iam::{account}:role/FISExperimentRole",
  "tags": {
    "Purpose": "chaos-engineering",
    "RiskId": "R-004"
  }
}
```

## Execution Commands

```bash
# Confirm target AZ subnets
aws ec2 describe-subnets \
  --filters "Name=availability-zone,Values={region}a" \
  --query 'Subnets[].{Id:SubnetId,AZ:AvailabilityZone,VPC:VpcId}'

# Confirm instance distribution across AZs
aws ec2 describe-instances \
  --filters "Name=tag:Environment,Values=production" \
  --query 'Reservations[].Instances[].{Id:InstanceId,AZ:Placement.AvailabilityZone,State:State.Name}'

# Create and start experiment
aws fis create-experiment-template --cli-input-json file://examples/az-network-disrupt-template.json
aws fis start-experiment --experiment-template-id <template-id>
```

## Observation Metrics

| Metric | Namespace | MetricName | Description |
|------|-----------|------------|------|
| ALB 5xx | AWS/ApplicationELB | HTTPCode_ELB_5XX_Count | Errors during AZ switchover |
| Healthy host count | AWS/ApplicationELB | HealthyHostCount | Observe by AZ dimension |
| Target response time | AWS/ApplicationELB | TargetResponseTime | Latency after single AZ load increase |
| RDS connection count | AWS/RDS | DatabaseConnections | If DB failover is triggered |
| Inter-AZ traffic | VPC Flow Logs | — | Verify traffic switchover |

## Expected Results

| Phase | Time | Expected |
|------|------|------|
| Injection | T+0s | Target AZ subnet network disrupted |
| Detection | T+10-30s | ALB detects AZ-a targets unhealthy |
| Switchover | T+30-60s | ALB routes traffic to AZ-b/AZ-c |
| Stabilization | T+60-120s | Single AZ (or dual AZ) handles full traffic |
| Recovery | T+5min | Network restored, AZ-a instances rejoin |

**If failed**: Common causes:
- All instances deployed in the same AZ (no redundancy)
- ALB cross-AZ health check interval too long
- RDS Multi-AZ not enabled
- Stateful services depend on local storage (EBS does not span AZs)
- Session stickiness causes session loss after switchover

## Caution

⚠️ **This is the experiment with the largest blast radius.** Recommendations:
1. Validate in Staging first
2. Confirm each AZ has sufficient capacity to independently handle full traffic
3. Choose a low-traffic time window
4. Ensure On-call team is in position
