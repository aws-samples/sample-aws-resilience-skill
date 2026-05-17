# 示例 10：ElastiCache 主节点重启 — 连接池韧性

**架构模式**：Application → ElastiCache Redis/Valkey（复制组、集群模式禁用）
**注入方式**：SSM Automation（RebootCacheCluster → 等待 available）
**验证点**：连接池韧性、重试逻辑、主节点短暂重启恢复

> 模板来源：基于 [aws-samples/fis-template-library/elasticache-redis-primary-node-reboot](https://github.com/aws-samples/fis-template-library/tree/main/elasticache-redis-primary-node-reboot)

---

## 假设

当 ElastiCache 主节点被重启时：
- 应用连接经历短暂中断（1-3 分钟）
- 连接池检测到故障并自动重连
- 不会导致上游服务级联故障
- 主节点在 5 分钟内恢复到 `available` 状态
- 与 AZ 电源中断不同，副本替换不会被阻止

**关键限制**：`RebootCacheCluster` **不支持集群模式启用的集群**（`ClusterEnabled: true`）。如果启用了集群模式，请使用示例 09（AZ 电源中断）或示例 11（故障转移）替代。

### 验证要点

- 主节点重启后 Redis/Valkey 客户端连接池的重连能力
- 缓存短暂不可用期间的应用重试逻辑
- 单节点故障影响（比 AZ 级别电源中断破坏性更小）
- 节点重启后的缓存预热行为
- 节点重启（同一节点保持主节点）与故障转移（角色互换）的区别

## 前置条件

- [ ] ElastiCache Redis/Valkey 复制组，`ClusterEnabled: false`
- [ ] 已启用 Multi-AZ 和自动故障转移
- [ ] 已确定主节点 CacheClusterId（参见执行命令）
- [ ] FIS IAM 角色，具有 `AWSFaultInjectionSimulatorSSMAccess` + `iam:PassRole`
- [ ] SSM Automation IAM 角色，具有 `elasticache:RebootCacheCluster` + `elasticache:DescribeCacheClusters`
- [ ] 应用连接池已配置重试逻辑

## SSM 自动化 Runbook

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

## 部署

### 1. 部署 SSM 自动化文档

```bash
aws ssm create-document \
  --name elasticache-primary-reboot \
  --document-type Automation \
  --content file://ssm-elasticache-reboot.yaml \
  --document-format YAML
```

### 2. 部署 IAM 角色

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

### 3. 创建 FIS 实验

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

## 执行

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

## 观测指标

| 指标 | 来源 | 预期行为 |
|------|------|----------|
| 节点状态 | ElastiCache API | available → rebooting → available |
| CurrConnections | CloudWatch | 重启期间下降，之后恢复 |
| EngineCPUUtilization | CloudWatch | 重启期间短暂尖峰 |
| CacheHitRate | CloudWatch | 临时下降，逐步恢复 |
| 应用错误率 | 应用指标 | 重启窗口期间短暂尖峰 |

## 清理

SSM 自动化 Runbook 会等待节点恢复到 `available` 状态 — 无需手动清理。

```bash
# Verify node is back to available
aws elasticache describe-cache-clusters \
  --cache-cluster-id {primary-cache-cluster-id} \
  --query "CacheClusters[0].CacheClusterStatus"

# Delete experiment template when done
aws fis delete-experiment-template --id {TEMPLATE_ID}
```
