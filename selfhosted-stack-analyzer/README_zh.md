# selfhosted-stack-analyzer

EKS 上**自建有状态中间件**（MySQL / TiDB / TiKV / PD / Redis / Kafka / ZooKeeper）的**拓扑绘制**与**韧性薄弱点分析** skill。分**两阶段**执行：阶段一在线采集证据，阶段二离线分析出结论。

## 解决什么问题

巨型互联网客户常把数据库、缓存、消息队列**全部自建**在 EKS 上，而不用 RDS/ElastiCache/MSK 等托管服务。这类自建有状态组件的韧性薄弱点（副本仲裁、跨 AZ 落点、数据丢失窗口、脑裂、拓扑感知调度）是通用 EKS 检查和 Well-Architected 评审的**盲区**。本 skill 专门填补这一盲区，产出：

1. **拓扑图**（Mermaid）—— 部署拓扑（AZ/节点/角色/存储）+ 依赖数据流拓扑。
2. **薄弱点分析报告** —— 逐组件 + 跨组件，含 AZ 故障爆炸半径、数据丢失 RPO、风险分级与可执行修复。

## 与家族其它 skill 的分工

| Skill | 关注点 |
|-------|--------|
| `aws-well-architected-review` | AWS 托管服务的 6 支柱评审 |
| `eks-resilience-checker` | EKS **通用工作负载**韧性（26 项） |
| **`selfhosted-stack-analyzer`（本 skill）** | EKS 上**自建有状态中间件本身**的分布式拓扑与数据面薄弱点 |
| `aws-resilience-modeling` | 系统级韧性建模与风险 |
| `chaos-engineering-on-aws` | 故障注入验证（下游消费本 skill 的 findings） |

## 两阶段工作流

```
阶段一 · 采集 (在线)                         阶段二 · 分析 (离线)
┌────────────────────────┐                 ┌────────────────────────────┐
│ collect.sh             │  evidence-      │ 建拓扑模型 → 薄弱点检查目录  │
│ 只读抓全部证据          │  bundle.tar.gz  │ → 风险分级 → 拓扑图 + 报告   │
│ → evidence-bundle/     │ ═══════════════▶│ → analysis-output/          │
└────────────────────────┘                 └────────────────────────────┘
     需集群/AWS 访问                              无需任何在线访问
```

**为什么分两阶段**：采集常受限于跳板机/生产窗口（一次抓全）；分析是耗时推理，宜离线反复迭代；bundle 作为证据留档，便于审计与协作。

## 目录结构

```
selfhosted-stack-analyzer/
├── SKILL.md                       # 语言路由入口 + frontmatter
├── SKILL_ZH.md / SKILL_EN.md      # 主指令（两阶段工作流总纲）
├── README_zh.md
├── scripts/
│   ├── collect.sh                 # 阶段一(A)：EKS-pod 底座只读采集 → evidence-bundle
│   ├── collect-ec2.sh             # 阶段一(B)：裸 EC2 底座只读采集(按 Name tag 分组) → evidence-bundle
│   └── generate-html-report.py    # 阶段二：Markdown 报告 → HTML（含 Mermaid 渲染）
└── references/
    ├── collection-guide_zh.md     # 阶段一：采集清单/方法/脱敏/bundle 结构
    ├── topology-modeling_zh.md    # 阶段二：inventory + Mermaid 拓扑建模
    ├── weakness-catalog_zh.md     # ★核心：各中间件专项薄弱点检查目录
    ├── risk-scoring_zh.md         # 风险分级 + AZ 爆炸半径 + RPO
    └── report-template_zh.md      # 报告结构模板
```

## 使用方法

### 阶段一（在线采集）

前置：`kubectl`、`aws` CLI、`jq`（可选 `helm`），只读权限。

自建中间件有两种承载底座，按实际选择：

**(A) EKS-pod 底座**（中间件是 StatefulSet/Operator）：
```bash
bash scripts/collect.sh \
  --cluster <CLUSTER_NAME> \
  --region <REGION> \
  --namespaces <ns1,ns2,...> \
  --output ./evidence-bundle
# 可选: --no-aws (跳过 AWS 层)  --metrics (拉取 kubectl top 快照)
```

**(B) 裸 EC2 底座**（中间件跑在专用 EC2、按 Name tag 区分，如 `tikv-source-1`）：
```bash
bash scripts/collect-ec2.sh \
  --region <REGION> \
  --vpcs <vpc-id1,vpc-id2,...> \
  --output ./evidence-bundle
# 或 --vpc-names <name1,name2>;不指定则采集所有非默认 VPC
```
`collect-ec2.sh` 按 **EC2 Name tag** 把实例归组为组件集群，并采集 EBS/子网/安全组。

产出 `evidence-bundle/...`（原始 dump + `manifest.json`）与 `.tar.gz` 打包。
**采集只读**：仅 get/list/describe；Secret 只记 name/type/keys，ConfigMap 只记 keys，绝不导出密文。

> **组件识别关键**：本客户按 **EC2 主机 Name tag** 区分自建组件，脚本会派生 `aws/node-nametag-map.json`（instanceId → Name tag → AZ），阶段二据此识别每个 Pod 属于哪个组件。务必确保采集到全部节点 Name tag。

### 阶段二（离线分析）

把 bundle 交给 skill：“分析这个 bundle：<路径>”。skill 会：
1. 建 `inventory.json` + 两张 Mermaid 拓扑图（`topology.md`）。
2. 跑薄弱点检查目录（P/MY/TI/RD/KA/X 六族）。
3. 风险分级 + AZ 爆炸半径矩阵 + RPO 分析 → `findings.json`。
4. 生成报告：

```bash
python3 scripts/generate-html-report.py analysis-output/weakness-report-<date>.md
```

## 输出

```
analysis-output/
├── inventory.json                 # 归一化组件清单
├── topology.md                    # Mermaid 拓扑图
├── findings.json                  # 结构化薄弱点（下游 chaos skill 可消费）
├── weakness-report-<date>.md      # 完整报告
└── weakness-report-<date>.html    # HTML 报告（内联样式 + Mermaid 渲染）
```

## 检查目录覆盖（核心价值）

| 族 | 覆盖 |
|----|------|
| **P 平台层** | 副本数、跨 AZ 分布、反亲和、PDB、探针、资源 QoS、存储类拓扑、备份、监控 |
| **MY MySQL** | 部署形态、自动故障切换、半同步、主从跨 AZ、连接层、binlog/GTID、备份 PITR |
| **TI TiDB** | PD 奇数仲裁、TiKV 副本数、**location-labels 拓扑感知**、TiDB 无状态副本、反亲和、BR 备份 |
| **RD Redis** | 部署模式、哨兵 quorum、主从/哨兵跨 AZ、持久化 AOF/RDB、maxmemory、Cluster 分片冗余 |
| **KA Kafka** | Broker 跨 AZ、replication.factor、min.insync.replicas、**rack awareness**、ZK/KRaft 仲裁、磁盘水位 |
| **X 跨组件** | 全栈 AZ 爆炸半径、共享节点命运共担、单网关依赖、级联故障、统一备份/监控 |

> ★ 最隐蔽也最致命的薄弱点是**拓扑感知调度**（TiKV `location-labels`、Kafka `rack awareness`、Pod AZ 分布）——它们让"看起来跨 AZ"的部署在真实 AZ 故障时依然丢数据。

## 安全原则

- 阶段一全程只读；不 exec 进容器；不导出任何密文。
- 报告只用标识符引用 Secret/连接串/证书，绝不内联其值。
- 证据驱动：每个 finding 引用 bundle 中的具体文件/字段；缺证据标 `UNABLE_TO_ASSESS`，不臆测。
