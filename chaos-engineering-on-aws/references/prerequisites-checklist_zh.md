# 混沌工程前置条件清单

本文档列出混沌工程实验所需的所有前置条件，按架构模式分类。在运行实验前使用此清单准备环境。

> **提示**：运行 `scripts/setup-prerequisites.sh` 可自动化常见配置任务。

---

## 通用前置条件（所有架构）

### IAM 权限

#### FIS 实验角色

FIS 执行实验时假设的 IAM 角色。所有基于 FIS 的实验都需要。

```
角色名: FISExperimentRole（推荐）
信任策略: fis.amazonaws.com
```

**按实验类型的最小权限：**

| 实验类型 | 所需权限 |
|---------|---------|
| EC2 终止/停止/重启 | `ec2:TerminateInstances`、`ec2:StopInstances`、`ec2:StartInstances`、`ec2:RebootInstances`、`ec2:DescribeInstances` |
| EKS 节点终止 | `ec2:TerminateInstances`、`eks:DescribeNodegroup`、`autoscaling:*` |
| RDS 故障转移/重启 | `rds:FailoverDBCluster`、`rds:RebootDBInstance`、`rds:DescribeDBClusters` |
| 网络中断 | `ec2:CreateNetworkAcl`、`ec2:CreateNetworkAclEntry`、`ec2:DeleteNetworkAcl`、`ec2:DeleteNetworkAclEntry`、`ec2:DescribeNetworkAcls`、`ec2:ReplaceNetworkAclAssociation`、`ec2:DescribeSubnets`、`ec2:DescribeVpcs` |
| EBS 卷 IO 暂停 | `ec2:PauseVolumeIO`、`ec2:DescribeVolumes` |
| Lambda 故障注入 | `lambda:InvokeFunction`、`lambda:GetFunction`（FIS 扩展权限） |
| API 错误注入 | `fis:InjectApiInternalError`、`fis:InjectApiThrottleError` |
| ElastiCache AZ 电力 | `elasticache:InterruptClusterAzPower`、`elasticache:DescribeReplicationGroups` |
| S3 复制暂停 | `s3:PutReplicationConfiguration`、`s3:GetReplicationConfiguration` |
| DynamoDB 复制暂停 | `dynamodb:DescribeTable`、`dynamodb:UpdateTable` |

**FIS 还需要：**
- `logs:CreateLogDelivery`（如日志输出到 CloudWatch Logs）
- `cloudwatch:DescribeAlarms`（用于停止条件）

#### 分级 FIS IAM Policy 模板

无需手动拼凑权限，直接使用以下即用型 Policy 模板，将合适的 Tier 附加到 `FISExperimentRole`。

> **推荐**：为 `FISExperimentRole` 添加[权限边界（Permission Boundary）](https://docs.aws.amazon.com/IAM/latest/UserGuide/access_policies_boundaries.html)，防止权限提升，将范围限定在实验所需服务内。

**Tier 1 — 仅 EC2**（EC2 实验的安全起点）：

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "FISTier1EC2",
      "Effect": "Allow",
      "Action": [
        "ec2:DescribeInstances",
        "ec2:TerminateInstances",
        "ec2:StopInstances",
        "ec2:StartInstances",
        "ec2:RebootInstances",
        "ec2:SendSpotInstanceInterruptions",
        "ec2:CreateNetworkAcl",
        "ec2:CreateNetworkAclEntry",
        "ec2:DeleteNetworkAcl",
        "ec2:DeleteNetworkAclEntry",
        "ec2:DescribeNetworkAcls",
        "ec2:ReplaceNetworkAclAssociation",
        "ec2:DescribeSubnets",
        "ec2:DescribeVpcs",
        "ec2:PauseVolumeIO",
        "ec2:DescribeVolumes",
        "logs:CreateLogDelivery",
        "cloudwatch:DescribeAlarms"
      ],
      "Resource": "*"
    }
  ]
}
```

**Tier 2 — EC2 + RDS**（在 Tier 1 基础上增加数据库故障转移）：

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "FISTier2EC2RDS",
      "Effect": "Allow",
      "Action": [
        "ec2:DescribeInstances",
        "ec2:TerminateInstances",
        "ec2:StopInstances",
        "ec2:StartInstances",
        "ec2:RebootInstances",
        "ec2:SendSpotInstanceInterruptions",
        "ec2:CreateNetworkAcl",
        "ec2:CreateNetworkAclEntry",
        "ec2:DeleteNetworkAcl",
        "ec2:DeleteNetworkAclEntry",
        "ec2:DescribeNetworkAcls",
        "ec2:ReplaceNetworkAclAssociation",
        "ec2:DescribeSubnets",
        "ec2:DescribeVpcs",
        "ec2:PauseVolumeIO",
        "ec2:DescribeVolumes",
        "rds:FailoverDBCluster",
        "rds:RebootDBInstance",
        "rds:DescribeDBClusters",
        "logs:CreateLogDelivery",
        "cloudwatch:DescribeAlarms"
      ],
      "Resource": "*"
    }
  ]
}
```

**Tier 3 — 完整版**（包含 EKS、Lambda、ECS、DynamoDB、ElastiCache、S3 的所有 FIS action）：

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "FISTier3Full",
      "Effect": "Allow",
      "Action": [
        "ec2:DescribeInstances",
        "ec2:TerminateInstances",
        "ec2:StopInstances",
        "ec2:StartInstances",
        "ec2:RebootInstances",
        "ec2:SendSpotInstanceInterruptions",
        "ec2:CreateNetworkAcl",
        "ec2:CreateNetworkAclEntry",
        "ec2:DeleteNetworkAcl",
        "ec2:DeleteNetworkAclEntry",
        "ec2:DescribeNetworkAcls",
        "ec2:ReplaceNetworkAclAssociation",
        "ec2:DescribeSubnets",
        "ec2:DescribeVpcs",
        "ec2:PauseVolumeIO",
        "ec2:DescribeVolumes",
        "ec2:CreateRoute",
        "ec2:DeleteRoute",
        "ec2:ReplaceRoute",
        "ec2:DescribeRouteTables",
        "ec2:DescribeTransitGateways",
        "eks:DescribeNodegroup",
        "eks:ListNodegroups",
        "autoscaling:DescribeAutoScalingGroups",
        "autoscaling:TerminateInstanceInAutoScalingGroup",
        "rds:FailoverDBCluster",
        "rds:RebootDBInstance",
        "rds:DescribeDBClusters",
        "lambda:InvokeFunction",
        "lambda:GetFunction",
        "ecs:StopTask",
        "ecs:UpdateContainerInstancesState",
        "ecs:DescribeTasks",
        "ecs:ListTasks",
        "dynamodb:DescribeTable",
        "dynamodb:UpdateTable",
        "elasticache:InterruptClusterAzPower",
        "elasticache:DescribeReplicationGroups",
        "s3:PutReplicationConfiguration",
        "s3:GetReplicationConfiguration",
        "ssm:SendCommand",
        "ssm:GetCommandInvocation",
        "fis:InjectApiInternalError",
        "fis:InjectApiThrottleError",
        "logs:CreateLogDelivery",
        "cloudwatch:DescribeAlarms"
      ],
      "Resource": "*"
    }
  ]
}
```

> **权限边界示例** — 创建边界策略限制 FIS Role 的爆炸半径：
>
> ```json
> {
>   "Version": "2012-10-17",
>   "Statement": [
>     {
>       "Effect": "Allow",
>       "Action": [
>         "ec2:*", "rds:*", "eks:*", "ecs:*", "lambda:*",
>         "elasticache:*", "dynamodb:*", "s3:GetReplicationConfiguration",
>         "s3:PutReplicationConfiguration", "autoscaling:*", "ssm:SendCommand",
>         "ssm:GetCommandInvocation", "fis:InjectApi*",
>         "logs:CreateLogDelivery", "cloudwatch:DescribeAlarms"
>       ],
>       "Resource": "*"
>     }
>   ]
> }
> ```
>
> 创建角色时附加边界：
> ```bash
> aws iam create-role \
>   --role-name FISExperimentRole \
>   --assume-role-policy-document file://fis-trust-policy.json \
>   --permissions-boundary arn:aws:iam::<ACCOUNT_ID>:policy/FISPermissionBoundary
> ```

#### 操作人员权限

执行实验的人员/CI 需要：

```
fis:CreateExperimentTemplate
fis:StartExperiment
fis:StopExperiment
fis:GetExperiment
fis:ListExperiments
fis:ListExperimentTemplates
fis:DeleteExperimentTemplate
cloudwatch:PutMetricAlarm
cloudwatch:DescribeAlarms
cloudwatch:GetMetricData
iam:PassRole（传递 FIS Role）
```

### CloudWatch 监控

- 至少配置一个 CloudWatch Alarm 作为停止条件
- 关键指标可采集（延迟、错误率、成功率）
- 告警评估周期 ≤ 60s 以快速响应

### 网络

- VPC 安全组规则正确（允许监控流量）
- 出站互联网访问或 VPC Endpoint 用于 AWS API 调用

---

## 架构特定前置条件

### EKS 微服务

#### Kubernetes 访问

- `kubectl` 已配置集群访问权限
- EKS 认证模式支持当前凭证（ConfigMap 或 API）
- 实验命名空间的 RBAC 权限

#### Chaos Mesh（可选但推荐用于 Pod 级故障）

```bash
# 检查是否已安装
kubectl get crd | grep chaos-mesh

# 如需安装（Helm）
helm repo add chaos-mesh https://charts.chaos-mesh.org
helm install chaos-mesh chaos-mesh/chaos-mesh \
  --namespace chaos-mesh --create-namespace \
  --set chaosDaemon.runtime=containerd \
  --set chaosDaemon.socketPath=/run/containerd/containerd.sock
```

**Chaos Mesh 要求：**
- 集群版本 >= 1.24
- containerd 或 Docker 运行时
- Chaos Mesh controller 的 RBAC 权限
- 目标命名空间未被排除在 Chaos Mesh 范围之外

#### EKS 特定

| 要求 | 检查命令 | 说明 |
|-----|---------|------|
| 托管节点组或 ASG | `aws eks list-nodegroups --cluster-name <name>` | 用于节点终止实验 |
| 多副本 | `kubectl get deploy -n <ns>` | 副本数 >= 2 才有韧性 |
| 资源限制已设 | `kubectl describe pod <pod>` | StressChaos 必需 |
| Pod 中断预算 | `kubectl get pdb -n <ns>` | 推荐用于受控中断 |
| 健康检查已配置 | `kubectl get deploy -o yaml` | 存活探针 + 就绪探针 |

### Serverless（Lambda + API Gateway + DynamoDB）

| 要求 | 检查命令 | 说明 |
|-----|---------|------|
| Lambda 函数 ARN | `aws lambda get-function --function-name <name>` | 目标函数存在且活跃 |
| 预留并发 | `aws lambda get-function-concurrency` | 避免限流无关函数 |
| DynamoDB 全局表 | `aws dynamodb describe-table` | 用于复制暂停实验 |
| API Gateway 阶段 | `aws apigateway get-stages` | 用于端到端延迟监控 |
| CloudWatch Logs | 检查日志组存在 | 用于实验后日志分析 |
| X-Ray 追踪 | `aws lambda get-function-configuration` | 推荐用于延迟分析 |

### EC2 传统架构（ALB + ASG + RDS）

| 要求 | 检查命令 | 说明 |
|-----|---------|------|
| ASG 已配置 | `aws autoscaling describe-auto-scaling-groups` | 用于实例替换 |
| ALB 健康检查 | `aws elbv2 describe-target-health` | 检测不健康实例 |
| 多 AZ RDS | `aws rds describe-db-clusters` | 用于故障转移实验 |
| EBS 快照 | `aws ec2 describe-snapshots` | IO 暂停前备份 |
| SSM Agent 已安装 | `aws ssm describe-instance-information` | 用于 SSM 实验 |
| CloudWatch Agent | 检查指标命名空间 | 用于实例级指标 |

### 多区域

| 要求 | 检查命令 | 说明 |
|-----|---------|------|
| 多区域部署 | 验证两个区域的资源 | 架构必须跨区域 |
| Route 53 健康检查 | `aws route53 list-health-checks` | 基于 DNS 的故障转移 |
| Global Accelerator | `aws globalaccelerator list-accelerators` | 网络层故障转移 |
| 跨区域 VPC Peering 或 TGW | `aws ec2 describe-vpc-peering-connections` | 用于路由中断实验 |
| S3 CRR 已配置 | `aws s3api get-bucket-replication` | 用于复制暂停 |
| DynamoDB 全局表 | `aws dynamodb describe-table` | 用于复制暂停 |
| 跨区域监控 | CloudWatch 跨账号/区域 | 同时监控两个区域 |

---

## FIS Scenario Library 额外前置条件

使用 FIS Scenario Library（复合场景）时，有额外要求：

### 资源打标

Scenario Library 使用**强制标签**识别目标资源。创建实验**前**必须打标：

```bash
# AZ Power Interruption / AZ Application Slowdown / Cross-AZ Traffic
aws ec2 create-tags --resources <instance-id> <volume-id> \
  --tags Key=AzImpairmentPower,Value=IceQualified

# 验证标签
aws ec2 describe-instances --instance-ids <id> \
  --query "Reservations[].Instances[].Tags[?Key=='AzImpairmentPower']"
```

### 扩展 FIS Role 权限

Scenario Library 实验涉及多个服务。FIS Role 需要所有子操作的组合权限：

| 场景 | 单 Action 之外的额外权限 |
|------|------------------------|
| AZ Power Interruption | EC2 停止/启动 + EBS IO 暂停 + RDS 故障转移 + ElastiCache 中断 全部组合 |
| AZ Application Slowdown | 网络 NACL + Lambda 调用 全部组合 |
| Cross-AZ Traffic | 网络 NACL（与单个 network:disrupt-connectivity 相同） |
| Cross-Region | 两个区域的路由表 + TGW 修改权限 |

### 容量验证

AZ 级实验前，验证剩余 AZ 能承接全部流量：

```bash
# 检查 ASG 跨 AZ 分布
aws autoscaling describe-auto-scaling-groups \
  --query "AutoScalingGroups[].{Name:AutoScalingGroupName,AZs:AvailabilityZones,Desired:DesiredCapacity}"

# 检查每个 AZ 的目标组健康状态
aws elbv2 describe-target-health --target-group-arn <arn>
```

---

## Pre-flight 快速参考

任何实验前运行以下检查：

```bash
# 1. AWS 凭证有效
aws sts get-caller-identity

# 2. FIS Role 存在
aws iam get-role --role-name FISExperimentRole

# 3. 目标资源健康
aws ec2 describe-instance-status --instance-ids <ids>
aws rds describe-db-clusters --db-cluster-identifier <id>
aws eks describe-cluster --name <name>

# 4. 停止条件告警存在
aws cloudwatch describe-alarms --alarm-names <alarm-name>

# 5. Chaos Mesh 已安装（如 EKS Pod 实验）
kubectl get crd | grep chaos-mesh
kubectl get pods -n chaos-mesh

# 6. 监控正常工作
aws cloudwatch get-metric-data --metric-data-queries '[...]' \
  --start-time $(date -u -d '5 minutes ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S)
```
