# FIS Scenario Library 参考

> ⚠️ **重要**：FIS Scenario Library 场景是**控制台体验**——场景不是完整的实验模板，不能直接通过 API 导入。
> 三种自动化路径：(1) 通过控制台 Scenario Library 创建模板，然后用 `aws fis get-experiment-template` 导出；(2) 从控制台 Content tab 复制场景内容，手动补全缺失参数，通过 `aws fis create-experiment-template` API 创建；
> (3) 使用下方的 JSON 模板骨架，将占位符替换为实际值，直接通过 `aws fis create-experiment-template --cli-input-json` API 创建——完全无需控制台操作，实现全自动化。
> 以下 JSON 骨架从 AWS 文档提取，供参考 — 用于理解结构，
> 或直接配合 CLI 实现全自动化。

## 概述

FIS Scenario Library 提供**预构建的多 action 实验模板**，模拟真实世界的故障场景。
与单 action 实验（如终止一个 EC2 实例）不同，这些场景协调**多个服务的多个操作**，
模拟 AZ 级或 Region 级故障。

### 与单 Action 实验的关键区别

| 方面 | 单 Action | Scenario Library |
|------|----------|-----------------|
| 范围 | 单服务、单操作 | 多服务、协调操作 |
| 模板创建 | API / CLI / 控制台 | 控制台 Scenario Library UI，或通过 API/CLI 手动组装等效的多 action 模板 |
| 资源定位 | ARN / 标签过滤 | **强制资源标签**（场景特定） |
| 复杂度 | 简单 | 编排式多阶段 |
| 用途 | 组件级验证 | AZ/Region 级韧性验证 |

---

## 场景 1：AZ Power Interruption（AZ 电力中断）

**场景 ID**：`az-availability-scenario`

模拟单个可用区的完全电力故障，同时影响多个服务。

### 子操作

| Action | 服务 | 效果 |
|--------|------|------|
| `aws:ec2:stop-instances` | EC2 | 停止目标 AZ 的实例 |
| `aws:rds:failover-db-cluster` | RDS/Aurora | 触发数据库故障转移 |
| `aws:ebs:pause-volume-io` | EBS | 暂停目标 AZ 的卷 IO |
| `aws:elasticache:interrupt-cluster-az-power` | ElastiCache | 中断 AZ 内缓存节点电力 |

### 必需资源标签

资源**必须**打上以下标签，场景才能定位：

| 标签键 | 标签值 | 应用于 |
|--------|--------|--------|
| `AzImpairmentPower` | `IceQualified` | EC2 实例、EBS 卷 |
| （RDS 集群） | 在控制台中通过集群标识符选择 | RDS/Aurora |
| （ElastiCache） | 在控制台中通过集群标识符选择 | ElastiCache |

### 参数

| 参数 | 说明 | 示例 |
|------|------|------|
| `availabilityZone` | 目标中断的 AZ | `ap-northeast-1a` |
| `duration` | 中断持续时间 | `PT10M`（ISO 8601） |

### JSON 模板骨架

```json
{
  "description": "AZ Power Interruption - 模拟单 AZ 电力中断",
  "targets": {
    "ec2-instances": {
      "resourceType": "aws:ec2:instance",
      "resourceTags": {
        "AzImpairmentPower": "IceQualified"
      },
      "filters": [
        {
          "path": "Placement.AvailabilityZone",
          "values": ["{{availabilityZone}}"]
        }
      ],
      "selectionMode": "ALL"
    },
    "ebs-volumes": {
      "resourceType": "aws:ebs:volume",
      "resourceTags": {
        "AzImpairmentPower": "IceQualified"
      },
      "filters": [
        {
          "path": "AvailabilityZone",
          "values": ["{{availabilityZone}}"]
        }
      ],
      "selectionMode": "ALL"
    },
    "rds-clusters": {
      "resourceType": "aws:rds:cluster",
      "resourceArns": ["{{rdsClusterArn}}"],
      "selectionMode": "ALL"
    },
    "elasticache-clusters": {
      "resourceType": "aws:elasticache:replicationgroup",
      "resourceArns": ["{{elasticacheArn}}"],
      "selectionMode": "ALL"
    }
  },
  "actions": {
    "stop-ec2": {
      "actionId": "aws:ec2:stop-instances",
      "parameters": {
        "startInstancesAfterDuration": "{{duration}}"
      },
      "targets": {
        "Instances": "ec2-instances"
      }
    },
    "pause-ebs-io": {
      "actionId": "aws:ebs:pause-volume-io",
      "parameters": {
        "duration": "{{duration}}"
      },
      "targets": {
        "Volumes": "ebs-volumes"
      }
    },
    "failover-rds": {
      "actionId": "aws:rds:failover-db-cluster",
      "parameters": {},
      "targets": {
        "Clusters": "rds-clusters"
      }
    },
    "interrupt-elasticache": {
      "actionId": "aws:elasticache:interrupt-cluster-az-power",
      "parameters": {
        "duration": "{{duration}}"
      },
      "targets": {
        "ReplicationGroups": "elasticache-clusters"
      }
    }
  },
  "stopConditions": [
    {
      "source": "aws:cloudwatch:alarm",
      "value": "{{stopConditionAlarmArn}}"
    }
  ],
  "roleArn": "{{fisRoleArn}}",
  "tags": {
    "Purpose": "chaos-engineering",
    "Scenario": "az-power-interruption"
  }
}
```

### CLI 命令（API 自动化）

将上方 JSON 模板保存为 `az-power-interruption.json`（替换所有 `{{placeholder}}` 占位符），然后执行：

```bash
aws fis create-experiment-template --cli-input-json file://az-power-interruption.json
```

创建后，启动实验：

```bash
aws fis start-experiment --experiment-template-id <TEMPLATE_ID>
```

### 前置条件

- 所有目标 EC2 实例和 EBS 卷已打标签 `AzImpairmentPower: IceQualified`
- FIS IAM Role 拥有权限：`ec2:StopInstances`、`ec2:StartInstances`、`ebs:PauseVolumeIO`、`rds:FailoverDBCluster`、`elasticache:InterruptClusterAzPower`
- 多 AZ 部署（否则此测试无韧性验证价值）
- CloudWatch Alarm 已配置用作停止条件
- 剩余 AZ 有足够容量承接全部流量

---

## 场景 2：AZ Application Slowdown（AZ 应用减速）

**场景 ID**：`az-application-slowdown-scenario`

模拟单 AZ 应用层性能退化 — 网络延迟和丢包影响应用流量，但不完全断电。

### 子操作

| Action | 服务 | 效果 |
|--------|------|------|
| `aws:ec2:disrupt-network-connectivity` | EC2 | 通过 NACL 注入网络中断（延迟/丢包） |
| `aws:lambda:invocation-add-delay` | Lambda | 为 Lambda 调用增加延迟 |

### 必需资源标签

| 标签键 | 标签值 | 应用于 |
|--------|--------|--------|
| `AzImpairmentPower` | `IceQualified` | 目标 AZ 的 EC2 实例 |
| （Lambda 函数） | 在控制台中通过函数名选择 | Lambda 函数 |

### 参数

| 参数 | 说明 | 示例 |
|------|------|------|
| `availabilityZone` | 目标 AZ | `ap-northeast-1a` |
| `duration` | 减速持续时间 | `PT10M` |
| `scope` | 中断范围（`availability-zone` 或 `vpc`） | `availability-zone` |

### JSON 模板骨架

```json
{
  "description": "AZ Application Slowdown - 单 AZ 网络性能退化",
  "targets": {
    "ec2-subnets": {
      "resourceType": "aws:ec2:subnet",
      "resourceTags": {
        "AzImpairmentPower": "IceQualified"
      },
      "filters": [
        {
          "path": "AvailabilityZone",
          "values": ["{{availabilityZone}}"]
        }
      ],
      "selectionMode": "ALL"
    },
    "lambda-functions": {
      "resourceType": "aws:lambda:function",
      "resourceArns": ["{{lambdaFunctionArn}}"],
      "selectionMode": "ALL"
    }
  },
  "actions": {
    "disrupt-network": {
      "actionId": "aws:network:disrupt-connectivity",
      "parameters": {
        "duration": "{{duration}}",
        "scope": "{{scope}}"
      },
      "targets": {
        "Subnets": "ec2-subnets"
      }
    },
    "slow-lambda": {
      "actionId": "aws:lambda:invocation-add-delay",
      "parameters": {
        "duration": "{{duration}}",
        "invocationPercentage": "100",
        "delayMilliseconds": "2000"
      },
      "targets": {
        "Functions": "lambda-functions"
      }
    }
  },
  "stopConditions": [
    {
      "source": "aws:cloudwatch:alarm",
      "value": "{{stopConditionAlarmArn}}"
    }
  ],
  "roleArn": "{{fisRoleArn}}",
  "tags": {
    "Purpose": "chaos-engineering",
    "Scenario": "az-application-slowdown"
  }
}
```

### CLI 命令（API 自动化）

将上方 JSON 模板保存为 `az-application-slowdown.json`（替换所有 `{{placeholder}}` 占位符），然后执行：

```bash
aws fis create-experiment-template --cli-input-json file://az-application-slowdown.json
```

创建后，启动实验：

```bash
aws fis start-experiment --experiment-template-id <TEMPLATE_ID>
```

### 前置条件

- 目标子网已打适当标签
- FIS IAM Role 拥有权限：`ec2:CreateNetworkAcl*`、`ec2:DeleteNetworkAcl*`、`lambda:InvokeFunction`（FIS 扩展）
- 已配置应用层健康检查（非仅 TCP 健康检查）
- 延迟感知告警已就位用作停止条件

---

## 场景 3：Cross-AZ Traffic Slowdown（跨 AZ 流量减速）

**场景 ID**：`cross-az-traffic-slowdown-scenario`

模拟可用区之间的网络性能退化 — 跨 AZ 流量延迟增加和丢包，但 AZ 内流量正常。

### 子操作

| Action | 服务 | 效果 |
|--------|------|------|
| `aws:network:disrupt-connectivity` | VPC | 中断跨 AZ 网络路径 |

### 必需资源标签

| 标签键 | 标签值 | 应用于 |
|--------|--------|--------|
| `AzImpairmentPower` | `IceQualified` | 涉及跨 AZ 流量的子网 |

### 参数

| 参数 | 说明 | 示例 |
|------|------|------|
| `availabilityZone` | 跨 AZ 流量退化的源 AZ | `ap-northeast-1a` |
| `duration` | 流量退化持续时间 | `PT10M` |
| `scope` | 必须为 `availability-zone` | `availability-zone` |

### JSON 模板骨架

```json
{
  "description": "Cross-AZ Traffic Slowdown - 跨 AZ 网络性能退化",
  "targets": {
    "target-subnets": {
      "resourceType": "aws:ec2:subnet",
      "resourceTags": {
        "AzImpairmentPower": "IceQualified"
      },
      "filters": [
        {
          "path": "AvailabilityZone",
          "values": ["{{availabilityZone}}"]
        }
      ],
      "selectionMode": "ALL"
    }
  },
  "actions": {
    "disrupt-cross-az-traffic": {
      "actionId": "aws:network:disrupt-connectivity",
      "parameters": {
        "duration": "{{duration}}",
        "scope": "availability-zone"
      },
      "targets": {
        "Subnets": "target-subnets"
      }
    }
  },
  "stopConditions": [
    {
      "source": "aws:cloudwatch:alarm",
      "value": "{{stopConditionAlarmArn}}"
    }
  ],
  "roleArn": "{{fisRoleArn}}",
  "tags": {
    "Purpose": "chaos-engineering",
    "Scenario": "cross-az-traffic-slowdown"
  }
}
```

### CLI 命令（API 自动化）

将上方 JSON 模板保存为 `cross-az-traffic-slowdown.json`（替换所有 `{{placeholder}}` 占位符），然后执行：

```bash
aws fis create-experiment-template --cli-input-json file://cross-az-traffic-slowdown.json
```

创建后，启动实验：

```bash
aws fis start-experiment --experiment-template-id <TEMPLATE_ID>
```

### 前置条件

- 目标 AZ 子网已打标签 `AzImpairmentPower: IceQualified`
- FIS IAM Role 拥有权限：`ec2:CreateNetworkAcl*`、`ec2:DeleteNetworkAcl*`、`ec2:DescribeSubnets`、`ec2:DescribeVpcs`
- 应用采用多 AZ 架构（否则无韧性可验证）
- 跨 AZ 延迟监控已就位（CloudWatch 或应用指标）

---

## 场景 4：Cross-Region Connectivity（跨区域连接中断）

**场景 ID**：`cross-region-scenario`

模拟 AWS 区域之间的连接中断 — 通过路由表或 Transit Gateway 修改中断跨区域流量。

### 子操作

| Action | 服务 | 效果 |
|--------|------|------|
| `aws:network:route-table-disrupt-cross-region-connectivity` | VPC | 中断跨区域路由 |
| `aws:network:transit-gateway-disrupt-cross-region-connectivity` | TGW | 中断 TGW 跨区域对等连接 |

### 必需资源标签

| 标签键 | 标签值 | 应用于 |
|--------|--------|--------|
| （路由表） | 在控制台中通过路由表 ID 选择 | VPC 路由表 |
| （Transit Gateway） | 在控制台中通过 TGW ID 选择 | Transit Gateway |

### 参数

| 参数 | 说明 | 示例 |
|------|------|------|
| `duration` | 跨区域中断持续时间 | `PT10M` |
| `region` | 要断开连接的远程区域 | `us-west-2` |

### JSON 模板骨架

```json
{
  "description": "Cross-Region Connectivity - 中断区域间连接",
  "targets": {
    "route-tables": {
      "resourceType": "aws:ec2:routeTable",
      "resourceArns": ["{{routeTableArn}}"],
      "selectionMode": "ALL"
    },
    "transit-gateways": {
      "resourceType": "aws:ec2:transit-gateway",
      "resourceArns": ["{{transitGatewayArn}}"],
      "selectionMode": "ALL"
    }
  },
  "actions": {
    "disrupt-route-tables": {
      "actionId": "aws:network:route-table-disrupt-cross-region-connectivity",
      "parameters": {
        "duration": "{{duration}}"
      },
      "targets": {
        "RouteTables": "route-tables"
      }
    },
    "disrupt-tgw": {
      "actionId": "aws:network:transit-gateway-disrupt-cross-region-connectivity",
      "parameters": {
        "duration": "{{duration}}"
      },
      "targets": {
        "TransitGateways": "transit-gateways"
      }
    }
  },
  "stopConditions": [
    {
      "source": "aws:cloudwatch:alarm",
      "value": "{{stopConditionAlarmArn}}"
    }
  ],
  "roleArn": "{{fisRoleArn}}",
  "tags": {
    "Purpose": "chaos-engineering",
    "Scenario": "cross-region-connectivity"
  }
}
```

### CLI 命令（API 自动化）

将上方 JSON 模板保存为 `cross-region-connectivity.json`（替换所有 `{{placeholder}}` 占位符），然后执行：

```bash
aws fis create-experiment-template --cli-input-json file://cross-region-connectivity.json
```

创建后，启动实验：

```bash
aws fis start-experiment --experiment-template-id <TEMPLATE_ID>
```

### 前置条件（VPC Peering、TGW 或 Direct Connect 跨区域）
- FIS IAM Role 拥有权限：`ec2:CreateRoute`、`ec2:DeleteRoute`、`ec2:ReplaceRoute`、`ec2:DescribeRouteTables`、`ec2:DescribeTransitGateways`
- 跨区域健康检查和故障转移机制已配置
- DNS 故障转移（Route 53）或 Global Accelerator 已就位
- **注意**：这是影响最大的场景 — 务必先在非生产环境验证

---

## 在混沌工程工作流中的使用

### 何时使用 Scenario Library（vs. 单 Action）

| 场景 | 推荐 |
|------|------|
| 验证单组件韧性 | 单 FIS action 或 Chaos Mesh |
| 验证 AZ 级韧性 | **Scenario Library**（AZ Power / AZ Slowdown） |
| 验证跨 AZ 架构 | **Scenario Library**（Cross-AZ Traffic） |
| 验证多区域故障转移 | **Scenario Library**（Cross-Region） |
| Game Day 演练 | **Scenario Library**（真实复合故障） |

### 控制台创建流程

1. 打开 **AWS 控制台 → FIS → Scenario Library**
2. 选择目标场景
3. 配置参数（AZ、持续时间、目标资源）
4. 审查自动生成的多 action 模板
5. 确保所有目标资源已打上**必需标签**
6. 创建实验模板
7. 配置停止条件和监控后运行

### API/CLI 工作流（全自动化）

1. 从上方对应场景中复制 JSON 模板骨架
2. 将所有 `{{placeholder}}` 占位符替换为实际资源 ARN、AZ 名称、持续时间、角色 ARN
3. 保存为 JSON 文件（如 `az-power-interruption.json`）
4. 确保所有目标资源已打上**必需标签**
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
