# AWS 常见服务风险参考手册

本文档整理了 AWS 常见服务的韧性风险点，供韧性评估过程中参考。评估时应结合客户实际环境，识别是否存在以下风险，并给出针对性的改进建议。

---

## 1. 存储类风险

### 1.1 EBS (Elastic Block Store)

| 风险编号 | 风险点 | 风险原因 | 改进建议 |
|---------|--------|---------|---------|
| 存储-风险点1 | EBS gp3 I/O Latency 升高 | gp3 I/O Latency 有时升高到 10ms 以上，可能持续几分钟到几十分钟，影响上层应用性能 | 对 I/O Latency 敏感的应用升级到 io2（一致性比 gp3 高 2 个数量级）；自建 MySQL 可迁移到 Aurora（底层分布式存储非 EBS）；应用层构建 HA，Latency 达到阈值时切换到备节点 |
| 存储-风险点2 | EBS Volume 损坏丢盘 | Volume 发生损坏丢盘，数据丢失不能恢复 | RPO=0 的业务在应用层配置多副本分布到不同 AZ，多副本写成功才返回；使用 DLM 定期备份 Volume；使用 AWS Backup 定期备份 EBS |
| 存储-风险点3 | Snapshot 创建的 EBS Volume 初始化性能问题 | 从 Snapshot 创建的 Volume 未完全初始化前读写 Latency 较高（几十毫秒） | 启用 FSR（Fast Snapshot Restore）功能；使用 FIO 对 Volume 进行顺序读触发主动初始化 |
| 存储-风险点4 | 缺乏 EBS I/O 故障模拟工具 | 缺乏模拟 EBS Volume I/O Latency 升高/停止的方法和工具 | 使用 AWS FIS 对 EBS Volume 进行 I/O 停止读写模拟注入（秒级到小时级），验证上层应用是否能正确 failover |
| 存储-风险点5 | EBS Volume 性能达不到预设指标 | 应用 workload 提升时 Volume 性能（IOPS/throughput）未达预设指标 | EC2 实例有 I/O 性能上限，多 Volume 累积性能达到上限后需升级 EC2 规格；监控 ec2_instance_ebs_performance_exceeded_iops 指标 |

### 1.2 S3

| 风险编号 | 风险点 | 风险原因 | 改进建议 |
|---------|--------|---------|---------|
| 存储-风险点6 | S3 对象被删除或覆盖无法恢复 | 对象被删除或覆盖时用户不能恢复原来的数据 | 开启 S3 Versioning；考虑打开 Object Lock 功能保证旧版本不被删除 |
| 存储-风险点9 | S3 高并发 503 错误 | 高并发读写时发生 503 错误 | S3 同一 prefix 有 3500 PUT/5500 GET 限制，将请求打散到不同 prefix；在 prefix 加入哈希字符串或属性；代码加入 retry |

### 1.3 EFS

| 风险编号 | 风险点 | 风险原因 | 改进建议 |
|---------|--------|---------|---------|
| 存储-风险点7 | EFS 账单飙高 | Elastic Throughput 模式按流量收费，高峰时段长时产生高额费用 | 高峰时段 >5% 时应切换为 Provisioned Throughput 模式 |

### 1.4 FSx

| 风险编号 | 风险点 | 风险原因 | 改进建议 |
|---------|--------|---------|---------|
| 存储-风险点8 | FSx 定期性能下降 | 维护窗口（软件升级、安全补丁）期间 I/O 受影响 | 选择 Multi-region 模式降低影响（<1 分钟 vs Single-region 几分钟到 30 分钟）；将维护窗口设置在业务低谷时间 |

### 1.5 DataSync

| 风险编号 | 风险点 | 风险原因 | 改进建议 |
|---------|--------|---------|---------|
| 存储-风险点10 | DataSync 产生大量 S3 Request 费用 | 每次启动都全量扫描 source 和 destination bucket | 降低 DataSync job 运行频率；如需 Bucket 同步改用 S3 Replication |

---

## 2. 数据库类风险

### 2.1 架构与高可用

| 风险编号 | 适用服务 | 风险点 | 风险原因 | 改进建议 |
|---------|---------|--------|---------|---------|
| 数据库-风险点1 | RDS/Aurora/ElastiCache/DocumentDB | 未使用 Multi-AZ 高可用架构 | 无法应对主节点/单 AZ 故障 | RDS 生产环境选择 Multi-AZ Instance/Cluster（SLA 从 99.5% 提升到 99.95%）；Multi-AZ Cluster 大部分 Failover <35s；Aurora/ElastiCache/DocumentDB 至少创建一个跨 AZ 副本 |
| 数据库-风险点2 | RDS/Aurora/ElastiCache/MemoryDB/DocumentDB/DynamoDB | 未选择跨 Region 架构 | 有跨区域容灾需求但未配置 | RDS 创建跨区域只读副本；Aurora 选择 Global Database（复制延迟 <1s）；ElastiCache 选择 Global Datastore；MemoryDB 选择 Multi-Region（SLA 99.999%）；DynamoDB 选择 Global Table（支持多写） |

### 2.2 性能与配置

| 风险编号 | 适用服务 | 风险点 | 风险原因 | 改进建议 |
|---------|---------|--------|---------|---------|
| 数据库-风险点3 | RDS | 生产环境使用 T 系列机型 | T 系列使用信用点数系统，耗尽时性能下降 | 生产环境使用 M/R 系列；高并发场景推荐 R 系列（CPU:内存=1:8）；追求性价比可用 r8g/r7g/r6g Graviton |
| 数据库-风险点4 | RDS | 存储类型选择不当导致延迟不满足要求 | 延迟敏感业务选择了 io1/gp3 | 推荐使用 io2 存储（支持在线磁盘类型转换）；或选择 Aurora 提供更低延迟；主从复制延迟敏感推荐 Aurora（基于 redo 的物理复制） |
| 数据库-风险点5 | Aurora/RDS | 版本选择问题 | 稳定性优先但选择了非 LTS 版本，每年需升级 | LTS 版本拥有至少三年生命周期；Aurora LTS 版本为 3.04（截至 2025/02）；RDS 用户可迁移到 Aurora LTS |

### 2.3 应用与运维

| 风险编号 | 适用服务 | 风险点 | 风险原因 | 改进建议 |
|---------|---------|--------|---------|---------|
| 数据库-风险点6 | RDS/Aurora | 应用程序未经过故障恢复性测试 | 线上异常时无法快速恢复 | 在测试环境进行 Failover 恢复性测试；Aurora 有更精细化的故障注入测试场景 |
| 数据库-风险点7 | 数据库客户端 | 程序端配置了本地 DNS 缓存 | Failover 时客户端不能及时感知新节点 | 关闭本地 DNS 缓存（注意 Java JVM 默认 DNS Cache）；使用 AWS Driver/RDS Proxy 加速感知；ElastiCache 集群模式配置客户端拓扑刷新 |
| 数据库-风险点8 | 数据库应用 | 应用程序未使用连接池 | 连接数过高或短时间大量新建连接影响性能 | 开启驱动侧连接池并配置合理超时/重连策略；驱动不支持连接池可使用 RDS Proxy |
| 数据库-风险点9 | 数据库 | 未开启慢查询日志或未定期优化 | 数据库性能下降甚至雪崩 | 开启慢查询日志定期分析优化；开启 Performance Insight 关注 Top SQL；控制单表数据量；大表场景上线前模拟数据量摸高测试 |
| 数据库-风险点10 | 数据库 | 未订阅资源相关告警信息 | 业务增长时未能及时扩容优化 | 订阅核心监控指标（CPU/内存/latency）；开启 Performance Insight 关注 Database Load 和 AAS；运维不足可使用 Serverless 自动伸缩 |
| 数据库-风险点11 | 数据库 | 对存储空间未进行合理评估 | 磁盘/内存数据被写满 | 订阅存储指标；RDS 开启磁盘自动扩展；ElastiCache 配置数据淘汰策略和 TTL；大容量使用集群模式+AutoScaling/Serverless；Aurora >128TB 可用 Limitless Database/DSQL |
| 数据库-风险点12 | 数据库 | 高峰期执行运维操作 | 版本强制升级等导致意外中断 | 及时关注版本生命周期通知主动升级；遵循升级最佳实践（准备/测试/方案设计/回滚）；关闭小版本自动升级；规划在业务低峰期操作；使用蓝绿部署减少中断 |
| 数据库-风险点13 | 数据库 | 未制定合理的数据恢复预案 | 数据误删除/丢失无法恢复 | RDS/Aurora/DocumentDB 使用 PITR 恢复到任意时间点；Aurora 开启 Backtrack 支持原集群恢复；AWS Backup 跨区域备份；MemoryDB 提供 AZ 故障 RPO=0 保护 |
| 数据库-风险点14 | 数据库 | 未对成本进行合理优化 | 成本超出预期 | 使用 Graviton 系列；使用 RI；波峰波谷明显考虑 Serverless；Aurora/DocumentDB IO 成本 >25% 考虑 IO Optimized；ElastiCache 迁移到 Valkey 节省 20%-33%；热数据 <20% 考虑数据分层 |

---

## 3. 容器类风险 (EKS)

### 3.1 集群与基础设施

| 风险编号 | 风险点 | 风险原因 | 改进建议 |
|---------|--------|---------|---------|
| EKS-风险点1 | EKS 集群所在区域故障 | 区域故障导致服务中断 | 在其他区域部署灾备集群，通过 Route 53 转移流量 |
| EKS-风险点2 | 工作节点未跨多可用区部署 | 单 AZ 故障导致服务中断 | 使用多节点组或跨 AZ 节点组；应用 Pod Topology Spread Constraints；启用 EKS Zonal Shift；定期混沌工程测试 |
| EKS-风险点3 | 可用区特定实例类型容量不足 | GPU 等特殊实例类型容量不足导致无法扩容 | 设置跨 AZ 节点组；利用 Karpenter 多实例类型选择能力；预留部分计算资源 |
| EKS-风险点4 | 子网 IP 地址不足 | 无法扩充节点或 Pod | 创建更大子网或在更大子网创建新节点组；使用 Custom Networking 拆分 Pod 和节点子网 |
| EKS-风险点5 | 控制平面升级导致不可用 | API Server 或集群组件不可用 | 更新前检查兼容性和审计日志；定期更新集群组件版本；使用蓝绿升级策略 |
| EKS-风险点6 | 控制平面超负荷 | 节点过多或 API 请求过多导致响应延迟 | 监测 API Server 指标优化请求方式（分页/减少 Watch）；高峰前开工单扩容控制平面；定期更新集群版本 |

### 3.2 集群组件

| 风险编号 | 风险点 | 风险原因 | 改进建议 |
|---------|--------|---------|---------|
| EKS-风险点7 | CoreDNS 服务异常 | CoreDNS 异常或超出 DNS PPS 限制导致域名解析失败 | CoreDNS 至少 2 副本跨 AZ 部署；利用 EKS Managed Addon 自动扩展；使用 Node-Local DNS；监控 CoreDNS 指标 |
| EKS-风险点8 | 集群其他组件异常（CSI 等） | 依赖组件异常导致 Pod 无法调度 | 配置 Liveness Probe 自动重启；监测组件日志和集群事件 |

### 3.3 节点与实例

| 风险编号 | 风险点 | 风险原因 | 改进建议 |
|---------|--------|---------|---------|
| EKS-风险点9 | EC2 实例故障无法自动恢复 | 实例停机/重启/网络维护导致不可用 | 使用托管节点组或 Karpenter 自动感知并修复；使用 Descheduler 快速驱逐 Pod；使用 Node Monitoring Agent 或 EKS Auto Mode |
| EKS-风险点10 | 节点资源预留不足 | 系统组件失去响应 | 持续监控节点资源；利用 Right-Sizing 工具配置 Pod Request/Limit；kubelet 配置增加资源预留 |
| EKS-风险点11 | 不正确的 sysctl 参数配置 | 节点性能下降或不稳定 | 尽可能不修改操作系统内核参数 |
| EKS-风险点12 | Spot 实例中断率高 | 不合适的实例类型配置 | 利用 Karpenter 扩展实例选择范围和多 AZ；基线工作负载选择按需实例或 Capacity Block |

### 3.4 Pod 与工作负载

| 风险编号 | 风险点 | 风险原因 | 改进建议 |
|---------|--------|---------|---------|
| EKS-风险点13 | Pod 单点故障 | Pod 所有副本在同一节点上 | 配置多副本；配置 Pod Anti-Affinity 或 Topology Spread Constraints |
| EKS-风险点14 | 持久化存储单点故障 | EBS 单点故障导致数据不可用 | 尽可能使用 EFS 共享存储；StatefulSet 配置 volumeClaimTemplates 并在应用层同步数据；定期快照备份 |
| EKS-风险点15 | Pod 无法应对重新调度 | 资源或 Spot 中断导致 Pod 重调度失败 | 评估应用是否适合 Kubernetes；启用 PreStop Lifecycle Hook 实现优雅终止 |
| EKS-风险点16 | Pod 缺乏健康检查机制 | 故障或滚动更新时无法自动恢复 | 配置 Liveness/Readiness 探针；设置 PDB 保证最小可用副本；启用 PreStop Hook 优雅终止 |
| EKS-风险点17 | Pod 间网络不稳定 | 请求失败或高延迟 | 应用配置重试机制（保证幂等）；利用服务网格统一实现路由和重试 |
| EKS-风险点18 | Pod 资源配置不合理 | 调度器无法正常工作导致资源浪费/争抢 | 利用 krr+Prometheus 等 right-sizing 工具配置 Request；利用 HPA+Karpenter 动态调整资源 |

---

## 4. 计算类风险 (EC2)

### 4.1 可观测性与故障感知

| 风险编号 | 风险点 | 风险原因 | 改进建议 |
|---------|--------|---------|---------|
| EC2-风险点1 | 缺乏对 EC2 实例底层维护的感知 | 无法感知停机/重启/网络维护事件 | 借助 EC2 Health Dashboard；使用 EC2 Health API 构建自动化脚本；AWS Health Event + EventBridge 构建事件驱动可观测；部署 AWS Health Aware 方案 |
| EC2-风险点2 | 缺乏对 EC2 实例底层故障的感知 | 无法感知底层故障 | 借助 CloudWatch 监控 Status Check Failed (system) 指标并指定触发操作 |

### 4.2 高可用与容量

| 风险编号 | 风险点 | 风险原因 | 改进建议 |
|---------|--------|---------|---------|
| EC2-风险点3 | 缺乏处理 EC2 单点故障的手段 | 单点故障无法自动恢复 | 优先使用 EC2 Auto Scaling 管理（内置健康检查和自动替换）；未使用 ASG 的启用 EC2 Auto Recovery；应用层启用高可用（如 Redis/Kafka 多副本） |
| EC2-风险点4 | 缺乏对 EC2 实例的运维测试手段 | 无法验证 HA/DR 方案 | 使用 AWS FIS 进行故障注入与模拟测试 |
| EC2-风险点5 | 缺乏有效容量规划 | 稳定重要业务缺乏容量预留 | 通过 ODCR 进行按需容量预留；使用 Future-dated Capacity Reservation；FOOB 流程作为补充 |
| EC2-风险点6 | 容量需求突增遇到 ICE 报错 | Insufficient Capacity Error | 提高灵活性（Instance → Geography → Time）；设置重试和指数回退；提早扩容、小步长、高频率 |

### 4.3 Spot 实例

| 风险编号 | 风险点 | 风险原因 | 改进建议 |
|---------|--------|---------|---------|
| EC2-风险点7 | Spot 中断率过高 | 实例类型/AZ 选择不够灵活 | 提高灵活性（实例家族/代系/规格/AZ）；使用 capacity-optimized/price-capacity-optimized 分配策略；借助 Spot Placement Score/Spot Instance Advisor/Attribute-based Instance Selection |
| EC2-风险点8 | 业务应用无法高效应对 Spot 中断 | 应用未做中断处理 | 评估应用是否适合 Spot（异步/高容错/Time Shiftable）；设置 Checkpoint/State Management；利用 CloudWatch Event 监听中断通知；借助 FIS 模拟 Spot 中断 |

### 4.4 成本优化

| 风险编号 | 风险点 | 风险原因 | 改进建议 |
|---------|--------|---------|---------|
| EC2-风险点9 | 实例选型不恰当导致成本增加 | 选型过大或过小 | 借助 Compute Optimizer/Cost Explorer 获取建议；突发型用 T 系列；迁移到最新一代实例；适配 Graviton 提高性价比；X86 可从 Intel 迁移到 AMD |
| EC2-风险点10 | 操作维护不当导致成本增加 | 已停止实例未终止等 | 借助控制台或 Trusted Advisor 查看停止实例；CloudWatch 监控 Status Check Failed 终止受损实例；Instance Scheduler 自动启停 |
| EC2-风险点11 | 未选择最佳实例购买选项 | 未使用 SP/RI/Spot | 稳定业务购买 Savings Plans；灵活无状态业务使用 Spot |
| EC2-风险点12 | 配置容量超过业务需求 | 资源浪费 | 使用 EC2 Auto Scaling 配置伸缩策略匹配业务需求 |

---

## 5. 网络类风险

### 5.1 Direct Connect

| 风险编号 | 风险点 | 风险原因 | 改进建议 |
|---------|--------|---------|---------|
| 网络-风险点1 | Direct Connect 单点风险 | 单条无备份/备份带宽不足/同一 AWS router/同一 pop 点 | 备份与主用带宽一致；选择不同 DX location；选择 VPN 作为备份 |
| 网络-风险点2 | Direct Connect 发生 gray failure 无法及时切换 | 缺乏端到端可见性，无法识别连接质量问题 | 使用 Network Synthetic Monitor 监控延迟和丢包；利用 NHI 快速定位根因；配置 CloudWatch 警报自动/手动切换；定期故障转移演练 |

### 5.2 VPN & SDWAN

| 风险编号 | 风险点 | 风险原因 | 改进建议 |
|---------|--------|---------|---------|
| 网络-风险点3 | Site-to-site VPN 单点风险 | 未配置冗余 tunnel | 利用 BGP 同时使用 2 条 tunnel（负载均衡模式）；创建 2 个 VPN connection（避免同时维护）；本地使用多台 VPN 路由器 |
| 网络-风险点4 | SDWAN 内部发生短时间断连 | TGW 底层维护导致 BGP session 中断 | 每个 connect peer 分别建立 2 个 BGP peering session（共 4 个） |

### 5.3 NAT Gateway

| 风险编号 | 风险点 | 风险原因 | 改进建议 |
|---------|--------|---------|---------|
| 网络-风险点5 | 使用 NAT Gateway 出公网连接失败 | 每个目标最多 55000 并发连接，超出后新连接失败 | 使用 NAT Gateway Multiple IP（最多 8 个 IP，并发提升到 440000） |

### 5.4 负载均衡

| 风险编号 | 风险点 | 风险原因 | 改进建议 |
|---------|--------|---------|---------|
| 网络-风险点6 | ALB 无法处理突增流量 | 突增流量超出 ALB 扩容能力 | 使用 Load Balancer Capacity Unit Reservation（预热）提前预留最低容量 |
| 网络-风险点7 | ALB 的 IP 地址无法固定 | 底层 EC2 扩缩容导致 IP 变化 | 客户端必须使用 DNS 连接 ALB（遵循 TTL=1 分钟）；如必须固定 IP 使用 ALB-type Target Group for NLB |
| 网络-风险点8 | 使用 NLB 做长连接会发生超时 | NLB TCP timeout 默认 350 秒 | 将 NLB TCP 空闲超时配置为 60-6000 秒之间的合适值 |
| 网络-风险点9 | 使用 GWLB+第三方防火墙时有 50% 概率丢包 | 单 AZ 部署防火墙或防火墙故障 | 开启 GWLB cross-zone load balancing；结合 TGW 做东西向检查时开启 appliance mode |

### 5.5 网络监控

| 风险编号 | 风险点 | 风险原因 | 改进建议 |
|---------|--------|---------|---------|
| 网络-风险点10 | 应用性能下降 TCP 连接超时 | 无法快速定位是网络还是应用问题 | 使用 Network Flow Monitor 的 NHI 快速区分；监控 Retransmissions 和 Timeouts 指标；设置 CloudWatch 警报 |

---

## 6. 评估检查清单

在进行韧性评估时，针对每个服务类型，按以下检查清单逐项确认：

### 存储检查清单
- [ ] EBS 存储类型是否匹配业务 I/O 需求（gp3 vs io2）
- [ ] EBS Volume 是否有定期备份策略（DLM/AWS Backup）
- [ ] 从 Snapshot 恢复的 Volume 是否启用了 FSR
- [ ] 是否进行过 EBS I/O 故障模拟测试（FIS）
- [ ] EC2 实例 I/O 性能上限是否满足多 Volume 需求
- [ ] S3 是否开启了 Versioning
- [ ] S3 高并发场景是否做了 prefix 打散
- [ ] EFS 吞吐模式是否匹配使用模式
- [ ] FSx 维护窗口是否设置在业务低谷

### 数据库检查清单
- [ ] 生产环境是否使用 Multi-AZ 架构
- [ ] 是否有跨 Region 容灾方案（如需要）
- [ ] 生产环境是否避免使用 T 系列机型
- [ ] 存储类型是否满足延迟要求
- [ ] 是否选择了合适的数据库版本（LTS vs 非 LTS）
- [ ] 是否进行过 Failover 恢复性测试
- [ ] 客户端是否关闭了本地 DNS 缓存
- [ ] 应用是否使用了连接池
- [ ] 是否开启了慢查询日志和 Performance Insight
- [ ] 是否订阅了核心监控告警
- [ ] 存储空间是否有自动扩展或告警
- [ ] 运维操作是否安排在低峰期
- [ ] 是否有数据恢复预案（PITR/Backtrack/跨区域备份）
- [ ] 成本是否经过优化评估

### EKS 检查清单
- [ ] 是否有跨区域灾备集群
- [ ] 工作节点是否跨多 AZ 部署
- [ ] 是否配置了多实例类型应对容量不足
- [ ] 子网 IP 地址是否充足
- [ ] 控制平面升级是否有兼容性验证流程
- [ ] 控制平面是否有负载监控
- [ ] CoreDNS 是否多副本跨 AZ 部署
- [ ] 集群组件是否配置了健康检查
- [ ] 节点故障是否能自动恢复（托管节点组/Karpenter）
- [ ] 节点资源预留是否充足
- [ ] Spot 实例是否配置了多实例类型和多 AZ
- [ ] Pod 是否配置了多副本和反亲和性
- [ ] 持久化存储是否有备份策略
- [ ] Pod 是否配置了 Liveness/Readiness 探针
- [ ] Pod 是否配置了 PDB 和优雅终止
- [ ] Pod 资源 Request/Limit 是否合理

### EC2 检查清单
- [ ] 是否有 EC2 底层维护事件的感知手段
- [ ] 是否有 EC2 底层故障的感知手段
- [ ] 是否使用 Auto Scaling 或 Auto Recovery 处理单点故障
- [ ] 是否使用 FIS 进行过运维测试
- [ ] 稳定业务是否有容量预留（ODCR）
- [ ] 是否有 ICE 报错的应对策略
- [ ] Spot 实例是否配置了灵活的实例选择
- [ ] 应用是否能高效应对 Spot 中断
- [ ] 实例选型是否经过优化
- [ ] 是否有自动启停策略避免浪费
- [ ] 是否选择了最佳购买选项（SP/RI/Spot）

### 网络检查清单
- [ ] Direct Connect 是否有冗余（不同 DX location）
- [ ] Direct Connect 是否有 gray failure 检测手段
- [ ] VPN 是否配置了冗余 tunnel
- [ ] NAT Gateway 是否跨 AZ 部署
- [ ] NAT Gateway 并发连接是否满足需求
- [ ] ALB 是否有预热策略应对突增流量
- [ ] NLB TCP 超时是否配置合理
- [ ] GWLB 是否开启了 cross-zone load balancing
- [ ] 是否有网络性能监控手段（Network Flow Monitor）

---

## 7. 生成式 AI 类风险（Amazon Bedrock）

| 风险编号 | 风险点 | 风险原因 | 改进建议 |
|---------|--------|---------|---------|
| Bedrock-风险点1 | 模型端点限流 | 推理高峰期 API 返回 429 错误 | 实现客户端指数退避重试；申请配额增加；关键工作负载使用 Provisioned Throughput |
| Bedrock-风险点2 | 单区域模型可用性 | 目标区域中模型版本不可用 | 预先验证跨区域模型可用性；使用 Amazon Bedrock 跨区域推理实现跨区域回退 |
| Bedrock-风险点3 | 模型响应延迟飙高 | 面向用户的延迟 SLA 违约 | 设置客户端超时；实现流式响应；在适用场景使用模型缓存 |
| Bedrock-风险点4 | Token 配额耗尽 | 批处理任务执行中途失败 | 通过 CloudWatch 监控 Token 使用量；为批处理任务实现断路器；预先计算 Token 需求 |

## 8. 流处理类风险（Amazon MSK）

| 风险编号 | 风险点 | 风险原因 | 改进建议 |
|---------|--------|---------|---------|
| MSK-风险点1 | Broker 故障 | 分区领导权重平衡，临时延迟增加 | 多 AZ 部署（至少 3 个 Broker 跨 3 个 AZ）；配置 `min.insync.replicas=2`、`replication.factor=3` |
| MSK-风险点2 | 分区重平衡风暴 | 消费者组不稳定，重复处理 | 调优 `session.timeout.ms` 和 `max.poll.interval.ms`；使用静态组成员；实现幂等消费者 |
| MSK-风险点3 | 存储耗尽 | Broker 变为不健康状态，停止接受写入 | 启用自动扩展存储；设置 `KafkaDataLogsDiskUsed` CloudWatch 告警；配置日志保留策略 |
| MSK-风险点4 | ZooKeeper 仲裁丢失（KRaft 之前） | 集群元数据操作失败 | 使用 KRaft 模式（MSK 3.7+）或确保 3 节点 ZK 集群；传统集群监控 ZK 延迟 |

## 9. 搜索类风险（Amazon OpenSearch Service）

| 风险编号 | 风险点 | 风险原因 | 改进建议 |
|---------|--------|---------|---------|
| OpenSearch-风险点1 | 蓝绿部署性能影响 | 部署期间查询延迟临时增加 | 在非高峰期安排部署；使用专用主节点；更新期间监控 `SearchLatency` 和 `IndexingLatency` |
| OpenSearch-风险点2 | 分片不均衡/热点 | 资源利用不均匀，查询超时 | 使用索引生命周期策略；配置分片分配 AZ 感知；监控每节点 `JVMMemoryPressure` |
| OpenSearch-风险点3 | 快照恢复失败 | 灾难期间数据恢复受阻 | 定期快照测试；跨区域快照复制；定期验证恢复时间 |
| OpenSearch-风险点4 | 搜索查询过载（噪声邻居） | 集群范围性能下降 | 实现请求限流；对低频数据使用 UltraWarm 层；配置断路器设置 |

## 10. 工作流类风险（AWS Step Functions）

| 风险编号 | 风险点 | 风险原因 | 改进建议 |
|---------|--------|---------|---------|
| StepFunctions-风险点1 | 长时间执行超时 | Standard Workflow 最长 1 年；Express 最长 5 分钟 | 长流程使用 Standard Workflow；实现检查点以支持可恢复工作流 |
| StepFunctions-风险点2 | 故障时状态数据丢失 | 工作流进度丢失，需从头重新开始 | 实现幂等 Activity；将中间状态存储在 DynamoDB；使用 Step Functions 执行历史进行重放 |
| StepFunctions-风险点3 | Activity Worker 故障 | 任务卡在"等待 Activity"状态 | 设置心跳和任务超时；实现 Worker 自动扩展；监控 `ActivitiesTimedOut` 指标 |
| StepFunctions-风险点4 | 突发期间限流 | 状态转换因 ThrottlingException 失败 | 申请配额增加；实现退避重试；将大型工作流拆分为子工作流 |
