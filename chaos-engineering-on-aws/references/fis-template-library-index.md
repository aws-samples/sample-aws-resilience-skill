# AWS FIS Template Library — Scenario Index

> Source: [aws-samples/fis-template-library](https://github.com/aws-samples/fis-template-library) (commit: ee74d58, 2026-11-03)
> License: MIT-0
> Last synced: 2026-11-09

This index catalogs all 27 experiment templates from the AWS FIS Template Library at commit ee74d58.
Each template includes a ready-to-deploy FIS experiment JSON, IAM policies, and (where applicable) SSM Automation documents.
Injection methods list the actual `actionId` values in each experiment template.

Templates marked with ⭐ (8) are embedded in `references/fis-templates/` for direct use.

**Every template ships without a stop condition** (`"stopConditions": [{"source": "none"}]`). Add a CloudWatch alarm on a customer-impact metric before running beyond a short test.

New since the previous index (e2c94c3): agentcore-strands-agent-faults, database-blocking-locks, database-io-exhaustion, ecs-fargate-az-evacuation, ecs-fargate-az-impairment, eks-automode-az-impairment, elasticache-az-power-interruption, msk-broker-reboot.

---

## Compute — EC2

### ec2-instances-terminate
- **Fault type**: Instance termination
- **Injection method**: FIS native (`aws:ec2:terminate-instances`)
- **Target**: `aws:ec2:instance` tagged `FIS-Ready=True`, `selectionMode: PERCENT(25)`
- **Hypothesis**: The application remains available when 25% of the EC2 instances in its Auto Scaling group are terminated: the load balancer stops sending requests to them and Auto Scaling replaces them. Requests sent to an instance before the load balancer stops using it can fail.
- **Applicable architectures**: EC2 workloads behind a load balancer with Auto Scaling
- **⚠ Warnings**: Selection is **Region-wide** across all tagged instances, not one ASG — tag only the instances you mean to test. Needs **at least four** running tagged instances (25% rounded down); with fewer, nothing is selected and the experiment fails with "Target resolution returned empty set." The action completes in about 12 s, and a stop does not restore a terminated instance.
- [GitHub](https://github.com/aws-samples/fis-template-library/tree/main/ec2-instances-terminate)

### ec2-spot-interruption
- **Fault type**: Spot Instance interruption notice
- **Injection method**: FIS native (`aws:ec2:send-spot-instance-interruptions`, `durationBeforeInterruption: PT2M`)
- **Target**: `aws:ec2:spot-instance` tagged `FIS-Ready=True`, `selectionMode: ALL`
- **Hypothesis**: If the targeted Spot Instances run in an Auto Scaling group behind a load balancer, the application recovers without manual action: each instance uses the two-minute notice to finish or hand off work, Auto Scaling launches replacements and the load balancer routes to them. Because every targeted instance is interrupted at once, requests are expected to fail until the first replacement serves.
- **Applicable architectures**: Cost-optimized workloads using Spot Instances
- **⚠ Warnings**: Interrupts **every** tagged running Spot Instance in the Region (On-Demand instances are ignored). The experiment ends ~12 s after start, ~2 minutes before EC2 interrupts; a later stop cannot cancel the interruption. `emptyTargetResolutionMode: fail`.
- [GitHub](https://github.com/aws-samples/fis-template-library/tree/main/ec2-spot-interruption)

### ec2-windows-stop-iis
- **Fault type**: Windows IIS application pool stop
- **Injection method**: SSM Run Command via FIS (`aws:ssm:send-command`, document `StopIISAppPool`: validate → stop app pool → restore; `DurationSeconds: 285`, `IISAppPoolName: DefaultAppPool`, action `duration: PT5M`)
- **Target**: `aws:ec2:instance` tagged `FIS-Ready=True`, `selectionMode: ALL`, SSM Agent running
- **Hypothesis**: The application remains available and resilient when IIS is stopped on one of the Windows EC2 instances, simulating a web server crash or failure to start.
- **Applicable architectures**: Windows/.NET workloads on EC2
- **⚠ Warnings**: Template selects `ALL` tagged instances although the hypothesis speaks of one — change to `COUNT(1)` if that is what you test.
- [GitHub](https://github.com/aws-samples/fis-template-library/tree/main/ec2-windows-stop-iis)

---

## Containers — ECS / EKS

### ecs-fargate-az-impairment
- **Fault type**: AZ network impairment for an ECS Fargate service (detection-only, no service change)
- **Injection method**: FIS native (`aws:network:disrupt-connectivity` scope `availability-zone` PT15M, `aws:ecs:task-network-packet-loss` 100% to `0.0.0.0/0` PT15M)
- **Target**: `aws:ec2:subnet` tagged `FIS-Ready=True` filtered to the target AZ; `aws:ecs:task` tagged `FIS-Ready=True`, AZ filter, `LastStatus=RUNNING`
- **Hypothesis**: When an AZ experiences a network impairment, the service detects degraded health in that AZ and keeps operating with reduced capacity on tasks in the healthy AZs. The template makes no change to the service's network configuration, so replacement tasks may be scheduled back into the impaired AZ — the experiment measures whether detection still flags the AZ. All faults revert automatically at the end of their duration.
- **Applicable architectures**: ECS Fargate services spread over ≥ 2 AZs
- **⚠ Warnings**: Packet-loss action needs an SSM agent sidecar per task (`pidMode: task`, `awsvpc`, `enableFaultInjection: true`, ECS Exec disabled) plus task-role and managed-instance-role permissions; otherwise it fails with "At least one ECS Task is not registered as a SSM managed instance." Tags must propagate to tasks. `emptyTargetResolutionMode: skip`.
- [GitHub](https://github.com/aws-samples/fis-template-library/tree/main/ecs-fargate-az-impairment)

### ecs-fargate-az-evacuation
- **Fault type**: AZ impairment plus operator-style AZ evacuation of an ECS Fargate service
- **Injection method**: FIS native (`aws:network:disrupt-connectivity` scope `availability-zone` PT20M, `aws:ecs:task-network-packet-loss` PT20M, `aws:fis:wait`, `aws:ecs:stop-task`) + SSM Automation (`aws:ssm:start-automation-execution`, document `ecs-fargate-az-evacuation-subnet-automation`: remove the AZ's subnet from the service, wait, restore)
- **Target**: Same subnet/task targets as ecs-fargate-az-impairment; the ECS cluster, **service** and tasks must be tagged `FIS-Ready=True`
- **Hypothesis**: Drills the response to a detected AZ impairment: after a detection delay, removing the impaired AZ's subnet starts a new service deployment that cycles **all** tasks (including healthy-AZ tasks); within your target time all running tasks are in healthy AZs, the service never drops below `minimumHealthyPercent`, no SLO alarm fires, and the subnet is restored automatically at the end.
- **Applicable architectures**: ECS Fargate services with ≥ 2 subnets in different AZs
- **⚠ Warnings**: The redeploy is the intended effect, not a side effect. Remaining AZs must absorb a full-service redeploy for up to ~30 minutes. An untagged service fails at the first automation step (`AccessDenied`). The automation cannot remove the last subnet. `emptyTargetResolutionMode: skip`.
- [GitHub](https://github.com/aws-samples/fis-template-library/tree/main/ecs-fargate-az-evacuation)

### eks-automode-az-impairment
- **Fault type**: AZ impairment for an EKS Auto Mode cluster (network + node exclusion + pod eviction)
- **Injection method**: FIS native (`aws:network:disrupt-connectivity` scope `all` PT15M) + SSM Automation (`aws:ssm:start-automation-execution`, document `eks-automode-az-impairment-automation`: launch an ephemeral in-VPC client EC2, cordon nodes in the AZ, patch the NodePool to exclude the AZ, delete non-system pods, wait, restore NodePool and uncordon)
- **Target**: `aws:ec2:subnet` tagged `FIS-Ready=True` with `availabilityZoneIdentifier` = target AZ
- **Hypothesis**: The workload sustains an AZ impairment by running its replicas in the remaining healthy AZs — scaling up there as needed — rather than losing capacity: pods in the AZ become unreachable, Auto Mode provisions no new nodes there, evicted pods reschedule only into healthy AZs, the application stays available, and capacity returns to the AZ after restore.
- **Applicable architectures**: EKS Auto Mode clusters across ≥ 2 AZs (3 recommended)
- **⚠ Warnings**: Needs a **custom** NodePool (built-in pools are reconciled and silently revert the AZ exclusion). Kubernetes calls run under the **instance profile role** (EKS access entry + RBAC must map it). The client subnet must not be in the target AZ and must reach the private API endpoint and SSM. A workload that cannot fail over runs at reduced capacity and the experiment still reports success. Total 30–45 minutes.
- [GitHub](https://github.com/aws-samples/fis-template-library/tree/main/eks-automode-az-impairment)

---

## Database — RDS / Aurora

### aurora-cluster-failover
- **Fault type**: Aurora cluster failover (writer ↔ reader)
- **Injection method**: FIS native (`aws:rds:failover-db-cluster`)
- **Target**: `aws:rds:cluster` tagged `FIS-Ready=True`, `selectionMode: ALL`
- **Hypothesis**: Failover between the reader and writer may cause requests to fail for a brief period, but requests recover automatically and the application continues to function as normal after the failover.
- **Applicable architectures**: Aurora clusters with a writer and at least one reader in different AZs
- **⚠ Warnings**: **Every** tagged cluster in the Region fails over; the action also supports DocumentDB clusters, so tag only what you mean. The action completes as soon as `FailoverDBCluster` returns — **a stop cannot undo the failover** (a stop 4 s after the call was rejected because the experiment had already completed). The FIS role is now scoped to `arn:aws:rds:<REGION>:<ACCOUNT>:cluster:*` with a `FIS-Ready=True` tag condition.
- [GitHub](https://github.com/aws-samples/fis-template-library/tree/main/aurora-cluster-failover)

### aurora-postgres-cluster-loadtest-failover
- **Fault type**: CPU load followed by failover under load
- **Injection method**: FIS native + SSM Run Command (`aws:ssm:send-command` document `aurora-cluster-loadtest-document` for 10 min on the load generator; `aws:fis:wait` PT5M then `aws:rds:failover-db-cluster`)
- **Target**: `aws:rds:cluster` and `aws:ec2:instance` (load generator), both tagged `FIS-Ready=True`
- **Hypothesis**: When high CPU load occurs on an Aurora cluster followed by a failover, the system restores normal operation with minimal disruption; recovery completes within minutes and request processing continues at near 100% efficiency after the failover.
- **Applicable architectures**: Aurora PostgreSQL workloads needing stress + failover validation
- **⚠ Warnings**: Creates `load_test_users` and `load_test_transactions` tables (with indexes) that **persist** after the run. Requires a pre-existing tagged EC2 load generator with SSM Agent and DB connectivity.
- [GitHub](https://github.com/aws-samples/fis-template-library/tree/main/aurora-postgres-cluster-loadtest-failover)

### aurora-global-region-failover ⭐
- **Fault type**: Aurora Global Database cross-Region switchover / failover
- **Injection method**: SSM Automation (`aws:ssm:start-automation-execution`, `FailoverGlobalCluster` with `Switchover=True` or `AllowDataLoss=True`, `maxDuration` PT10M)
- **Target**: Global cluster named by `globalClusterIdentifier` (no FIS target block)
- **Hypothesis**: With `switchover` (default) the secondary becomes primary and the application resumes reads and writes within 5 minutes (RTO 5 min), retried writes all succeed, and an error-rate/connection alarm returns to OK within 5 minutes. With `failover`, writes from the last seconds can be lost, spanning no more than `AuroraGlobalDBRPOLag` showed just before.
- **Applicable architectures**: Multi-Region DR with Aurora Global Database
- **⚠ Warnings**: The experiment does not switch back, and a stop cannot undo an accepted switchover. The README asks for a `FIS-Ready=True` tag but nothing enforces it. The document's worst-case runtime (10 s + 600 s polling) exceeds `maxDuration` PT10M.
- Embedded: `references/fis-templates/aurora-global-failover/`
- [GitHub](https://github.com/aws-samples/fis-template-library/tree/main/aurora-global-region-failover)

### mysql-rds-loadtest-failover
- **Fault type**: CPU load followed by Multi-AZ failover under load
- **Injection method**: FIS native + SSM Run Command (`aws:ssm:send-command` document `MySQL-LoadTest-Document` PT15M → `aws:rds:reboot-db-instances` with `forceFailover: true` → `aws:ssm:send-command` `AWS-RunShellScript` to stop the load)
- **Target**: `aws:rds:db` and `aws:ec2:instance` (load generator), both tagged `FIS-Ready=True`
- **Hypothesis**: Under high CPU load on a Multi-AZ MySQL RDS instance followed by failover, the system moves to the standby with about 25 seconds of downtime, and applications with proper connection handling reconnect automatically at nearly 100% success.
- **Applicable architectures**: MySQL RDS Multi-AZ workloads
- **⚠ Warnings**: Creates a `loadtest` table that persists after the run.
- [GitHub](https://github.com/aws-samples/fis-template-library/tree/main/mysql-rds-loadtest-failover)

### database-connection-limit-exhaustion ⭐
- **Fault type**: Database connection-limit exhaustion
- **Injection method**: SSM Automation (`aws:ssm:start-automation-execution`, document `ConnectionLimitExhaustion-Automation`: temporary SG → ephemeral EC2 load generator → hold connections → cleanup; `maxDuration` PT180M)
- **Target**: Database named in document parameters (endpoint, SG, secret ARN); no FIS target block
- **Hypothesis**: Approaching the limit, the {service1} journey stays within its 2 s SLA, the circuit breaker stays closed and a leading alarm fires within {y} min. At exhaustion, the circuit breaker opens, the UI degrades gracefully, an alarm fires, other journeys continue, and after connections drain the breaker closes within {z} min and steady state resumes.
- **Applicable architectures**: Aurora PostgreSQL/MySQL, RDS PostgreSQL/MySQL/SQL Server
- **⚠ Warnings**: Adds a temporary ingress rule to the database SG. Upstream now routes every step's `onFailure`/`onCancel` to cleanup (instance, ingress rule, SG are removed on failure or stop) and requires IMDSv2. Role and document names are hard-coded (`ConnectionLimitExhaustion-*`, instance profile `SSM-Managed-Instance-Profile`); the password is read on the instance, so Secrets Manager access belongs to the instance profile role (it was removed from the SSM role).
- Embedded: `references/fis-templates/database-connection-exhaustion/`
- [GitHub](https://github.com/aws-samples/fis-template-library/tree/main/database-connection-limit-exhaustion)

### database-blocking-locks
- **Fault type**: Row-level blocking locks (one Blocker session + ramped Waiter sessions)
- **Injection method**: SSM Automation (`aws:ssm:start-automation-execution`, document `DatabaseBlockingLocks-Automation`: ephemeral EC2 load generator; defaults `WaiterCount` 50, `ExperimentDuration` PT10M, `RampTime` PT1M, `RampSteps` 10; `maxDuration` PT180M)
- **Target**: Database named in document parameters; no FIS target block
- **Hypothesis**: When the {service1} database is subjected to synthetic (or directed) row-level blocking locks, an alarm fires and the DevOps team is notified within {x} minutes, and the team can respond to the cause within {y} minutes via the engine-specific blocked-waiter metric. Critical user journeys continue unaffected (synthetic) / should or shouldn't be impacted in a stated manner (directed).
- **Applicable architectures**: Aurora PostgreSQL/MySQL, RDS PostgreSQL/MySQL/SQL Server
- **⚠ Warnings**: Synthetic_Mode creates and drops `fis_blocking_locks_target`, so `DatabaseName` must be a **user-created** database the user can `CREATE`/`DROP` in (system databases are not suitable, though the template default is `postgres`). Setting `TargetTableName` to any other value enables **Real_Mode**, which locks the first row of a real application table and causes real impact for up to `ExperimentDuration`. Narrow fault by design; use connection exhaustion for wide degradation.
- [GitHub](https://github.com/aws-samples/fis-template-library/tree/main/database-blocking-locks)

### database-io-exhaustion
- **Fault type**: Database I/O saturation
- **Injection method**: SSM Automation (`aws:ssm:start-automation-execution`, document `DatabaseIOExhaustion-Automation`: ephemeral EC2 with `WorkerThreads` 50, `IOPattern` `read`/`write`/`mixed`, `SeedRowCount` 500, `MinActiveWorkerPercentage` 50; `maxDuration` PT180M)
- **Target**: Database named in document parameters; the database SG must be tagged `FIS-Ready=True`
- **Hypothesis**: Approaching I/O saturation, the {service1} journey stays within its 2 s SLA, steady state holds and a leading alarm fires within {y} min. At exhaustion, response times degrade gracefully, the UI signals degraded performance, an alarm fires, other journeys continue, and after the load is removed performance recovers within {z} min.
- **Applicable architectures**: Aurora PostgreSQL, RDS PostgreSQL, RDS Oracle (validated); Aurora MySQL, RDS MySQL, RDS SQL Server (experimental)
- **⚠ Warnings**: Each worker creates and drops its own `fis_io_<suffix>_<thread>` table, so the user needs `CREATE`/`DROP`. The run **fails** if fewer than `MinActiveWorkerPercentage` workers did I/O. Keep `ExperimentDuration` well under PT115M (2 h step timeout). Role/document names are hard-coded; the instance role (not the SSM role) needs Secrets Manager.
- [GitHub](https://github.com/aws-samples/fis-template-library/tree/main/database-io-exhaustion)

---

## Cache — ElastiCache

### elasticache-redis-connection-failure ⭐
- **Fault type**: Redis connection disruption (security-group rule removal)
- **Injection method**: SSM Automation (`aws:ssm:start-automation-execution`, remove port 6379 ingress rules → wait PT5M → restore; `maxDuration` PT30M)
- **Target**: Redis cache clusters (nodes) tagged `FIS-Ready=True`, at most 100 nodes
- **Hypothesis**: With the 6379 rules removed for 5 minutes, the error rate stays under your threshold from 30 s after the first failed call (circuit breakers serve degraded responses), Redis calls succeed at their usual rate within 60 s of restore, and summed `NewConnections` in the minute after restore does not exceed the clients' normal pool size (no retry storm).
- **Applicable architectures**: Applications using ElastiCache (Redis OSS engine, not Valkey)
- **⚠ Warnings**: Only rules with exactly `FromPort=ToPort=6379` are removed. Every resource sharing those SGs loses access. Open tracked connections can keep working. The run ends `Success` even if no rule matched or the restore failed — check SGs after every run. A stop during `restoreRedisConnections` can leave rules removed.
- Embedded: `references/fis-templates/redis-connection-failure/`
- [GitHub](https://github.com/aws-samples/fis-template-library/tree/main/elasticache-redis-connection-failure)

### elasticache-redis-primary-node-failover ⭐
- **Fault type**: Redis primary failover (replica promotion)
- **Injection method**: SSM Automation (`aws:ssm:start-automation-execution`, ElastiCache `TestFailover` on node group `0001`)
- **Target**: First available replication group with `AutomaticFailover=enabled` tagged `FIS-Ready=True`
- **Hypothesis**: When the primary fails over to a replica, applications detect it and reconnect to the new primary within 30 seconds, connection pools handle the DNS endpoint change, no data is lost, and performance returns to normal within 60 seconds of completion.
- **Applicable architectures**: Redis replication groups with Multi-AZ and automatic failover
- **⚠ Warnings**: **Does not run as shipped at ee74d58**: the SSM role lacks `elasticache:TestFailover` (the error is swallowed and reported as "No cluster found"), the template passes `region`/`AutomationAssumeRole` parameters the document does not declare, and the document's `assumeRole` name differs from the template's. The automation returns as soon as the failover is initiated; a stop cannot undo it. See the embedded README.
- Embedded: `references/fis-templates/elasticache-redis-primary-node-failover/`
- [GitHub](https://github.com/aws-samples/fis-template-library/tree/main/elasticache-redis-primary-node-failover)

### elasticache-redis-primary-node-reboot ⭐
- **Fault type**: Redis primary node reboot (**clears the data**)
- **Injection method**: SSM Automation (`aws:ssm:start-automation-execution`, document `ElastiCache-Redis-Primary-Node-Reboot`: `RebootCacheCluster` on each tagged group's primary, then wait up to 17 min; `maxDuration` PT30M)
- **Target**: Every replication group tagged `FIS-Ready=True` in the Region (refuses if > 20); Redis OSS, cluster mode disabled, Multi-AZ + automatic failover, ≥ 1 replica, not in a Global Datastore
- **Hypothesis**: Writes to the primary endpoint fail for no more than 30 seconds, the error rate is back to baseline within 60 seconds of the group showing `available`, and because the reboot clears the cache the application reads from its source of truth and repopulates it without returning errors.
- **Applicable architectures**: ElastiCache (Redis OSS) replication groups whose contents can be lost
- **⚠ Warnings**: Corrected hypothesis upstream: a primary reboot does **not** fail over; the primary comes back empty and the replicas clear their copy, so **all data in the group is lost**. All tagged groups are rebooted at once. A stop after the call ends the wait, not the reboot or the data loss. Valkey groups are refused.
- Embedded: `references/fis-templates/elasticache-redis-primary-node-reboot/`
- [GitHub](https://github.com/aws-samples/fis-template-library/tree/main/elasticache-redis-primary-node-reboot)

### elasticache-az-power-interruption
- **Fault type**: ElastiCache AZ power interruption
- **Injection method**: FIS native (`aws:elasticache:replicationgroup-interrupt-az-power`, `duration: PT10M`)
- **Target**: `aws:elasticache:replicationgroup` tagged `FIS-Ready=True` with `availabilityZoneIdentifier` = target AZ, `selectionMode: ALL`
- **Hypothesis**: If power is interrupted to the nodes in a target AZ while the primary is there, the time from that node no longer answering to the first successful write on the primary endpoint does not exceed 30 seconds once automatic failover promotes a replica in a healthy AZ; applications reconnect without manual action; replica replacements stay blocked in the AZ for the duration; after it ends, nodes rejoin and the cluster returns to full capacity.
- **Applicable architectures**: Multi-AZ replication groups with automatic failover (not Serverless)
- **⚠ Warnings**: Power loss starts 42–74 s after the action starts (keep `duration` well above that). The node in the AZ answered `PING` again only ~9–10 minutes after the end, though the group showed `available` within 2 minutes. `IsMaster` can read 1 on two nodes for a minute. A stop ends the interruption but does not undo the failover. Targets every tagged group with a node in the AZ; `resourceArns` targeting is rejected.
- [GitHub](https://github.com/aws-samples/fis-template-library/tree/main/elasticache-az-power-interruption)

---

## Streaming — Amazon MSK

### msk-broker-reboot ⭐
- **Fault type**: Single MSK broker reboot
- **Injection method**: SSM Automation (`aws:ssm:start-automation-execution`, document `msk-broker-reboot-automation`: MSK `RebootBroker` + `DescribeClusterOperation` polling; `maxDuration` PT21M)
- **Target**: First `ACTIVE` provisioned cluster tagged `FIS-Ready=True` returned by `ListClustersV2`; lowest broker ID by default
- **Hypothesis**: The cluster keeps serving produce/consume on the remaining brokers while leadership moves to in-sync replicas: the longest delivery stall on the rebooted broker's partitions stays within your allowance (in testing ≤ 150 ms in 3 of 5 reboots, 36 s and 62 s in the other 2, with no error to the application), `acks=all` + idempotent producers lose nothing, `OfflinePartitionsCount` stays 0, `UnderReplicatedPartitions` returns to 0, the cluster is `ACTIVE` within a few minutes (135–196 s) and surviving brokers' CPU stays within headroom.
- **Applicable architectures**: Provisioned MSK, RF ≥ 3 across ≥ 2 AZs, `min.insync.replicas` ≥ 2
- **⚠ Warnings**: **Clients can stall up to their request timeout** (62 s observed, matching librdkafka's 60 s `socket.timeout.ms`). Tag **one cluster per Region** — there is no cluster parameter. `brokerSelection=random` actually picks the lowest broker ID. A stop after `RebootBroker` does not stop the reboot. While `REBOOTING_BROKER`, MSK refuses updates from anyone.
- Embedded: `references/fis-templates/msk-broker-reboot/`
- [GitHub](https://github.com/aws-samples/fis-template-library/tree/main/msk-broker-reboot)

---

## CDN — CloudFront

### cloudfront-impairment ⭐
- **Fault type**: CloudFront origin failure (S3 `GetObject` denied)
- **Injection method**: SSM Automation (`aws:ssm:start-automation-execution`: deny `s3:GetObject` on primary-origin buckets + invalidate `/*` → wait PT10M → remove deny + invalidate; `maxDuration` PT1H)
- **Target**: CloudFront distributions tagged `FIS-Ready=True`; only the primary member of each origin group (S3 origins)
- **Hypothesis**: When S3 origins are impaired, CloudFront fails over to secondary origins within 30 seconds, an alarm notifies the team within 2–3 minutes, delivery continues through the failover origin, and CloudFront resumes using the primary within 30 seconds after the impairment ends.
- **Applicable architectures**: CloudFront + S3 origins with origin-group failover
- **⚠ Warnings**: Distributions without origin groups are not impaired. The deny uses `Principal: "*"`, so every `GetObject` caller of the bucket is affected, not only CloudFront. Two full-cache invalidations per run. The SSM role can change any bucket policy (no tag condition).
- Embedded: `references/fis-templates/cloudfront-impairment/`
- [GitHub](https://github.com/aws-samples/fis-template-library/tree/main/cloudfront-impairment)

---

## NoSQL — DynamoDB

### dynamodb-region-impairment
- **Fault type**: DynamoDB Regional failure (replication pause + access block)
- **Injection method**: FIS native (`aws:dynamodb:global-table-pause-replication` PT12M) + SSM Automation (`aws:ssm:start-automation-execution`, document `DynamoDB-Region-Impairment`: deny statement `FISDenyAccess` in the table resource policy for PT10M, then cleanup)
- **Target**: `aws:dynamodb:global-table` tagged `FIS-Ready=True`; `tableName` and Region in document parameters
- **Hypothesis**: When DynamoDB has a complete Regional failure in us-east-1, an alarm notifies the team within 5 minutes, the application fails over to the us-west-2 replica within 2 minutes, all reads and writes go to the healthy Region during the impairment, and after recovery normal cross-Region operation resumes within 5 minutes.
- **Applicable architectures**: Multi-Region applications on DynamoDB global tables
- **⚠ Warnings**: Template files use us-east-1 / example table names — update every Region and table reference.
- [GitHub](https://github.com/aws-samples/fis-template-library/tree/main/dynamodb-region-impairment)

### dynamodb-traffic-blackhole-region-impairment
- **Fault type**: Network-level DynamoDB blackhole + replication pause
- **Injection method**: FIS native (`aws:network:disrupt-connectivity` scope `dynamodb` PT10M + `aws:dynamodb:global-table-pause-replication` PT10M)
- **Target**: `aws:ec2:subnet` tagged `FIS-Ready=True`; `aws:dynamodb:global-table` replicas tagged `FIS-Ready=True` in the Region
- **Hypothesis**: For 10 minutes no DynamoDB call from the tagged subnets succeeds while calls from other subnets and to other services stay at their normal error rate; replication to and from the tagged replicas stops within 5 minutes and no successful write is missing from other replicas 20 minutes after the end; monitoring detects within 3 minutes and notifies within 5; configured automated failover completes within the 10-minute fault.
- **Applicable architectures**: VPC applications reaching DynamoDB through the Regional endpoint (e.g. a gateway endpoint), with global tables
- **⚠ Warnings**: Every resource in a tagged subnet loses DynamoDB (other library experiments tag subnets too). Interface (PrivateLink) endpoints are outside the prefix list and are not expected to be blocked. The role may change NACL associations **only on subnets tagged `FIS-Ready=True`** — don't remove the tag during a run or FIS cannot restore the subnet. The role can put/delete resource policies on any table/stream in the Region (a tag condition made DynamoDB refuse FIS). `emptyTargetResolutionMode: fail`. Record each subnet's NACL before every run.
- [GitHub](https://github.com/aws-samples/fis-template-library/tree/main/dynamodb-traffic-blackhole-region-impairment)

---

## Messaging — SQS

### sqs-queue-impairment ⭐
- **Fault type**: SQS queue access denied (progressive impairment)
- **Injection method**: SSM Automation (4 × `aws:ssm:start-automation-execution` for PT2M / PT5M / PT7M / PT15M, separated by `aws:fis:wait` PT3M / PT3M / PT2M)
- **Target**: SQS queues tagged `FIS-Ready=True`
- **Hypothesis**: When SQS is impaired in a Region, an alarm notifies the DevOps team within 5 minutes; component A is unavailable to end users while other components operate normally; component A is available again within 5 minutes after the impairment is resolved.
- **Applicable architectures**: Applications using SQS for asynchronous messaging
- **⚠ Warnings**: Upstream now adds a **scoped** deny (data-plane actions only, on the queue ARN, via `SetQueueAttributes`), so cleanup can never be blocked; optional `targetPrincipalArn` limits it to one principal (default `*`). Do not use the source queue's own metrics as a stop condition — they move by design.
- Embedded: `references/fis-templates/sqs-queue-impairment/`
- [GitHub](https://github.com/aws-samples/fis-template-library/tree/main/sqs-queue-impairment)

---

## Networking

### direct-connect-resiliency
- **Fault type**: Direct Connect virtual interface disconnect
- **Injection method**: FIS native (`aws:directconnect:virtual-interface-disconnect`, `duration: PT10M`)
- **Target**: `aws:directconnect:virtual-interface` tagged `FIS-Ready=True`, `selectionMode: COUNT(1)`
- **Hypothesis**: The hybrid cloud application maintains connectivity and performance when Direct Connect virtual interfaces are brought down, failing over to backup paths (VPN or secondary Direct Connect).
- **Applicable architectures**: Hybrid cloud with Direct Connect and a backup path
- **⚠ Warnings**: Requires a configured backup path; without one, on-premises connectivity is lost for 10 minutes.
- [GitHub](https://github.com/aws-samples/fis-template-library/tree/main/direct-connect-resiliency)

---

## AI Agents — Amazon Bedrock AgentCore

### agentcore-strands-agent-faults
- **Fault type**: Tool-call faults inside a Strands agent (cancelled calls: `timeout`, `network_error`, `execution_error`, `validation_error`; corrupted results: `truncate_fields`, `remove_fields`, `corrupt_values`)
- **Injection method**: SSM Automation (`aws:ssm:start-automation-execution`, document `ChaosExperiment`: writes `/chaos/{runtime_id}/` SSM parameters, holds for `DurationSeconds` (900), disables and deletes them; `maxDuration` PT20M) read by the in-agent `chaos_plugins()` module
- **Target**: A dedicated chaos AgentCore Runtime identified by the `RuntimeId` parameter (no FIS target block)
- **Hypothesis**: When tool calls are cancelled or results corrupted, the agent detects that a trustworthy result is unavailable and fails safe (acknowledges it cannot complete, returns a caveated or partial answer, or escalates) rather than fabricating a result; raw errors are not surfaced; unfaulted journeys continue; after removal the agent returns to steady state within the parameter cache TTL (10 s default).
- **Applicable architectures**: Strands agents on Amazon Bedrock AgentCore Runtime
- **⚠ Warnings**: Requires a separate chaos build/runtime (`strands_agentcore_chaos.py`, `strands_evals`); production must not include it. **Replace the demo tool names** (`get_move`, `get_pokemon`) — names that match nothing inject nothing and the run still "succeeds". `maxDuration` must exceed `DurationSeconds` + 15 s.
- [GitHub](https://github.com/aws-samples/fis-template-library/tree/main/agentcore-strands-agent-faults)

---

## SAP Workloads

### sap-ebs-pause-database-data
- **Fault type**: EBS I/O pause on the SAP database data volume
- **Injection method**: FIS native (`aws:ebs:pause-volume-io`, `duration: PT5M`)
- **Target**: `aws:ec2:ebs-volume` tagged `FIS-Ready=True`, `FIS-Application=SAP`, `FIS-SAP-App-Tier=Database`, `FIS-SAP-Database-Type=Data`, `FIS-SAP-Environment-Type=Dev`, `FIS-SAP-SID=S4`, `availabilityZoneIdentifier: us-east-1a`
- **Hypothesis**: When the block storage of the SAP database host is interrupted, the application cannot write data and fails over to the standby EC2 instance in another AZ within 15–30 minutes (RTO 30 min, RPO near zero), validating the database cluster configuration.
- **Applicable architectures**: SAP on AWS with HA database clustering
- **⚠ Warnings**: Update the AZ and SAP tag values; the template defaults to `Dev` / `S4` / `us-east-1a`.
- [GitHub](https://github.com/aws-samples/fis-template-library/tree/main/sap-ebs-pause-database-data)

### sap-ec2-instance-stop-ascs
- **Fault type**: SAP ASCS instance stop
- **Injection method**: FIS native (`aws:ec2:stop-instances`, `startInstancesAfterDuration: PT5M`)
- **Target**: `aws:ec2:instance` tagged `FIS-Ready=True`, `FIS-Application=SAP`, `FIS-SAP-App-Tier=Application`, `FIS-SAP-HA-Node=Primary`, `FIS-SAP-Environment-Type=Dev`, `FIS-SAP-SID=S4`
- **Hypothesis**: When the EC2 instance hosting ASCS is interrupted, ASCS fails over to the standby instance hosting ERS within 5–15 minutes and users can resume operations, validating the application cluster configuration.
- **Applicable architectures**: SAP S/4HANA with ASCS/ERS HA clustering
- **⚠ Warnings**: Update the SAP tag values to your environment.
- [GitHub](https://github.com/aws-samples/fis-template-library/tree/main/sap-ec2-instance-stop-ascs)

### sap-ec2-instance-stop-database
- **Fault type**: SAP database instance stop
- **Injection method**: FIS native (`aws:ec2:stop-instances`, `startInstancesAfterDuration: PT5M`)
- **Target**: `aws:ec2:instance` tagged `FIS-Ready=True`, `FIS-Application=SAP`, `FIS-SAP-App-Tier=Database`, `FIS-SAP-HA-Node=Primary`, `FIS-SAP-Environment-Type=Dev`, `FIS-SAP-SID=S4`
- **Hypothesis**: When the EC2 instance hosting the SAP database is interrupted, the application fails over to the standby instance in another AZ within 15–30 minutes (RTO 30 min, RPO near zero), validating the database cluster configuration.
- **Applicable architectures**: SAP on AWS with HA database clustering
- **⚠ Warnings**: Update the SAP tag values to your environment.
- [GitHub](https://github.com/aws-samples/fis-template-library/tree/main/sap-ec2-instance-stop-database)

---

## Injection Method Summary

| Method | Scenarios | Characteristics |
|--------|-----------|----------------|
| **FIS native action only** | ec2-instances-terminate, ec2-spot-interruption, aurora-cluster-failover, ecs-fargate-az-impairment, elasticache-az-power-interruption, dynamodb-traffic-blackhole-region-impairment, direct-connect-resiliency, SAP (3) | Single service API; FIS reverts time-bound actions itself; one-shot actions (terminate, failover, spot notice) cannot be undone by a stop |
| **FIS native + SSM Automation** | ecs-fargate-az-evacuation, eks-automode-az-impairment, dynamodb-region-impairment | Native fault plus orchestrated control-plane changes (subnet removal, NodePool patch, resource policy) with their own restore steps |
| **FIS native + SSM Run Command** (`aws:ssm:send-command`) | aurora-postgres-cluster-loadtest-failover, mysql-rds-loadtest-failover, ec2-windows-stop-iis | Command runs on a pre-existing tagged instance (load generator or IIS host) |
| **SSM Automation — ephemeral load generator** | database-connection-limit-exhaustion, database-blocking-locks, database-io-exhaustion | Creates a temporary SG + EC2, generates DB load, cleans up; needs DB credentials in Secrets Manager |
| **SSM Automation — service API call** | aurora-global-region-failover, elasticache-redis-primary-node-failover, elasticache-redis-primary-node-reboot, msk-broker-reboot | Calls an API FIS has no action for (`FailoverGlobalCluster`, `TestFailover`, `RebootCacheCluster`, `RebootBroker`); effect cannot be undone by a stop |
| **SSM Automation — security-group manipulation** | elasticache-redis-connection-failure | Removes/restores port 6379 ingress rules; targets one service's connections |
| **SSM Automation — resource-policy denial** | cloudfront-impairment, sqs-queue-impairment (and the SSM half of dynamodb-region-impairment) | Deny statement in bucket/queue/table policy; simulates service unavailability at the authorization layer |
| **SSM Automation — application parameter flag** | agentcore-strands-agent-faults | Writes SSM parameters that an in-process chaos module reads |
| **Network ACL cloning** (`aws:network:disrupt-connectivity`) | dynamodb-traffic-blackhole-region-impairment, ecs-fargate-az-impairment, ecs-fargate-az-evacuation, eks-automode-az-impairment | FIS clones the subnet NACL, adds deny rules (scope `dynamodb` / `availability-zone` / `all`) and restores the original association |
