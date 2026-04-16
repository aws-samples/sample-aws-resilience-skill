中文 | [**English**](README.md)

# AWS 韧性评估 Skill 集

一组 AI 驱动的 Agent Skill，覆盖 AWS 系统韧性的完整生命周期 — 从成熟度评估、风险分析到混沌工程验证。适用于 [Claude Code](https://docs.anthropic.com/en/docs/agents-and-tools/claude-code/overview)、[Kiro](https://kiro.dev/)、[OpenClaw](https://openclaw.dev/) 以及任何支持 skill/prompt 框架的 AI 编程助手。

## 四个 Skill 的关系

四个 Skill 对应 [AWS Resilience Lifecycle Framework](https://docs.aws.amazon.com/prescriptive-guidance/latest/resilience-lifecycle-framework/overview.html) 的不同阶段，组成完整的韧性改进流水线：

```
┌──────────────────────────────────────────────────────────────────────────────────────────────────┐
│                              AWS Resilience Lifecycle Framework                                    │
│                                                                                                   │
│  Stage 1: 设定目标          Stage 2: 设计与实施          Stage 3: 评估与测试                       │
│  ┌───────────────────┐      ┌───────────────────────┐      ┌─────────────────────┐               │
│  │  aws-rma-          │      │  resilience-            │      │  chaos-engineering-  │               │
│  │  assessment        │─────►│  modeling               │─────►│  on-aws              │               │
│  │                    │      │                        │      │                      │               │
│  │  "我们在哪里？"    │      │  "哪里可能出问题？"    │      │  "真的会坏吗？"      │               │
│  └───────────────────┘      └───────────────────────┘      └──────────┬───────────┘               │
│                                        ▲                              │                            │
│                                        └──────── 反馈闭环 ────────────┘                            │
│                                                                                                   │
│                                        Stage 3: 评估与测试                                        │
│                                        ┌─────────────────────┐                                    │
│                                        │  eks-resilience-      │                                    │
│                                        │  checker              │──── 输出供混沌工程消费             │
│                                        │                      │                                    │
│                                        │  "EKS 够韧吗？"      │                                    │
│                                        └─────────────────────┘                                    │
└──────────────────────────────────────────────────────────────────────────────────────────────────┘
```

| # | Skill | 生命周期阶段 | 输入 | 输出 |
|---|-------|-------------|------|------|
| 1 | **aws-rma-assessment** | Stage 1: 设定目标 | 引导式问答 | 韧性成熟度评分 + 改进路线图 |
| 2 | **aws-resilience-modeling** | Stage 2: 设计与实施 | AWS 账户访问或架构文档 | 风险清单 + 资源扫描 + 缓解策略 |
| 3 | **chaos-engineering-on-aws** | Stage 3: 评估与测试 | Skill #2 的评估报告 | 实验结果 + 验证报告 + 更新后的韧性评分 |
| 4 | **eks-resilience-checker** | Stage 3: 评估与测试 | EKS 集群 kubectl 访问权限 | 26 项合规报告 + 实验建议 |

### 推荐使用流程

0. **运行 EKS 韧性检查**（可选）— 建立 K8s 级别基线，识别集群特定风险
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

### 2. 韧性建模 (`aws-resilience-modeling`)

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
- 双通道可观测性：CloudWatch 指标（`monitor.sh`）+ 应用日志（`log-collector.sh`）并行采集
- 日志 5 类错误分类（timeout、connection、5xx、oom、other）
- 实验后日志分析模式
- 报告中包含应用日志分析章节（错误时间线、跨服务关联、恢复检测）
- Markdown + HTML 双格式报告（含 MTTR 分阶段分析）
- Game Day 团队演练模式
- **19 场景 FIS 模板库**索引 + 5 个内嵌可直接部署模板（数据库连接耗尽、Redis 连接中断、SQS 队列不可用、CloudFront 不可用、Aurora 全局故障转移）
- 3 种进阶注入模式：SSM 自动化编排、安全组操作、资源策略拒绝

**调用方式：** 在对话中提及 "混沌工程"、"故障注入" 或 "chaos engineering"。

### 4. EKS 韧性检查器 (`eks-resilience-checker`)

**功能：** 基于 26 项最佳实践对 Amazon EKS 集群的韧性进行评估，覆盖应用工作负载、控制平面和数据平面 — 输出结构化建议，可直接供混沌工程 Skill 消费。

**适用场景：** EKS 专项基线 — 在运行混沌实验之前识别 Kubernetes 级别的韧性缺口。

**核心能力：**
- 26 项韧性检查，覆盖 3 大类别：应用层 (A1-A14)、控制平面 (C1-C5)、数据平面 (D1-D7)
- 自动化 `assess.sh` 脚本 — 一条命令生成 4 个输出文件（JSON + Markdown + HTML + 修复脚本）
- 合规评分 + 关键故障计数
- 实验建议：将失败检查项映射到混沌实验（供 `chaos-engineering-on-aws` 消费）
- 可移植：自动检测集群名称、区域和 Kubernetes 版本

**调用方式：** 在对话中提及 "EKS 韧性检查"、"集群评估" 或 "cluster resilience check"。

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

任何支持自定义 Skill 的 AI 编程助手：[Claude Code](https://docs.anthropic.com/en/docs/agents-and-tools/claude-code/overview)、[Kiro](https://kiro.dev/)、[Cursor](https://cursor.sh/)、[OpenClaw](https://openclaw.dev/) 等。

### 2. 安装

**方式 A：npx skills（推荐）**
```bash
# 安装单个 Skill
npx skills add aws-samples/sample-aws-resilience-skill --skill eks-resilience-checker

# 安装全部 4 个韧性 Skill
npx skills add aws-samples/sample-aws-resilience-skill --skill '*'
```

**方式 B：Git 克隆**
```bash
git clone https://github.com/aws-samples/sample-aws-resilience-skill.git
```
将 Skill 目录复制到项目的 `.kiro/skills/`、`.claude/skills/` 或等效文件夹中。

**方式 C：直接下载**
从 [GitHub 仓库](https://github.com/aws-samples/sample-aws-resilience-skill) 下载单个 Skill 目录。

### 3. AWS 访问权限（推荐）

- 具有只读权限的 AWS 账户（评估用）或实验权限（混沌工程用）
- 已配置凭证的 AWS CLI
- 可选：MCP 服务器以增强自动化（参见各 Skill 目录下的 `MCP_SETUP_GUIDE.md`）

## 项目结构

```
.
├── aws-rma-assessment/                # Skill 1: 韧性成熟度评估
│   ├── SKILL.md / SKILL_EN.md / SKILL_ZH.md  # Skill 定义（双语）
│   ├── README.md / README_zh.md       # Skill 说明文档
│   ├── references/                    # 参考文档（按需加载）
│   │   ├── questions-index.json       # 问题索引 — 先加载此文件
│   │   ├── questions-group-{1-10}.json # 82 个问题按域拆分（按组加载）
│   │   ├── questions-priority.md      # 优先级分类（P0-P3）
│   │   ├── question-groups.md         # 批量问答分组策略
│   │   ├── assessment-workflow.md     # 分步工作流详情
│   │   ├── auto-analysis-rules.md     # 自动推断和置信度规则
│   │   ├── scoring-guide.md           # 评分公式和域评级
│   │   └── report-template.md         # 报告生成模板
│   ├── scripts/
│   │   └── merge-questions.py         # 问题数据合并工具
│   └── assets/
│       ├── html-report-template.html  # 交互式 HTML 报告模板
│       └── example-report-snippet.md  # 示例报告输出
│
├── aws-resilience-modeling/           # Skill 2: 技术韧性评估
│   ├── SKILL.md / SKILL_EN.md / SKILL_ZH.md  # Skill 定义（双语）
│   ├── README.md / README_zh.md       # Skill 说明文档
│   ├── references/                    # 参考文档（按需加载）
│   │   ├── analysis-tasks.md          # 8 个分析任务详情
│   │   ├── resilience-framework.md    # 框架索引和参考资料映射
│   │   ├── resilience-analysis-core.md # 9 维度评分方法论
│   │   ├── waf-reliability-pillar.md  # WAF 可靠性支柱 + DR 成本基线
│   │   ├── common-risks-reference.md  # 50+ 常见 AWS 风险模式
│   │   ├── assessment-output-spec.md  # Chaos Skill 桥接：8 段输出规格
│   │   ├── compliance-mapping.md      # SOC2/ISO/NIST 框架映射
│   │   ├── report-generation.md       # 报告生成指南
│   │   ├── MCP_SETUP_GUIDE.md        # MCP 服务器配置
│   │   └── ...                        # （每个文件有 EN/ZH 对）
│   ├── scripts/
│   │   └── generate-html-report.py    # HTML 报告生成脚本
│   └── assets/
│       ├── html-report-template.html  # 交互式 HTML 报告模板
│       └── example-report-template.md # Markdown 报告示例
│
├── eks-resilience-checker/            # Skill 3: EKS 韧性最佳实践检查
│   ├── SKILL.md / SKILL_EN.md / SKILL_ZH.md  # Skill 定义（双语）
│   ├── README.md / README_zh.md       # Skill 说明文档
│   ├── references/                    # 参考文档（按需加载）
│   │   ├── EKS-Resiliency-Checkpoints.md  # 26 项检查描述和原理
│   │   ├── check-commands.md          # 每项检查的 kubectl/aws 命令
│   │   ├── eks-resiliency-checks-mcp.md   # MCP 方式执行检查
│   │   ├── remediation-templates.md   # 修复命令模板（含 YAML 示例）
│   │   ├── fail-to-experiment-mapping.md  # FAIL → 混沌实验映射
│   │   └── eks-auth-setup.md          # EKS 认证配置指南
│   ├── scripts/
│   │   └── assess.sh                  # 自动化 26 项检查评估脚本
│   └── examples/
│       └── petsite-assessment.md      # 评估报告示例
│
├── chaos-engineering-on-aws/          # Skill 4: 混沌工程实验
│   ├── SKILL.md / SKILL_EN.md / SKILL_ZH.md  # Skill 定义（双语）
│   ├── MCP_SETUP_GUIDE.md             # MCP 服务器配置
│   ├── references/                    # 渐进式加载参考文档
│   │   ├── workflow-guide.md          # 详细 6 步工作流指令
│   │   ├── fault-catalog.yaml         # 统一故障类型目录（3 层）
│   │   ├── fis-actions.md             # AWS FIS Actions 参考
│   │   ├── chaosmesh-crds.md          # Chaos Mesh CRD 参考
│   │   ├── scenario-library.md        # FIS Scenario Library 模板
│   │   ├── fis-template-library-index.md  # aws-samples/fis-template-library 19 场景索引
│   │   ├── fis-templates/             # 5 个内嵌可直接部署的 FIS 模板
│   │   ├── templates/                 # 参数化 FIS 多 Action 模板
│   │   ├── report-templates.md        # 报告模板（MD + HTML）
│   │   ├── emergency-procedures.md    # 紧急回滚流程
│   │   └── gameday.md                 # Game Day 执行指南
│   ├── examples/                      # 实验场景示例（01-08）
│   ├── scripts/
│   │   ├── experiment-runner.sh       # FIS/ChaosMesh 实验执行器
│   │   ├── monitor.sh                 # CloudWatch 指标采集
│   │   ├── log-collector.sh           # Pod 日志采集 + 错误分类
│   │   └── setup-prerequisites.sh     # FIS 角色、Chaos Mesh、资源标签配置
│   └── validate-skill.sh             # 静态验证（105 项检查）
│
├── quickstart/                        # 快速入门（含示例应用）
│   ├── README.md / README_zh.md
│   ├── sample-app/                    # 测试用 K8s 部署文件
│   └── expected-output/               # 参考评估输出
│
├── .kiro/skills/                      # Kiro Skill 注册（自动同步）
├── README.md                          # 本文件（英文）
└── README_zh.md                       # 中文版
```

## 安全

详见 [CONTRIBUTING](CONTRIBUTING.md#security-issue-notifications)。

## 许可证

本项目基于 MIT-0 许可证授权。详见 [LICENSE](LICENSE) 文件。
