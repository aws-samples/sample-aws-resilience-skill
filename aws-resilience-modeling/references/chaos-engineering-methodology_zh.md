> 属于 [AWS 韧性分析框架参考](resilience-framework_zh.md) 的一部分。

## 3. 混沌工程方法论

### 3.1 核心定义

> "混沌工程是通过在系统上进行实验来建立对系统能力的信心，使其能够承受生产环境中的动荡条件"
>
> —— Principles of Chaos Engineering

**目标**：
- 发现系统弱点在造成实际影响前
- 建立对系统韧性的信心
- 验证监控和告警是否有效
- 改进事故响应流程

### 3.2 四步实验流程

```yaml
步骤 1: 建立稳态基线
  定义:
    - "稳态"为可测量的系统输出
    - 表示正常行为

  示例:
    - 请求成功率: > 99.9%
    - P95 延迟: < 200ms
    - 吞吐量: 1000 req/s
    - 错误率: < 0.1%

步骤 2: 形成假设
  预测:
    - 稳态将在控制组和实验组中持续
    - 基于系统理解

  示例:
    "假设：终止 2 个 EC2 实例后，
     Auto Scaling 将在 5 分钟内恢复容量，
     用户体验影响 < 1%"

步骤 3: 引入变量
  模拟真实世界破坏:
    - 服务器崩溃
    - 网络故障
    - 磁盘满
    - 时钟偏移

  评估影响:
    - 观测稳态指标
    - 记录系统行为

步骤 4: 验证或反驳
  对比:
    - 控制组 vs 实验组
    - 识别稳态偏差

  结果:
    - 假设正确：系统韧性得到验证
    - 假设错误：发现弱点，改进系统
```

### 3.3 高级实施原则

| 原则 | 说明 | 实践 |
|------|------|------|
| **稳态关注** | 测量系统输出，而非内部机制 | 监控用户可见指标（延迟、错误） |
| **真实世界事件** | 变量应镜像实际运营中断 | 参考历史故障（EC2 故障、AZ 中断） |
| **生产测试** | "采样真实流量是唯一可靠方式" | 在生产环境中进行（受控） |
| **持续自动化** | 手动实验不可持续 | 自动化实现持续验证（每周/每月） |
| **控制爆炸半径** | 最小化客户影响 | 限制影响范围（单 AZ、10% 流量） |

### 3.4 常见混沌实验场景

#### AWS 环境常见场景：

| 实验类别 | 场景 | AWS FIS 操作 | 预期系统行为 |
|---------|------|-------------|-------------|
| **实例故障** | 终止 EC2 实例 | `aws:ec2:terminate-instances` | Auto Scaling 自动替换 |
| | 停止 EC2 实例 | `aws:ec2:stop-instances` | 健康检查失败，流量转移 |
| **网络故障** | 网络延迟 | `aws:ec2:api-network-latency` | 请求超时，重试机制触发 |
| | 网络丢包 | `aws:ec2:api-packet-loss` | 断路器打开，降级服务 |
| **AZ 故障** | 模拟 AZ 不可用 | 组合实验（终止所有 AZ 实例） | 流量转移到其他 AZ |
| **数据库** | RDS 故障转移 | `aws:rds:failover-db-cluster` | 应用自动重连，短暂中断 |
| **容器** | ECS 任务终止 | `aws:ecs:stop-task` | ECS 重启任务 |
| | EKS Pod 删除 | `aws:eks:pod-delete` | Deployment 重建 Pod |
| **资源耗尽** | CPU 压力 | `aws:ec2:cpu-stress` | Auto Scaling 扩容 |
| | 内存压力 | `aws:ec2:memory-stress` | OOM kill，容器重启 |
| | 磁盘满 | `aws:ec2:disk-fill` | 告警触发，清理流程启动 |

### 3.5 AWS FIS 实验模板示例

**实验 1：EC2 实例终止**

```json
{
  "description": "Terminate 30% of EC2 instances to test Auto Scaling",
  "targets": {
    "ec2-instances": {
      "resourceType": "aws:ec2:instance",
      "resourceTags": {
        "Environment": "production",
        "AutoScaling": "enabled"
      },
      "filters": [
        {
          "path": "State.Name",
          "values": ["running"]
        }
      ],
      "selectionMode": "PERCENT(30)"
    }
  },
  "actions": {
    "terminate-instances": {
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
      "value": "arn:aws:cloudwatch:us-east-1:123456789012:alarm:high-error-rate"
    }
  ],
  "roleArn": "arn:aws:iam::123456789012:role/FISExperimentRole",
  "tags": {
    "Name": "EC2-Instance-Termination-Test"
  }
}
```

**实验 2：网络延迟注入**

```json
{
  "description": "Inject 200ms latency to 50% of API calls",
  "targets": {
    "api-gw-targets": {
      "resourceType": "aws:ec2:instance",
      "resourceTags": {
        "Service": "api-gateway"
      },
      "selectionMode": "PERCENT(50)"
    }
  },
  "actions": {
    "inject-latency": {
      "actionId": "aws:ec2:api-network-latency",
      "parameters": {
        "duration": "PT10M",
        "latencyMs": "200",
        "jitterMs": "50",
        "apiList": "ec2,rds,dynamodb"
      },
      "targets": {
        "Instances": "api-gw-targets"
      }
    }
  },
  "stopConditions": [
    {
      "source": "aws:cloudwatch:alarm",
      "value": "arn:aws:cloudwatch:us-east-1:123456789012:alarm:high-p95-latency"
    }
  ],
  "roleArn": "arn:aws:iam::123456789012:role/FISExperimentRole"
}
```

**实验 3：RDS 故障转移**

```json
{
  "description": "Test RDS Multi-AZ failover",
  "targets": {
    "rds-cluster": {
      "resourceType": "aws:rds:cluster",
      "resourceArns": [
        "arn:aws:rds:us-east-1:123456789012:cluster:production-db"
      ],
      "selectionMode": "ALL"
    }
  },
  "actions": {
    "failover-cluster": {
      "actionId": "aws:rds:failover-db-cluster",
      "parameters": {
        "targetInstance": "production-db-instance-2"
      },
      "targets": {
        "Clusters": "rds-cluster"
      }
    }
  },
  "stopConditions": [
    {
      "source": "none"
    }
  ],
  "roleArn": "arn:aws:iam::123456789012:role/FISExperimentRole",
  "tags": {
    "Name": "RDS-Failover-Test",
    "Frequency": "monthly"
  }
}
```

---

