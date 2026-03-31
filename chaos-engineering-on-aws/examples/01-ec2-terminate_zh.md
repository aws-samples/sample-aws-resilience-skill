# 示例 1: EC2 实例终止 — Auto Scaling 恢复验证

**架构模式**：传统 EC2 + ALB + Auto Scaling Group
**FIS Action**：`aws:ec2:terminate-instances`
**验证点**：ASG 自动启动替代实例、ALB 健康检查通过、请求不中断

---

## 稳态假设

当终止 ASG 中 1 个 EC2 实例后：
- ALB 请求成功率 >= 99.5%（5 分钟窗口）
- P99 延迟 <= 500ms
- ASG 在 300s 内补充新实例并通过健康检查
- 无数据丢失

## 停止条件

```json
{
  "stopConditions": [
    {
      "source": "aws:cloudwatch:alarm",
      "value": "arn:aws:cloudwatch:{region}:{account}:alarm:chaos-stop-5xx-rate"
    }
  ]
}
```

对应 CloudWatch Alarm：
```bash
aws cloudwatch put-metric-alarm \
  --alarm-name "chaos-stop-5xx-rate" \
  --namespace "AWS/ApplicationELB" \
  --metric-name "HTTPCode_Target_5XX_Count" \
  --statistic Sum \
  --period 60 \
  --threshold 50 \
  --comparison-operator GreaterThanThreshold \
  --evaluation-periods 2 \
  --alarm-actions "arn:aws:sns:{region}:{account}:chaos-alerts"
```

## FIS 实验模板

```json
{
  "description": "Terminate one EC2 instance in ASG to validate auto-recovery",
  "targets": {
    "ec2-instances": {
      "resourceType": "aws:ec2:instance",
      "resourceArns": [
        "arn:aws:ec2:{region}:{account}:instance/{instance-id}"
      ],
      "selectionMode": "COUNT(1)"
    }
  },
  "actions": {
    "terminate-instance": {
      "actionId": "aws:ec2:terminate-instances",
      "parameters": {},
      "targets": {
        "Instances": "ec2-instances"
      }
    }
  },
  "stopConditions": [
    {
      "source": "aws:cloudwatch:alarm",
      "value": "arn:aws:cloudwatch:{region}:{account}:alarm:chaos-stop-5xx-rate"
    }
  ],
  "roleArn": "arn:aws:iam::{account}:role/FISExperimentRole",
  "tags": {
    "Purpose": "chaos-engineering",
    "RiskId": "R-001"
  }
}
```

## 执行命令

```bash
# 创建模板
aws fis create-experiment-template \
  --cli-input-json file://examples/ec2-terminate-template.json

# 启动实验
aws fis start-experiment --experiment-template-id <template-id>

# 监控实验状态
aws fis get-experiment --id <experiment-id> \
  --query 'experiment.state.status'
```

## 观测指标

| 指标 | Namespace | MetricName | 维度 |
|------|-----------|------------|------|
| 5xx 错误数 | AWS/ApplicationELB | HTTPCode_Target_5XX_Count | LoadBalancer, TargetGroup |
| 请求数 | AWS/ApplicationELB | RequestCount | LoadBalancer |
| 健康主机数 | AWS/ApplicationELB | HealthyHostCount | TargetGroup |
| ASG 实例数 | AWS/AutoScaling | GroupInServiceInstances | AutoScalingGroupName |

## 预期结果

| 阶段 | 时间 | 预期 |
|------|------|------|
| 注入 | T+0s | 目标实例被终止 |
| 检测 | T+10-30s | ALB 检测到实例不可用 |
| ASG 响应 | T+30-60s | ASG 启动新实例 |
| 恢复 | T+180-300s | 新实例通过健康检查，流量恢复 |

**如果失败**：说明 ASG 配置有问题（最小容量、健康检查间隔、启动模板），需检查 ASG 策略和 Launch Template。
