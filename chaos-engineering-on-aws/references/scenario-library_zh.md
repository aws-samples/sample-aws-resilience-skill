# FIS Scenario Library 参考

> ⚠️ **重要**：FIS Scenario Library 是控制台功能。场景是一组预构建的 action 和 target，不是可直接运行的实验模板：角色、停止条件、资源标签和部分标识符仍需自行补充。
> 每个官方场景页面都公布了 **Scenario Content** JSON，AWS 明确说明该 JSON 可保存后配合 `aws fis create-experiment-template` 使用。创建模板的三种方式：
> (1) 通过控制台 Scenario Library 创建模板，再用 `aws fis get-experiment-template` 导出；
> (2) 从控制台 **Content** 标签页（最新版本）复制场景内容，补全缺失值，用 `aws fis create-experiment-template` 创建；
> (3) 使用下方转载的官方 Scenario Content JSON，补全缺失值，用 `aws fis create-experiment-template --cli-input-json` 创建——全自动，无需控制台操作。
> 下方 JSON 块逐字复制自 AWS 文档页面（`us-east-1a`、空 `roleArn` 等占位值均为 AWS 原文）。控制台 Content 标签页可能比这些副本更新。

> 🛑 **停止条件**：AWS 文档对四个场景都写明了同一限制——场景**不包含停止条件**，必须在实验模板中加入适合你应用的停止条件。
> 本 skill **要求**每个实验都绑定 CloudWatch 告警停止条件：创建模板前，把官方 JSON 的 `stopConditions` 块替换为 `[{"source": "aws:cloudwatch:alarm", "value": "<告警 ARN>"}]`。

## 概述

FIS Scenario Library 提供**预构建的多 action 实验模板**，模拟真实世界的故障场景。
与单 action 实验（如终止一个 EC2 实例）不同，这些场景协调**多个服务的多个操作**，
模拟 AZ 级或 Region 级故障。

### 与单 Action 实验的关键区别

| 方面 | 单 Action | Scenario Library |
|------|----------|-----------------|
| 范围 | 单服务、单操作 | 多服务、协调操作 |
| 模板创建 | API / CLI / 控制台 | 控制台 Scenario Library UI，或将官方 Scenario Content JSON 交给 `create-experiment-template` |
| 资源定位 | ARN / 标签过滤 | **场景默认标签**（或你自己的标签）、EKS Pod label、IAM 角色 ARN |
| 目标为空 | 实验失败 | `emptyTargetResolutionMode: skip`——没有匹配目标的 action 被跳过 |
| 复杂度 | 简单 | 编排式多阶段 |
| 用途 | 组件级验证 | AZ/Region 级韧性验证 |

> ⚠️ 由于场景使用 `emptyTargetResolutionMode: skip`，标签缺失或拼错不会让实验失败——对应 action 会被静默跳过。在把任何结果解读为"有韧性"之前，先核对实验解析出的目标列表。

---

## 场景 1：AZ Power Interruption（AZ 电力中断）

**场景 ID**：`az-availability-scenario`（控制台名称：**AZ Availability: Power Interruption**）

制造单个可用区完全断电时的预期症状：AZ 内计算资源丢失（EC2，以及运行在 EC2 上的 EKS/ECS）、AZ 内计算无法重新扩容、子网连通性丢失、RDS 故障转移、ElastiCache 故障转移、EBS 卷无响应。
默认先注入 30 分钟断电症状，之后再用 30 分钟注入恢复期可能出现的症状（`Pause-EBS-IO` 在两个停止 action 都结束后才开始）。

### 子操作

| Action 名称（JSON） | Action ID | 效果 |
|--------------------|-----------|------|
| `Stop-Instances` | `aws:ec2:stop-instances` | 停止 AZ 内带标签的运行中实例 30 分钟，然后重启 |
| `Stop-ASG-Instances` | `aws:ec2:stop-instances` | 停止 AZ 内 ASG 管理的实例 30 分钟，然后重启 |
| `Pause-Instance-Launches` | `aws:ec2:api-insufficient-instance-capacity-error` | 对目标 IAM 角色在该 AZ 发起的 `RunInstances`/`StartInstances`/`CreateFleet` 调用返回 InsufficientInstanceCapacity |
| `Pause-ASG-Scaling` | `aws:ec2:asg-insufficient-instance-capacity-error` | 对 ASG 控制平面在该 AZ 的调用返回 InsufficientInstanceCapacity（同时阻止 EKS/ECS 在该 AZ 扩容） |
| `Pause-network-connectivity` | `aws:network:disrupt-connectivity` | 阻断 AZ 内带标签子网的全部流量（`scope: all`）2 分钟，近似 DNS 更新窗口 |
| `Failover-RDS` | `aws:rds:failover-db-cluster` | 对 writer 位于该 AZ 的带标签集群执行故障转移 |
| `Pause-ElastiCache` | `aws:elasticache:replicationgroup-interrupt-az-power` | 对启用 Multi-AZ 的复制组中位于该 AZ 的节点断电 30 分钟，期间阻止替换 |
| `Pause-EBS-IO` | `aws:ebs:pause-volume-io` | 停止 action 结束后，暂停 1 个带标签卷（`COUNT(1)`）的 I/O 30 分钟 |

文档正文还描述了 `aws:arc:start-zonal-autoshift`（开始 5 分钟后启动，流量迁移 25 分钟，标签值 `RecoverAutoshiftResources`）以及一个针对 S3 Express One Zone 目录桶的 `aws:network:disrupt-connectivity` action。这两个都不在文档页的 Scenario Content JSON 中；如需使用，请查看控制台 Content 标签页。

### 必需资源标签

所有标签的 key 都是 `AzImpairmentPower`。下表取值来自官方 Scenario Content JSON；你可以在模板中替换为自己的标签。

| 标签 Key | 标签 Value | 应用于 |
|---------|-----------|--------|
| `AzImpairmentPower` | `StopInstances` | EC2 实例（不在 ASG 中） |
| `AzImpairmentPower` | `IceAsg` | Auto Scaling 组**及其** EC2 实例 |
| `AzImpairmentPower` | `DisruptSubnet` | 该 AZ 内的子网 |
| `AzImpairmentPower` | `DisruptRds` | RDS / Aurora 集群 |
| `AzImpairmentPower` | `DisruptElasticache` | ElastiCache 复制组 |
| `AzImpairmentPower` | `ApiPauseVolume` | EBS 卷（只选中 `DeleteOnTermination=false` 的卷） |
| （无） | `IAM-role` target 中的 IAM 角色 ARN | 负责创建实例的角色（该 action 不支持标签） |

> ⚠️ 文档正文对其中两项写的是 `ElasticacheImpact` 和 `APIPauseVolume`，但 Scenario Content JSON 用的是 `DisruptElasticache` 和 `ApiPauseVolume`。请按你实际创建的模板中的取值给资源打标签。

### 参数

| 参数 | 在 JSON 中的位置 | 默认值 |
|------|-----------------|--------|
| 可用区 | `Placement.AvailabilityZone` / `AvailabilityZone` 过滤器、`availabilityZoneIdentifier`、`writerAvailabilityZoneIdentifiers`、`availabilityZoneIdentifiers` | `us-east-1a`（**每一处**都要替换） |
| 中断时长 | `duration` / `startInstancesAfterDuration` | `PT30M` |
| 网络中断时长 | `Pause-network-connectivity.duration` | `PT2M` |
| ICE 百分比 | 两个 ICE action 的 `percentage` | `100` |
| 创建实例的角色 | `targets.IAM-role.resourceArns` | `[]`（需填写，否则该 action 被跳过） |
| 实验角色 | `roleArn` | `""`（必须填写） |

### 官方 Scenario Content JSON

source: official doc https://docs.aws.amazon.com/fis/latest/userguide/az-availability-scenario.html, retrieved 2026-11-09; the console Content tab is the latest version

```json
{
  "targets": {
    "IAM-role": {
      "resourceType": "aws:iam:role",
      "resourceArns": [],
      "selectionMode": "ALL"
    },
    "EBS-Volumes": {
      "resourceType": "aws:ec2:ebs-volume",
      "resourceTags": {
        "AzImpairmentPower": "ApiPauseVolume"
      },
      "selectionMode": "COUNT(1)",
      "parameters": {
        "availabilityZoneIdentifier": "us-east-1a"
      },
      "filters": [
        {
          "path": "Attachments.DeleteOnTermination",
          "values": [
            "false"
          ]
        }
      ]
    },
    "EC2-Instances": {
      "resourceType": "aws:ec2:instance",
      "resourceTags": {
        "AzImpairmentPower": "StopInstances"
      },
      "filters": [
        {
          "path": "State.Name",
          "values": [
            "running"
          ]
        },
        {
          "path": "Placement.AvailabilityZone",
          "values": [
            "us-east-1a"
          ]
        }
      ],
      "selectionMode": "ALL"
    },
    "ASG": {
      "resourceType": "aws:ec2:autoscaling-group",
      "resourceTags": {
        "AzImpairmentPower": "IceAsg"
      },
      "selectionMode": "ALL"
    },
    "ASG-EC2-Instances": {
      "resourceType": "aws:ec2:instance",
      "resourceTags": {
        "AzImpairmentPower": "IceAsg"
      },
      "filters": [
        {
          "path": "State.Name",
          "values": [
            "running"
          ]
        },
        {
          "path": "Placement.AvailabilityZone",
          "values": [
            "us-east-1a"
          ]
        }
      ],
      "selectionMode": "ALL"
    },
    "Subnet": {
      "resourceType": "aws:ec2:subnet",
      "resourceTags": {
        "AzImpairmentPower": "DisruptSubnet"
      },
      "filters": [
        {
          "path": "AvailabilityZone",
          "values": [
            "us-east-1a"
          ]
        }
      ],
      "selectionMode": "ALL",
      "parameters": {}
    },
    "RDS-Cluster": {
      "resourceType": "aws:rds:cluster",
      "resourceTags": {
        "AzImpairmentPower": "DisruptRds"
      },
      "selectionMode": "ALL",
      "parameters": {
        "writerAvailabilityZoneIdentifiers": "us-east-1a"
      }
    },
    "ElastiCache-Cluster": {
      "resourceType": "aws:elasticache:replicationgroup",
      "resourceTags": {
        "AzImpairmentPower": "DisruptElasticache"
      },
      "selectionMode": "ALL",
      "parameters": {
        "availabilityZoneIdentifier": "us-east-1a"
      }
    }
  },
  "actions": {
    "Pause-Instance-Launches": {
      "actionId": "aws:ec2:api-insufficient-instance-capacity-error",
      "parameters": {
        "availabilityZoneIdentifiers": "us-east-1a",
        "duration": "PT30M",
        "percentage": "100"
      },
      "targets": {
        "Roles": "IAM-role"
      }
    },
    "Pause-EBS-IO": {
      "actionId": "aws:ebs:pause-volume-io",
      "parameters": {
        "duration": "PT30M"
      },
      "targets": {
        "Volumes": "EBS-Volumes"
      },
      "startAfter": [
        "Stop-Instances",
        "Stop-ASG-Instances"
      ]
    },
    "Stop-Instances": {
      "actionId": "aws:ec2:stop-instances",
      "parameters": {
        "completeIfInstancesTerminated": "true",
        "startInstancesAfterDuration": "PT30M"
      },
      "targets": {
        "Instances": "EC2-Instances"
      }
    },
    "Pause-ASG-Scaling": {
      "actionId": "aws:ec2:asg-insufficient-instance-capacity-error",
      "parameters": {
        "availabilityZoneIdentifiers": "us-east-1a",
        "duration": "PT30M",
        "percentage": "100"
      },
      "targets": {
        "AutoScalingGroups": "ASG"
      }
    },
    "Stop-ASG-Instances": {
      "actionId": "aws:ec2:stop-instances",
      "parameters": {
        "completeIfInstancesTerminated": "true",
        "startInstancesAfterDuration": "PT30M"
      },
      "targets": {
        "Instances": "ASG-EC2-Instances"
      }
    },
    "Pause-network-connectivity": {
      "actionId": "aws:network:disrupt-connectivity",
      "parameters": {
        "duration": "PT2M",
        "scope": "all"
      },
      "targets": {
        "Subnets": "Subnet"
      }
    },
    "Failover-RDS": {
      "actionId": "aws:rds:failover-db-cluster",
      "parameters": {},
      "targets": {
        "Clusters": "RDS-Cluster"
      }
    },
    "Pause-ElastiCache": {
      "actionId": "aws:elasticache:replicationgroup-interrupt-az-power",
      "parameters": {
        "duration": "PT30M"
      },
      "targets": {
        "ReplicationGroups": "ElastiCache-Cluster"
      }
    }
  },
  "stopConditions": [
    {
      "source": "aws:cloudwatch:alarm",
      "value": ""
    }
  ],
  "roleArn": "",
  "tags": {
    "Name": "AZ Impairment: Power Interruption"
  },
  "logConfiguration": {
    "logSchemaVersion": 2
  },
  "experimentOptions": {
    "accountTargeting": "single-account",
    "emptyTargetResolutionMode": "skip"
  },
  "description": "Affect multiple resource types in a single AZ, targeting by tags and explicit ARNs, to approximate power interruption in one AZ."
}
```

创建模板前：填写 `roleArn`（API 要求至少 20 个字符，`""` 会被拒绝）；把 `stopConditions` 中空的告警 `value` 替换为你的告警 ARN；替换所有 `us-east-1a`；在 `IAM-role` 中填入角色 ARN，或删除 `Pause-Instance-Launches`（见下文裁剪）。JSON 中的 `logConfiguration` 只有 `logSchemaVersion` 没有目的地；请添加 CloudWatch Logs 或 S3 目的地，或删除该块（一份 CloudFormation 参考指南报告无目的地的该块会报错 "Must specify at least one log destination"；此处未通过 CLI 验证）。

### CLI 命令（API 自动化）

将修改后的 JSON 保存为 `az-power-interruption.json`，然后：

```bash
aws fis create-experiment-template --cli-input-json file://az-power-interruption.json
```

创建后启动实验：

```bash
aws fis start-experiment --experiment-template-id <TEMPLATE_ID>
```

带强制告警停止条件的参数化版本见 `references/templates/az-power-interruption.json`。它保留了官方的子操作、target 和标签，但有两处有意的差异：`Pause-EBS-IO` 在一个 `aws:fis:wait` action（`Wait-Before-EBS-Pause`，时长与中断相同）之后启动，而不是对两个停止 action 使用 `startAfter`，这样任一停止 action 都可以单独裁剪而不会留下悬空引用；并且省略了 `logConfiguration`。

### 前置条件

- 按上表给资源打标签（或把模板改成你自己的标签）
- FIS 实验角色附加文档页中的策略。该策略授予：`ec2:StopInstances`、`ec2:StartInstances`、`ec2:DescribeInstances`、`ec2:InjectApiError`（条件 `ec2:FisActionId` = 两个 ICE action）、`autoscaling:DescribeAutoScalingGroups`、`ec2:PauseVolumeIO`、`ec2:DescribeVolumes`、`kms:CreateGrant`（用于加密卷，经由 `ec2.*.amazonaws.com`）、网络 ACL 权限组（`ec2:CreateNetworkAcl`、`ec2:CreateNetworkAclEntry`、`ec2:DeleteNetworkAcl`、`ec2:ReplaceNetworkAclAssociation`、带 `managedByFIS=true` 的 `ec2:CreateTags`、`ec2:DescribeVpcs`、`ec2:DescribeSubnets`、`ec2:DescribeNetworkAcls`、`ec2:DescribeManagedPrefixLists`）、`rds:FailoverDBCluster`、`rds:RebootDBInstance`、`elasticache:InterruptClusterAzPower`、`elasticache:DescribeReplicationGroups`、`tag:GetResources`，以及 CloudWatch Logs 投递权限
- 如果加入 ARC zonal autoshift：需要服务关联角色 `AWSServiceRoleForZonalAutoshiftPracticeRun`（由 ARC 自动创建）
- Multi-AZ 部署（否则此测试没有韧性验证价值）；ElastiCache 复制组必须启用 Multi-AZ
- 用作停止条件的 CloudWatch 告警（本 skill 强制要求）
- 剩余 AZ 有足够容量承接全部流量
- 文档列出的限制：Fargate 上的 EKS Pod 和 ECS 任务不受影响；不支持带两个可读备用实例的 RDS Multi-AZ（受影响 AZ 会立即重新补充容量）

### 按服务裁剪子动作

当用户点名具体服务时（"AZ 断电对 RDS 的影响"、"测试 EC2 和 ElastiCache"），**只**保留这些服务的子操作，再加上模拟 AZ 本身的子操作。不要默认下发全部八个子操作：同一 AZ 内的其他应用会被波及。只有用户要求完整 AZ 断电或没有点名任何服务时才运行全套，并且在创建模板前始终把最终子操作清单向用户复述确认。

**模拟 AZ 本身的子操作**（依据官方文档判断）：

| 子操作 | 决定 | 理由 |
|--------|------|------|
| `Pause-network-connectivity`（`aws:network:disrupt-connectivity`，target `Subnet`） | 每个裁剪后的集合**默认保留** | 文档说明事件期间 AZ 内网络不可用，且 DNS 在几分钟内可能返回不可达的私有 IP；正是这 2 分钟的阻断让范围内的客户端看到这一现象。只有用户明确拒绝网络中断时才删除，并需确认。 |
| `Pause-ASG-Scaling`（`aws:ec2:asg-insufficient-instance-capacity-error`，target `ASG`） | 只要范围内有**任何计算资源**（ASG 中的 EC2、EC2 上的 EKS 或 ECS）就保留 | 文档把它对应到"AZ 内计算无法重新扩容"，并说明它同样阻止 EKS 和 ECS 在该 AZ 扩容。它只作用于带标签的 ASG，所以对只测 RDS、ElastiCache 或 EBS 的实验没有贡献。 |
| `Pause-Instance-Launches`（`aws:ec2:api-insufficient-instance-capacity-error`，target `IAM-role`） | **仅当**用户提供了在 Auto Scaling 之外创建实例的角色 ARN（脚本、CI/CD、Lambda）时保留 | 文档说明该 action 只能按 ARN 定位 IAM 角色，找不到时跳过。参考指南另外报告服务关联角色不被接受、空 `resourceArns` 会导致 CloudFormation 校验失败；这两点官方文档没有写明，视为未验证。 |
| ARC zonal autoshift（`aws:arc:start-zonal-autoshift`） | 仅当环境中有启用 autoshift 的资源时添加 | 文档正文有描述，但不在文档的 Scenario Content JSON 中，也不在 `references/templates/az-power-interruption.json` 中。 |

**用户提到 X → 保留：**

| 用户提到 | 保留子操作 | 保留 target | 需打的标签（`AzImpairmentPower=`） | 保留的 IAM 语句 |
|---------|-----------|------------|----------------------------------|----------------|
| （始终，除非用户拒绝） | `Pause-network-connectivity` | `Subnet` | 该 AZ 子网上的 `DisruptSubnet` | 网络 ACL 权限组（`ec2:CreateNetworkAcl`、`ec2:CreateNetworkAclEntry`、`ec2:DeleteNetworkAcl`、`ec2:ReplaceNetworkAclAssociation`、带 `managedByFIS` 的 `ec2:CreateTags`、`ec2:DescribeVpcs`、`ec2:DescribeSubnets`、`ec2:DescribeNetworkAcls`、`ec2:DescribeManagedPrefixLists`） |
| （始终） | — | — | — | `tag:GetResources`；如保留 `logConfiguration`，还需 CloudWatch Logs 投递语句 |
| EC2（独立实例） | `Stop-Instances` | `EC2-Instances` | `StopInstances` | `ec2:StopInstances`、`ec2:StartInstances`、`ec2:DescribeInstances`、`kms:CreateGrant`（加密卷） |
| ASG 中的 EC2、Auto Scaling、EC2 上的 EKS 或 ECS | `Stop-ASG-Instances`、`Pause-ASG-Scaling` | `ASG-EC2-Instances`、`ASG` | ASG **及其**当前实例上的 `IceAsg` | 同上，另加 `ec2:InjectApiError`（条件 `ec2:FisActionId` = `aws:ec2:asg-insufficient-instance-capacity-error`）和 `autoscaling:DescribeAutoScalingGroups` |
| 调用 `RunInstances` 的自定义角色 | `Pause-Instance-Launches` | `IAM-role`（角色 ARN） | —（仅 ARN） | `ec2:InjectApiError`（条件 `ec2:FisActionId` = `aws:ec2:api-insufficient-instance-capacity-error`） |
| RDS / Aurora | `Failover-RDS` | `RDS-Cluster` | `DisruptRds` | `rds:FailoverDBCluster`（文档策略还列出 `rds:RebootDBInstance`） |
| ElastiCache（Redis / Valkey） | `Pause-ElastiCache` | `ElastiCache-Cluster` | `DisruptElasticache` | `elasticache:InterruptClusterAzPower`、`elasticache:DescribeReplicationGroups` |
| EBS | `Pause-EBS-IO`（skill 模板中另加 `Wait-Before-EBS-Pause`） | `EBS-Volumes` | `ApiPauseVolume`（`DeleteOnTermination=false` 的卷） | `ec2:PauseVolumeIO`、`ec2:DescribeVolumes`、`kms:CreateGrant`（加密卷） |

**裁剪规则：**

1. 删除子操作时**连同它的 target 一起**删除。`references/templates/az-power-interruption.json` 中每个 action 都有独立的 target（action 的 `description` 写明了删除单元），所以删除一对 action+target 后模板仍能通过 `validate-skill.sh`。在官方文档 JSON 中，`Pause-EBS-IO` 带有 `startAfter: ["Stop-Instances", "Stop-ASG-Instances"]`；在那里裁剪停止 action 时，也要从该列表中删掉对应名称。
2. 删除不再被任何 action 引用的 target。官方 FIS 文档没有说明 `create-experiment-template` 是否拒绝未被引用的 target（未验证），所以无论如何都删掉；未使用的基于标签的 target 只会造成混淆。
3. 同时删除被裁剪服务的 IAM 语句和标签，使角色保持最小权限。
4. **裁剪永远不删除 `stopConditions`。** CloudWatch 告警停止条件保留在每个裁剪后的模板中。不要采用 `"source": "none"`，即使官方跨 AZ、跨 Region 场景内容和某些参考指南使用了它。
5. 裁剪缩小了爆炸半径，但并不能隔离其余服务：只要保留了 `Pause-network-connectivity`，**带标签子网中的所有资源在其持续时间内都会失去连通性**，不论属于哪个服务。要缩小这一影响，只给承载范围内服务的子网打标签，并告知用户哪些其他工作负载共享这些子网。

---

## 场景 2：AZ Application Slowdown（AZ 应用减速）

**场景 ID**：`az-application-slowdown-scenario`（控制台名称：**AZ: Application Slowdown**）

在单个 AZ 内的资源之间的网络流上增加延迟——一种灰色故障。默认对 100% 的流增加 200 ms 延迟，持续 30 分钟。三个 action 并行运行；场景要求该 AZ 内至少有一个 EC2 实例、ECS 任务或 EKS Pod，且所有目标必须在同一个 VPC 中。

### 子操作

| Action 名称（JSON） | Action ID | 效果 |
|--------------------|-----------|------|
| `LatencyForEC2` | `aws:ssm:send-command`（文档 `AWSFIS-Run-Network-Latency-Sources`） | 在 EC2 实例上对发往该 AZ 的流量增加延迟 |
| `LatencyForECS` | `aws:ecs:task-network-latency` | 在 ECS 任务（EC2 或 Fargate）上增加延迟 |
| `LatencyForEKS` | `aws:eks:pod-network-latency` | 在 EKS Pod（运行于 EC2）上增加延迟 |

### 必需资源标签

| 标签 Key / Label | Value | 应用于 |
|-----------------|-------|--------|
| `AZApplicationSlowdown`（标签） | `LatencyForEC2` | EC2 实例 |
| `AZApplicationSlowdown`（标签） | `LatencyForECS` | ECS 任务 |
| `AZApplicationSlowdown`（Pod label） | `LatencyForEKS` | `clusterIdentifier` 所指集群 `default` 命名空间中的 EKS Pod |

### 参数

| 参数 | 在 JSON 中的位置 | 默认值 |
|------|-----------------|--------|
| 可用区 | `sources`、`documentParameters` 中的 `Sources`、AZ 过滤器、`availabilityZoneIdentifier` | `us-east-1a` |
| 延迟 | `delayMilliseconds` / `DelayMilliseconds` | `200` |
| 流百分比 | `flowsPercent` / `FlowsPercent` | `100` |
| 时长 | `duration`（EC2 另有 `DurationSeconds`） | `PT30M`（`1800`） |
| EKS 集群 | `TargetsForEKS.parameters.clusterIdentifier` | `""`——填写，或**删除 EKS action 和 target** |
| EKS 服务账户 | `kubernetesServiceAccount` | `fis-service-account` |

### 官方 Scenario Content JSON

source: official doc https://docs.aws.amazon.com/fis/latest/userguide/az-application-slowdown-scenario.html, retrieved 2026-11-09; the console Content tab is the latest version

```json
{
  "tags": {
    "Name": "AZ: Application Slowdown"
  },
  "description": "Add latency between resources within a single AZ.",
  "actions": {
    "LatencyForEKS": {
      "actionId": "aws:eks:pod-network-latency",
      "parameters": {
        "delayMilliseconds": "200",
        "duration": "PT30M",
        "flowsPercent": "100",
        "interface": "DEFAULT",
        "kubernetesServiceAccount": "fis-service-account",
        "sources": "us-east-1a"
      },
      "targets": {
        "Pods": "TargetsForEKS"
      }
    },
    "LatencyForEC2": {
      "actionId": "aws:ssm:send-command",
      "parameters": {
        "duration": "PT30M",
        "documentArn": "arn:aws:ssm:us-east-1::document/AWSFIS-Run-Network-Latency-Sources",
        "documentParameters": "{\"DelayMilliseconds\":\"200\",\"Sources\":\"us-east-1a\",\"Interface\":\"DEFAULT\",\"TrafficType\":\"egress\",\"DurationSeconds\":\"1800\",\"FlowsPercent\":\"100\",\"InstallDependencies\":\"True\"}"
      },
      "targets": {
        "Instances": "TargetsForEC2"
      }
    },
    "LatencyForECS": {
      "actionId": "aws:ecs:task-network-latency",
      "parameters": {
        "delayMilliseconds": "200",
        "duration": "PT30M",
        "flowsPercent": "100",
        "installDependencies": "true",
        "sources": "us-east-1a",
        "useEcsFaultInjectionEndpoints": "true"
      },
      "targets": {
        "Tasks": "TargetsForECS"
      },
      "startAfter": []
    }
  },
  "targets": {
    "TargetsForEKS": {
      "parameters": {
        "availabilityZoneIdentifier": "us-east-1a",
        "clusterIdentifier": "",
        "namespace": "default",
        "selectorType": "labelSelector",
        "selectorValue": "AZApplicationSlowdown=LatencyForEKS"
      },
      "resourceType": "aws:eks:pod",
      "selectionMode": "ALL"
    },
    "TargetsForEC2": {
      "filters": [
        {
          "path": "Placement.AvailabilityZone",
          "values": [
            "us-east-1a"
          ]
        }
      ],
      "resourceTags": {
        "AZApplicationSlowdown": "LatencyForEC2"
      },
      "resourceType": "aws:ec2:instance",
      "selectionMode": "ALL"
    },
    "TargetsForECS": {
      "filters": [
        {
          "path": "AvailabilityZone",
          "values": [
            "us-east-1a"
          ]
        }
      ],
      "resourceTags": {
        "AZApplicationSlowdown": "LatencyForECS"
      },
      "resourceType": "aws:ecs:task",
      "selectionMode": "ALL"
    }
  },
  "experimentOptions": {
    "accountTargeting": "single-account",
    "emptyTargetResolutionMode": "skip"
  },
  "stopConditions": [
    {
      "source": "none"
    }
  ]
}
```

创建模板前：添加 `roleArn`；把 `"stopConditions": [{"source": "none"}]` 替换为告警停止条件；设置 AZ 以及 `documentArn` 中的 Region；填写或删除 EKS target。

### CLI 命令（API 自动化）

将修改后的 JSON 保存为 `az-application-slowdown.json`，然后：

```bash
aws fis create-experiment-template --cli-input-json file://az-application-slowdown.json
```

创建后启动实验：

```bash
aws fis start-experiment --experiment-template-id <TEMPLATE_ID>
```

### 前置条件

- 一个 FIS 可以扮演的 IAM 角色。从控制台场景创建模板时，FIS 会创建该角色并附加托管策略 `AWSFaultInjectionSimulatorEC2Access`、`AWSFaultInjectionSimulatorECSAccess` 和 `AWSFaultInjectionSimulatorEKSAccess`。使用已有角色时，文档中的策略授予 `ssm:SendCommand`、`ssm:ListCommands`、`ssm:CancelCommand`、`ec2:DescribeInstances`、`ec2:DescribeSubnets`、`ecs:DescribeTasks`、`ecs:DescribeContainerInstances`、`eks:DescribeCluster` 和 `tag:GetResources`
- EC2：已安装 SSM Agent，实例由 Systems Manager 管理
- ECS：完成 ECS 任务 action 的准备（任务由 SSM 管理、`pidMode: task`、网络模式不能是 `bridge`；`flowsPercent` 需要 ECS agent 1.100.0+）
- EKS：完成 EKS Pod action 的准备（服务账户 `fis-service-account` 及其 RBAC，并把 FIS 角色映射进集群；见 FIS 用户指南 "Use the AWS FIS aws:eks:pod actions"）
- 感知延迟的 CloudWatch 告警作为停止条件（本 skill 强制要求）

---

## 场景 3：Cross-AZ Traffic Slowdown（跨 AZ 流量减速）

**场景 ID**：`cross-az-traffic-slowdown-scenario`（控制台名称：**Cross-AZ: Traffic Slowdown**）

对所选 AZ 内资源发往同 Region 其他 AZ 的出站流量注入丢包——跨 AZ 通信中的灰色故障。默认对 100% 的出站流注入 15% 丢包，持续 30 分钟。三个 action 并行运行；该 AZ 内至少需要一个 EC2 实例、ECS 任务或 EKS Pod，且所有目标必须在同一个 VPC 中。

### 子操作

| Action 名称（JSON） | Action ID | 效果 |
|--------------------|-----------|------|
| `PacketLossForEC2` | `aws:ssm:send-command`（文档 `AWSFIS-Run-Network-Packet-Loss-Sources`） | EC2 发往其他 AZ 的出站流量丢包 |
| `PacketLossForECS` | `aws:ecs:task-network-packet-loss` | ECS 任务发往其他 AZ 的出站流量丢包 |
| `PacketLossForEKS` | `aws:eks:pod-network-packet-loss` | EKS Pod 发往其他 AZ 的出站流量丢包 |

### 必需资源标签

| 标签 Key / Label | Value | 应用于 |
|-----------------|-------|--------|
| `CrossAZTrafficSlowdown`（标签） | `PacketLossForEC2` | 所选 AZ 内的 EC2 实例 |
| `CrossAZTrafficSlowdown`（标签） | `PacketLossForECS` | 所选 AZ 内的 ECS 任务 |
| `CrossAZTrafficSlowdown`（Pod label） | `PacketLossForEKS` | `clusterIdentifier` 所指集群 `default` 命名空间中的 EKS Pod |

> ⚠️ 文档正文给出的 EKS label 是 `CrossAZTraffic=PacketLossForEKS`，而 Scenario Content JSON 使用 `CrossAZTrafficSlowdown=PacketLossForEKS`。请按你实际创建的模板中的 `selectorValue` 给 Pod 打 label。

### 参数

| 参数 | 在 JSON 中的位置 | 默认值 |
|------|-----------------|--------|
| 受损 AZ | AZ 过滤器和 `availabilityZoneIdentifier` | `us-east-1a` |
| 目的 AZ | `sources` / `Sources` | `us-east-1b,…,us-east-1f`——设为你所在 Region 的**其他** AZ |
| 丢包率 | `lossPercent` / `LossPercent` | `15` |
| 流百分比 | `flowsPercent` / `FlowsPercent` | `100` |
| 时长 | `duration`（EC2 另有 `DurationSeconds`） | `PT30M`（`1800`） |
| EKS 集群 | `TargetsForEKS.parameters.clusterIdentifier` | `""`——填写，或**删除 EKS action 和 target** |

### 官方 Scenario Content JSON

source: official doc https://docs.aws.amazon.com/fis/latest/userguide/cross-az-traffic-slowdown-scenario.html, retrieved 2026-11-09; the console Content tab is the latest version

```json
{
  "tags": {
    "Name": "Cross-AZ: Traffic Slowdown"
  },
  "description": "Inject packet loss to disrupt and slow down traffic between AZs.",
  "actions": {
    "PacketLossForEC2": {
      "actionId": "aws:ssm:send-command",
      "parameters": {
        "duration": "PT30M",
        "documentArn": "arn:aws:ssm:us-east-1::document/AWSFIS-Run-Network-Packet-Loss-Sources",
        "documentParameters": "{\"Sources\":\"us-east-1b,us-east-1c,us-east-1d,us-east-1e,us-east-1f\",\"LossPercent\":\"15\",\"Interface\":\"DEFAULT\",\"TrafficType\":\"egress\",\"DurationSeconds\":\"1800\",\"FlowsPercent\":\"100\",\"InstallDependencies\":\"True\"}"
      },
      "targets": {
        "Instances": "TargetsForEC2"
      }
    },
    "PacketLossForECS": {
      "actionId": "aws:ecs:task-network-packet-loss",
      "parameters": {
        "sources": "us-east-1b,us-east-1c,us-east-1d,us-east-1e,us-east-1f",
        "lossPercent": "15",
        "duration": "PT30M",
        "flowsPercent": "100",
        "installDependencies": "true",
        "useEcsFaultInjectionEndpoints": "true"
      },
      "targets": {
        "Tasks": "TargetsForECS"
      }
    },
    "PacketLossForEKS": {
      "actionId": "aws:eks:pod-network-packet-loss",
      "parameters": {
        "sources": "us-east-1b,us-east-1c,us-east-1d,us-east-1e,us-east-1f",
        "lossPercent": "15",
        "duration": "PT30M",
        "flowsPercent": "100",
        "interface": "DEFAULT",
        "kubernetesServiceAccount": "fis-service-account"
      },
      "targets": {
        "Pods": "TargetsForEKS"
      }
    }
  },
  "targets": {
    "TargetsForEC2": {
      "filters": [
        {
          "path": "Placement.AvailabilityZone",
          "values": [
            "us-east-1a"
          ]
        }
      ],
      "resourceTags": {
        "CrossAZTrafficSlowdown": "PacketLossForEC2"
      },
      "resourceType": "aws:ec2:instance",
      "selectionMode": "ALL"
    },
    "TargetsForECS": {
      "filters": [
        {
          "path": "AvailabilityZone",
          "values": [
            "us-east-1a"
          ]
        }
      ],
      "resourceTags": {
        "CrossAZTrafficSlowdown": "PacketLossForECS"
      },
      "resourceType": "aws:ecs:task",
      "selectionMode": "ALL"
    },
    "TargetsForEKS": {
      "parameters": {
        "availabilityZoneIdentifier": "us-east-1a",
        "clusterIdentifier": "",
        "namespace": "default",
        "selectorType": "labelSelector",
        "selectorValue": "CrossAZTrafficSlowdown=PacketLossForEKS"
      },
      "resourceType": "aws:eks:pod",
      "selectionMode": "ALL"
    }
  },
  "experimentOptions": {
    "accountTargeting": "single-account",
    "emptyTargetResolutionMode": "skip"
  },
  "stopConditions": [
    {
      "source": "none"
    }
  ]
}
```

创建模板前：添加 `roleArn`；把 `"stopConditions": [{"source": "none"}]` 替换为告警停止条件；设置各 AZ 以及 `documentArn` 中的 Region；填写或删除 EKS target。

### CLI 命令（API 自动化）

将修改后的 JSON 保存为 `cross-az-traffic-slowdown.json`，然后：

```bash
aws fis create-experiment-template --cli-input-json file://cross-az-traffic-slowdown.json
```

创建后启动实验：

```bash
aws fis start-experiment --experiment-template-id <TEMPLATE_ID>
```

### 前置条件

- 角色和权限与场景 2 相同：托管策略 `AWSFaultInjectionSimulatorEC2Access`、`AWSFaultInjectionSimulatorECSAccess`、`AWSFaultInjectionSimulatorEKSAccess`，或文档中的策略（`ssm:SendCommand`、`ssm:ListCommands`、`ssm:CancelCommand`、`ec2:DescribeInstances`、`ec2:DescribeSubnets`、`ecs:DescribeTasks`、`ecs:DescribeContainerInstances`、`eks:DescribeCluster`、`tag:GetResources`）
- EC2 / ECS / EKS 的准备与场景 2 相同
- 应用按多 AZ 设计（否则没有可验证的韧性）
- 跨 AZ 延迟 / 错误监控，以及作为停止条件的 CloudWatch 告警（本 skill 强制要求）

---

## 场景 4：Cross-Region Connectivity（跨区域连接中断）

**场景 ID**：`cross-region-scenario`（控制台名称：**Cross-Region: Connectivity**）

阻断从实验 Region 发往目的 Region 的出站应用流量，并暂停跨 Region 复制。来自目的 Region 的无状态入站流量以及 AWS 托管服务的流量可能不会被阻断。各 action 默认并行运行 3 小时（最长 12 小时）。

### 子操作

| Action 名称（JSON） | Action ID | 效果 |
|--------------------|-----------|------|
| `Disrupt-Transit-Gateway-Connectivity` | `aws:network:transit-gateway-disrupt-cross-region-connectivity` | 阻断经 TGW peering 发往目的 Region 的流量 |
| `Disrupt-Subnet-Connectivity` | `aws:network:route-table-disrupt-cross-region-connectivity` | 阻断目标子网发往目的 Region 公共 AWS IP 段以及经跨 Region VPC peering 的流量 |
| `Disrupt-Vpc-Endpoint` | `aws:network:disrupt-vpc-endpoint` | 阻断目标接口 VPC 端点（PrivateLink）的流量 |
| `Pause-S3-Replication` | `aws:s3:bucket-pause-replication` | 暂停从实验 Region 到目的 Region 的 CRR |
| `Pause-DynamoDB-Replication` | `aws:dynamodb:global-table-pause-replication` | 暂停全局表进出实验 Region 的复制 |
| `Pause-MemoryDB-Multi-Region-Cluster-Replication` | `aws:memorydb:multi-region-cluster-pause-replication` | 暂停 MemoryDB 多 Region 集群中实验 Region 成员的复制 |

### 必需资源标签

下表取值来自官方 Scenario Content JSON。Transit gateway 和子网 target 使用的是字面占位标签，必须替换。

| 标签 Key | 标签 Value | 应用于 |
|---------|-----------|--------|
| `TgwTag`（占位） | `TgwValue`（占位） | Transit gateway——文档正文默认：`DisruptTransitGateway=Allowed` |
| `SubnetKey`（占位） | `SubnetValue`（占位） | 实验 Region 内的子网——文档正文默认：`DisruptSubnet=Allowed` |
| `DisruptPrivateLink` | `Allowed` | 接口 VPC 端点（正文：`DisruptVpcEndpoint`） |
| `S3Impact` | `Allowed` | 配置了到目的 Region CRR 的 S3 桶（正文：`DisruptS3`） |
| `DisruptDynamoDb` | `Allowed` | DynamoDB 全局表（MREC 和 MRSC） |
| `DisruptMemoryDb` | `Allowed` | MemoryDB 多 Region 集群（正文：`DisruptMemoryDB`） |

> ⚠️ 文档正文与 Scenario Content JSON 在四个标签 key 上不一致（见括号）。请按你实际创建的模板中的取值给资源打标签。

### 参数

| 参数 | 在 JSON 中的位置 | 默认值 |
|------|-----------------|--------|
| 目的 Region | TGW、子网、S3 和 MemoryDB action 上的 `region` | `eu-west-1` |
| 时长 | 每个 action 的 `duration` | `PT3H`（最长 12 小时） |

### 官方 Scenario Content JSON

source: official doc https://docs.aws.amazon.com/fis/latest/userguide/cross-region-scenario.html, retrieved 2026-11-09; the console Content tab is the latest version

```json
{
  "targets": {
    "Transit-Gateway": {
      "resourceType": "aws:ec2:transit-gateway",
      "resourceTags": {
        "TgwTag": "TgwValue"
      },
      "selectionMode": "ALL"
    },
    "Subnet": {
      "resourceType": "aws:ec2:subnet",
      "resourceTags": {
        "SubnetKey": "SubnetValue"
      },
      "selectionMode": "ALL",
      "parameters": {}
    },
    "VPC-Endpoint": {
      "resourceType": "aws:ec2:vpc-endpoint",
      "resourceTags": {
        "DisruptPrivateLink": "Allowed"
      },
      "selectionMode": "ALL"
    },
    "S3-Bucket": {
      "resourceType": "aws:s3:bucket",
      "resourceTags": {
        "S3Impact": "Allowed"
      },
      "selectionMode": "ALL"
    },
    "DynamoDB-Global-Table": {
      "resourceType": "aws:dynamodb:global-table",
      "resourceTags": {
        "DisruptDynamoDb": "Allowed"
      },
      "selectionMode": "ALL"
    },
    "MemoryDB-Multi-Region-Cluster": {
      "resourceType": "aws:memorydb:multi-region-cluster",
      "resourceTags": {
        "DisruptMemoryDb": "Allowed"
      },
      "selectionMode": "ALL"
    }
  },
  "actions": {
    "Disrupt-Transit-Gateway-Connectivity": {
      "actionId": "aws:network:transit-gateway-disrupt-cross-region-connectivity",
      "parameters": {
        "duration": "PT3H",
        "region": "eu-west-1"
      },
      "targets": {
        "TransitGateways": "Transit-Gateway"
      }
    },
    "Disrupt-Subnet-Connectivity": {
      "actionId": "aws:network:route-table-disrupt-cross-region-connectivity",
      "parameters": {
        "duration": "PT3H",
        "region": "eu-west-1"
      },
      "targets": {
        "Subnets": "Subnet"
      }
    },
    "Disrupt-Vpc-Endpoint": {
      "actionId": "aws:network:disrupt-vpc-endpoint",
      "parameters": {
        "duration": "PT3H"
      },
      "targets": {
        "VPCEndpoints": "VPC-Endpoint"
      }
    },
    "Pause-S3-Replication": {
      "actionId": "aws:s3:bucket-pause-replication",
      "parameters": {
        "duration": "PT3H",
        "region": "eu-west-1"
      },
      "targets": {
        "Buckets": "S3-Bucket"
      }
    },
    "Pause-DynamoDB-Replication": {
      "actionId": "aws:dynamodb:global-table-pause-replication",
      "parameters": {
        "duration": "PT3H"
      },
      "targets": {
        "Tables": "DynamoDB-Global-Table"
      }
    },
    "Pause-MemoryDB-Multi-Region-Cluster-Replication": {
      "actionId": "aws:memorydb:multi-region-cluster-pause-replication",
      "parameters": {
        "duration": "PT3H",
        "region": "eu-west-1"
      },
      "targets": {
        "MultiRegionClusters": "MemoryDB-Multi-Region-Cluster"
      }
    }
  },
  "stopConditions": [
    {
      "source": "none"
    }
  ],
  "roleArn": "",
  "logConfiguration": {
    "logSchemaVersion": 2
  },
  "tags": {
    "Name": "Cross-Region: Connectivity"
  },
  "experimentOptions": {
    "accountTargeting": "single-account",
    "emptyTargetResolutionMode": "skip"
  },
  "description": "Block application network traffic from experiment Region to target Region and pause cross-Region replication"
}
```

创建模板前：填写 `roleArn`；把 `"stopConditions": [{"source": "none"}]` 替换为告警停止条件；替换占位标签；设置 `region`。

### CLI 命令（API 自动化）

将修改后的 JSON 保存为 `cross-region-connectivity.json`，然后：

```bash
aws fis create-experiment-template --cli-input-json file://cross-region-connectivity.json
```

创建后启动实验：

```bash
aws fis start-experiment --experiment-template-id <TEMPLATE_ID>
```

### 前置条件

- 已部署多 Region 架构（TGW peering、跨 Region VPC peering、S3 CRR、DynamoDB 全局表或 MemoryDB 多 Region）
- FIS 实验角色附加文档页中的策略。该策略授予的权限包括：路由表与前缀列表管理（`ec2:CreateRouteTable`、`ec2:CreateRoute`、`ec2:AssociateRouteTable`、`ec2:DisassociateRouteTable`、`ec2:ReplaceRouteTableAssociation`、`ec2:DeleteRouteTable`、`ec2:CreateManagedPrefixList`、`ec2:ModifyManagedPrefixList`、`ec2:DeleteManagedPrefixList`、`ec2:GetManagedPrefixListEntries`）、TGW 路由表关联（`ec2:AssociateTransitGatewayRouteTable`、`ec2:DisassociateTransitGatewayRouteTable`）、VPC 端点隔离（`ec2:CreateSecurityGroup`、`ec2:RevokeSecurityGroupEgress`、`ec2:DeleteSecurityGroup`、`ec2:ModifyVpcEndpoint`、`ec2:CreateNetworkInterface`、`ec2:DeleteNetworkInterface`、`vpce:AllowMultiRegion`）、`s3:PauseReplication`、`s3:GetReplicationConfiguration`、`s3:PutReplicationConfiguration`、`s3:ListAllMyBuckets`、`dynamodb:InjectError`、`dynamodb:DescribeTable`、`dynamodb:GetResourcePolicy`、`dynamodb:PutResourcePolicy`、`dynamodb:DeleteResourcePolicy`、`memorydb:PauseMultiRegionClusterReplication`、`memorydb:DescribeMultiRegionClusters`、相应的 `ec2:Describe*` 调用和 `tag:GetResources`
- 已配置跨 Region 健康检查和故障转移机制
- 已部署 DNS 故障转移（Route 53）或 Global Accelerator
- 用作停止条件的 CloudWatch 告警（本 skill 强制要求）
- **注意**：这是影响最大的场景——先在非生产环境验证

---

## 在混沌工程工作流中的使用

### 何时使用 Scenario Library（vs. 单 Action）

| 场景 | 建议 |
|------|------|
| 验证单组件韧性 | 单个 FIS action 或 Chaos Mesh |
| 验证 AZ 级韧性 | **Scenario Library**（AZ Power / AZ Slowdown） |
| 验证跨 AZ 架构 | **Scenario Library**（Cross-AZ Traffic） |
| 验证多 Region 故障转移 | **Scenario Library**（Cross-Region） |
| Game Day 演练 | **Scenario Library**（真实的复合故障） |

### 控制台创建流程

1. 打开 **AWS Console → FIS → Scenario Library**
2. 选择目标场景
3. 配置共享参数（AZ、时长、延迟 / 丢包、目标标签或 label）
4. 检查生成的多 action 模板（Content 标签页）
5. 确认所有目标资源带有模板所用的标签 / label
6. **添加 CloudWatch 告警停止条件**——场景本身没有
7. 创建实验模板
8. 在监控就位的情况下运行，并在相信结果之前核对解析出的目标

### API/CLI 工作流（全自动化）

1. 从上方对应场景章节（或控制台 Content 标签页）复制官方 Scenario Content JSON
2. 填写 `roleArn`，把 `stopConditions` 块替换为你的告警，并替换 AZ / Region / 标签占位值
3. 保存为 JSON 文件（如 `az-power-interruption.json`）
4. 确认所有目标资源带有模板所用的标签 / label
5. 创建实验模板：
   ```bash
   aws fis create-experiment-template --cli-input-json file://az-power-interruption.json
   ```
6. 启动实验：
   ```bash
   aws fis start-experiment --experiment-template-id <TEMPLATE_ID>
   ```
7. 监控，必要时停止：
   ```bash
   aws fis stop-experiment --id <EXPERIMENT_ID>
   ```

> **参考**：[AWS FIS Scenario Library 文档](https://docs.aws.amazon.com/fis/latest/userguide/scenario-library.html)

---

## 外部模板库

> 以上场景来自 **FIS 控制台 Scenario Library**（基于控制台、多 action 编排的场景）。
> 本节介绍 [aws-samples/fis-template-library](https://github.com/aws-samples/fis-template-library)——
> 一组可直接部署的 FIS 实验模板，附带 IAM 策略和 SSM Automation 文档。
> 与控制台 Scenario Library 场景不同，这些模板可以直接通过 CLI/API 部署，无需任何控制台操作。

完整的 27 个场景索引及详细元数据见 [`fis-template-library-index_zh.md`](fis-template-library-index_zh.md)。

`fis-templates/<name>/` 下内嵌了八个模板可直接使用：

### 数据库连接池耗尽 ⭐
- **注入方式**：SSM Automation——动态创建 EC2 负载生成器，耗尽数据库连接，自动清理
- **引擎**：Aurora PostgreSQL、Aurora MySQL、RDS PostgreSQL、RDS MySQL、RDS SQL Server
- **验证**：连接池监控、熔断器触发、优雅降级
- **模板**：`fis-templates/database-connection-exhaustion/`
- **模式**：动态资源注入

### ElastiCache Redis 连接中断 ⭐
- **注入方式**：SSM Automation——删除安全组规则以阻断应用→Redis 流量
- **验证**：熔断器（30s）、防止重试风暴、降级模式、恢复（60s）
- **模板**：`fis-templates/redis-connection-failure/`
- **模式**：安全组操纵

### SQS 队列不可用 ⭐
- **注入方式**：SSM Automation——分 4 轮递增（2→5→7→15 分钟）施加拒绝所有访问的 SQS 队列策略
- **验证**：5 分钟内告警、组件隔离、DLQ 捕获、生产者背压
- **模板**：`fis-templates/sqs-queue-impairment/`
- **模式**：资源策略拒绝（渐进式）

### CloudFront 分发不可用 ⭐
- **注入方式**：SSM Automation——对 S3 源桶施加拒绝策略
- **前置条件**：必须配置 CloudFront 源组
- **验证**：源组故障转移（30s）、告警（2-3 分钟）、恢复后回到主源
- **模板**：`fis-templates/cloudfront-impairment/`
- **模式**：资源策略拒绝

### Aurora 全局数据库跨区域故障转移 ⭐
- **注入方式**：SSM Automation——Aurora Global DB switchover 或紧急 failover API
- **模式**：Switchover（无数据丢失）或 Failover（允许数据丢失）
- **验证**：跨 Region 提升、RTO/RPO 目标、端点更新
- **模板**：`fis-templates/aurora-global-failover/`

### MSK Broker 重启 ⭐
- **注入方式**：SSM Automation——重启 Amazon MSK 集群的一个 broker
- **验证**：客户端重连、分区 leader 切换、生产者/消费者错误处理
- **模板**：`fis-templates/msk-broker-reboot/`

### ElastiCache Redis 主节点重启 ⭐
- **注入方式**：SSM Automation——重启每个带 `FIS-Ready=True` 标签的复制组的主节点；重启会清空该节点的数据
- **验证**：主节点不可用期间的客户端重连与行为
- **模板**：`fis-templates/elasticache-redis-primary-node-reboot/`

### ElastiCache Redis 主节点故障转移 ⭐
- **注入方式**：SSM Automation——对主节点执行故障转移，提升一个副本
- **验证**：副本提升、端点更新、客户端故障转移处理
- **模板**：`fis-templates/elasticache-redis-primary-node-failover/`

各模板的确切参数和 IAM 权限见其目录下的 README。

### 更多场景（通过索引查看）

索引中其余 19 个场景包括：
- EC2 实例终止、Spot 中断、Windows IIS 停止
- Aurora 集群故障转移、Aurora/MySQL 负载测试 + 故障转移
- DynamoDB 区域受损（资源策略 + 网络黑洞）
- Direct Connect 虚拟接口断开
- SAP 工作负载 HA 验证（ASCS、数据库、EBS）

完整详情见 [`fis-template-library-index_zh.md`](fis-template-library-index_zh.md)。
