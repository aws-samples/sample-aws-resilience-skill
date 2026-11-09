# FIS Actions 参考（按服务分类）

> Action ID 已于 2026-11-09 对照 [AWS FIS actions reference](https://docs.aws.amazon.com/fis/latest/userguide/fis-actions-reference.html) 核对。该页面列出的所有故障 action 都在下文中。

## FIS 通用 — API 故障注入（仅 ec2 和 kinesis）

> ⚠️ 这三个 action **只**支持 `service=ec2` 和 `service=kinesis`。
> 其他 AWS 服务请使用各自专用的 FIS Action：
>
> | 服务 | 专用 FIS Action |
> |------|----------------|
> | DynamoDB | `aws:dynamodb:global-table-pause-replication` |
> | Lambda | `aws:lambda:invocation-add-delay`、`aws:lambda:invocation-error`、`aws:lambda:invocation-http-integration-response` |
> | EBS | `aws:ebs:pause-volume-io`、`aws:ebs:volume-io-latency` |
> | S3 | `aws:s3:bucket-pause-replication` |
> | RDS | `aws:rds:failover-db-cluster`、`aws:rds:reboot-db-instances` |
> | Aurora DSQL | `aws:dsql:cluster-connection-failure` |
> | Kinesis Data Streams | `aws:kinesis:stream-provisioned-throughput-exception`、`aws:kinesis:stream-expired-iterator-exception` |

| Action | 说明 |
|--------|------|
| `aws:fis:inject-api-internal-error` | 向目标 IAM Role 的 API 请求注入 500 错误 |
| `aws:fis:inject-api-throttle-error` | 注入限流错误 |
| `aws:fis:inject-api-unavailable-error` | 注入服务不可用错误 |
| `aws:fis:wait` | 等待指定时间（编排用） |

## EC2
| Action | 说明 |
|--------|------|
| `aws:ec2:terminate-instances` | 终止实例（SPOF 验证） |
| `aws:ec2:stop-instances` | 停止实例（可恢复） |
| `aws:ec2:reboot-instances` | 重启实例 |
| `aws:ec2:send-spot-instance-interruptions` | 模拟 Spot 中断 |
| `aws:ec2:api-insufficient-instance-capacity-error` | 对目标 IAM 角色在指定 AZ 发起的 `RunInstances`/`StartInstances`/`CreateFleet`/`CreateCapacityReservation` 返回 InsufficientInstanceCapacity（只能按角色 ARN 定位） |
| `aws:ec2:asg-insufficient-instance-capacity-error` | 对目标 Auto Scaling 组在指定 AZ 返回 InsufficientInstanceCapacity（仅支持使用启动模板的 ASG） |

> EC2 网络故障（子网级 NACL 中断）使用 `aws:network:disrupt-connectivity`——见"网络"一节。实例级延迟 / 丢包使用 `aws:ssm:send-command` 配合 `AWSFIS-Run-*` 文档。

## EBS
| Action | 说明 |
|--------|------|
| `aws:ebs:pause-volume-io` | 暂停 EBS 卷 IO |
| `aws:ebs:volume-io-latency` | 对目标卷的 I/O 注入延迟（同一 AZ，不支持 Outposts） |

## EKS
| Action | 说明 |
|--------|------|
| `aws:eks:terminate-nodegroup-instances` | 终止节点组实例（**推荐用于节点级故障**） |
| `aws:eks:inject-kubernetes-custom-resource` | 在单个目标集群上运行 Chaos Mesh 或 Litmus 实验（需已安装该工具） |
| `aws:eks:pod-cpu-stress` | 对目标 Pod 施加 CPU 压力 |
| `aws:eks:pod-memory-stress` | 对目标 Pod 施加内存压力 |
| `aws:eks:pod-io-stress` | 对目标 Pod 施加 I/O 压力 |
| `aws:eks:pod-delete` | 删除目标 Pod |
| `aws:eks:pod-network-latency` | 给 Pod 网络接口增加延迟 / 抖动（tc） |
| `aws:eks:pod-network-packet-loss` | 给 Pod 网络接口增加丢包（tc） |
| `aws:eks:pod-network-blackhole-port` | 丢弃指定协议和端口的入站或出站流量 |

> ⚠️ `aws:eks:pod-*` 系列：默认**不推荐**——初始化慢（>2min），需额外 SA/RBAC 配置。Pod 级故障优先用 Chaos Mesh。FIS Scenario Library 的两个减速场景确实使用 `aws:eks:pod-network-latency` / `aws:eks:pod-network-packet-loss`。

## ECS
| Action | 说明 |
|--------|------|
| `aws:ecs:drain-container-instances` | 排空容器实例 |
| `aws:ecs:stop-task` | 停止 ECS 任务 |
| `aws:ecs:task-cpu-stress` | 对目标任务施加 CPU 压力（任务需由 SSM 管理） |
| `aws:ecs:task-io-stress` | 对目标任务施加 I/O 压力（任务需由 SSM 管理） |
| `aws:ecs:task-kill-process` | 在目标任务中杀掉指定进程（`killall`） |
| `aws:ecs:task-network-latency` | 对任务发往指定 sources 的出站流量增加延迟 / 抖动 |
| `aws:ecs:task-network-packet-loss` | 对任务发往指定 sources 的出站流量增加丢包 |
| `aws:ecs:task-network-blackhole-port` | 丢弃指定协议和端口的入站或出站流量 |

## RDS
| Action | 说明 |
|--------|------|
| `aws:rds:failover-db-cluster` | Aurora/RDS 集群故障转移 |
| `aws:rds:reboot-db-instances` | 重启 RDS 实例 |

## Aurora DSQL
| Action | 说明 |
|--------|------|
| `aws:dsql:cluster-connection-failure` | 在指定时长和百分比内对 Aurora DSQL 集群制造受控的连接失败 |

## DynamoDB
| Action | 说明 |
|--------|------|
| `aws:dynamodb:global-table-pause-replication` | 暂停全局表复制 |

## ElastiCache / MemoryDB
| Action | 说明 |
|--------|------|
| `aws:elasticache:replicationgroup-interrupt-az-power` | 对启用 Multi-AZ 的复制组（Redis / Valkey，不支持 serverless）执行 AZ 断电；主节点受影响时提升一个副本 |
| `aws:memorydb:multi-region-cluster-pause-replication` | 暂停 MemoryDB **多 Region** 集群中实验 Region 成员与其他成员之间的复制（属于复制故障，不是 AZ 断电故障） |

> FIS 没有 MemoryDB 的 AZ 断电 action。要演练 MemoryDB 节点故障，请使用该服务自身的故障转移 API（例如通过 `aws:ssm:start-automation-execution`）。

## Lambda

> ⚠️ **前置条件**：所有 Lambda FIS action 需要目标 Lambda 函数：
> 1. 安装 **FIS Extension Layer**（各 Region ARN 见 [AWS 文档](https://docs.aws.amazon.com/fis/latest/userguide/actions-lambda-extension-arns.html)）
> 2. 设置 **`AWS_FIS_CONFIGURATION_LOCATION`** 环境变量，值为**配置目录的 S3 ARN**，例如 `arn:aws:s3:::my-fis-config-bucket/FisConfigs/`
> 3. 设置 **`AWS_LAMBDA_EXEC_WRAPPER`** 为 `/opt/aws-fis/bootstrap`
> 4. 函数角色对该 S3 目录有读权限，FIS 实验角色有写权限
>
> ❌ **常见错误**：把此环境变量设为 `s3://bucket/config` 形式的 URI 或实验 ARN——官方格式是包含桶和路径的 S3 ARN（`arn:aws:s3:::<bucket>/<prefix>/`），见 [Use the AWS FIS aws:lambda:function actions](https://docs.aws.amazon.com/fis/latest/userguide/use-lambda-actions.html)。无此配置 FIS action 将**静默失败**。另外，该扩展不能用于使用响应流（response streaming）的函数。

| Action | 说明 |
|--------|------|
| `aws:lambda:invocation-add-delay` | Lambda 调用注入延迟 |
| `aws:lambda:invocation-error` | Lambda 调用注入错误 |
| `aws:lambda:invocation-http-integration-response` | 返回指定的 HTTP 状态码 / 内容类型（ALB、API Gateway、VPC Lattice 集成） |

## S3
| Action | 说明 |
|--------|------|
| `aws:s3:bucket-pause-replication` | 暂停跨区域复制 |

## Kinesis
| Action | 说明 |
|--------|------|
| `aws:kinesis:stream-provisioned-throughput-exception` | 对目标流的 `GetRecords`、`GetShardIterator`、`PutRecord`、`PutRecords` 返回 ProvisionedThroughputExceededException |
| `aws:kinesis:stream-expired-iterator-exception` | 对目标流的 `GetRecords` 返回 ExpiredIteratorException |

## 网络
| Action | 说明 |
|--------|------|
| `aws:network:disrupt-connectivity` | 通过克隆 NACL 实现子网级网络中断（AZ 隔离；EC2 网络故障也用它） |
| `aws:network:route-table-disrupt-cross-region-connectivity` | 跨区域路由中断 |
| `aws:network:transit-gateway-disrupt-cross-region-connectivity` | TGW 跨区域中断 |
| `aws:network:disrupt-vpc-endpoint` | 阻断目标接口 VPC 端点的入站和出站流量（临时替换为空规则安全组） |

## 其他
| Action | 说明 |
|--------|------|
| `aws:arc:start-zonal-autoshift` | 触发 AZ 自动流量迁移 |
| `aws:cloudwatch:assert-alarm-state` | 断言告警状态（编排条件检查） |
| `aws:ssm:send-command` | 实例上执行 SSM 文档 |
| `aws:ssm:start-automation-execution` | 运行 SSM Automation |
| `aws:directconnect:virtual-interface-disconnect` | 让目标 Direct Connect 虚拟接口的 BGP 会话进入 down 状态（10 分钟 – 12 小时） |

> 完整列表：[AWS FIS Actions Reference](https://docs.aws.amazon.com/fis/latest/userguide/fis-actions-reference.html)
