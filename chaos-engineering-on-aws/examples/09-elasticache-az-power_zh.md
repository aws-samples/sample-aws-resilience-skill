# 示例 9：ElastiCache AZ 电源中断 — 缓存层 AZ 韧性

**架构模式**：Application → ElastiCache Redis/Valkey（复制组、Multi-AZ）
**FIS Action**：`aws:elasticache:replicationgroup-interrupt-az-power`
**验证点**：AZ 级别故障转移、副本提升、降低容量运行、连接恢复

---

## 稳态假设

中断目标 AZ 中 ElastiCache 节点的电源后：
- 主节点故障转移在 30 秒内完成（复制延迟最小的副本被提升）
- 应用连接池在 60 秒内重新连接到新主节点
- 缓存命中率在 5 分钟内恢复至 >= 90%
- 故障转移期间无数据丢失（实验前复制延迟接近零）
- 目标 AZ 中的只读副本替换在整个持续期间被阻止 — 集群以降低容量运行

### 验证要点

- ElastiCache Multi-AZ 自动故障转移是否正确工作
- 应用是否能够优雅地处理主端点变更
- AZ 级别故障下的连接池重试和重连逻辑
- 降低容量（受损 AZ 中副本被阻止）下的集群行为
- CloudWatch 告警是否检测到 `ReplicationLag` 尖峰和 `IsPrimary` 角色变更

## 停止条件

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

对应告警：
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

## FIS 实验模板

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

**重要说明：**
- 目标选择仅使用 `resourceTags` — ElastiCache 复制组不支持 `resourceArns` 和 `filters`
- 该操作已从 `aws:elasticache:interrupt-cluster-az-power` 重命名 — 请始终使用新名称
- 需要在复制组上启用 Multi-AZ；不支持 ElastiCache Serverless

## IAM 权限

ElastiCache FIS 操作没有 AWS 托管策略。请附加内联策略：

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

## 执行命令

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

## 观测指标

| 指标 | Namespace | MetricName | 说明 |
|------|-----------|------------|------|
| 复制延迟 | AWS/ElastiCache | ReplicationLag | 故障转移期间出现尖峰，提升后下降 |
| 主节点角色 | AWS/ElastiCache | IsPrimary | 从 1→0（旧主节点）和 0→1（新主节点）翻转 |
| 引擎 CPU | AWS/ElastiCache | EngineCPUUtilization | 提升期间新主节点可能出现尖峰 |
| 连接数 | AWS/ElastiCache | CurrConnections | 故障转移期间下降，重连后恢复 |
| 缓存命中率 | AWS/ElastiCache | CacheHitRate | 故障转移窗口期间临时下降 |

## 预期结果

| 阶段 | 时间 | 预期 |
|------|------|------|
| 注入 | T+0s | AZ 电源中断，目标 AZ 中的节点断电 |
| 检测 | T+1-5s | ElastiCache 检测到节点故障 |
| 故障转移 | T+5-30s | 延迟最小的副本被提升为主节点 |
| 恢复 | T+30-60s | 应用连接池重新连接到新主节点 |
| 稳定 | T+60-300s | 缓存命中率恢复，降低容量运行（受损 AZ 副本被阻止） |

**如果失败**：常见原因 — 未启用 Multi-AZ、应用使用节点特定端点而非主端点、连接池缺少重试逻辑、复制组为 ElastiCache Serverless（不支持）。
