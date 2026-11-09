# FIS Actions Reference (by Service)

> Action IDs checked against the [AWS FIS actions reference](https://docs.aws.amazon.com/fis/latest/userguide/fis-actions-reference.html) on 2026-11-09. Every fault action listed there appears below.

## FIS General — API Fault Injection (ec2 and kinesis ONLY)

> ⚠️ These three actions ONLY support `service=ec2` and `service=kinesis`.
> For other AWS services, use their dedicated FIS Actions:
>
> | Service | Dedicated FIS Action |
> |---------|---------------------|
> | DynamoDB | `aws:dynamodb:global-table-pause-replication` |
> | Lambda | `aws:lambda:invocation-add-delay`, `aws:lambda:invocation-error`, `aws:lambda:invocation-http-integration-response` |
> | EBS | `aws:ebs:pause-volume-io`, `aws:ebs:volume-io-latency` |
> | S3 | `aws:s3:bucket-pause-replication` |
> | RDS | `aws:rds:failover-db-cluster`, `aws:rds:reboot-db-instances` |
> | Aurora DSQL | `aws:dsql:cluster-connection-failure` |
> | Kinesis Data Streams | `aws:kinesis:stream-provisioned-throughput-exception`, `aws:kinesis:stream-expired-iterator-exception` |

| Action | Description |
|--------|------|
| `aws:fis:inject-api-internal-error` | Inject 500 errors into API requests for the target IAM Role |
| `aws:fis:inject-api-throttle-error` | Inject throttling errors |
| `aws:fis:inject-api-unavailable-error` | Inject service unavailable errors |
| `aws:fis:wait` | Wait for a specified duration (for orchestration) |

## EC2
| Action | Description |
|--------|------|
| `aws:ec2:terminate-instances` | Terminate instances (SPOF validation) |
| `aws:ec2:stop-instances` | Stop instances (recoverable) |
| `aws:ec2:reboot-instances` | Reboot instances |
| `aws:ec2:send-spot-instance-interruptions` | Simulate Spot interruptions |
| `aws:ec2:api-insufficient-instance-capacity-error` | InsufficientInstanceCapacity errors on `RunInstances`/`StartInstances`/`CreateFleet`/`CreateCapacityReservation` made by target IAM roles in given AZs (targets by role ARN only) |
| `aws:ec2:asg-insufficient-instance-capacity-error` | InsufficientInstanceCapacity errors for target Auto Scaling groups in given AZs (launch-template ASGs only) |

> EC2 network faults (subnet-level NACL disruption) use `aws:network:disrupt-connectivity` — see the Network section. Instance-level latency / packet loss uses `aws:ssm:send-command` with an `AWSFIS-Run-*` document.

## EBS
| Action | Description |
|--------|------|
| `aws:ebs:pause-volume-io` | Pause EBS volume IO |
| `aws:ebs:volume-io-latency` | Inject latency on I/O of target volumes (same AZ, not on Outposts) |

## EKS
| Action | Description |
|--------|------|
| `aws:eks:terminate-nodegroup-instances` | Terminate node group instances (**recommended for node-level faults**) |
| `aws:eks:inject-kubernetes-custom-resource` | Run a Chaos Mesh or Litmus experiment on one target cluster (the tool must already be installed) |
| `aws:eks:pod-cpu-stress` | CPU stress on target pods |
| `aws:eks:pod-memory-stress` | Memory stress on target pods |
| `aws:eks:pod-io-stress` | I/O stress on target pods |
| `aws:eks:pod-delete` | Delete target pods |
| `aws:eks:pod-network-latency` | Add latency / jitter to pod network interface (tc) |
| `aws:eks:pod-network-packet-loss` | Add packet loss to pod network interface (tc) |
| `aws:eks:pod-network-blackhole-port` | Drop inbound or outbound traffic for a protocol and port |

> ⚠️ `aws:eks:pod-*` actions: **Not recommended** by default — slow initialization (>2min), require additional SA/RBAC config. Prefer Chaos Mesh for Pod-level faults. The FIS Scenario Library slowdown scenarios do use `aws:eks:pod-network-latency` / `aws:eks:pod-network-packet-loss`.

## ECS
| Action | Description |
|--------|------|
| `aws:ecs:drain-container-instances` | Drain container instances |
| `aws:ecs:stop-task` | Stop ECS tasks |
| `aws:ecs:task-cpu-stress` | CPU stress on target tasks (SSM-managed tasks) |
| `aws:ecs:task-io-stress` | I/O stress on target tasks (SSM-managed tasks) |
| `aws:ecs:task-kill-process` | Kill a named process in target tasks (`killall`) |
| `aws:ecs:task-network-latency` | Add latency / jitter to task egress traffic toward given sources |
| `aws:ecs:task-network-packet-loss` | Add packet loss to task egress traffic toward given sources |
| `aws:ecs:task-network-blackhole-port` | Drop inbound or outbound traffic for a protocol and port |

## RDS
| Action | Description |
|--------|------|
| `aws:rds:failover-db-cluster` | Aurora/RDS cluster failover |
| `aws:rds:reboot-db-instances` | Reboot RDS instances |

## Aurora DSQL
| Action | Description |
|--------|------|
| `aws:dsql:cluster-connection-failure` | Controlled connection failures on an Aurora DSQL cluster for a set duration and percentage |

## DynamoDB
| Action | Description |
|--------|------|
| `aws:dynamodb:global-table-pause-replication` | Pause global table replication |

## ElastiCache / MemoryDB
| Action | Description |
|--------|------|
| `aws:elasticache:replicationgroup-interrupt-az-power` | ElastiCache AZ power interruption for Multi-AZ replication groups (Redis / Valkey, not serverless); a replica is promoted if the primary is hit |
| `aws:memorydb:multi-region-cluster-pause-replication` | Pause replication between the experiment-Region member and the other members of a MemoryDB **multi-Region** cluster (a replication fault, not an AZ power fault) |

> MemoryDB has no AZ power interruption action in FIS. To exercise a MemoryDB node failure use the service's own failover API (for example via `aws:ssm:start-automation-execution`).

## Lambda

> ⚠️ **Prerequisites**: All Lambda FIS actions require the target Lambda function to have:
> 1. **FIS Extension Layer** installed (region-specific ARN from [AWS docs](https://docs.aws.amazon.com/fis/latest/userguide/actions-lambda-extension-arns.html))
> 2. **`AWS_FIS_CONFIGURATION_LOCATION`** environment variable set to the **S3 ARN of the configuration folder**, e.g. `arn:aws:s3:::my-fis-config-bucket/FisConfigs/`
> 3. **`AWS_LAMBDA_EXEC_WRAPPER`** set to `/opt/aws-fis/bootstrap`
> 4. Read access to that S3 folder for the function role, and write access for the FIS experiment role
>
> Without these, FIS actions will silently fail. See `fault-catalog.yaml` for setup commands.
>
> ⚠️ **Common mistake**: Setting `AWS_FIS_CONFIGURATION_LOCATION` to an `s3://bucket/config` URI or to an experiment ARN.
> The official format is an S3 ARN including bucket and path (`arn:aws:s3:::<bucket>/<prefix>/`); see
> [Use the AWS FIS aws:lambda:function actions](https://docs.aws.amazon.com/fis/latest/userguide/use-lambda-actions.html).
> The extension also cannot be used with functions that use response streaming.

| Action | Description |
|--------|------|
| `aws:lambda:invocation-add-delay` | Inject delay into Lambda invocations |
| `aws:lambda:invocation-error` | Inject errors into Lambda invocations |
| `aws:lambda:invocation-http-integration-response` | Return a chosen HTTP status / content type (ALB, API Gateway, VPC Lattice integrations) |

## S3
| Action | Description |
|--------|------|
| `aws:s3:bucket-pause-replication` | Pause cross-region replication |

## Kinesis
| Action | Description |
|--------|------|
| `aws:kinesis:stream-provisioned-throughput-exception` | ProvisionedThroughputExceededException on `GetRecords`, `GetShardIterator`, `PutRecord`, `PutRecords` for target streams |
| `aws:kinesis:stream-expired-iterator-exception` | ExpiredIteratorException on `GetRecords` for target streams |

## Network
| Action | Description |
|--------|------|
| `aws:network:disrupt-connectivity` | Subnet-level network disruption via a cloned NACL (AZ isolation; use this for EC2 network faults) |
| `aws:network:route-table-disrupt-cross-region-connectivity` | Cross-region route disruption |
| `aws:network:transit-gateway-disrupt-cross-region-connectivity` | TGW cross-region disruption |
| `aws:network:disrupt-vpc-endpoint` | Block inbound and outbound traffic of target interface VPC endpoints (temporary empty security group) |

## Others
| Action | Description |
|--------|------|
| `aws:arc:start-zonal-autoshift` | Trigger AZ automatic traffic shift |
| `aws:cloudwatch:assert-alarm-state` | Assert alarm state (orchestration condition check) |
| `aws:ssm:send-command` | Execute SSM document on instances |
| `aws:ssm:start-automation-execution` | Run SSM Automation |
| `aws:directconnect:virtual-interface-disconnect` | Take the BGP sessions of target Direct Connect virtual interfaces down (10 min – 12 h) |

> Full list: [AWS FIS Actions Reference](https://docs.aws.amazon.com/fis/latest/userguide/fis-actions-reference.html)
