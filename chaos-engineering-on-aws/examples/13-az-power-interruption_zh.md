# 示例 13：AZ 电力中断 — 多服务可用区故障模拟

> 本示例演示如何使用 **FIS 场景库** 模拟单个可用区的全面电力故障，同时影响多个 AWS 服务。

## 场景

通过同时执行以下操作来模拟单个可用区的电力中断：
1. **停止目标 AZ 中的 EC2 实例**
2. **停止 ASG 托管的实例**并阻止替换启动
3. **中断目标 AZ 中子网的网络连接**
4. **触发 RDS Aurora 故障转移**（如果写入节点位于目标 AZ）
5. **中断 ElastiCache 电力**（针对目标 AZ 中有节点的复制组）
6. **暂停目标 AZ 中 EBS 卷的 IO**
7. **中断 S3 Express One Zone** 目标 AZ 中的目录存储桶
8. **触发 ARC Zonal Autoshift** 以模拟流量转移响应

所有操作并行执行，默认持续时间为 PT10M（10 分钟）。

## 架构

```
          AZ-a（目标 — 电力中断）                     AZ-b / AZ-c（健康）
  ┌─────────────────────────────────────┐    ┌─────────────────────────────────┐
  │  EC2：已停止 ❌                      │    │  EC2：运行中 ✅                  │
  │  ASG：实例已停止，无法替换            │    │  ASG：扩容补偿中 ✅              │
  │  网络：连接已中断 ❌                  │    │  网络：正常 ✅                   │
  │  RDS 写入节点 → 故障               │───►│  RDS 读取节点 → 提升为写入节点   │
  │  ElastiCache：电力中断 ❌            │    │  ElastiCache：故障转移 ✅         │
  │  EBS：IO 已暂停 ❌                   │    │  EBS：正常 ✅                    │
  │  S3 Express：已中断 ❌               │    │                                 │
  └─────────────────────────────────────┘    └─────────────────────────────────┘
```

## 假设

**假设陈述**：当模拟完整的 AZ 电力中断时，应用程序应当：
- 通过健康的可用区继续提供请求服务
- 在 60 秒内完成所有服务故障转移（RDS、ElastiCache）
- 在事件期间保持请求成功率 >= 95%
- 在实验结束后 5 分钟内完全恢复
- ARC Zonal Autoshift 应将流量从受损 AZ 重定向

### 验证要点

- 跨所有基础设施层的真正多 AZ 弹性
- 协调的多服务故障行为（EC2 + 网络 + RDS + ElastiCache + EBS）
- 跨 AZ 容量规划 — 剩余 AZ 承载全部生产负载
- ARC Zonal Autoshift 集成和流量转移时机
- 基于标签的资源定位与 Lambda 自定义资源
- 爆炸半径控制 — 仅目标 AZ 的资源受到影响

## 前置条件

- [ ] 多 AZ 部署，至少在 2 个 AZ 中有实例
- [ ] 目标资源已使用 `AzImpairmentPower` 键打标签（参见标签策略）
- [ ] RDS Aurora 集群在另一个 AZ 中有读取副本
- [ ] ElastiCache 复制组已启用多 AZ
- [ ] FIS IAM 角色具有所需的托管策略 + 内联策略
- [ ] 已配置 CloudWatch 告警作为停止条件
- [ ] 剩余 AZ 有足够容量承载全部负载

## Sub-Action 参考

| 子操作 | Action ID | 目标类型 | 标签值 |
|-------|-----------|---------|--------|
| Stop-Instances | `aws:ec2:stop-instances` | EC2 Instance | `StopInstances` |
| Stop-ASG-Instances | `aws:ec2:stop-instances` | EC2 Instance (ASG) | `IceAsg` |
| Pause-ASG-Scaling | `aws:ec2:asg-insufficient-instance-capacity-error` | Auto Scaling Group | `IceAsg` |
| Pause-Network-Connectivity | `aws:network:disrupt-connectivity` | Subnet | `DisruptSubnet` |
| Failover-RDS | `aws:rds:failover-db-cluster` | RDS Cluster | `DisruptRds` |
| Pause-ElastiCache | `aws:elasticache:replicationgroup-interrupt-az-power` | ElastiCache RG | `ElasticacheImpact` |
| Pause-EBS-IO | `aws:ebs:pause-volume-io` | EBS Volume | `ApiPauseVolume` |
| Disrupt-S3-Express | `aws:network:disrupt-connectivity` | Subnet (S3 Express) | `DisruptSubnet` |
| Start-ARC-Autoshift | `aws:arc:start-zonal-autoshift` | — | `RecoverAutoshiftResources` |

**爆炸半径控制**：仅测试特定服务时，可裁剪 Sub-Action 仅保留相关服务加上 `Pause-Network-Connectivity`（逼真模拟 AZ 故障的必要条件）。

## 标签策略

所有 Sub-Action 共享标签键 `AzImpairmentPower`。标签不区分 AZ — 实验模板内部的 AZ 过滤器负责 AZ 选择。

标签通过同一 CloudFormation 堆栈中的 **Lambda 支持的 CFN 自定义资源** 应用：

```python
import json
import boto3
import cfnresponse

def handler(event, context):
    try:
        # Tagging logic for Create/Update/Delete events
        # Apply AzImpairmentPower tags to target resources
        cfnresponse.send(event, context, cfnresponse.SUCCESS, {})
    except Exception as e:
        print(f"ERROR: {e}")
        cfnresponse.send(event, context, cfnresponse.FAILED, {"Error": str(e)})
```

**ASG 标签分两步**（关键）：
1. 为 ASG 打标签并设置 `PropagateAtLaunch: true`（未来的实例会自动继承标签）
2. 直接为 ASG 中现有的 EC2 实例打标签（当前实例需要立即获得标签）

## FIS IAM 角色权限

对覆盖范围完善的部分使用 AWS 托管策略，其余使用内联策略：

| Managed Policy | 覆盖范围 |
|---------------|---------|
| `AWSFaultInjectionSimulatorEC2Access` | EC2 停止/启动、KMS 授权、SSM |
| `AWSFaultInjectionSimulatorNetworkAccess` | 用于连接中断的网络 ACL |
| `AWSFaultInjectionSimulatorRDSAccess` | RDS 集群故障转移 |

其余权限的内联策略：
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "elasticache:InterruptClusterAzPower",
        "elasticache:DescribeReplicationGroups",
        "ebs:PauseVolumeIO",
        "ebs:DescribeVolumes",
        "ec2:DescribeVolumes",
        "autoscaling:DescribeAutoScalingGroups",
        "tag:GetResources"
      ],
      "Resource": "*"
    }
  ]
}
```

## 执行

```bash
# 1. Deploy the CloudFormation stack (includes experiment template + tagging)
aws cloudformation deploy \
  --template-file az-power-interruption.yaml \
  --stack-name fis-az-power-int-2a-$(openssl rand -hex 3) \
  --parameter-overrides \
    TargetAZ=us-east-1a \
    ExperimentName=az-power-test \
  --capabilities CAPABILITY_NAMED_IAM

# 2. Get the experiment template ID
TEMPLATE_ID=$(aws cloudformation describe-stacks \
  --stack-name {STACK_NAME} \
  --query "Stacks[0].Outputs[?OutputKey=='ExperimentTemplateId'].OutputValue" \
  --output text)

# 3. Start the experiment
aws fis start-experiment --experiment-template-id $TEMPLATE_ID

# 4. Monitor experiment status
watch -n 15 'aws fis get-experiment \
  --id {EXPERIMENT_ID} \
  --query "experiment.{State:state.status,Actions:actions}"'
```

## 停止条件告警

```bash
aws cloudwatch put-metric-alarm \
  --alarm-name "chaos-stop-az-power" \
  --namespace "AWS/ApplicationELB" \
  --metric-name "HTTPCode_Target_5XX_Count" \
  --statistic Sum \
  --period 60 \
  --threshold 100 \
  --comparison-operator GreaterThanThreshold \
  --evaluation-periods 2 \
  --treat-missing-data notBreaching \
  --dimensions Name=LoadBalancer,Value=app/my-alb/1234567890
```

## 观测指标

| 指标 | 来源 | 预期行为 |
|-----|------|---------|
| EC2 实例状态 | EC2 API | running → stopped → running（实验结束后） |
| ALB 健康主机数 | CloudWatch (AWS/ApplicationELB) | 目标 AZ 下降，健康 AZ 保持稳定 |
| RDS 故障转移事件 | RDS Events | 触发故障转移，写入节点切换 AZ |
| ElastiCache IsPrimary | CloudWatch (AWS/ElastiCache) | 如果主节点在目标 AZ 则发生角色交换 |
| EBS 卷 IO | CloudWatch (AWS/EBS) | 目标 AZ 的卷 IO 暂停 |
| 网络连接 | VPC Flow Logs | 目标 AZ 子网被阻断 |
| ARC Zonal Autoshift | ARC API | 流量从受损 AZ 转移 |

## 预期结果

### 通过
- 目标 AZ 中的所有服务按预期受损
- 流量自动转移到健康的 AZ
- 服务故障转移（RDS、ElastiCache）在 60 秒内完成
- 实验全程应用程序成功率 >= 95%
- 实验结束后 5 分钟内完全恢复

### 失败
- 应用程序成功率低于 95% — 未真正实现 AZ 弹性
- RDS 或 ElastiCache 故障转移超过 60 秒 — 高可用配置需要调优
- 恢复时间超过 5 分钟 — 自动扩缩或健康检查过慢
- 级联故障扩散到健康 AZ — 存在单点故障
- ASG 无法在健康 AZ 中扩容 — 容量或限额问题

## 自定义实验时长

运行较短版本：

```bash
# Default: PT10M (10 minutes), override to PT5M
# Update all action durations in the experiment template
```

## 清理

```bash
# Delete the CloudFormation stack (removes experiment template + tags)
aws cloudformation delete-stack --stack-name {STACK_NAME}

# Verify stack deletion
aws cloudformation wait stack-delete-complete --stack-name {STACK_NAME}
```

Lambda 自定义资源会在堆栈删除期间自动移除所有 `AzImpairmentPower` 标签。

## 设计说明

- **每个 AZ 一个堆栈**：目标 AZ 在实验模板中硬编码。要测试不同的 AZ，需删除后重新部署。
- **默认移除 Pause-Instance-Launches**：`aws:ec2:api-insufficient-instance-capacity-error` 操作被排除，因为 `Pause-ASG-Scaling` 已经阻止了 ASG 启动，且 FIS 不接受服务关联角色作为目标。
- **基于标签的定位**：AZ 过滤由实验模板完成，而非由标签完成。所有 AZ 中的资源可以同时携带相同的标签。
