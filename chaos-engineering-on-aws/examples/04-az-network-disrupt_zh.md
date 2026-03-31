# 示例 4: AZ 网络隔离 — 多 AZ 容错验证

**架构模式**：多 AZ 部署（ALB + EC2/EKS + RDS Multi-AZ）
**FIS Action**：`aws:network:disrupt-connectivity`
**验证点**：单 AZ 网络中断后，流量自动切换到健康 AZ，服务保持可用

---

## 稳态假设

当隔离 1 个 AZ 的网络后：
- ALB 请求成功率 >= 99%（允许切换期间短暂下降）
- P99 延迟 <= 1000ms（单 AZ 承载全量可能略升）
- 恢复时间 <= 120s
- 数据库 Multi-AZ 故障转移成功（如 Primary 在被隔离 AZ）

## 停止条件

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

对应 Alarm：
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

## FIS 实验模板

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

## 执行命令

```bash
# 确认目标 AZ 的子网
aws ec2 describe-subnets \
  --filters "Name=availability-zone,Values={region}a" \
  --query 'Subnets[].{Id:SubnetId,AZ:AvailabilityZone,VPC:VpcId}'

# 确认各 AZ 实例分布
aws ec2 describe-instances \
  --filters "Name=tag:Environment,Values=production" \
  --query 'Reservations[].Instances[].{Id:InstanceId,AZ:Placement.AvailabilityZone,State:State.Name}'

# 创建并启动实验
aws fis create-experiment-template --cli-input-json file://examples/az-network-disrupt-template.json
aws fis start-experiment --experiment-template-id <template-id>
```

## 观测指标

| 指标 | Namespace | MetricName | 说明 |
|------|-----------|------------|------|
| ALB 5xx | AWS/ApplicationELB | HTTPCode_ELB_5XX_Count | AZ 切换期间的错误 |
| 健康主机数 | AWS/ApplicationELB | HealthyHostCount | 按 AZ 维度观察 |
| 目标响应时间 | AWS/ApplicationELB | TargetResponseTime | 单 AZ 负载增加后的延迟 |
| RDS 连接数 | AWS/RDS | DatabaseConnections | 如触发 DB 故障转移 |
| AZ 间流量 | VPC Flow Logs | — | 验证流量切换 |

## 预期结果

| 阶段 | 时间 | 预期 |
|------|------|------|
| 注入 | T+0s | 目标 AZ 子网网络中断 |
| 检测 | T+10-30s | ALB 检测到 AZ-a 目标不健康 |
| 切换 | T+30-60s | ALB 将流量路由到 AZ-b/AZ-c |
| 稳定 | T+60-120s | 单（双）AZ 承载全量流量 |
| 恢复 | T+5min | 网络恢复，AZ-a 实例重新加入 |

**如果失败**：常见原因：
- 实例全部部署在同一 AZ（无冗余）
- ALB 跨 AZ 健康检查间隔过长
- RDS 未开启 Multi-AZ
- 有状态服务依赖本地存储（EBS 不跨 AZ）
- Session sticky 导致切换后丢失会话

## 注意事项

⚠️ **这是爆炸半径最大的实验。**建议：
1. 先在 Staging 验证
2. 确认每个 AZ 都有足够容量独立承载全量流量
3. 选择业务低峰时段
4. 确保 On-call 团队就位
