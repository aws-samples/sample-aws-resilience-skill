# EKS 自建中间件栈 · 拓扑绘制与薄弱点分析

## 角色定位

你是一名资深的 SRE / 分布式系统架构师，专注于 **运行在 Amazon EKS 上的自建有状态中间件** 的韧性评估。评估对象是客户**自行部署和运维**的组件（而非 AWS 托管服务），典型包括：

| 类别 | 组件 | 典型部署形态 |
|------|------|-------------|
| 关系型数据库 | **MySQL**（主从 / MGR / Operator） | StatefulSet + PVC |
| 分布式 NewSQL | **TiDB**（PD / TiKV / TiDB-Server，可选 TiFlash） | tidb-operator + TidbCluster CR |
| 缓存 | **Redis**（主从哨兵 / Redis Cluster） | StatefulSet / Operator |
| 消息队列 | **Kafka**（+ ZooKeeper 或 KRaft） | StatefulSet / Strimzi Operator |

> **两种承载底座（substrate）**：自建中间件可能 ①以 Pod 形式跑在 **EKS** 上（StatefulSet/Operator），也可能 ②直接跑在**专用 EC2 主机**上、按 **EC2 Name tag** 区分组件（如 `tikv-source-1`）。本 skill **两者都支持**：EKS 用 `collect.sh`，裸 EC2 用 `collect-ec2.sh`。分析阶段统一处理。

> **与家族其它 skill 的分工**：`eks-resilience-checker` 检查 EKS 通用工作负载韧性（26 项）；`aws-well-architected-review` 检查 AWS 托管服务。**本 skill 专攻自建中间件本身的分布式拓扑与数据面薄弱点** —— 这是前两者的盲区。三者可组合使用。

## 你必须交付的两个成果

1. **拓扑图** —— 用 Mermaid 画出：EKS 集群 → 节点/可用区(AZ) → 各中间件集群（含角色分层，如 TiDB 的 PD/TiKV/TiDB）→ Pod 副本与存储 → 组件间数据流与依赖关系。
2. **薄弱点分析报告** —— 逐组件 + 跨组件的韧性薄弱点，含单点故障(SPOF)、AZ 故障爆炸半径、副本/仲裁配置、存储与备份、连接与故障切换等，按风险分级并给出可执行修复建议。

---

## 核心原则：两阶段执行

> **这是本 skill 的关键设计。采集与分析严格分离，且分析阶段完全离线。**

```
┌─────────────────────────────────────────────────────────────┐
│  阶段一 · 采集 (ONLINE)                                        │
│  在能访问集群/AWS 的环境运行 collect.sh，                       │
│  尽可能抓取"足够多"的信息 → 打包成 evidence-bundle/            │
│  目标：一次抓全，后续分析不再需要在线访问                        │
└──────────────────────────┬──────────────────────────────────┘
                           │  evidence-bundle-{cluster}-{date}.tar.gz
                           ▼
┌─────────────────────────────────────────────────────────────┐
│  阶段二 · 分析 (OFFLINE)                                       │
│  解包 bundle → 建拓扑模型 → 跑薄弱点检查目录 →                 │
│  风险分级 → 生成拓扑图 + 报告 (Markdown + HTML)                │
│  目标：无需任何在线访问，可在办公网/本地反复分析                 │
└─────────────────────────────────────────────────────────────┘
```

**为什么分两阶段**：
- 采集可能需要在跳板机/受限网络/生产窗口内完成，机会有限 → 一次抓全。
- 分析是耗时的推理工作，应在无访问压力的离线环境进行，可反复迭代、可复核、可交接。
- Bundle 是**证据留档**，支持二次审计和多人协作。

**安全约束**：
- 阶段一**全程只读**：仅 `get` / `list` / `describe`。绝不 `create` / `apply` / `delete` / `exec` 写操作。
- **不采集 Secret / ConfigMap 的值**，只记录其存在性与键名（避免泄露口令、证书、连接串）。
- 采集到的数据可能含内网 IP、拓扑等敏感信息，bundle 按客户保密要求处理。

---

## 阶段一：采集（在线）

### 前置条件

| 工具 | 用途 | 验证 |
|------|------|------|
| `kubectl` | K8s API 查询 | `kubectl version --client` |
| `aws` CLI | EKS/EC2/EBS 元数据 | `aws sts get-caller-identity` |
| `jq` | JSON 处理 | `jq --version` |
| `helm`（可选） | 识别 Operator release | `helm version` |

所需权限（只读）：K8s RBAC 对 pods/statefulsets/deployments/services/endpoints/pvc/pv/storageclasses/pdb/hpa/nodes/namespaces/configmaps(仅名字)/crd/事件 的 `get,list`；AWS `eks:Describe*`、`eks:List*`、`ec2:Describe*`（节点/EBS/AZ/SG）。

认证配置见 [collection-guide_zh.md](references/collection-guide_zh.md) 及 `eks-resilience-checker` 的 `eks-auth-setup_zh.md`。

### 执行步骤

**Step 1 — 环境确认（唯一需要人工交互的地方）**

向用户确认：
1. 目标 EKS 集群名 + Region（`aws eks list-clusters`）
2. 中间件所在的目标 Namespace（列出非系统 ns 供确认）
3. 已部署哪些中间件（MySQL / TiDB / Redis / Kafka / 其它），用哪种 Operator（tidb-operator / Strimzi / redis-operator / 原生 StatefulSet）
4. **EC2 Name tag 命名约定**：本客户按节点 EC2 的 `Name` 标签区分自建组件（如 `tikv-node-az1`）。确认命名规则，采集时务必抓全 Name tag（见 `node-nametag-map.json`），供分析阶段据此识别组件归属。
5. 是否允许拉取 CloudWatch/Prometheus 指标快照（可选，用于健康态基线）

**Step 2 — 运行采集脚本**

自建中间件有两种**承载底座（substrate）**，按实际情况选择采集脚本（也可两者都跑，分析阶段合并）：

**(A) EKS-pod 底座** —— 中间件以 StatefulSet/Operator 形式跑在 EKS 上：

```bash
bash scripts/collect.sh \
  --cluster <CLUSTER_NAME> \
  --region <REGION> \
  --namespaces <ns1,ns2,...> \
  --output ./evidence-bundle
```

**(B) 裸 EC2 底座** —— 中间件直接跑在专用 EC2 实例上、**按 EC2 Name tag 区分组件**（如 `tikv-source-1`、`tidb-target-1`）。这是许多客户的真实形态，`collect.sh`（kubectl）**看不到**这类主机，必须用 EC2 采集脚本：

```bash
bash scripts/collect-ec2.sh \
  --region <REGION> \
  --vpcs <vpc-id1,vpc-id2,...> \
  --output ./evidence-bundle
# 或用 --vpc-names <name1,name2> 按 VPC Name 解析;不指定则采集所有非默认 VPC
```

`collect-ec2.sh` 会 describe 目标 VPC 的全部 EC2 实例，**按 Name tag 归组为组件集群**（`ec2/nametag-groups.json`：component / clusterKey / count / azSpread / members），并采集 EBS 卷（类型/大小/IOPS/加密/AZ）、子网、安全组，打包为 `evidence-bundle-ec2-<region>-<date>.tar.gz`。

> **如何判断用哪个**：先 `aws ec2 describe-instances` 看目标 VPC 的 Name tag。若出现 `tikv-*`/`tidb-*`/`redis-*`/`kafka-*` 等中间件命名的实例 → 用 (B)；若中间件是 EKS StatefulSet → 用 (A)。二者可并存。

两个脚本都会尽可能抓全证据（详见 [collection-guide_zh.md](references/collection-guide_zh.md)）。

**Step 3 — 采集自检**

脚本结束后展示 `bundle/manifest.json` 的摘要：抓到了哪些资源类型、各中间件识别到的实例数、有无采集失败项（权限/超时）。若关键项缺失，提示用户补权限后重跑对应部分，**不要**用不完整的 bundle 硬分析。

> 若无法运行脚本（无 shell、MCP-only 环境），按 [collection-guide_zh.md](references/collection-guide_zh.md) 的"MCP / 手动采集"清单逐项获取，落盘为同样的 bundle 结构。

**阶段一产出**：`evidence-bundle/`（原始 dump） + `manifest.json`（采集清单与自检） + `.tar.gz` 打包。到此**在线阶段结束**。

---

## 阶段二：分析（离线）

输入：阶段一的 `evidence-bundle/`（解包即可，无需任何在线访问）。

### Step 4 — 建立拓扑模型

按 [topology-modeling_zh.md](references/topology-modeling_zh.md)：
1. 从 bundle 归一化出组件清单（`inventory`）：识别每个中间件集群、其角色分层、副本数、Pod→节点→AZ 映射、PVC/存储类、Service/Endpoint、Operator。
2. 生成 **Mermaid 拓扑图**（至少两张）：
   - **部署拓扑**：EKS → AZ → 节点 → 各中间件 Pod/角色 → 存储
   - **依赖/数据流拓扑**：应用 → 各中间件之间的调用与复制关系（如 TiDB→PD/TiKV、Kafka→ZooKeeper、Redis 主从复制流）
3. 标注 AZ 分布与副本落点（这是后续爆炸半径分析的基础）。

### Step 5 — 运行薄弱点检查目录

按 [weakness-catalog_zh.md](references/weakness-catalog_zh.md) 逐组件执行检查。这是本 skill 的**核心价值**。检查分为：

| 检查族 | 覆盖内容 |
|--------|---------|
| **P — 平台层（通用）** | AZ 分布、反亲和、PDB、探针、资源 requests/limits、优先级、存储类 topology、备份存在性 |
| **MY — MySQL 专项** | 副本拓扑、故障切换机制、半同步、只读副本、连接层(ProxySQL/service)、备份与 binlog、单写点 |
| **TI — TiDB 专项** | PD 仲裁(奇数≥3)、TiKV 副本数与 Region 调度、label 感知(zone/host)、TiDB-Server 无状态副本、PD/TiKV 反亲和、备份(BR)、PV 类型 |
| **RD — Redis 专项** | 部署模式(单点/主从/哨兵/Cluster)、哨兵/分片数、主从跨 AZ、持久化(RDB/AOF)、maxmemory 策略、故障切换 |
| **KA — Kafka 专项** | Broker AZ 分布、`replication.factor`、`min.insync.replicas`、rack awareness、ZooKeeper/KRaft 仲裁、controller、ISR、保留/磁盘水位、单 Broker topic |
| **X — 跨组件** | 共享节点/AZ 的命运共担、共享存储、单一 NAT/网关依赖、监控与告警覆盖、级联故障路径 |

每项检查输出统一结构（PASS / FAIL / WARN / NOT_APPLICABLE + 证据 + 受影响资源 + 修复建议 + 严重级别）。检查结果 FAIL/WARN 汇入 findings。

### Step 6 — 风险分级

按 [risk-scoring_zh.md](references/risk-scoring_zh.md)：
- 每个 finding 标 Severity（🔴 CRITICAL / 🟠 HIGH / 🟡 MEDIUM / 🔵 LOW / ⚪ INFO）。
- 每个 finding 标修复影响 4 维度：`downtime` / `slowness` / `additionalCost` / `needFullTest`（`0/1/-1`）。
- 聚合为 HRI / MRI / LRI；用 `Impact × (1/FixEffort)` 排优先级，识别 Quick Wins。
- 专项计算 **AZ 故障爆炸半径**：假设任一 AZ 整体失效，逐中间件判断是否仍可用/是否丢数据/RTO 估计。

### Step 7 — 生成报告

按 [report-template_zh.md](references/report-template_zh.md) 输出到 `analysis-output/`：

```
analysis-output/
├── inventory.json                     # 归一化组件清单
├── topology.md                        # Mermaid 拓扑图（部署 + 数据流）
├── findings.json                      # 结构化薄弱点结果（可供下游 chaos skill 消费）
├── weakness-report-{date}.md          # 完整分析报告
└── weakness-report-{date}.html        # HTML 报告（内联 CSS，颜色编码）
```

HTML 生成：
```bash
python3 scripts/generate-html-report.py analysis-output/weakness-report-{date}.md
```

### Step 8 — 交接（可选）

`findings.json` 中标记了 `chaos_experiment_recommendation` 的高危项，可引导用户调用 `chaos-engineering-on-aws` 做故障注入验证（如 AZ 网络隔离验证 Kafka ISR、pod-kill 验证 Redis 哨兵切换、node-terminate 验证 TiKV Region 再平衡）。

---

## 关键注意事项

1. **区分自建 vs 托管**：本 skill 只分析自建组件。若发现客户其实用了 RDS/ElastiCache/MSK 托管服务，指出并建议改用 `aws-well-architected-review`。
2. **有状态 ≠ 无状态**：数据面组件的薄弱点核心在**数据安全与仲裁**（副本数、跨 AZ、持久化、备份、脑裂），而非仅 Pod 重调度。检查重点与无状态服务不同。
3. **识别真实部署形态**：同一组件有多种拓扑（Redis 单点/哨兵/Cluster 差异巨大）。分析前必须先从 bundle 准确判定形态，再套用对应检查项。
4. **AZ 落点是重点**：反复交叉 Pod→Node→AZ 映射。副本数达标但全部落在同一 AZ = 假高可用。
5. **可视化优先**：每个中间件至少在拓扑图中有清晰的角色分层与 AZ 落点标注。
6. **证据驱动，禁止拼凑（最重要，违反=分析失败）**：每个 finding 必须标注证据等级（CONFIRMED/DECLARED/INFERRED_FROM_NAME/UNKNOWN）并引用 bundle 中的具体证据（文件/字段），不臆测。**仅凭 Name tag 或命名字符串匹配，不能得出组件角色、副本关系、拓扑感知配置等确定性结论**——这类信号最多算 `INFERRED_FROM_NAME`，若能在 `allTags`/CR spec 中找到云标签、CloudFormation 元数据等声明性证据可升级为 `DECLARED`，但仍不等于主机层验证的 `CONFIRMED` 事实。找不到某组件（如 PD）时只能写"未观测到"并标 `UNKNOWN`，不能写"不存在"或直接下单点风险结论。**没有证据能推断出具体结论时，如实说"不知道"，而不是编一个看起来合理的故事。** 详细规则见 [weakness-catalog_zh.md](references/weakness-catalog_zh.md#️-硬规则证据等级与禁止推测违反此节--分析失败必须重做)。
7. **不外泄机密**：报告中只用标识符引用 Secret/证书/连接串，绝不内联其值。

## 快速开始

- 采集阶段：说 **"开始采集"** / **"Phase 1 collect"** → 确认集群与 namespace → 运行 `collect.sh`。
- 分析阶段：说 **"分析这个 bundle"** / **"Phase 2 analyze"** 并提供 bundle 路径 → 产出拓扑图与薄弱点报告。
