# Example 10: ElastiCache Primary Node Reboot — Connection Pool Resilience

**Architecture pattern**: Application → ElastiCache Redis/Valkey (replication group, cluster mode disabled)
**Injection method**: SSM Automation (RebootCacheCluster → wait for available)
**Validates**: Connection pool resilience, retry logic, brief primary node restart recovery

> Template source: Based on [aws-samples/fis-template-library/elasticache-redis-primary-node-reboot](https://github.com/aws-samples/fis-template-library/tree/main/elasticache-redis-primary-node-reboot)

---

## Hypothesis

When the ElastiCache primary node is rebooted:
- Application connections experience a brief interruption (1-3 minutes)
- Connection pool detects the failure and reconnects automatically
- No cascading failures to upstream services
- Primary node returns to `available` status within 5 minutes
- Unlike AZ power interruption, replica replacements are NOT blocked

**Critical limitation**: `RebootCacheCluster` is **NOT supported on cluster-mode-enabled clusters** (`ClusterEnabled: true`). If cluster mode is enabled, use Example 09 (AZ Power Interruption) or Example 11 (Failover) instead.

### What does this enable you to verify?

- Redis/Valkey client connection pool reconnection after primary node restart
- Application retry logic during brief cache unavailability
- Single-node failure impact (less disruptive than AZ-level power interruption)
- Cache warming behavior after node reboot
- Difference between node reboot (same node stays primary) vs. failover (role swap)

## Prerequisites

- [ ] ElastiCache Redis/Valkey replication group with `ClusterEnabled: false`
- [ ] Multi-AZ and Automatic Failover enabled
- [ ] Primary node CacheClusterId identified (see Execution Commands)
- [ ] FIS IAM Role with `AWSFaultInjectionSimulatorSSMAccess` + `iam:PassRole`
- [ ] SSM Automation IAM Role with `elasticache:RebootCacheCluster` + `elasticache:DescribeCacheClusters`
- [ ] Application connection pool configured with retry logic

## SSM Automation Runbook

```yaml
description: 'FIS: Reboot ElastiCache primary node to test client resilience'
schemaVersion: '0.3'
assumeRole: '{{ AutomationAssumeRoleArn }}'
parameters:
  AutomationAssumeRoleArn:
    type: String
    description: IAM Role ARN for SSM Automation to assume
  CacheClusterId:
    type: String
    description: CacheClusterId of the primary node to reboot
mainSteps:
  - name: RebootPrimaryNode
    action: aws:executeAwsApi
    inputs:
      Service: elasticache
      Api: RebootCacheCluster
      CacheClusterId: '{{ CacheClusterId }}'
      CacheNodeIdsToReboot:
        - '0001'
    outputs:
      - Name: CacheClusterId
        Selector: $.CacheCluster.CacheClusterId
        Type: String

  - name: WaitForNodeAvailable
    action: aws:waitForAwsResourceProperty
    timeoutSeconds: 600
    inputs:
      Service: elasticache
      Api: DescribeCacheClusters
      CacheClusterId: '{{ CacheClusterId }}'
      PropertySelector: $.CacheClusters[0].CacheClusterStatus
      DesiredValues:
        - available
```

## Setup

### 1. Deploy SSM Automation Document

```bash
aws ssm create-document \
  --name elasticache-primary-reboot \
  --document-type Automation \
  --content file://ssm-elasticache-reboot.yaml \
  --document-format YAML
```

### 2. Deploy IAM Roles

```bash
# FIS Role (trusts fis.amazonaws.com)
aws iam create-role \
  --role-name FIS-EC-Reboot \
  --assume-role-policy-document '{
    "Version": "2012-10-17",
    "Statement": [{"Effect": "Allow", "Principal": {"Service": "fis.amazonaws.com"}, "Action": "sts:AssumeRole"}]
  }'

aws iam attach-role-policy \
  --role-name FIS-EC-Reboot \
  --policy-arn arn:aws:iam::aws:policy/service-role/AWSFaultInjectionSimulatorSSMAccess

aws iam put-role-policy \
  --role-name FIS-EC-Reboot \
  --policy-name PassSSMRole \
  --policy-document '{
    "Version": "2012-10-17",
    "Statement": [{"Effect": "Allow", "Action": "iam:PassRole", "Resource": "arn:aws:iam::{account}:role/SSM-EC-Reboot", "Condition": {"StringEquals": {"iam:PassedToService": "ssm.amazonaws.com"}}}]
  }'

# SSM Automation Role (trusts ssm.amazonaws.com)
aws iam create-role \
  --role-name SSM-EC-Reboot \
  --assume-role-policy-document '{
    "Version": "2012-10-17",
    "Statement": [{"Effect": "Allow", "Principal": {"Service": "ssm.amazonaws.com"}, "Action": "sts:AssumeRole"}]
  }'

aws iam put-role-policy \
  --role-name SSM-EC-Reboot \
  --policy-name ElastiCacheAccess \
  --policy-document '{
    "Version": "2012-10-17",
    "Statement": [{"Effect": "Allow", "Action": ["elasticache:RebootCacheCluster", "elasticache:DescribeCacheClusters"], "Resource": "*"}]
  }'
```

### 3. Create FIS Experiment

```bash
aws fis create-experiment-template --cli-input-json '{
  "description": "Reboot ElastiCache primary node to test connection pool resilience",
  "targets": {},
  "actions": {
    "reboot-primary": {
      "actionId": "aws:ssm:start-automation-execution",
      "parameters": {
        "documentArn": "arn:aws:ssm:{region}:{account}:document/elasticache-primary-reboot",
        "documentParameters": "{\"AutomationAssumeRoleArn\":\"arn:aws:iam::{account}:role/SSM-EC-Reboot\",\"CacheClusterId\":\"{primary-cache-cluster-id}\"}",
        "maxDuration": "PT15M"
      }
    }
  },
  "stopConditions": [{"source": "none"}],
  "roleArn": "arn:aws:iam::{account}:role/FIS-EC-Reboot",
  "tags": {"Purpose": "chaos-engineering", "RiskId": "R-010"}
}'
```

## Execution

```bash
# Identify the primary node
aws elasticache describe-replication-groups \
  --replication-group-id {rg-id} \
  --query 'ReplicationGroups[0].NodeGroups[].NodeGroupMembers[].[CacheClusterId,CurrentRole,PreferredAvailabilityZone]' \
  --output table

# Verify cluster mode is disabled
aws elasticache describe-replication-groups \
  --replication-group-id {rg-id} \
  --query 'ReplicationGroups[0].ClusterEnabled'

# Start the experiment
aws fis start-experiment --experiment-template-id {TEMPLATE_ID}

# Monitor node status
watch -n 10 'aws elasticache describe-cache-clusters \
  --cache-cluster-id {primary-cache-cluster-id} \
  --query "CacheClusters[0].CacheClusterStatus"'
```

## Observation Metrics

| Metric | Source | Expected Behavior |
|--------|--------|-------------------|
| Node status | ElastiCache API | available → rebooting → available |
| CurrConnections | CloudWatch | Drop during reboot, recover after |
| EngineCPUUtilization | CloudWatch | Brief spike during restart |
| CacheHitRate | CloudWatch | Temporary drop, gradual recovery |
| Application error rate | Application metrics | Brief spike during reboot window |

## Cleanup

The SSM Automation runbook waits for the node to return to `available` — no manual cleanup needed.

```bash
# Verify node is back to available
aws elasticache describe-cache-clusters \
  --cache-cluster-id {primary-cache-cluster-id} \
  --query "CacheClusters[0].CacheClusterStatus"

# Delete experiment template when done
aws fis delete-experiment-template --id {TEMPLATE_ID}
```
