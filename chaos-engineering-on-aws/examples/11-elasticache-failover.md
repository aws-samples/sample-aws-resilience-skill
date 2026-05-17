# Example 11: ElastiCache Replication Group Failover — Primary-Replica Role Swap

**Architecture pattern**: Application → ElastiCache Redis/Valkey (replication group, cluster mode disabled or enabled)
**Injection method**: SSM Automation (TestFailover → wait for available)
**Validates**: Automatic failover, primary-replica role swap, endpoint topology change, connection recovery

> Template source: Based on [ElastiCache TestFailover API](https://docs.aws.amazon.com/AmazonElastiCache/latest/APIReference/API_TestFailover.html)

---

## Hypothesis

When automatic failover is triggered on an ElastiCache replication group:
- The current primary becomes a replica and a replica is promoted to primary
- Application detects the endpoint topology change and reconnects within 60 seconds
- No data loss — writes to the new primary succeed after promotion
- The replication group returns to `available` status within 5 minutes
- More realistic than a reboot (Example 10) because the endpoint topology actually changes

**Key differences from Example 10 (Primary Reboot):**

| Aspect | Example 10 (Reboot) | Example 11 (Failover) |
|--------|---------------------|----------------------|
| API | `RebootCacheCluster` | `TestFailover` |
| Effect | Primary node restarts, same node stays primary | Replica promoted, old primary becomes replica |
| Cluster mode | Disabled only | Both disabled and enabled |
| Parameters | `CacheClusterId` | `ReplicationGroupId` + `NodeGroupId` |

### What does this enable you to verify?

- ElastiCache automatic failover mechanism and role swap behavior
- Application handling of primary endpoint topology changes
- Connection pool behavior when primary identity changes (not just restarts)
- Cluster-mode-enabled shard-level failover (target specific shards)
- Failover rate limits and sequential constraints for cluster-mode-enabled

## Prerequisites

- [ ] ElastiCache Redis/Valkey replication group with Automatic Failover enabled
- [ ] Multi-AZ enabled
- [ ] `ReplicationGroupId` and target `NodeGroupId` identified
- [ ] FIS IAM Role with `AWSFaultInjectionSimulatorSSMAccess` + `iam:PassRole`
- [ ] SSM Automation IAM Role with `elasticache:TestFailover` + `elasticache:DescribeReplicationGroups`
- [ ] For cluster-mode-enabled: shard distribution baseline recorded

## SSM Automation Runbook

```yaml
description: 'FIS: Test automatic failover on ElastiCache replication group'
schemaVersion: '0.3'
assumeRole: '{{ AutomationAssumeRoleArn }}'
parameters:
  AutomationAssumeRoleArn:
    type: String
    description: IAM Role ARN for SSM Automation to assume
  ReplicationGroupId:
    type: String
    description: Replication group ID to trigger failover on
  NodeGroupId:
    type: String
    description: >-
      Node group (shard) ID to failover. For cluster-mode-disabled,
      this is always '0001'. For cluster-mode-enabled, specify the
      target shard ID (e.g., '0001', '0002').
mainSteps:
  - name: TestFailover
    action: aws:executeAwsApi
    inputs:
      Service: elasticache
      Api: TestFailover
      ReplicationGroupId: '{{ ReplicationGroupId }}'
      NodeGroupId: '{{ NodeGroupId }}'
    outputs:
      - Name: ReplicationGroupId
        Selector: $.ReplicationGroup.ReplicationGroupId
        Type: String

  - name: WaitForReplicationGroupAvailable
    action: aws:waitForAwsResourceProperty
    timeoutSeconds: 600
    inputs:
      Service: elasticache
      Api: DescribeReplicationGroups
      ReplicationGroupId: '{{ ReplicationGroupId }}'
      PropertySelector: $.ReplicationGroups[0].Status
      DesiredValues:
        - available
```

## Setup

### 1. Deploy SSM Automation Document

```bash
aws ssm create-document \
  --name elasticache-test-failover \
  --document-type Automation \
  --content file://ssm-elasticache-failover.yaml \
  --document-format YAML
```

### 2. Deploy IAM Roles

```bash
# FIS Role (trusts fis.amazonaws.com)
aws iam create-role \
  --role-name FIS-EC-Failover \
  --assume-role-policy-document '{
    "Version": "2012-10-17",
    "Statement": [{"Effect": "Allow", "Principal": {"Service": "fis.amazonaws.com"}, "Action": "sts:AssumeRole"}]
  }'

aws iam attach-role-policy \
  --role-name FIS-EC-Failover \
  --policy-arn arn:aws:iam::aws:policy/service-role/AWSFaultInjectionSimulatorSSMAccess

aws iam put-role-policy \
  --role-name FIS-EC-Failover \
  --policy-name PassSSMRole \
  --policy-document '{
    "Version": "2012-10-17",
    "Statement": [{"Effect": "Allow", "Action": "iam:PassRole", "Resource": "arn:aws:iam::{account}:role/SSM-EC-Failover", "Condition": {"StringEquals": {"iam:PassedToService": "ssm.amazonaws.com"}}}]
  }'

# SSM Automation Role (trusts ssm.amazonaws.com)
aws iam create-role \
  --role-name SSM-EC-Failover \
  --assume-role-policy-document '{
    "Version": "2012-10-17",
    "Statement": [{"Effect": "Allow", "Principal": {"Service": "ssm.amazonaws.com"}, "Action": "sts:AssumeRole"}]
  }'

aws iam put-role-policy \
  --role-name SSM-EC-Failover \
  --policy-name ElastiCacheAccess \
  --policy-document '{
    "Version": "2012-10-17",
    "Statement": [{"Effect": "Allow", "Action": ["elasticache:TestFailover", "elasticache:DescribeReplicationGroups"], "Resource": "*"}]
  }'
```

### 3. Create FIS Experiment

```bash
aws fis create-experiment-template --cli-input-json '{
  "description": "Test ElastiCache automatic failover to validate primary-replica role swap",
  "targets": {},
  "actions": {
    "test-failover": {
      "actionId": "aws:ssm:start-automation-execution",
      "parameters": {
        "documentArn": "arn:aws:ssm:{region}:{account}:document/elasticache-test-failover",
        "documentParameters": "{\"AutomationAssumeRoleArn\":\"arn:aws:iam::{account}:role/SSM-EC-Failover\",\"ReplicationGroupId\":\"{rg-id}\",\"NodeGroupId\":\"0001\"}",
        "maxDuration": "PT15M"
      }
    }
  },
  "stopConditions": [{"source": "none"}],
  "roleArn": "arn:aws:iam::{account}:role/FIS-EC-Failover",
  "tags": {"Purpose": "chaos-engineering", "RiskId": "R-011"}
}'
```

## Execution

```bash
# Check current node roles (cluster-mode-disabled)
aws elasticache describe-replication-groups \
  --replication-group-id {rg-id} \
  --query 'ReplicationGroups[0].NodeGroups[].NodeGroupMembers[].[CacheClusterId,CurrentRole,PreferredAvailabilityZone]' \
  --output table

# For cluster-mode-enabled (CurrentRole is null), use CloudWatch IsMaster metric
# IsMaster = 1.0 → Primary, IsMaster = 0.0 → Replica

# Start the experiment
aws fis start-experiment --experiment-template-id {TEMPLATE_ID}

# Monitor replication group status
watch -n 10 'aws elasticache describe-replication-groups \
  --replication-group-id {rg-id} \
  --query "ReplicationGroups[0].{Status:Status,NodeGroups:NodeGroups[].NodeGroupMembers[].[CacheClusterId,CurrentRole]}" \
  --output table'
```

## Observation Metrics

| Metric | Source | Expected Behavior |
|--------|--------|-------------------|
| ReplicationGroup status | ElastiCache API | available → modifying → available |
| IsPrimary | CloudWatch | Role swap: old primary 1→0, new primary 0→1 |
| ReplicationLag | CloudWatch | Brief spike during failover, then drops to near-zero |
| CurrConnections | CloudWatch | Brief drop during role swap, then recovery |
| Application error rate | Application metrics | Brief spike, then normal |

## Cleanup

The SSM Automation runbook waits for the replication group to return to `available`. The failover is permanent — roles are swapped. No rollback needed.

```bash
# Verify replication group is available
aws elasticache describe-replication-groups \
  --replication-group-id {rg-id} \
  --query "ReplicationGroups[0].Status"

# Verify new role assignment
aws elasticache describe-replication-groups \
  --replication-group-id {rg-id} \
  --query 'ReplicationGroups[0].NodeGroups[].NodeGroupMembers[].[CacheClusterId,CurrentRole]' \
  --output table

# Delete experiment template when done
aws fis delete-experiment-template --id {TEMPLATE_ID}
```

**Rate limits**: Up to 15 node groups per rolling 24-hour period. For cluster-mode-enabled, the first failover must complete before triggering another on the same replication group.
