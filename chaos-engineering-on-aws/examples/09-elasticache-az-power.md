# Example 9: ElastiCache AZ Power Interruption — Cache Layer AZ Resilience

**Architecture pattern**: Application → ElastiCache Redis/Valkey (replication group, Multi-AZ)
**FIS Action**: `aws:elasticache:replicationgroup-interrupt-az-power`
**Validation target**: AZ-level failover, replica promotion, reduced-capacity operation, connection recovery

---

## Steady-State Hypothesis

After interrupting power to ElastiCache nodes in the target AZ:
- Primary node failover completes within 30 seconds (replica with least replication lag is promoted)
- Application connection pool reconnects to the new primary within 60 seconds
- Cache hit rate recovers to >= 90% within 5 minutes
- No data loss during failover (replication lag near zero pre-experiment)
- Read replica replacements in the target AZ are blocked for the entire duration — cluster operates at reduced capacity

### What does this enable you to verify?

- ElastiCache Multi-AZ automatic failover works correctly
- Application handles primary endpoint changes gracefully
- Connection pool retry and reconnect logic under AZ-level failure
- Cluster behavior under reduced capacity (replicas blocked in impaired AZ)
- CloudWatch alarm detection for `ReplicationLag` spike and `IsPrimary` role change

## Stop Conditions

```json
{
  "stopConditions": [
    {
      "source": "aws:cloudwatch:alarm",
      "value": "arn:aws:cloudwatch:{region}:{account}:alarm:chaos-stop-cache-connections"
    }
  ]
}
```

Corresponding Alarm:
```bash
aws cloudwatch put-metric-alarm \
  --alarm-name "chaos-stop-cache-connections" \
  --namespace "AWS/ElastiCache" \
  --metric-name "CurrConnections" \
  --dimensions Name=CacheClusterId,Value={cache-cluster-id} \
  --statistic Average \
  --period 60 \
  --threshold 0 \
  --comparison-operator LessThanOrEqualToThreshold \
  --evaluation-periods 3 \
  --treat-missing-data notBreaching
```

## FIS Experiment Template

```json
{
  "description": "Interrupt ElastiCache AZ power to validate cache layer AZ resilience",
  "targets": {
    "elasticache-rg": {
      "resourceType": "aws:elasticache:replicationgroup",
      "resourceTags": {
        "AzImpairmentPower": "ElasticacheImpact"
      },
      "parameters": {
        "availabilityZoneIdentifier": "{target-az}"
      },
      "selectionMode": "ALL"
    }
  },
  "actions": {
    "interrupt-az-power": {
      "actionId": "aws:elasticache:replicationgroup-interrupt-az-power",
      "parameters": {
        "duration": "PT10M"
      },
      "targets": {
        "ReplicationGroups": "elasticache-rg"
      }
    }
  },
  "stopConditions": [
    {
      "source": "aws:cloudwatch:alarm",
      "value": "arn:aws:cloudwatch:{region}:{account}:alarm:chaos-stop-cache-connections"
    }
  ],
  "roleArn": "arn:aws:iam::{account}:role/FISExperimentRole",
  "tags": {
    "Purpose": "chaos-engineering",
    "RiskId": "R-009"
  }
}
```

**Important notes:**
- Target selection uses `resourceTags` ONLY — `resourceArns` and `filters` are NOT supported for ElastiCache replication groups
- The action was renamed from `aws:elasticache:interrupt-cluster-az-power` — always use the new name
- Requires Multi-AZ enabled on the replication group; NOT supported on ElastiCache Serverless

## IAM Permissions

No AWS managed policy exists for ElastiCache FIS actions. Attach an inline policy:

```json
{
  "Version": "2012-10-17",
  "Statement": [
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
      "Sid": "TagResolution",
      "Effect": "Allow",
      "Action": [
        "tag:GetResources"
      ],
      "Resource": "*"
    }
  ]
}
```

## Execution Commands

```bash
# Tag the replication group
aws elasticache add-tags-to-resource \
  --resource-name "arn:aws:elasticache:{region}:{account}:replicationgroup:{rg-id}" \
  --tags Key=AzImpairmentPower,Value=ElasticacheImpact

# Check pre-experiment state
aws elasticache describe-replication-groups \
  --replication-group-id {rg-id} \
  --query 'ReplicationGroups[0].NodeGroups[].NodeGroupMembers[].[CacheClusterId,CurrentRole,PreferredAvailabilityZone]' \
  --output table

# Create and start experiment
aws fis create-experiment-template --cli-input-json file://examples/09-elasticache-az-power-template.json
aws fis start-experiment --experiment-template-id {TEMPLATE_ID}

# Monitor failover
watch -n 5 'aws elasticache describe-replication-groups \
  --replication-group-id {rg-id} \
  --query "ReplicationGroups[0].NodeGroups[].NodeGroupMembers[].[CacheClusterId,CurrentRole,PreferredAvailabilityZone]" \
  --output table'
```

## Observation Metrics

| Metric | Namespace | MetricName | Description |
|--------|-----------|------------|-------------|
| Replication lag | AWS/ElastiCache | ReplicationLag | Spikes during failover, drops after promotion |
| Primary role | AWS/ElastiCache | IsPrimary | Flips from 1→0 (old primary) and 0→1 (new primary) |
| Engine CPU | AWS/ElastiCache | EngineCPUUtilization | New primary may spike during promotion |
| Connections | AWS/ElastiCache | CurrConnections | Drops during failover, recovers after reconnect |
| Cache hit rate | AWS/ElastiCache | CacheHitRate | Temporary drop during failover window |

## Expected Results

| Phase | Time | Expected |
|-------|------|----------|
| Injection | T+0s | AZ power interrupted, nodes in target AZ lose power |
| Detection | T+1-5s | ElastiCache detects node failure |
| Failover | T+5-30s | Replica with least lag promoted to primary |
| Recovery | T+30-60s | Application connection pool reconnects to new primary |
| Stabilization | T+60-300s | Cache hit rate recovers, reduced capacity (impaired AZ replicas blocked) |

**If failed**: Common causes — Multi-AZ not enabled, application using node-specific endpoints instead of primary endpoint, connection pool lacks retry logic, replication group is ElastiCache Serverless (not supported).
