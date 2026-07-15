# 薄弱点检查目录（Weakness Catalog）

> **这是本 skill 的核心价值。** 针对 EKS 上自建有状态中间件的分布式韧性薄弱点，逐组件给出检查项。
> 每项检查：**做什么 / 从 bundle 看哪里 / PASS 判据 / 典型 FAIL 修复 / 严重级别**。
> 严重级别与评分见 [risk-scoring_zh.md](risk-scoring_zh.md)。

## 检查结果统一结构

```json
{
  "id": "KA2",
  "component": "kafka-events",
  "name": "Topic 副本因子 (replication.factor)",
  "family": "kafka",
  "severity": "critical",
  "status": "FAIL",
  "evidence": "components/kafka-topics.json: topic 'orders' rf=1",
  "resources_affected": ["topic/orders", "topic/payments"],
  "impact": "任一 broker 或其所在 AZ 故障即永久丢失该 topic 全部数据",
  "remediation": "将业务 topic 的 replication.factor 提升到 ≥3，并设置 min.insync.replicas=2",
  "fixImpact": {"downtime": 0, "slowness": 1, "additionalCost": 1, "needFullTest": 0},
  "chaos_experiment_recommendation": {"fault_type": "az_network_disrupt", "priority": "P0"}
}
```

状态取值：`PASS` / `FAIL` / `WARN` / `NOT_APPLICABLE` / `UNKNOWN`（无证据，禁止推测）/ `UNABLE_TO_ASSESS`（bundle 缺证据，理论上可补采）。

---

## ⚠️ 硬规则：证据等级与禁止推测（违反此节 = 分析失败，必须重做）

> 本节是本 skill 最重要的行为约束。历史上曾出现过"用 Name tag 字符串匹配拼凑出完整组件角色/副本关系/拓扑感知结论"的错误分析（例如把 3 台叫 `tikv-source-N` 的机器直接判定为"3 副本 TiKV 集群，AZ 分布良好"，把 `cdcmon-*` 编造成"TiCDC 复制监控组件"并画进数据流图）。**这种拼凑必须杜绝。**

### 证据分为四级，严禁跨级下结论

| 等级 | 定义 | 能支撑的结论 | 典型来源 |
|------|------|-------------|---------|
| **CONFIRMED** | 主机层证据：进程列表、配置文件内容、`pd-ctl`/`tiup`/`redis-cli`/`kafka-topics --describe` 等只读命令的直接输出 | 组件**确实在运行**、副本关系**确实存在**、配置参数的**确实值** | SSH/SSM 到主机执行的只读命令 |
| **DECLARED** | 云资源侧的声明性元数据：云厂商标签（如 `tidb-poc:role=tikv`）、CloudFormation/Terraform 元数据、Operator CR 的 spec 字段 | 部署时**声明的意图**——即"有人打算部署/配置成这样" | `describe-instances` 的 Tags、CFN stack、K8s CR spec |
| **INFERRED_FROM_NAME** | 仅靠资源命名字符串模式匹配（如实例名含 "tikv"、StatefulSet 名含 "redis"） | **仅能提示"值得进一步用 DECLARED/CONFIRMED 证据核实的方向"**，本身不能作为任何检查结果的依据 | Name tag、StatefulSet/Pod 名称 |
| **UNKNOWN** | 无任何以上证据 | 不能支撑任何结论 | — |

### 强制规则

1. **每条 finding 必须标注其证据等级**，并在 `evidence` 字段写清楚具体来源（哪个文件、哪个字段），不能只写"根据命名判断"。
2. **INFERRED_FROM_NAME 单独存在时，不得写成 PASS/FAIL 结论**，只能用于：①决定要不要跑某个检查族（如"看起来有 tikv → 值得跑 TI 族检查"）；②在报告里提示"存在同名模式，但未经标签/主机验证"。
3. **DECLARED 证据不能升级为 CONFIRMED 的表述**。例如：标签写了 `role=tikv` 且有 3 台同批次机器，只能写"3 台机器被声明为 tikv 角色"，**不能写"3 副本 TiKV 集群"**（"副本"暗示了已验证的集群关系，这是过度引申）。同理：EC2 物理跨 3 AZ ≠ "该组件已实现跨 AZ 高可用"，后者还依赖调度层是否感知 AZ（如 TiKV `location-labels`、Kafka `rack awareness`），这类配置**只能来自主机层证据**。
4. **组件的"角色故事"不能脑补**。看到 `cdcmon`、`ops`、类似缩写标签时，若无法从证据链确认其具体功能，**如实写"标签声明为 X，具体功能未知"**，不要因为字面像某个技术术语就编出一整套工作原理、数据流方向、依赖关系。
5. **未观测到 ≠ 已确认不存在**。例如没找到 `pd-*` 命名或 `role=pd` 标签的实例，只能写"未观测到 PD 相关证据"，**不能写"PD 是单点"或"没有 PD"**——正确的做法是标 `UNKNOWN` 并说明这是决定性缺口，建议如何补证据。
6. **不给"整体是否合格"的结论，除非支撑它的每一个子项都有对应证据等级**。如果决定性检查项（PD 拓扑、副本真实性、location-labels/rack awareness 等）是 UNKNOWN，那么"该系统能否容忍 AZ 故障"这一类汇总结论也必须是 UNKNOWN，不能因为部分物理层指标好看就给出正面结论，也不能因为看着像有问题就给负面结论——两个方向的过度引申都是拼凑。
7. **报告与拓扑图必须让读者看出证据等级**（如用不同颜色/线型区分 CONFIRMED/DECLARED/UNKNOWN），不能用一张"看起来完整、确定"的图掩盖背后大量未经验证的假设。
8. **裸 EC2 底座是 INFERRED_FROM_NAME → DECLARED 陷阱高发区**：Name tag 本身只是 `INFERRED_FROM_NAME`；若同时能拿到云资源标签/CFN 元数据（如 `collect-ec2.sh` 采集的 `allTags`），才能升级到 `DECLARED`——采集与分析时都要检查 `allTags` 是否有比 Name tag 更强的证据，而不是只看 Name tag 就下笔。

### 自检清单（写每条 finding 前问自己）

- [ ] 这条结论的证据字段具体指向 bundle 里的哪个文件、哪个字段？能不能给别人复现？
- [ ] 如果只有 Name tag/命名模式，我是不是在暗示"已验证"的语气（如用了"3 副本""跨 AZ 高可用""XX 组件"这类确定性措辞）？
- [ ] 我是否把"部署声明"（DECLARED）写成了"运行事实"（CONFIRMED）？
- [ ] 我是否因为找不到某组件就直接下"不存在/是单点"的结论，而不是标 UNKNOWN？
- [ ] 我是否为了让报告看起来完整，给未经验证的字段编了具体数值/角色/关系？

---

## 承载底座映射（EKS-pod vs 裸 EC2）

检查目录**同时适用两种底座**，字段来源不同，且证据等级不同：

| 概念 | EKS-pod 底座 | 裸 EC2 底座（Name tag + 标签） |
|------|-------------|------------------------|
| 一个组件集群 | StatefulSet / Operator CR（DECLARED：spec 声明；Pod 实际 Running 状态才是 CONFIRMED） | `nametag-groups.json` 的一个 clusterKey——**默认只是 INFERRED_FROM_NAME**；若能从 `allTags` 读到云标签（如 `tidb-poc:role`）则升级为 DECLARED |
| 副本数 | `.spec.replicas`（DECLARED，需 Pod Running 才 CONFIRMED） | 该组实例数（DECLARED 上限，不能称"副本"——除非有主机层证据证明它们确实组成同一逻辑集群） |
| AZ 分布 | Pod→node→zone label（CONFIRMED，K8s API 直接返回） | 组内成员的 `azSpread`（CONFIRMED，AWS API 直接返回的物理位置，但不代表调度层感知） |
| 存储 | PVC→PV→EBS/StorageClass（CONFIRMED） | 实例 `blockDevices` → `volumes.json`（CONFIRMED，但是否被中间件正确使用未知） |
| 反亲和/host 分散 | `podAntiAffinity`（DECLARED：spec 配置） | 成员天然是不同 EC2 实例（CONFIRMED 物理隔离，但不代表应用层已配置容错） |

> **裸 EC2 的固有盲区**：主机内配置（PD 仲裁数、TiKV `location-labels`、副本因子、`min.insync.replicas`、备份、复制模式、进程是否真的在跑）**无法通过 AWS 只读 API 获取**，只能停留在 DECLARED 或更低等级。这类检查在裸 EC2 底座上必须标 `UNKNOWN`（如果完全没有云标签支撑）或至少不越级为 PASS/FAIL 的确定性结论，并建议在 ops/bastion 主机上只读补采（`pd-ctl`/`tiup`/`redis-cli info`/`kafka-topics --describe`）。纯物理层检查（实例数量、AZ 物理分布、EBS 配置、安全组规则）可以从 AWS 元数据给出 CONFIRMED 结论，但**必须在措辞上明确这只是物理层事实，不代表应用层已生效**。

---

# P — 平台层通用检查（适用于所有中间件）

### P1 — 副本数 ≥ 2（消除单实例 SPOF）　🔴 CRITICAL
- **看**：该组件每个有状态角色的 `replicas`（CR 或 statefulsets.json）。
- **PASS**：所有数据面角色副本 ≥ 2（仲裁类角色见各专项，通常 ≥3 奇数）。
- **FAIL 修复**：提升副本数；单实例数据库必须至少配主从。

### P2 — 跨 AZ 分布（消除单 AZ 命运共担）　🔴 CRITICAL
- **看**：`inventory` 中该角色的 `azSpread`（每 AZ 副本数）。
- **PASS**：副本分散在 ≥2（理想 3）个 AZ，且无单一 AZ 承载 > ⌈N/2⌉ 副本（否则该 AZ 挂即失去多数）。
- **FAIL 修复**：配置 `topologySpreadConstraints`（`topologyKey: topology.kubernetes.io/zone`, `maxSkew: 1`）或跨 AZ 反亲和；确保各 AZ 有对应节点池。
- **注意**：这是自建中间件最常见的致命薄弱点——副本数够但全落一个 AZ。

### P3 — Pod 反亲和（消除单节点命运共担）　🟠 HIGH
- **看**：`spec.template.spec.affinity.podAntiAffinity`（同 app 的 Pod 不落同一节点）。
- **PASS**：多副本有状态角色配置了 `requiredDuringScheduling`（强制）或至少 `preferred` 的节点级反亲和。
- **FAIL 修复**：加 `podAntiAffinity`，`topologyKey: kubernetes.io/hostname`。

### P4 — PodDisruptionBudget　🟠 HIGH
- **看**：`k8s/poddisruptionbudgets.json` 是否覆盖该组件；`minAvailable`/`maxUnavailable` 是否合理。
- **PASS**：每个中间件有 PDB，且 `maxUnavailable=1`（或 `minAvailable = N-1`），避免节点排空/升级时同时驱逐多个副本。
- **FAIL 修复**：为每个有状态集加 PDB。仲裁类务必保证不会一次驱逐到失去多数。

### P5 — 存储类与卷拓扑　🟠 HIGH
- **看**：`storageclasses.json` 的 `volumeBindingMode`、`allowedTopologies`；PV 的 AZ 亲和。
- **PASS**：使用 `volumeBindingMode: WaitForFirstConsumer`（避免卷在 Pod 之前绑定到错误 AZ）；EBS 卷类型为 gp3/io2（非 gp2/sc1/st1 做数据库）。
- **FAIL 修复**：改用 WaitForFirstConsumer；数据库卷升级到 gp3/io2 并按 IOPS 需求配置。
- **注意**：EBS 是**单 AZ** 资源。Pod 重调度到其它 AZ 时无法挂载原卷——跨 AZ 高可用**必须靠应用层复制**，不能靠卷迁移。

### P6 — 资源 requests/limits 与 QoS　🟡 MEDIUM
- **看**：容器 `resources.requests/limits`；events.json 中的 `OOMKilled`。
- **PASS**：数据面容器设置了 memory `requests==limits`（Guaranteed QoS，避免被驱逐）；CPU request 合理。
- **FAIL 修复**：为中间件设 Guaranteed QoS；关键组件配 `PriorityClass` 防止被抢占。

### P7 — 健康探针　🟡 MEDIUM
- **看**：`livenessProbe` / `readinessProbe` / `startupProbe`。
- **PASS**：有 readiness（避免流量打到未就绪副本）；有 startup（慢启动组件如 Kafka/TiKV 避免被 liveness 误杀）。
- **FAIL 修复**：补探针。数据库/大状态组件优先 `startupProbe` + 保守 `livenessProbe`，避免恢复期间被反复重启。

### P8 — 备份存在性　🔴 CRITICAL（数据库） / 🟠 HIGH（缓存/队列）
- **看**：备份 CR（`tidb-backups.json`）、CronJob、或配置中的备份策略；有无备份目标（S3）。
- **PASS**：持久化数据组件有**自动**备份 + 明确保留策略 + 验证过恢复。
- **FAIL 修复**：建立定时备份到 S3（跨 AZ/跨区域），并定期演练恢复。副本 ≠ 备份（逻辑错误/误删会同步到所有副本）。

### P9 — 监控与告警覆盖　🟡 MEDIUM
- **看**：`mon-servicemonitors.json` / `mon-prometheusrules.json` 是否覆盖该组件；exporter sidecar。
- **PASS**：每个中间件有指标采集 + 关键告警（副本不健康、复制延迟、磁盘水位、仲裁丢失）。
- **FAIL 修复**：部署对应 exporter + 告警规则。

---

# MY — MySQL 专项

### MY1 — 部署形态与单写点　🔴 CRITICAL
- **看**：CR 类型 / 副本数 / `server_id` / 复制配置。判定：单实例 / 主从异步 / 半同步 / MGR / PXC。
- **PASS**：生产使用主从（≥1 从）或 MGR/PXC 多主；**非单实例**。
- **FAIL 修复**：单实例 → 至少配一主一从 + 自动故障切换。

### MY2 — 自动故障切换机制　🔴 CRITICAL
- **看**：是否有 Operator（MOCO/Oracle/PXC 自带切换）或 Orchestrator/MHA；裸主从往往**无自动切换**。
- **PASS**：主库故障能自动选新主并重定向写流量（Operator 或 orchestrator 管理）。
- **FAIL 修复**：引入 Operator 或 orchestrator；避免依赖人工切换（RTO 不可控）。

### MY3 — 复制模式（数据丢失风险）　🟠 HIGH
- **看**：`rpl_semi_sync_master_enabled`、`sync_binlog`、MGR 的 `group_replication_consistency`。
- **PASS**：对不可丢数据的业务启用**半同步**或 MGR（同步）；`sync_binlog=1` + `innodb_flush_log_at_trx_commit=1`。
- **FAIL 修复**：异步复制在主库宕机时会丢失未同步 binlog → 按 RPO 要求升级为半同步。

### MY4 — 主从跨 AZ　🔴 CRITICAL
- **看**：主 Pod 与从 Pod 的 `azSpread`。
- **PASS**：主、从分处不同 AZ。
- **FAIL 修复**：主从同 AZ = AZ 故障丢失整套 → 调度到不同 AZ。

### MY5 — 连接层 / 读写分离入口　🟠 HIGH
- **看**：`services.json` 是否有独立的 writer/reader Service；是否用 ProxySQL/Vitess。
- **PASS**：应用通过稳定的 writer endpoint 连接，故障切换后 endpoint 自动指向新主（headless + Operator 更新，或 proxy）。
- **FAIL 修复**：避免应用硬编码 Pod IP/单 Pod DNS；引入 writer/reader Service 或 proxy。

### MY6 — Binlog 与 GTID　🟡 MEDIUM
- **看**：`log_bin`、`gtid_mode=ON`、`enforce_gtid_consistency`。
- **PASS**：开启 binlog + GTID（便于安全切换与恢复）。
- **FAIL 修复**：开启 GTID 复制。

### MY7 — 备份 + PITR　🔴 CRITICAL
- **看**：全量备份（xtrabackup/mysqldump）+ binlog 归档到 S3。
- **PASS**：定时全量 + binlog 增量，可 PITR，异地留存。
- **FAIL 修复**：建立备份 + binlog 归档；演练恢复。

### MY8 — 存储与 IOPS　🟡 MEDIUM
- **看**：数据卷 storageClass/EBS 类型/大小；`events` 有无磁盘压力。
- **PASS**：gp3/io2，IOPS 满足峰值，预留增长空间。
- **FAIL 修复**：升级卷类型/容量；配置磁盘使用率告警。

---

# TI — TiDB / TiKV / PD 专项

### TI1 — PD 仲裁（奇数 ≥ 3）　🔴 CRITICAL
- **看**：`tidb-tidbclusters.json` `.spec.pd.replicas`。
- **PASS**：PD 副本为奇数且 ≥3（3 或 5）。PD 是元数据/调度大脑，丢失多数 = 集群不可用。
- **FAIL 修复**：PD=1 或 2 → 提升到 3；偶数 → 调为奇数。

### TI2 — PD 跨 AZ 分布　🔴 CRITICAL
- **看**：PD 三副本的 `azSpread`。
- **PASS**：PD 分处 3 个 AZ（3 副本时每 AZ 1 个）。
- **FAIL 修复**：任一 AZ 含 ≥2 个 PD → 该 AZ 挂即失去多数 → 重新分布到 3 AZ。

### TI3 — TiKV 副本数（max-replicas）　🔴 CRITICAL
- **看**：`.spec.tikv.replicas` 与 PD 配置 `replication.max-replicas`（默认 3）。
- **PASS**：TiKV 实例数 ≥ `max-replicas`（≥3），使每个 Region 的多副本能分散。
- **FAIL 修复**：TiKV < 3 → 扩到至少 3；否则 Region 无法满足副本数，冗余失效。

### TI4 — location-labels 与 TiKV 拓扑感知　🔴 CRITICAL
- **看**：PD `.spec.pd.config` 的 `replication.location-labels`（应含 `zone`/`host`）；TiKV Pod 的 `--labels` 是否带真实 zone。
- **PASS**：配置了 location-labels 且 TiKV 标注了 zone → PD 会把同一 Region 的 3 副本强制分散到不同 AZ。
- **FAIL 修复**：**这是 TiDB 最关键也最常被忽略的一项**。未配 location-labels 时，即使 TiKV 跨 AZ，PD 也可能把一个 Region 的 3 副本放进同一 AZ → AZ 挂即丢该 Region。必须配 `location-labels=["zone","host"]` 并给 TiKV 打 zone 标签。

### TI5 — TiKV 反亲和　🟠 HIGH
- **看**：TiKV StatefulSet 的 podAntiAffinity（host 级）。
- **PASS**：TiKV 不同副本不落同一节点。
- **FAIL 修复**：加 host 级反亲和，避免单节点故障影响多个 TiKV。

### TI6 — TiDB-Server 无状态多副本　🟠 HIGH
- **看**：`.spec.tidb.replicas` 与其 AZ 分布。
- **PASS**：TiDB-Server ≥2 且跨 AZ（无状态，可水平扩展，是 SQL 入口）。
- **FAIL 修复**：单 TiDB-Server → 扩副本 + 跨 AZ + 前置负载均衡。

### TI7 — 备份（BR / Backup CR）　🔴 CRITICAL
- **看**：`tidb-backups.json` / `tidb-backupschedules.json`；是否备份到 S3。
- **PASS**：有定时 BR 备份到 S3 + 保留策略。
- **FAIL 修复**：配置 BackupSchedule 到 S3。

### TI8 — PD/TiKV 存储类型　🟡 MEDIUM
- **看**：TiKV/PD 数据卷 storageClass（应为 SSD gp3/io2/本地 NVMe）。
- **PASS**：TiKV 使用高 IOPS SSD；`WaitForFirstConsumer`。
- **FAIL 修复**：升级到 gp3/io2；高性能场景考虑 local NVMe + 副本冗余。

### TI9 — TiKV 副本数与 PD 调度健康　🟡 MEDIUM
- **看**：events / metrics 中 TiKV OOM、Region 不健康、store 下线。
- **PASS**：无长期 down store / 无 pending Region。
- **FAIL 修复**：排查资源不足或调度限制。

---

# RD — Redis 专项

### RD1 — 部署形态（禁止裸单点）　🔴 CRITICAL
- **看**：单点 / 主从 / 哨兵 / Cluster（CR mode 或 sentinel Pod / cluster-enabled）。
- **PASS**：生产为哨兵主从或 Redis Cluster；**非单点**。
- **FAIL 修复**：单点 → 至少主从 + 哨兵，或迁移到 Redis Cluster。

### RD2 — 自动故障切换（哨兵 quorum / Cluster）　🔴 CRITICAL
- **看**：哨兵副本数与 `quorum`；Cluster 模式的 master 数。
- **PASS**：哨兵 ≥3 且 `quorum` 合理（多数）；Cluster 每分片有 ≥1 副本且 master ≥3。
- **FAIL 修复**：哨兵不足 3 或 quorum 配置错误 → 无法可靠选主。补足哨兵、修正 quorum。

### RD3 — 主从跨 AZ / 哨兵跨 AZ　🔴 CRITICAL
- **看**：master/replica/sentinel 的 `azSpread`。
- **PASS**：主从分处不同 AZ；哨兵分处 3 个 AZ（否则一个 AZ 挂即失去哨兵多数，无法选主）。
- **FAIL 修复**：分散到多 AZ。哨兵全在一个 AZ 是常见隐患。

### RD4 — 持久化（RDB/AOF）　🟠 HIGH
- **看**：`redis.conf` 的 `appendonly`、`save`、`appendfsync`。
- **PASS**：按数据重要性开启 AOF（`appendfsync everysec` 或 `always`）或 RDB+AOF。
- **FAIL 修复**：纯内存无持久化 → 全副本重启即全部丢失。开启 AOF。
- **注意**：若 Redis 仅作纯缓存（可从源重建），可标 `NOT_APPLICABLE` 并注明，但需与用户确认。

### RD5 — maxmemory 与淘汰策略　🟡 MEDIUM
- **看**：`maxmemory`、`maxmemory-policy`；容器 memory limit。
- **PASS**：`maxmemory` 设置且 < 容器 limit（留出开销）；淘汰策略符合业务（缓存 `allkeys-lru`，持久数据 `noeviction`）。
- **FAIL 修复**：未设 maxmemory → 可能 OOMKilled。设置并配合 QoS。

### RD6 — Cluster 分片冗余　🟠 HIGH（仅 Cluster 模式）
- **看**：每个分片 master 是否都有 replica；分片数。
- **PASS**：每个 master 至少 1 replica 且跨 AZ；无孤立 master。
- **FAIL 修复**：为每个分片补 replica。孤立 master 挂 = 该分片槽位不可用，整集群写受影响。

### RD7 — 客户端连接与故障切换感知　🟡 MEDIUM
- **看**：应用是否走哨兵/Cluster 感知客户端，还是直连单 Pod。
- **PASS**：客户端通过哨兵发现主，或用 Cluster-aware 客户端。
- **FAIL 修复**：避免硬编码 master IP；用哨兵/Cluster 客户端。

---

# KA — Kafka 专项

### KA1 — Broker 数量与跨 AZ　🔴 CRITICAL
- **看**：`.spec.kafka.replicas` 与 broker `azSpread`。
- **PASS**：Broker ≥3 且分处 3 个 AZ。
- **FAIL 修复**：<3 broker 或未跨 AZ → 扩容并分散。

### KA2 — Topic 副本因子 replication.factor　🔴 CRITICAL
- **看**：`kafka-topics.json` 各 topic 的 rf；集群 `default.replication.factor`。
- **PASS**：业务 topic 与内部 topic（`__consumer_offsets`、事务日志）rf ≥3。
- **FAIL 修复**：rf=1 → 任一 broker/AZ 挂即永久丢该 topic 数据。提升到 3（需分区重分配）。

### KA3 — min.insync.replicas + acks　🔴 CRITICAL
- **看**：集群/topic 的 `min.insync.replicas`；生产者 `acks`（若可得）。
- **PASS**：`min.insync.replicas=2`（rf=3 时）且生产者 `acks=all` → 保证已确认消息至少写入 2 副本。
- **FAIL 修复**：`min.insync.replicas=1` 或 `acks=1` → AZ 故障可能丢已确认消息。设为 2 + acks=all。
- **注意**：`min.insync.replicas` 必须 < rf，否则单副本故障即阻塞写入。rf=3 + minISR=2 是黄金组合。

### KA4 — Rack Awareness（broker.rack = AZ）　🔴 CRITICAL
- **看**：`.spec.kafka.rack.topologyKey` 或 `broker.rack` 配置。
- **PASS**：启用 rack awareness 且 rack=AZ → Kafka 把同一分区的副本强制分散到不同 AZ。
- **FAIL 修复**：**与 TI4 同理**——未配 rack awareness 时，即使 broker 跨 AZ，同一分区的 3 副本也可能落在同一 AZ → AZ 挂即丢分区。启用 rack awareness（Strimzi `.spec.kafka.rack`）。

### KA5 — 协调层仲裁（ZooKeeper / KRaft）　🔴 CRITICAL
- **看**：ZooKeeper 模式 → zk 副本数与 AZ 分布；KRaft 模式 → controller quorum 数与分布。
- **PASS**：ZooKeeper/KRaft controller 为奇数 ≥3 且跨 3 AZ。
- **FAIL 修复**：zk/controller <3 或未跨 AZ 或偶数 → 修正。失去协调层多数 = 整个 Kafka 不可用。

### KA6 — 内部 topic 副本因子　🟠 HIGH
- **看**：`offsets.topic.replication.factor`、`transaction.state.log.replication.factor`、`transaction.state.log.min.isr`。
- **PASS**：均 ≥3（minISR ≥2）。
- **FAIL 修复**：内部 topic rf=1 → 消费位点/事务状态易丢。提升 rf。

### KA7 — 磁盘水位与保留策略　🟠 HIGH
- **看**：`log.retention.*`、卷大小、events/metrics 磁盘压力。
- **PASS**：保留策略与卷容量匹配，有磁盘使用率告警。
- **FAIL 修复**：Kafka 磁盘满会导致 broker 宕机。配置保留 + 扩容 + 告警。

### KA8 — 分区/Leader 均衡与反亲和　🟡 MEDIUM
- **看**：broker podAntiAffinity（host 级）；是否启用自动 leader 再均衡 / Cruise Control。
- **PASS**：broker 不落同一节点；leader 分布均衡。
- **FAIL 修复**：加反亲和；考虑 Cruise Control（Strimzi KafkaRebalance）。

---

# X — 跨组件 / 系统级检查

### X1 — 全栈 AZ 故障爆炸半径　🔴 CRITICAL
- **看**：综合所有组件的 `azSpread`，逐 AZ 模拟失效。
- **PASS**：任一 AZ 整体失效后，所有中间件仍**可用且不丢已确认数据**。
- **FAIL 修复**：列出每个"AZ 挂即不可用/丢数据"的组件，按 P2/TI2/TI4/RD3/KA4/KA5 逐一修复。详见 [risk-scoring_zh.md](risk-scoring_zh.md) 的爆炸半径矩阵。

### X2 — 共享节点池的命运共担　🟠 HIGH
- **看**：多个中间件是否挤在同一批节点（`nodeName` 重叠）；是否用 nodeSelector/taint 隔离。
- **PASS**：关键有状态组件有独立节点池或至少不与高风险负载共节点。
- **FAIL 修复**：用 taint/toleration + nodeSelector 隔离数据面；避免一个节点挂同时影响多个中间件。

### X3 — 单一网关 / NAT / 出口依赖　🟠 HIGH
- **看**：备份上传 S3、跨集群复制是否依赖单 NAT/单 AZ 出口。
- **PASS**：关键出口路径多 AZ 冗余。
- **FAIL 修复**：多 AZ NAT / VPC endpoint。

### X4 — 级联故障路径　🟠 HIGH
- **看**：依赖拓扑（图 2）中的单向依赖链。
- **PASS**：上游组件（PD、ZooKeeper、哨兵）本身高可用，不会成为下游的隐藏 SPOF。
- **FAIL 修复**：加固协调层；对依赖调用加超时/重试/降级。

### X5 — 备份统一策略与异地留存　🟠 HIGH
- **看**：各数据库备份是否都存在、是否异地（跨区域）、是否验证恢复。
- **PASS**：全部持久化组件有备份 + 跨区域副本 + 恢复演练记录。
- **FAIL 修复**：补齐缺失备份；建立恢复演练。

### X6 — 监控/告警统一覆盖　🟡 MEDIUM
- **看**：是否所有中间件都接入统一监控，关键告警是否齐全。
- **PASS**：仲裁丢失、复制延迟、磁盘水位、副本不健康均有告警。
- **FAIL 修复**：补齐 exporter 与告警规则。

---

## 分析执行提示

1. 先从 `inventory` 确定**有哪些组件、什么形态**，只跑适用的检查族（无 Kafka 就跳过 KA）。
2. 每项检查**必须引用 bundle 证据**（文件+字段）。无证据 → `UNABLE_TO_ASSESS`，写入报告限制章节。
3. **★ 拓扑感知类**（TI4 location-labels、KA4 rack awareness、P2 AZ 分布）是自建中间件最隐蔽、最致命的薄弱点，务必重点核查——它们让"看起来跨 AZ"的部署在真实 AZ 故障时依然丢数据。
4. FAIL/WARN 项汇入 `findings.json`，按 [risk-scoring_zh.md](risk-scoring_zh.md) 分级排序。
