# AWS FIS Template Library — 场景索引

> 来源: [aws-samples/fis-template-library](https://github.com/aws-samples/fis-template-library) (commit: ee74d58, 2026-11-03)
> 许可证: MIT-0
> 最后同步: 2026-11-09

本索引收录 AWS FIS Template Library 在 commit ee74d58 时的全部 27 个实验模板。
每个模板包含可直接部署的 FIS 实验 JSON、IAM 策略,以及(如适用)SSM Automation 文档。
"注入方式"列出的是每个实验模板中实际的 `actionId`。

标记 ⭐ 的模板(8 个)已嵌入 `references/fis-templates/`,可直接使用。

**所有模板都不带停止条件**(`"stopConditions": [{"source": "none"}]`)。除短时测试外,运行前请先添加基于客户影响指标的 CloudWatch 告警。

相对上一版索引(e2c94c3)新增: agentcore-strands-agent-faults、database-blocking-locks、database-io-exhaustion、ecs-fargate-az-evacuation、ecs-fargate-az-impairment、eks-automode-az-impairment、elasticache-az-power-interruption、msk-broker-reboot。

---

## 计算 — EC2

### ec2-instances-terminate
- **故障类型**: 实例终止
- **注入方式**: FIS 原生 (`aws:ec2:terminate-instances`)
- **目标**: 带 `FIS-Ready=True` 标签的 `aws:ec2:instance`,`selectionMode: PERCENT(25)`
- **假设**: 当 Auto Scaling 组中 25% 的 EC2 实例被终止时,应用保持可用:负载均衡器停止向被终止实例发送请求,Auto Scaling 补充新实例。在负载均衡器停止使用某实例之前发往它的请求可能失败。
- **适用架构**: 负载均衡器 + Auto Scaling 的 EC2 工作负载
- **⚠ 警告**: 选择范围是**整个 Region** 内所有带标签的实例,而非单个 ASG —— 只给要测试的实例打标签。至少需要 **4 台**运行中的带标签实例(25% 向下取整);不足时选不到目标,实验失败并报 "Target resolution returned empty set."。动作约 12 秒完成,停止实验无法恢复已终止的实例。
- [GitHub](https://github.com/aws-samples/fis-template-library/tree/main/ec2-instances-terminate)

### ec2-spot-interruption
- **故障类型**: Spot 实例中断通知
- **注入方式**: FIS 原生 (`aws:ec2:send-spot-instance-interruptions`, `durationBeforeInterruption: PT2M`)
- **目标**: 带 `FIS-Ready=True` 标签的 `aws:ec2:spot-instance`,`selectionMode: ALL`
- **假设**: 如果目标 Spot 实例运行在负载均衡器后的 Auto Scaling 组中,应用无需人工介入即可恢复:每个实例利用两分钟通知完成或移交工作,Auto Scaling 启动替换实例,负载均衡器将请求转发给替换实例。由于所有目标实例同时被中断,在第一个替换实例开始服务前请求预计会失败。
- **适用架构**: 使用 Spot 实例的成本优化型工作负载
- **⚠ 警告**: 中断 Region 内**所有**带标签的运行中 Spot 实例(按需实例不受影响)。实验在开始约 12 秒后结束,比 EC2 实际中断早约 2 分钟;之后再停止无法取消中断。`emptyTargetResolutionMode: fail`。
- [GitHub](https://github.com/aws-samples/fis-template-library/tree/main/ec2-spot-interruption)

### ec2-windows-stop-iis
- **故障类型**: Windows IIS 应用程序池停止
- **注入方式**: 通过 FIS 执行 SSM Run Command (`aws:ssm:send-command`,文档 `StopIISAppPool`:校验 → 停止应用池 → 恢复;`DurationSeconds: 285`,`IISAppPoolName: DefaultAppPool`,动作 `duration: PT5M`)
- **目标**: 带 `FIS-Ready=True` 标签、运行 SSM Agent 的 `aws:ec2:instance`,`selectionMode: ALL`
- **假设**: 当某台 Windows EC2 实例上的 IIS 被停止(模拟 Web 服务器崩溃或无法启动)时,应用仍保持可用和弹性。
- **适用架构**: EC2 上的 Windows/.NET 工作负载
- **⚠ 警告**: 假设描述的是一台实例,但模板选择 `ALL` 带标签实例 —— 如需测试单台,改为 `COUNT(1)`。
- [GitHub](https://github.com/aws-samples/fis-template-library/tree/main/ec2-windows-stop-iis)

---

## 容器 — ECS / EKS

### ecs-fargate-az-impairment
- **故障类型**: ECS Fargate 服务的 AZ 网络受损(仅检测,不改服务配置)
- **注入方式**: FIS 原生 (`aws:network:disrupt-connectivity` scope `availability-zone` PT15M,`aws:ecs:task-network-packet-loss` 对 `0.0.0.0/0` 丢包 100% PT15M)
- **目标**: 带 `FIS-Ready=True` 标签并按目标 AZ 过滤的 `aws:ec2:subnet`;带 `FIS-Ready=True` 标签、按 AZ 过滤且 `LastStatus=RUNNING` 的 `aws:ecs:task`
- **假设**: 当某个 AZ 出现网络受损时,服务能检测到该 AZ 健康度下降,并依靠健康 AZ 中的任务以降级容量继续运行。模板不修改服务的网络配置,因此替换任务可能被重新调度回受损 AZ —— 实验衡量的是检测信号是否仍能标记该 AZ。所有故障在持续时间结束时自动恢复。
- **适用架构**: 跨 ≥ 2 个 AZ 的 ECS Fargate 服务
- **⚠ 警告**: 丢包动作要求每个任务带 SSM agent sidecar(`pidMode: task`、`awsvpc`、`enableFaultInjection: true`、关闭 ECS Exec),并配置任务角色和托管实例角色权限;否则报 "At least one ECS Task is not registered as a SSM managed instance."。标签必须传播到任务。`emptyTargetResolutionMode: skip`。
- [GitHub](https://github.com/aws-samples/fis-template-library/tree/main/ecs-fargate-az-impairment)

### ecs-fargate-az-evacuation
- **故障类型**: AZ 受损 + 运维式 AZ 撤离(ECS Fargate 服务)
- **注入方式**: FIS 原生 (`aws:network:disrupt-connectivity` scope `availability-zone` PT20M,`aws:ecs:task-network-packet-loss` PT20M,`aws:fis:wait`,`aws:ecs:stop-task`) + SSM Automation (`aws:ssm:start-automation-execution`,文档 `ecs-fargate-az-evacuation-subnet-automation`:从服务中移除该 AZ 的子网、等待、恢复)
- **目标**: 子网/任务目标同 ecs-fargate-az-impairment;ECS 集群、**服务**和任务都必须带 `FIS-Ready=True` 标签
- **假设**: 演练对已检测到的 AZ 受损的响应:经过检测延迟后,移除受损 AZ 的子网会触发新的服务部署,轮换**所有**任务(包括健康 AZ 中的任务);在你设定的时间内所有运行中任务都位于健康 AZ,服务从不低于 `minimumHealthyPercent`,没有 SLO 告警触发,结束时子网自动恢复。
- **适用架构**: 拥有 ≥ 2 个不同 AZ 子网的 ECS Fargate 服务
- **⚠ 警告**: 重新部署是预期效果而非副作用。剩余 AZ 需能承受最长约 30 分钟的全服务重新部署。服务未打标签会在自动化第一步报 `AccessDenied`。自动化不会移除最后一个子网。`emptyTargetResolutionMode: skip`。
- [GitHub](https://github.com/aws-samples/fis-template-library/tree/main/ecs-fargate-az-evacuation)

### eks-automode-az-impairment
- **故障类型**: EKS Auto Mode 集群的 AZ 受损(网络 + 节点排除 + Pod 驱逐)
- **注入方式**: FIS 原生 (`aws:network:disrupt-connectivity` scope `all` PT15M) + SSM Automation (`aws:ssm:start-automation-execution`,文档 `eks-automode-az-impairment-automation`:在 VPC 内启动临时客户端 EC2,cordon 该 AZ 的节点,修改 NodePool 排除该 AZ,删除非系统 Pod,等待,恢复 NodePool 并 uncordon)
- **目标**: 带 `FIS-Ready=True` 标签且 `availabilityZoneIdentifier` = 目标 AZ 的 `aws:ec2:subnet`
- **假设**: 工作负载在 AZ 受损时把副本运行在剩余健康 AZ 中(必要时在那里扩容),而不是损失容量:该 AZ 的 Pod 变得不可达,Auto Mode 不在该 AZ 新建节点,被驱逐的 Pod 只调度到健康 AZ,应用保持可用,恢复后该 AZ 的容量重新可用。
- **适用架构**: 跨 ≥ 2 个 AZ(推荐 3 个)的 EKS Auto Mode 集群
- **⚠ 警告**: 需要**自定义** NodePool(内置池会被 EKS 协调,AZ 排除会被静默回滚)。Kubernetes 调用以**实例配置文件角色**身份执行(EKS access entry 和 RBAC 必须映射该角色)。客户端子网不能位于目标 AZ,且需能访问私有 API 端点和 SSM。无法故障转移的工作负载会以降级容量运行,实验仍报告成功。总时长 30–45 分钟。
- [GitHub](https://github.com/aws-samples/fis-template-library/tree/main/eks-automode-az-impairment)

---

## 数据库 — RDS / Aurora

### aurora-cluster-failover
- **故障类型**: Aurora 集群故障转移(writer ↔ reader)
- **注入方式**: FIS 原生 (`aws:rds:failover-db-cluster`)
- **目标**: 带 `FIS-Ready=True` 标签的 `aws:rds:cluster`,`selectionMode: ALL`
- **假设**: reader 与 writer 之间的故障转移可能导致请求短暂失败,但请求会自动恢复,故障转移后应用继续正常运行。
- **适用架构**: writer 与至少一个 reader 位于不同 AZ 的 Aurora 集群
- **⚠ 警告**: Region 内**所有**带标签的集群都会故障转移;该动作也支持 DocumentDB 集群,只给要转移的集群打标签。`FailoverDBCluster` 一返回动作即完成 —— **停止实验无法撤销故障转移**(调用后 4 秒发出的停止请求因实验已完成被拒绝)。FIS 角色现限定为 `arn:aws:rds:<REGION>:<ACCOUNT>:cluster:*` 并带 `FIS-Ready=True` 标签条件。
- [GitHub](https://github.com/aws-samples/fis-template-library/tree/main/aurora-cluster-failover)

### aurora-postgres-cluster-loadtest-failover
- **故障类型**: CPU 负载后在负载下故障转移
- **注入方式**: FIS 原生 + SSM Run Command (`aws:ssm:send-command` 在负载生成器上运行文档 `aurora-cluster-loadtest-document` 10 分钟;`aws:fis:wait` PT5M 后执行 `aws:rds:failover-db-cluster`)
- **目标**: 均带 `FIS-Ready=True` 标签的 `aws:rds:cluster` 和 `aws:ec2:instance`(负载生成器)
- **假设**: 当 Aurora 集群出现高 CPU 负载并随后发生故障转移时,系统以最小中断恢复正常运行;自动恢复在几分钟内完成,故障转移后请求处理能力保持接近 100%。
- **适用架构**: 需要压力 + 故障转移验证的 Aurora PostgreSQL 工作负载
- **⚠ 警告**: 会创建 `load_test_users` 和 `load_test_transactions` 表(含索引),运行后**保留**。需要事先存在、带标签、运行 SSM Agent 且能连通数据库的 EC2 负载生成器。
- [GitHub](https://github.com/aws-samples/fis-template-library/tree/main/aurora-postgres-cluster-loadtest-failover)

### aurora-global-region-failover ⭐
- **故障类型**: Aurora Global Database 跨 Region 切换(switchover)/故障转移(failover)
- **注入方式**: SSM Automation (`aws:ssm:start-automation-execution`,`FailoverGlobalCluster` 带 `Switchover=True` 或 `AllowDataLoss=True`,`maxDuration` PT10M)
- **目标**: 由 `globalClusterIdentifier` 指定的全局集群(无 FIS target 块)
- **假设**: 使用 `switchover`(默认)时,secondary 成为 primary,应用在 5 分钟内恢复读写(RTO 5 分钟),重试的写入全部成功,错误率/连接告警在 5 分钟内回到 OK。使用 `failover` 时,最后几秒的写入可能丢失,丢失时间跨度不超过故障转移前 `AuroraGlobalDBRPOLag` 的值。
- **适用架构**: 使用 Aurora Global Database 的多 Region 容灾
- **⚠ 警告**: 实验不会切回,停止实验也无法撤销已被接受的切换。README 要求 `FIS-Ready=True` 标签,但没有任何机制强制。文档最坏耗时(10 秒 + 600 秒轮询)超过 `maxDuration` PT10M。
- 嵌入路径: `references/fis-templates/aurora-global-failover/`
- [GitHub](https://github.com/aws-samples/fis-template-library/tree/main/aurora-global-region-failover)

### mysql-rds-loadtest-failover
- **故障类型**: CPU 负载后在负载下 Multi-AZ 故障转移
- **注入方式**: FIS 原生 + SSM Run Command (`aws:ssm:send-command` 文档 `MySQL-LoadTest-Document` PT15M → `aws:rds:reboot-db-instances` 带 `forceFailover: true` → `aws:ssm:send-command` `AWS-RunShellScript` 停止负载)
- **目标**: 均带 `FIS-Ready=True` 标签的 `aws:rds:db` 和 `aws:ec2:instance`(负载生成器)
- **假设**: 在 Multi-AZ MySQL RDS 实例高 CPU 负载后发生故障转移时,系统切换到备用实例,停机约 25 秒,具备正确连接处理的应用以接近 100% 的成功率自动重连。
- **适用架构**: MySQL RDS Multi-AZ 工作负载
- **⚠ 警告**: 会创建 `loadtest` 表,运行后保留。
- [GitHub](https://github.com/aws-samples/fis-template-library/tree/main/mysql-rds-loadtest-failover)

### database-connection-limit-exhaustion ⭐
- **故障类型**: 数据库连接上限耗尽
- **注入方式**: SSM Automation (`aws:ssm:start-automation-execution`,文档 `ConnectionLimitExhaustion-Automation`:临时 SG → 临时 EC2 负载生成器 → 保持连接 → 清理;`maxDuration` PT180M)
- **目标**: 文档参数中指定的数据库(端点、SG、密钥 ARN);无 FIS target 块
- **假设**: 接近上限时,{service1} 用户旅程保持在 2 秒 SLA 内,熔断器保持关闭,先行告警在 {y} 分钟内触发。耗尽时,熔断器打开,UI 优雅降级,告警触发,其他旅程不受影响;连接释放后熔断器在 {z} 分钟内关闭,稳态恢复。
- **适用架构**: Aurora PostgreSQL/MySQL、RDS PostgreSQL/MySQL/SQL Server
- **⚠ 警告**: 会在数据库 SG 上临时添加入站规则。上游现已把每一步的 `onFailure`/`onCancel` 都路由到清理链(失败或停止时也会删除实例、入站规则和 SG),并强制 IMDSv2。角色和文档名称是硬编码的(`ConnectionLimitExhaustion-*`,实例配置文件 `SSM-Managed-Instance-Profile`);密码在实例上读取,因此 Secrets Manager 权限属于实例配置文件角色(已从 SSM 角色中移除)。
- 嵌入路径: `references/fis-templates/database-connection-exhaustion/`
- [GitHub](https://github.com/aws-samples/fis-template-library/tree/main/database-connection-limit-exhaustion)

### database-blocking-locks
- **故障类型**: 行级阻塞锁(一个 Blocker 会话 + 逐步增加的 Waiter 会话)
- **注入方式**: SSM Automation (`aws:ssm:start-automation-execution`,文档 `DatabaseBlockingLocks-Automation`:临时 EC2 负载生成器;默认 `WaiterCount` 50、`ExperimentDuration` PT10M、`RampTime` PT1M、`RampSteps` 10;`maxDuration` PT180M)
- **目标**: 文档参数中指定的数据库;无 FIS target 块
- **假设**: 当 {service1} 数据库受到合成(或定向)行级阻塞锁时,告警触发并在 {x} 分钟内通知 DevOps 团队,团队能通过引擎特定的 blocked-waiter 指标在 {y} 分钟内处理原因。关键用户旅程不受影响(合成模式)/ 按声明的方式受或不受影响(定向模式)。
- **适用架构**: Aurora PostgreSQL/MySQL、RDS PostgreSQL/MySQL/SQL Server
- **⚠ 警告**: Synthetic_Mode 会创建并删除 `fis_blocking_locks_target`,因此 `DatabaseName` 必须是用户可 `CREATE`/`DROP` 的**用户自建**数据库(系统数据库不适用,尽管模板默认值是 `postgres`)。把 `TargetTableName` 设为其他任何值会启用 **Real_Mode**,锁定真实应用表的第一行,在 `ExperimentDuration` 内造成真实影响。故障范围本就很窄;要测试大范围降级请用连接耗尽。
- [GitHub](https://github.com/aws-samples/fis-template-library/tree/main/database-blocking-locks)

### database-io-exhaustion
- **故障类型**: 数据库 I/O 饱和
- **注入方式**: SSM Automation (`aws:ssm:start-automation-execution`,文档 `DatabaseIOExhaustion-Automation`:临时 EC2,`WorkerThreads` 50、`IOPattern` `read`/`write`/`mixed`、`SeedRowCount` 500、`MinActiveWorkerPercentage` 50;`maxDuration` PT180M)
- **目标**: 文档参数中指定的数据库;数据库 SG 必须带 `FIS-Ready=True` 标签
- **假设**: 接近 I/O 饱和时,{service1} 旅程保持在 2 秒 SLA 内,稳态保持,先行告警在 {y} 分钟内触发。耗尽时,响应时间优雅降级,UI 提示性能下降,告警触发,其他旅程不受影响;负载移除后性能在 {z} 分钟内恢复。
- **适用架构**: Aurora PostgreSQL、RDS PostgreSQL、RDS Oracle(已验证);Aurora MySQL、RDS MySQL、RDS SQL Server(实验性)
- **⚠ 警告**: 每个 worker 创建并删除自己的 `fis_io_<suffix>_<thread>` 表,用户需要 `CREATE`/`DROP` 权限。若做过 I/O 的 worker 少于 `MinActiveWorkerPercentage`,运行**失败**。`ExperimentDuration` 要远小于 PT115M(步骤超时 2 小时)。角色/文档名硬编码;需要 Secrets Manager 权限的是实例角色而不是 SSM 角色。
- [GitHub](https://github.com/aws-samples/fis-template-library/tree/main/database-io-exhaustion)

---

## 缓存 — ElastiCache

### elasticache-redis-connection-failure ⭐
- **故障类型**: Redis 连接中断(删除安全组规则)
- **注入方式**: SSM Automation (`aws:ssm:start-automation-execution`,删除 6379 端口入站规则 → 等待 PT5M → 恢复;`maxDuration` PT30M)
- **目标**: 带 `FIS-Ready=True` 标签的 Redis 缓存集群(节点),最多 100 个节点
- **假设**: 6379 规则被删除 5 分钟期间,从第一次调用失败 30 秒后起错误率不超过你的阈值(熔断器返回降级响应),恢复后 60 秒内 Redis 调用恢复到正常速率,恢复后一分钟内 `NewConnections` 总和不超过客户端正常连接池规模(无重试风暴)。
- **适用架构**: 使用 ElastiCache(Redis OSS 引擎,非 Valkey)的应用
- **⚠ 警告**: 只删除 `FromPort=ToPort=6379` 的规则。共用这些 SG 的所有资源都会失去访问。已建立的被跟踪连接可能继续工作。即使没有规则匹配或恢复失败,运行仍以 `Success` 结束 —— 每次运行后都要检查 SG。在 `restoreRedisConnections` 期间停止可能导致规则未恢复。
- 嵌入路径: `references/fis-templates/redis-connection-failure/`
- [GitHub](https://github.com/aws-samples/fis-template-library/tree/main/elasticache-redis-connection-failure)

### elasticache-redis-primary-node-failover ⭐
- **故障类型**: Redis 主节点故障转移(副本提升)
- **注入方式**: SSM Automation (`aws:ssm:start-automation-execution`,对节点组 `0001` 调用 ElastiCache `TestFailover`)
- **目标**: 第一个可用、`AutomaticFailover=enabled` 且带 `FIS-Ready=True` 标签的复制组
- **假设**: 主节点故障转移到副本时,应用检测到并在 30 秒内重连到新主节点,连接池正确处理 DNS 端点变化,不丢数据,完成后 60 秒内性能恢复正常。
- **适用架构**: 启用 Multi-AZ 和自动故障转移的 Redis 复制组
- **⚠ 警告**: **ee74d58 版本按原样无法运行**:SSM 角色缺少 `elasticache:TestFailover`(错误被吞掉并报 "No cluster found"),模板传入了文档未声明的 `region`/`AutomationAssumeRole` 参数,文档的 `assumeRole` 角色名与模板不一致。自动化在发起故障转移后立即返回;停止实验无法撤销。详见嵌入的 README。
- 嵌入路径: `references/fis-templates/elasticache-redis-primary-node-failover/`
- [GitHub](https://github.com/aws-samples/fis-template-library/tree/main/elasticache-redis-primary-node-failover)

### elasticache-redis-primary-node-reboot ⭐
- **故障类型**: Redis 主节点重启(**会清空数据**)
- **注入方式**: SSM Automation (`aws:ssm:start-automation-execution`,文档 `ElastiCache-Redis-Primary-Node-Reboot`:对每个带标签复制组的主节点调用 `RebootCacheCluster`,然后最多等待 17 分钟;`maxDuration` PT30M)
- **目标**: Region 内所有带 `FIS-Ready=True` 标签的复制组(超过 20 个则拒绝运行);Redis OSS、集群模式禁用、Multi-AZ + 自动故障转移、≥ 1 个副本、不属于 Global Datastore
- **假设**: 对主端点的写入失败不超过 30 秒,复制组显示 `available` 后 60 秒内错误率回到基线;由于重启会清空缓存,应用应从数据源读取并重新填充缓存而不返回错误。
- **适用架构**: 内容可以丢失的 ElastiCache(Redis OSS)复制组
- **⚠ 警告**: 上游已修正假设:重启主节点**不会**故障转移;主节点重启后为空,副本随后也清空自己的副本,因此**复制组中的所有数据都会丢失**。所有带标签的复制组同时被重启。调用之后停止只会结束等待,不能阻止重启或数据丢失。Valkey 复制组会被拒绝。
- 嵌入路径: `references/fis-templates/elasticache-redis-primary-node-reboot/`
- [GitHub](https://github.com/aws-samples/fis-template-library/tree/main/elasticache-redis-primary-node-reboot)

### elasticache-az-power-interruption
- **故障类型**: ElastiCache AZ 断电
- **注入方式**: FIS 原生 (`aws:elasticache:replicationgroup-interrupt-az-power`, `duration: PT10M`)
- **目标**: 带 `FIS-Ready=True` 标签、`availabilityZoneIdentifier` = 目标 AZ 的 `aws:elasticache:replicationgroup`,`selectionMode: ALL`
- **假设**: 当主节点所在 AZ 的节点断电时,从该节点不再响应到主端点第一次写入成功的时间,在自动故障转移把健康 AZ 中的副本提升后不超过 30 秒;应用无需人工介入即可重连;实验期间该 AZ 的副本替换被阻止;结束后节点重新加入,集群恢复满容量。
- **适用架构**: 启用 Multi-AZ 和自动故障转移的复制组(非 Serverless)
- **⚠ 警告**: 断电在动作开始后 42–74 秒才发生(`duration` 要远大于此值)。虽然复制组在 2 分钟内显示 `available`,该 AZ 的节点要在结束后约 9–10 分钟才重新响应 `PING`。有一分钟内两个节点的 `IsMaster` 都可能为 1。停止会结束断电,但不会撤销故障转移。会命中所有在该 AZ 有节点的带标签复制组;不支持 `resourceArns` 定位。
- [GitHub](https://github.com/aws-samples/fis-template-library/tree/main/elasticache-az-power-interruption)

---

## 流处理 — Amazon MSK

### msk-broker-reboot ⭐
- **故障类型**: 单个 MSK broker 重启
- **注入方式**: SSM Automation (`aws:ssm:start-automation-execution`,文档 `msk-broker-reboot-automation`:MSK `RebootBroker` + `DescribeClusterOperation` 轮询;`maxDuration` PT21M)
- **目标**: `ListClustersV2` 返回的第一个 `ACTIVE`、预置型、带 `FIS-Ready=True` 标签的集群;默认选最小 broker ID
- **假设**: 在 leader 迁移到同步副本期间,集群继续在其余 broker 上处理生产/消费:被重启 broker 所领导分区的最长投递停顿在你的允许范围内(测试中 5 次重启有 3 次 ≤ 150 ms,另 2 次为 36 秒和 62 秒,且应用未收到错误),`acks=all` + 幂等生产者不丢消息,`OfflinePartitionsCount` 保持 0,`UnderReplicatedPartitions` 回到 0,集群在几分钟内(135–196 秒)回到 `ACTIVE`,存活 broker 的 CPU 保持在余量内。
- **适用架构**: 预置型 MSK,RF ≥ 3 跨 ≥ 2 个 AZ,`min.insync.replicas` ≥ 2
- **⚠ 警告**: **客户端可能停顿到请求超时**(观察到 62 秒,与 librdkafka 默认 60 秒 `socket.timeout.ms` 一致)。**每个 Region 只给一个集群打标签** —— 没有集群参数。`brokerSelection=random` 实际选择最小 broker ID。调用 `RebootBroker` 后停止实验不会停止重启。`REBOOTING_BROKER` 期间 MSK 拒绝任何人的更新操作。
- 嵌入路径: `references/fis-templates/msk-broker-reboot/`
- [GitHub](https://github.com/aws-samples/fis-template-library/tree/main/msk-broker-reboot)

---

## CDN — CloudFront

### cloudfront-impairment ⭐
- **故障类型**: CloudFront 源站故障(拒绝 S3 `GetObject`)
- **注入方式**: SSM Automation (`aws:ssm:start-automation-execution`:对主源站存储桶拒绝 `s3:GetObject` + 失效 `/*` → 等待 PT10M → 移除拒绝 + 失效;`maxDuration` PT1H)
- **目标**: 带 `FIS-Ready=True` 标签的 CloudFront 分配;只针对每个源站组的主成员(S3 源站)
- **假设**: S3 源站受损时,CloudFront 在 30 秒内切换到备用源站,告警在 2–3 分钟内通知团队,内容通过备用源站持续交付;受损结束后 CloudFront 在 30 秒内恢复使用主源站。
- **适用架构**: 使用源站组故障转移的 CloudFront + S3 源站
- **⚠ 警告**: 没有源站组的分配不会被注入故障。拒绝语句使用 `Principal: "*"`,因此该存储桶的所有 `GetObject` 调用方都受影响,而不只是 CloudFront。每次运行做两次全缓存失效。SSM 角色可修改任意存储桶策略(无标签条件)。
- 嵌入路径: `references/fis-templates/cloudfront-impairment/`
- [GitHub](https://github.com/aws-samples/fis-template-library/tree/main/cloudfront-impairment)

---

## NoSQL — DynamoDB

### dynamodb-region-impairment
- **故障类型**: DynamoDB Region 级故障(暂停复制 + 阻断访问)
- **注入方式**: FIS 原生 (`aws:dynamodb:global-table-pause-replication` PT12M) + SSM Automation (`aws:ssm:start-automation-execution`,文档 `DynamoDB-Region-Impairment`:在表资源策略中加入 `FISDenyAccess` 拒绝语句 PT10M,然后清理)
- **目标**: 带 `FIS-Ready=True` 标签的 `aws:dynamodb:global-table`;`tableName` 和 Region 在文档参数中指定
- **假设**: 当 us-east-1 的 DynamoDB 完全故障时,告警在 5 分钟内通知团队,应用在 2 分钟内切换到 us-west-2 副本,受损期间所有读写都转到健康 Region,故障恢复后 5 分钟内恢复正常跨 Region 运行。
- **适用架构**: 使用 DynamoDB 全局表的多 Region 应用
- **⚠ 警告**: 模板文件使用 us-east-1 和示例表名 —— 需更新所有 Region 和表名引用。
- [GitHub](https://github.com/aws-samples/fis-template-library/tree/main/dynamodb-region-impairment)

### dynamodb-traffic-blackhole-region-impairment
- **故障类型**: 网络层 DynamoDB 黑洞 + 暂停复制
- **注入方式**: FIS 原生 (`aws:network:disrupt-connectivity` scope `dynamodb` PT10M + `aws:dynamodb:global-table-pause-replication` PT10M)
- **目标**: 带 `FIS-Ready=True` 标签的 `aws:ec2:subnet`;Region 内带 `FIS-Ready=True` 标签的 `aws:dynamodb:global-table` 副本
- **假设**: 10 分钟内来自带标签子网的 DynamoDB 调用全部失败,而来自其他子网的调用以及到其他服务的调用错误率保持正常;到/从带标签副本的复制在 5 分钟内停止,结束 20 分钟后其他副本不缺任何成功写入;监控在 3 分钟内检测、5 分钟内通知;配置的自动故障转移在 10 分钟故障期内完成。
- **适用架构**: 通过 Region 端点(如网关端点)访问 DynamoDB 并使用全局表的 VPC 应用
- **⚠ 警告**: 带标签子网中的所有资源都会失去 DynamoDB 访问(库中其他实验也会给子网打这个标签)。接口(PrivateLink)端点不在前缀列表中,预计不会被阻断。角色**只能在带 `FIS-Ready=True` 标签的子网上**修改 NACL 关联 —— 运行期间不要移除标签,否则 FIS 无法恢复该子网。角色可对 Region 内任何表/流设置或删除资源策略(加标签条件会导致 DynamoDB 拒绝 FIS)。`emptyTargetResolutionMode: fail`。每次运行前记录每个子网的 NACL。
- [GitHub](https://github.com/aws-samples/fis-template-library/tree/main/dynamodb-traffic-blackhole-region-impairment)

---

## 消息 — SQS

### sqs-queue-impairment ⭐
- **故障类型**: SQS 队列访问被拒绝(渐进式受损)
- **注入方式**: SSM Automation (4 次 `aws:ssm:start-automation-execution`,分别 PT2M / PT5M / PT7M / PT15M,中间以 `aws:fis:wait` PT3M / PT3M / PT2M 间隔)
- **目标**: 带 `FIS-Ready=True` 标签的 SQS 队列
- **假设**: 当某 Region 的 SQS 受损时,告警在 5 分钟内通知 DevOps 团队;受损期间组件 A 对最终用户不可用,其他组件正常运行;受损解除后 5 分钟内组件 A 恢复可用。
- **适用架构**: 使用 SQS 进行异步消息传递的应用
- **⚠ 警告**: 上游现改为添加**限定范围**的拒绝语句(仅数据面动作、仅作用于队列 ARN、通过 `SetQueueAttributes` 添加),清理永远不会被阻断;可选的 `targetPrincipalArn` 可把拒绝限定到单一主体(默认 `*`)。不要用源队列自身的指标作为停止条件 —— 这些指标本就会变化。
- 嵌入路径: `references/fis-templates/sqs-queue-impairment/`
- [GitHub](https://github.com/aws-samples/fis-template-library/tree/main/sqs-queue-impairment)

---

## 网络

### direct-connect-resiliency
- **故障类型**: Direct Connect 虚拟接口断开
- **注入方式**: FIS 原生 (`aws:directconnect:virtual-interface-disconnect`, `duration: PT10M`)
- **目标**: 带 `FIS-Ready=True` 标签的 `aws:directconnect:virtual-interface`,`selectionMode: COUNT(1)`
- **假设**: 当 Direct Connect 虚拟接口断开时,混合云应用保持连通性和性能,切换到备用路径(VPN 或第二条 Direct Connect)。
- **适用架构**: 带备用路径的 Direct Connect 混合云
- **⚠ 警告**: 需要已配置的备用路径;否则本地连通性会中断 10 分钟。
- [GitHub](https://github.com/aws-samples/fis-template-library/tree/main/direct-connect-resiliency)

---

## AI Agent — Amazon Bedrock AgentCore

### agentcore-strands-agent-faults
- **故障类型**: Strands agent 内的工具调用故障(调用被取消: `timeout`、`network_error`、`execution_error`、`validation_error`;结果被破坏: `truncate_fields`、`remove_fields`、`corrupt_values`)
- **注入方式**: SSM Automation (`aws:ssm:start-automation-execution`,文档 `ChaosExperiment`:写入 `/chaos/{runtime_id}/` SSM 参数,保持 `DurationSeconds`(900),然后禁用并删除;`maxDuration` PT20M),由 agent 内的 `chaos_plugins()` 模块读取
- **目标**: 由 `RuntimeId` 参数指定的专用 chaos AgentCore Runtime(无 FIS target 块)
- **假设**: 工具调用被取消或结果被破坏时,agent 能识别出没有可信结果并安全失败(承认无法完成、返回带说明或部分的答案、或升级),而不是凭缺失数据编造结果;原始错误不暴露给用户;未注入故障的旅程不受影响;移除故障后 agent 在参数缓存 TTL(默认 10 秒)内回到稳态。
- **适用架构**: 运行在 Amazon Bedrock AgentCore Runtime 上的 Strands agent
- **⚠ 警告**: 需要独立的 chaos 构建/运行时(`strands_agentcore_chaos.py`、`strands_evals`);生产构建不得包含。**替换演示工具名**(`get_move`、`get_pokemon`)—— 匹配不到的名称不会注入任何故障,但运行仍"成功"。`maxDuration` 必须大于 `DurationSeconds` + 15 秒。
- [GitHub](https://github.com/aws-samples/fis-template-library/tree/main/agentcore-strands-agent-faults)

---

## SAP 工作负载

### sap-ebs-pause-database-data
- **故障类型**: SAP 数据库数据卷 EBS I/O 暂停
- **注入方式**: FIS 原生 (`aws:ebs:pause-volume-io`, `duration: PT5M`)
- **目标**: 带 `FIS-Ready=True`、`FIS-Application=SAP`、`FIS-SAP-App-Tier=Database`、`FIS-SAP-Database-Type=Data`、`FIS-SAP-Environment-Type=Dev`、`FIS-SAP-SID=S4` 标签的 `aws:ec2:ebs-volume`,`availabilityZoneIdentifier: us-east-1a`
- **假设**: 当 SAP 数据库主机的块存储中断时,应用无法写入数据,在 15–30 分钟内故障转移到另一个 AZ 的备用 EC2 实例(RTO 30 分钟,RPO 接近 0),验证数据库集群配置。
- **适用架构**: 带 HA 数据库集群的 SAP on AWS
- **⚠ 警告**: 更新 AZ 和 SAP 标签值;模板默认 `Dev` / `S4` / `us-east-1a`。
- [GitHub](https://github.com/aws-samples/fis-template-library/tree/main/sap-ebs-pause-database-data)

### sap-ec2-instance-stop-ascs
- **故障类型**: SAP ASCS 实例停止
- **注入方式**: FIS 原生 (`aws:ec2:stop-instances`, `startInstancesAfterDuration: PT5M`)
- **目标**: 带 `FIS-Ready=True`、`FIS-Application=SAP`、`FIS-SAP-App-Tier=Application`、`FIS-SAP-HA-Node=Primary`、`FIS-SAP-Environment-Type=Dev`、`FIS-SAP-SID=S4` 标签的 `aws:ec2:instance`
- **假设**: 当承载 ASCS 的 EC2 实例中断时,ASCS 在 5–15 分钟内故障转移到承载 ERS 的备用实例,用户可恢复操作,验证应用集群配置。
- **适用架构**: 带 ASCS/ERS HA 集群的 SAP S/4HANA
- **⚠ 警告**: 按你的环境更新 SAP 标签值。
- [GitHub](https://github.com/aws-samples/fis-template-library/tree/main/sap-ec2-instance-stop-ascs)

### sap-ec2-instance-stop-database
- **故障类型**: SAP 数据库实例停止
- **注入方式**: FIS 原生 (`aws:ec2:stop-instances`, `startInstancesAfterDuration: PT5M`)
- **目标**: 带 `FIS-Ready=True`、`FIS-Application=SAP`、`FIS-SAP-App-Tier=Database`、`FIS-SAP-HA-Node=Primary`、`FIS-SAP-Environment-Type=Dev`、`FIS-SAP-SID=S4` 标签的 `aws:ec2:instance`
- **假设**: 当承载 SAP 数据库的 EC2 实例中断时,应用在 15–30 分钟内故障转移到另一个 AZ 的备用实例(RTO 30 分钟,RPO 接近 0),验证数据库集群配置。
- **适用架构**: 带 HA 数据库集群的 SAP on AWS
- **⚠ 警告**: 按你的环境更新 SAP 标签值。
- [GitHub](https://github.com/aws-samples/fis-template-library/tree/main/sap-ec2-instance-stop-database)

---

## 注入方式汇总

| 方式 | 场景 | 特点 |
|--------|-----------|----------------|
| **仅 FIS 原生动作** | ec2-instances-terminate、ec2-spot-interruption、aurora-cluster-failover、ecs-fargate-az-impairment、elasticache-az-power-interruption、dynamodb-traffic-blackhole-region-impairment、direct-connect-resiliency、SAP (3) | 单个服务 API;有时限的动作由 FIS 自行恢复;一次性动作(终止、故障转移、Spot 通知)停止后无法撤销 |
| **FIS 原生 + SSM Automation** | ecs-fargate-az-evacuation、eks-automode-az-impairment、dynamodb-region-impairment | 原生故障加上编排的控制面变更(移除子网、修改 NodePool、资源策略),带各自的恢复步骤 |
| **FIS 原生 + SSM Run Command** (`aws:ssm:send-command`) | aurora-postgres-cluster-loadtest-failover、mysql-rds-loadtest-failover、ec2-windows-stop-iis | 命令在事先存在、带标签的实例(负载生成器或 IIS 主机)上执行 |
| **SSM Automation — 临时负载生成器** | database-connection-limit-exhaustion、database-blocking-locks、database-io-exhaustion | 创建临时 SG + EC2,产生数据库负载,然后清理;需要数据库凭证存放在 Secrets Manager |
| **SSM Automation — 调用服务 API** | aurora-global-region-failover、elasticache-redis-primary-node-failover、elasticache-redis-primary-node-reboot、msk-broker-reboot | 调用 FIS 没有对应动作的 API(`FailoverGlobalCluster`、`TestFailover`、`RebootCacheCluster`、`RebootBroker`);停止无法撤销其效果 |
| **SSM Automation — 安全组操作** | elasticache-redis-connection-failure | 删除/恢复 6379 端口入站规则;只针对单一服务的连接 |
| **SSM Automation — 资源策略拒绝** | cloudfront-impairment、sqs-queue-impairment(以及 dynamodb-region-impairment 的 SSM 部分) | 在存储桶/队列/表策略中加入拒绝语句;在授权层模拟服务不可用 |
| **SSM Automation — 应用参数开关** | agentcore-strands-agent-faults | 写入由进程内 chaos 模块读取的 SSM 参数 |
| **网络 ACL 克隆** (`aws:network:disrupt-connectivity`) | dynamodb-traffic-blackhole-region-impairment、ecs-fargate-az-impairment、ecs-fargate-az-evacuation、eks-automode-az-impairment | FIS 克隆子网 NACL,添加拒绝规则(scope `dynamodb` / `availability-zone` / `all`),结束后恢复原关联 |
