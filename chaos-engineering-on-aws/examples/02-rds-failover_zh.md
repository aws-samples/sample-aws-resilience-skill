# 示例 2: RDS Aurora 故障转移 — 数据库 HA 验证

**架构模式**：Aurora Cluster（Writer + Reader）
**FIS Action**：`aws:rds:failover-db-cluster`
**验证点**：Reader 提升为 Writer、应用连接自动恢复、零数据丢失

---

## 稳态假设

当触发 Aurora 集群故障转移后：
- 数据库写入恢复时间 <= 30s
- 应用请求成功率 >= 99%（故障转移期间允许短暂下降）
- 故障转移后数据完整性 100%
- 应用连接池自动重连，无需手动干预

## 停止条件

```json
{
  "stopConditions": [
    {
      "source": "aws:cloudwatch:alarm",
      "value": "arn:aws:cloudwatch:{region}:{account}:alarm:chaos-stop-db-connections"
    }
  ]
}
```

对应 Alarm（连接数归零超过 5 分钟则告警）：
```bash
aws cloudwatch put-metric-alarm \
  --alarm-name "chaos-stop-db-connections" \
  --namespace "AWS/RDS" \
  --metric-name "DatabaseConnections" \
  --dimensions Name=DBClusterIdentifier,Value={cluster-id} \
  --statistic Average \
  --period 60 \
  --threshold 0 \
  --comparison-operator LessThanOrEqualToThreshold \
  --evaluation-periods 5 \
  --alarm-actions "arn:aws:sns:{region}:{account}:chaos-alerts"
```

## FIS 实验模板

```json
{
  "description": "Failover Aurora cluster to validate HA and application reconnect",
  "targets": {
    "aurora-cluster": {
      "resourceType": "aws:rds:cluster",
      "resourceArns": [
        "arn:aws:rds:{region}:{account}:cluster:{cluster-id}"
      ],
      "selectionMode": "ALL"
    }
  },
  "actions": {
    "failover-cluster": {
      "actionId": "aws:rds:failover-db-cluster",
      "parameters": {},
      "targets": {
        "Clusters": "aurora-cluster"
      }
    }
  },
  "stopConditions": [
    {
      "source": "aws:cloudwatch:alarm",
      "value": "arn:aws:cloudwatch:{region}:{account}:alarm:chaos-stop-db-connections"
    }
  ],
  "roleArn": "arn:aws:iam::{account}:role/FISExperimentRole",
  "tags": {
    "Purpose": "chaos-engineering",
    "RiskId": "R-002"
  }
}
```

## 执行命令

```bash
# 确认当前 Writer
aws rds describe-db-clusters --db-cluster-identifier {cluster-id} \
  --query 'DBClusters[0].DBClusterMembers[?IsClusterWriter==`true`].DBInstanceIdentifier'

# 创建并启动实验
aws fis create-experiment-template --cli-input-json file://examples/rds-failover-template.json
aws fis start-experiment --experiment-template-id <template-id>

# 验证 Writer 已切换
aws rds describe-db-clusters --db-cluster-identifier {cluster-id} \
  --query 'DBClusters[0].DBClusterMembers[?IsClusterWriter==`true`].DBInstanceIdentifier'
```

## 观测指标

| 指标 | Namespace | MetricName | 说明 |
|------|-----------|------------|------|
| 连接数 | AWS/RDS | DatabaseConnections | 故障转移期间会归零 |
| 写入延迟 | AWS/RDS | CommitLatency | 故障转移后应恢复正常 |
| 副本延迟 | AWS/RDS | AuroraReplicaLag | 新 Writer 同步状态 |
| 应用错误率 | 应用层 | 5xx / connection refused | 验证连接池重连 |

## 预期结果

| 阶段 | 时间 | 预期 |
|------|------|------|
| 注入 | T+0s | 触发故障转移 |
| 影响 | T+5-15s | 数据库连接中断，写入失败 |
| 切换 | T+15-30s | Reader 提升为 Writer |
| 恢复 | T+20-35s | 连接池重连，写入恢复 |

**如果失败**：常见原因 — 应用未使用 Aurora 集群端点（使用了实例端点）、连接池无重试逻辑、DNS TTL 过长。检查连接字符串和重试配置。
