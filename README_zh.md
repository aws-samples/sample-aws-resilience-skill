中文 | [**English**](README.md)

# AWS 韧性评估 Skill 集

一组 AI 驱动的 Agent Skill，覆盖 AWS 系统韧性的完整生命周期 — 从成熟度评估、风险分析到混沌工程验证。适用于 [Claude Code](https://docs.anthropic.com/en/docs/agents-and-tools/claude-code/overview)、[Kiro](https://kiro.dev/) 以及任何支持 skill/prompt 框架的 AI 编程助手。

## 三个 Skill 的关系

三个 Skill 对应 [AWS Resilience Lifecycle Framework](https://docs.aws.amazon.com/prescriptive-guidance/latest/resilience-lifecycle-framework/overview.html) 的不同阶段，组成完整的韧性改进流水线：

```
┌─────────────────────────────────────────────────────────────────────────────────────┐
│                        AWS Resilience Lifecycle Framework                            │
│                                                                                     │
│  Stage 1: 设定目标          Stage 2: 设计与实施          Stage 3: 评估与测试          │
│  ┌───────────────────┐      ┌───────────────────────┐      ┌─────────────────────┐  │
│  │  aws-rma-          │      │  aws-resilience-       │      │  chaos-engineering-  │  │
│  │  assessment        │─────►│  assessment            │─────►│  on-aws              │  │
│  │                    │      │                        │      │                      │  │
│  │  "我们在哪里？"    │      │  "哪里可能出问题？"    │      │  "真的会坏吗？"      │  │
│  └───────────────────┘      └───────────────────────┘      └──────────┬───────────┘  │
│                                        ▲                              │              │
│                                        └──────── 反馈闭环 ────────────┘              │
└─────────────────────────────────────────────────────────────────────────────────────┘
```

| # | Skill | 生命周期阶段 | 输入 | 输出 |
|---|-------|-------------|------|------|
| 1 | **aws-rma-assessment** | Stage 1: 设定目标 | 引导式问答 | 韧性成熟度评分 + 改进路线图 |
| 2 | **aws-resilience-assessment** | Stage 2: 设计与实施 | AWS 账户访问或架构文档 | 风险清单 + 资源扫描 + 缓解策略 |
| 3 | **chaos-engineering-on-aws** | Stage 3: 评估与测试 | Skill #2 的评估报告 | 实验结果 + 验证报告 + 更新后的韧性评分 |

### 推荐使用流程

1. **先做 RMA 评估** — 了解组织的韧性成熟度水平，设定改进目标
2. **运行韧性评估** — 深入分析 AWS 基础设施，识别具体风险和故障模式
3. **执行混沌工程** — 通过受控故障注入实验验证发现的问题
4. **闭环反馈** — 将实验结果反馈到评估报告，更新风险评分，跟踪改进

## Skill 概览

### 1. RMA 评估助手 (`aws-rma-assessment`)

**功能：** 基于 [AWS Resilience Maturity Assessment](https://docs.aws.amazon.com/prescriptive-guidance/latest/resilience-lifecycle-framework/stage-1.html) 方法论的交互式韧性成熟度评估。

**适用场景：** 初始评估 — 了解组织在韧性成熟度谱系中的位置。

**核心能力：**
- 覆盖多个韧性维度的结构化问卷
- 与 AWS Well-Architected Framework 对齐的成熟度评分
- 优先级排序的改进路线图
- 交互式 HTML 报告（含可视化图表）

**调用方式：** 在对话中提及 "RMA 评估" 或 "韧性成熟度"。

### 2. AWS 韧性评估 (`aws-resilience-assessment`)

**功能：** 对 AWS 基础设施进行全面的技术韧性分析 — 映射组件、识别故障模式、评估风险、生成可操作的缓解策略。

**适用场景：** 深度技术分析 — 发现 AWS 架构中的具体薄弱点。

**核心能力：**
- 通过 AWS CLI/MCP 自动扫描资源
- 故障模式识别与分类（单点故障、延迟、过载、错误配置、共享命运）
- 9 维度韧性评分（5 星制）
- 风险优先级清单 + 缓解策略
- 输出结构化数据供混沌工程 Skill 消费

**调用方式：** 在对话中提及 "AWS 韧性评估" 或 "系统风险评估"。

### 3. AWS 混沌工程 (`chaos-engineering-on-aws`)

**功能：** 执行完整的混沌工程生命周期 — 从实验设计到受控故障注入再到结果分析 — 使用 AWS FIS 和可选的 Chaos Mesh。

**适用场景：** 实战验证 — 证明（或证伪）系统是否能正确处理故障。

**核心能力：**
- 六步工作流：目标定义 → 资源验证 → 假设设计 → 安全检查 → 执行实验 → 分析报告
- 双引擎：**AWS FIS**（基础设施故障：节点终止、AZ 隔离、数据库故障转移）+ **Chaos Mesh**（Pod/容器故障）
- 混合监控：后台指标采集 + Agent 驱动的 FIS 状态轮询
- 跨长时间实验的状态持久化
- Markdown + HTML 双格式报告（含 MTTR 分阶段分析）
- Game Day 团队演练模式

**调用方式：** 在对话中提及 "混沌工程"、"故障注入" 或 "chaos engineering"。

## 故障注入工具选择

基于 E2E 实测验证，混沌工程 Skill 执行以下明确的工具分工：

| 层级 | 工具 | 示例 |
|------|------|------|
| **基础设施层**（节点、网络、数据库） | AWS FIS | `eks:terminate-nodegroup-instances`、`network:disrupt-connectivity`、`rds:failover-db-cluster` |
| **Pod/容器层**（应用级） | Chaos Mesh | `PodChaos`、`NetworkChaos`、`HTTPChaos`、`StressChaos` |

> ⚠️ FIS 的 `aws:eks:pod-*` 系列 action **不推荐**用于 Pod 级故障 — 需要额外的 K8s ServiceAccount/RBAC 配置，且初始化慢（>2 分钟）。Pod 级请使用 Chaos Mesh。

## 特性

- 基于 **AWS Well-Architected Framework** 可靠性支柱 (2025)
- 整合 **AWS 韧性分析框架**（错误预算、SLO/SLI/SLA）
- 完整的**混沌工程**生命周期（AWS FIS + Chaos Mesh）
- **AWS 可观测性最佳实践**（CloudWatch、X-Ray、分布式追踪）
- **云设计模式**（Circuit Breaker、Bulkhead、Retry）
- **交互式 HTML 报告**（含 Chart.js 可视化图表和 Mermaid 架构图）

## 前提条件

### 1. AI 编程助手

任何支持自定义 Skill 的 AI 编程助手：[Claude Code](https://docs.anthropic.com/en/docs/agents-and-tools/claude-code/overview)、[Kiro](https://kiro.dev/)、[Cursor](https://cursor.sh/) 等。

### 2. 安装

```bash
git clone https://github.com/aws-samples/sample-gcr-resilience-skill.git
```

将 Skill 目录复制到项目的 Skill 文件夹中，或直接引用。

### 3. AWS 访问权限（推荐）

- 具有只读权限的 AWS 账户（评估用）或实验权限（混沌工程用）
- 已配置凭证的 AWS CLI
- 可选：MCP 服务器以增强自动化（参见各 Skill 目录下的 `MCP_SETUP_GUIDE.md`）

## 项目结构

```
.
├── aws-rma-assessment/                # 韧性成熟度评估
│   ├── SKILL.md                       # Skill 定义
│   ├── MCP_SETUP_GUIDE.md             # MCP 服务器配置
│   ├── resilience-framework.md        # AWS 最佳实践参考
│   ├── html-report-template.html      # 交互式 HTML 报告模板
│   └── generate-html-report.py        # HTML 报告生成脚本
│
├── aws-resilience-assessment/         # 技术韧性评估
│   ├── SKILL.md                       # Skill 定义
│   ├── MCP_SETUP_GUIDE.md             # MCP 服务器配置
│   ├── resilience-framework.md        # AWS 最佳实践参考
│   ├── html-report-template.html      # 交互式 HTML 报告模板
│   └── generate-html-report.py        # HTML 报告生成脚本
│
├── chaos-engineering-on-aws/          # 混沌工程实验
│   ├── SKILL.md                       # Skill 定义（六步工作流）
│   ├── MCP_SETUP_GUIDE.md             # MCP 服务器配置
│   ├── references/                    # 渐进式加载参考文档
│   │   ├── fis-actions.md             # AWS FIS Actions 参考
│   │   ├── chaosmesh-crds.md          # Chaos Mesh CRD 参考
│   │   ├── report-templates.md        # 报告模板（MD + HTML）
│   │   └── gameday.md                 # Game Day 执行指南
│   ├── examples/                      # 实验场景示例
│   │   ├── 01-ec2-terminate.md        # EC2 实例终止
│   │   ├── 02-rds-failover.md         # RDS Aurora 故障转移
│   │   ├── 03-eks-pod-kill.md         # EKS Pod Kill（Chaos Mesh）
│   │   └── 04-az-network-disrupt.md   # AZ 网络隔离
│   ├── scripts/
│   │   └── monitor.sh                 # CloudWatch 指标采集脚本
│   └── doc/                           # 设计文档（PRD、决议）
│
├── README.md                          # 本文件（英文）
└── README_zh.md                       # 中文版
```

## 安全

详见 [CONTRIBUTING](CONTRIBUTING.md#security-issue-notifications)。

## 许可证

本项目基于 MIT-0 许可证授权。详见 [LICENSE](LICENSE) 文件。
