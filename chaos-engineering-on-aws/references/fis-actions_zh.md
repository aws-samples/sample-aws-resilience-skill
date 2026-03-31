# FIS Actions 参考（按服务分类）

## FIS 通用
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
| `aws:ec2:asg-insufficient-instance-capacity-error` | ASG 容量不足 |
| `aws:ec2:disrupt-network-connectivity` | EC2 网络中断（NACL） |

## EBS
| Action | 说明 |
|--------|------|
| `aws:ebs:pause-volume-io` | 暂停 EBS 卷 IO |

## EKS
| Action | 说明 |
|--------|------|
| `aws:eks:terminate-nodegroup-instances` | 终止节点组实例（**推荐用于节点级故障**） |
| `aws:eks:pod-*` 系列 | Pod 故障注入 — ⚠️ **不推荐**：初始化慢（>2min），需额外 SA/RBAC 配置。Pod 级故障优先用 Chaos Mesh |

## ECS
| Action | 说明 |
|--------|------|
| `aws:ecs:drain-container-instances` | 排空容器实例 |
| `aws:ecs:stop-task` | 停止 ECS 任务 |
| `aws:ecs:task` 系列 | ECS 任务级故障注入 |

## RDS
| Action | 说明 |
|--------|------|
| `aws:rds:failover-db-cluster` | Aurora/RDS 集群故障转移 |
| `aws:rds:reboot-db-instances` | 重启 RDS 实例 |

## DynamoDB
| Action | 说明 |
|--------|------|
| `aws:dynamodb:global-table-pause-replication` | 暂停全局表复制 |

## ElastiCache / MemoryDB
| Action | 说明 |
|--------|------|
| `aws:elasticache:interrupt-cluster-az-power` | ElastiCache AZ 断电 |
| `aws:memorydb:interrupt-cluster-az-power` | MemoryDB AZ 断电 |

## Lambda
| Action | 说明 |
|--------|------|
| `aws:lambda:invocation-add-delay` | Lambda 调用注入延迟 |
| `aws:lambda:invocation-error` | Lambda 调用注入错误 |
| `aws:lambda:invocation-http-integration-response` | HTTP 集成响应注入 |

## S3
| Action | 说明 |
|--------|------|
| `aws:s3:bucket-pause-replication` | 暂停跨区域复制 |

## Kinesis
| Action | 说明 |
|--------|------|
| `aws:kinesis:add-put-record-throttle` | 写入限流 |

## 网络
| Action | 说明 |
|--------|------|
| `aws:network:disrupt-connectivity` | 子网/SG 级别网络中断（AZ 隔离） |
| `aws:network:route-table-disrupt-cross-region-connectivity` | 跨区域路由中断 |
| `aws:network:transit-gateway-disrupt-cross-region-connectivity` | TGW 跨区域中断 |

## 其他
| Action | 说明 |
|--------|------|
| `aws:arc:start-zonal-autoshift` | 触发 AZ 自动流量迁移 |
| `aws:cloudwatch:assert-alarm-state` | 断言告警状态（编排条件检查） |
| `aws:ssm:send-command` | 实例上执行 SSM 文档 |
| `aws:ssm:start-automation-execution` | 运行 SSM Automation |
| `aws:directconnect:disrupt-connectivity` | Direct Connect 中断 |

> 完整列表：[AWS FIS Actions Reference](https://docs.aws.amazon.com/fis/latest/userguide/fis-actions-reference.html)
