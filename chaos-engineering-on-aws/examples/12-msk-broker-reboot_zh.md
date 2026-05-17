# 示例 12：MSK Broker 重启 — Kafka 客户端韧性

**架构模式**：Kafka 生产者/消费者 → Amazon MSK（托管 Kafka 集群）
**注入方式**：SSM Automation（kafka:RebootBroker → 等待 ACTIVE）
**验证点**：Kafka 生产者/消费者韧性、分区领导者选举、Broker 恢复

> 说明：MSK 没有原生 FIS 操作。故障注入使用 SSM Automation 调用 MSK API。

---

## 假设

当 MSK Broker 被重启时：
- Kafka 生产者切换到其他 Broker 并以最小消息丢失继续生产
- Kafka 消费者在 60 秒内完成分区再平衡并恢复消费
- 集群状态从 `REBOOTING_BROKER` 恢复到 `ACTIVE`
- 重启 Broker 上的分区领导者被重新选举到其他 Broker
- 无需人工干预——Broker 自动恢复上线

### 验证要点

- Kafka 生产者 `acks` 配置和 Broker 故障时的重试行为
- 消费者组再平衡速度和分区重新分配
- 单个 Broker 重启后的 MSK 集群恢复时间
- 应用程序对分区领导者变更的韧性
- 通过 FIS 执行 SSM Automation 的双角色 IAM 模式

## 前置条件

- [ ] 处于 `ACTIVE` 状态的 Amazon MSK 集群
- [ ] 已确认目标 Broker ID（使用 `aws kafka list-nodes`）
- [ ] 具有 `AWSFaultInjectionSimulatorSSMAccess` + `iam:PassRole` 权限的 FIS IAM 角色
- [ ] 具有 `kafka:RebootBroker` + `kafka:DescribeCluster` 权限的 SSM Automation IAM 角色
- [ ] Kafka 生产者已配置 `acks=all` 和重试逻辑
- [ ] Kafka 消费者已配置适当的 `session.timeout.ms` 和 `heartbeat.interval.ms`

## SSM 自动化 Runbook

```yaml
description: 'FIS: Reboot MSK broker to test Kafka client resilience'
schemaVersion: '0.3'
assumeRole: '{{ AutomationAssumeRoleArn }}'
parameters:
  AutomationAssumeRoleArn:
    type: String
    description: IAM Role ARN for SSM Automation to assume
  ClusterArn:
    type: String
    description: MSK cluster ARN
  BrokerId:
    type: String
    description: 'Broker ID to reboot (e.g., 1, 2, 3)'
mainSteps:
  - name: RebootMskBroker
    action: aws:executeAwsApi
    inputs:
      Service: kafka
      Api: RebootBroker
      ClusterArn: '{{ ClusterArn }}'
      BrokerIds:
        - '{{ BrokerId }}'
    outputs:
      - Name: ClusterArn
        Selector: $.ClusterArn
        Type: String
      - Name: ClusterOperationArn
        Selector: $.ClusterOperationArn
        Type: String

  - name: WaitForClusterActive
    action: aws:waitForAwsResourceProperty
    timeoutSeconds: 600
    inputs:
      Service: kafka
      Api: DescribeCluster
      ClusterArn: '{{ ClusterArn }}'
      PropertySelector: $.ClusterInfo.State
      DesiredValues:
        - ACTIVE
```

## 部署

### 1. 部署 SSM Automation 文档

```bash
aws ssm create-document \
  --name msk-broker-reboot \
  --document-type Automation \
  --content file://ssm-msk-broker-reboot.yaml \
  --document-format YAML
```

### 2. 部署 IAM 角色

```bash
# FIS Role (trusts fis.amazonaws.com)
aws iam create-role \
  --role-name FIS-MSK-Reboot \
  --assume-role-policy-document '{
    "Version": "2012-10-17",
    "Statement": [{"Effect": "Allow", "Principal": {"Service": "fis.amazonaws.com"}, "Action": "sts:AssumeRole"}]
  }'

aws iam attach-role-policy \
  --role-name FIS-MSK-Reboot \
  --policy-arn arn:aws:iam::aws:policy/service-role/AWSFaultInjectionSimulatorSSMAccess

aws iam put-role-policy \
  --role-name FIS-MSK-Reboot \
  --policy-name PassSSMRole \
  --policy-document '{
    "Version": "2012-10-17",
    "Statement": [{"Effect": "Allow", "Action": "iam:PassRole", "Resource": "arn:aws:iam::{account}:role/SSM-MSK-Reboot", "Condition": {"StringEquals": {"iam:PassedToService": "ssm.amazonaws.com"}}}]
  }'

# SSM Automation Role (trusts ssm.amazonaws.com)
aws iam create-role \
  --role-name SSM-MSK-Reboot \
  --assume-role-policy-document '{
    "Version": "2012-10-17",
    "Statement": [{"Effect": "Allow", "Principal": {"Service": "ssm.amazonaws.com"}, "Action": "sts:AssumeRole"}]
  }'

aws iam put-role-policy \
  --role-name SSM-MSK-Reboot \
  --policy-name MskAccess \
  --policy-document '{
    "Version": "2012-10-17",
    "Statement": [{"Effect": "Allow", "Action": ["kafka:RebootBroker", "kafka:DescribeCluster"], "Resource": "*"}]
  }'
```

### 3. 创建 FIS 实验

```bash
aws fis create-experiment-template --cli-input-json '{
  "description": "Reboot MSK broker to test Kafka producer and consumer resilience",
  "targets": {},
  "actions": {
    "reboot-broker": {
      "actionId": "aws:ssm:start-automation-execution",
      "parameters": {
        "documentArn": "arn:aws:ssm:{region}:{account}:document/msk-broker-reboot",
        "documentParameters": "{\"AutomationAssumeRoleArn\":\"arn:aws:iam::{account}:role/SSM-MSK-Reboot\",\"ClusterArn\":\"{cluster-arn}\",\"BrokerId\":\"{broker-id}\"}",
        "maxDuration": "PT15M"
      }
    }
  },
  "stopConditions": [{"source": "none"}],
  "roleArn": "arn:aws:iam::{account}:role/FIS-MSK-Reboot",
  "tags": {"Purpose": "chaos-engineering", "RiskId": "R-012"}
}'
```

## 执行

```bash
# List available broker IDs
aws kafka list-nodes --cluster-arn {CLUSTER_ARN} \
  --query 'NodeInfoList[].BrokerNodeInfo.BrokerId' --output json

# Verify cluster is ACTIVE
aws kafka describe-cluster --cluster-arn {CLUSTER_ARN} \
  --query 'ClusterInfo.State'

# Start the experiment
aws fis start-experiment --experiment-template-id {TEMPLATE_ID}

# Monitor cluster state
watch -n 10 'aws kafka describe-cluster \
  --cluster-arn {CLUSTER_ARN} \
  --query "ClusterInfo.State"'
```

## 观测指标

| 指标 | 来源 | 预期行为 |
|------|------|----------|
| Cluster state | MSK API | ACTIVE → REBOOTING_BROKER → ACTIVE |
| ActiveControllerCount | CloudWatch (AWS/Kafka) | 如果重启的 Broker 是控制器，则短暂下降 |
| UnderReplicatedPartitions | CloudWatch (AWS/Kafka) | Broker 重启期间临时增加 |
| MessagesInPerSec | CloudWatch (AWS/Kafka) | 重启的 Broker 短暂下降，其他 Broker 补偿 |
| 消费者组延迟 | Kafka 指标 | 再平衡期间临时增加 |

## 清理

`kafka:RebootBroker` 是自恢复的——Broker 自动恢复上线，无需手动清理。

```bash
# Verify cluster is back to ACTIVE
aws kafka describe-cluster --cluster-arn {CLUSTER_ARN} \
  --query 'ClusterInfo.State'

# Delete experiment template when done
aws fis delete-experiment-template --id {TEMPLATE_ID}
```
