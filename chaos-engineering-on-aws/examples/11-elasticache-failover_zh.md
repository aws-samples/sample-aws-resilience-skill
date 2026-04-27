# 示例 11：ElastiCache 复制组故障转移 — 主副本角色切换

**架构模式**：应用程序 → ElastiCache Redis/Valkey（复制组，集群模式禁用或启用）
**注入方式**：SSM Automation（TestFailover → 等待 available）
**验证点**：自动故障转移、主副本角色切换、端点拓扑变更、连接恢复

> 模板来源：基于 [ElastiCache TestFailover API](https://docs.aws.amazon.com/AmazonElastiCache/latest/APIReference/API_TestFailover.html)

---

## 假设

当 ElastiCache 复制组触发自动故障转移时：
- 当前主节点变为副本，副本被提升为主节点
- 应用程序检测到端点拓扑变更并在 60 秒内重新连接
- 无数据丢失——提升后对新主节点的写入成功
- 复制组在 5 分钟内恢复到 `available` 状态
- 比重启（示例 10）更真实，因为端点拓扑实际发生了变化

**与示例 10（主节点重启）的关键差异：**

| 方面 | 示例 10（重启） | 示例 11（故障转移） |
|------|----------------|-------------------|
| API | `RebootCacheCluster` | `TestFailover` |
| 效果 | 主节点重启，同一节点仍为主节点 | 副本提升，原主节点变为副本 |
| 集群模式 | 仅禁用 | 禁用和启用均支持 |
| 参数 | `CacheClusterId` | `ReplicationGroupId` + `NodeGroupId` |

### 验证要点

- ElastiCache 自动故障转移机制和角色切换行为
- 应用程序对主端点拓扑变更的处理能力
- 主节点身份变更（而非仅重启）时的连接池行为
- 集群模式启用时的分片级故障转移（定向特定分片）
- 集群模式启用时的故障转移速率限制和顺序约束

## 前置条件

- [ ] 已启用自动故障转移的 ElastiCache Redis/Valkey 复制组
- [ ] 已启用多可用区
- [ ] 已确认 `ReplicationGroupId` 和目标 `NodeGroupId`
- [ ] 具有 `AWSFaultInjectionSimulatorSSMAccess` + `iam:PassRole` 权限的 FIS IAM 角色
- [ ] 具有 `elasticache:TestFailover` + `elasticache:DescribeReplicationGroups` 权限的 SSM Automation IAM 角色
- [ ] 集群模式启用时：已记录分片分布基线

## SSM 自动化 Runbook

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

## 部署

### 1. 部署 SSM Automation 文档

```bash
aws ssm create-document \
  --name elasticache-test-failover \
  --document-type Automation \
  --content file://ssm-elasticache-failover.yaml \
  --document-format YAML
```

### 2. 部署 IAM 角色

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

### 3. 创建 FIS 实验

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

## 执行

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

## 观测指标

| 指标 | 来源 | 预期行为 |
|------|------|----------|
| ReplicationGroup status | ElastiCache API | available → modifying → available |
| IsPrimary | CloudWatch | 角色切换：原主节点 1→0，新主节点 0→1 |
| ReplicationLag | CloudWatch | 故障转移期间短暂飙升，随后降至接近零 |
| CurrConnections | CloudWatch | 角色切换期间短暂下降，随后恢复 |
| 应用程序错误率 | 应用程序指标 | 短暂飙升，随后恢复正常 |

## 清理

SSM Automation Runbook 会等待复制组恢复到 `available` 状态。故障转移是永久性的——角色已切换，无需回滚。

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

**速率限制**：每滚动 24 小时最多 15 个节点组。集群模式启用时，第一次故障转移必须完成后才能在同一复制组上触发另一次故障转移。
