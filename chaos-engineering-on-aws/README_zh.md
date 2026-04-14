中文 | [English](README.md)

# AWS 混沌工程

AI 驱动的混沌工程 Agent Skill，在 AWS 上运行受控混沌实验，覆盖完整生命周期：目标定义 → 资源验证 → 实验设计 → 安全检查 → 受控执行 → 分析报告。

## 概述

本 Skill 基于 `aws-resilience-modeling` Skill 的评估报告，通过 **AWS FIS** 和可选的 **Chaos Mesh** 进行受控故障注入，系统性验证系统韧性。

## 安装

**方式 A：npx skills（推荐）**
```bash
# Install this skill
npx skills add aws-samples/sample-aws-resilience-skill --skill chaos-engineering-on-aws

# Install all 4 resilience skills
npx skills add aws-samples/sample-aws-resilience-skill --skill '*'
```

**方式 B：Git clone**
```bash
git clone https://github.com/aws-samples/sample-aws-resilience-skill.git
```

## 前置条件

- `aws-resilience-modeling` Skill 生成的评估报告（推荐）
- 具备 FIS 权限的 AWS 凭证
- 已配置 MCP Server（见下方）
- 前置条件检查完成（见 [references/prerequisites-checklist_zh.md](references/prerequisites-checklist_zh.md)）

## MCP Server 配置

### 必需

| Server | 包名 | 用途 |
|--------|------|------|
| aws-api-mcp-server | `awslabs.aws-api-mcp-server` | FIS 实验创建/执行/停止、资源验证 |
| cloudwatch-mcp-server | `awslabs.cloudwatch-mcp-server` | 指标读取、告警、停止条件 |

### 可选

| Server | 包名 | 适用场景 |
|--------|------|---------|
| eks-mcp-server | `awslabs.eks-mcp-server` | EKS 架构 |
| chaosmesh-mcp | [RadiumGu/Chaosmesh-MCP](https://github.com/RadiumGu/Chaosmesh-MCP) | 集群已安装 Chaos Mesh |

### 配置

> 完整配置指南和示例：[MCP_SETUP_GUIDE.md](MCP_SETUP_GUIDE.md)

无 MCP 时自动降级为 AWS CLI（`aws fis`、`aws cloudwatch`、`kubectl`）。

### Chaos Mesh MCP：EKS 认证

两种方式：**静态 ServiceAccount Token**（生产推荐）或**管理员 kubeconfig**（快速测试）。详见 [MCP_SETUP_GUIDE.md](MCP_SETUP_GUIDE.md)。

## 六步流程

| 步骤 | 名称 | 输出文件 |
|------|------|---------|
| 1 | 定义实验目标 | `output/step1-scope.json` |
| 2 | 选择目标资源 | `output/step2-assessment.json` |
| 3 | 定义假设和实验 | `output/step3-experiment.json` |
| 4 | 实验准备就绪检查 | `output/step4-validation.json` |
| 5 | 运行受控实验 | `output/step5-experiment.json` + `step5-metrics.jsonl` |
| 6 | 学习与报告 | `output/step6-report.md` + `step6-report.html` |

## 故障注入工具选择

> 📋 完整结构化目录：[references/fault-catalog.yaml](references/fault-catalog.yaml)

### 故障目录概览：41 个故障动作

| 后端 | 数量 | 覆盖范围 |
|------|------|---------|
| **AWS FIS** | 23 | EC2、RDS、Lambda、EBS、DynamoDB、S3、API Gateway、ECS、Network |
| **Chaos Mesh** | 14 | Pod 生命周期、网络、HTTP、CPU/内存压力、IO、DNS |
| **FIS Scenario** | 4 | AZ 断电、AZ 应用减速、跨 AZ 流量、跨 Region 连通性 |

```
AZ/Region 级复合故障  →  FIS Scenario Library
  ├── AZ 电源中断（EC2 + RDS + EBS + ElastiCache 联动）
  ├── AZ 应用延迟（网络延迟注入）
  ├── 跨 AZ 流量劣化（跨 AZ 丢包）
  └── 跨 Region 连通性（TGW + 路由表中断）
  三种创建路径：
    (1) Console Scenario Library → 用 `aws fis get-experiment-template` 导出
    (2) Console Content tab → 手动补全参数 → API 创建
    (3) 使用 references/scenario-library_zh.md 中的 JSON skeleton 直接通过 API 创建

组合多 Action 实验  →  FIS 原生（startAfter）
  ├── 并行：多个 action 不设 startAfter（同时启动）
  ├── 串行：action 之间通过 startAfter 定义依赖
  ├── 定时延迟：aws:fis:wait action 在 action 间插入等待
  └── 参数化模板：references/templates/（{{placeholder}} 格式）
  详见 examples/05-composite-az-degradation_zh.md 完整示例

AWS 托管服务 / 基础设施层  →  AWS FIS（单 action）
  ├── 节点级：   eks:terminate-nodegroup-instances
  ├── 实例级：   ec2:terminate/stop/reboot
  ├── 数据库级： rds:failover, rds:reboot
  ├── 网络级：   network:disrupt-connectivity
  └── Serverless：lambda:invocation-add-delay/error

混合后端实验  →  FIS + Chaos Mesh（编排执行）
  同时运行 FIS 和 Chaos Mesh，覆盖基础设施层 + Pod 层故障。
  CM 先注入 → 确认生效 → FIS 注入 → 并行监控 → 熔断顺序：先停 FIS，再删 CM。

K8s Pod / 容器层  →  Chaos Mesh（推荐）
  ├── Pod 生命周期：PodChaos (kill/failure)
  ├── 网络：       NetworkChaos (delay/loss/partition)
  ├── HTTP 层：    HTTPChaos (abort/delay)
  └── 资源压力：   StressChaos (cpu/memory)
```

## 核心能力

- 双通道可观测性：CloudWatch 指标（`monitor.sh`）+ 应用日志（`log-collector.sh`）
- 5 类错误自动分类（timeout、connection、5xx、oom、other）
- AI 引导的实验设计与自动安全验证
- 渐进式故障注入与强制停止条件
- 多工具支持：AWS FIS + Chaos Mesh + FIS Scenario Library
- **组合实验**：FIS 原生多 Action 模板 + `startAfter` 编排（并行、串行、定时延迟）
- **混合后端编排**：FIS + Chaos Mesh 同时注入，定义明确的熔断顺序
- **参数化模板**：`{{placeholder}}` 格式的可复用模板，适用于标准化场景

## 安全原则

- **强制停止条件**：每个 FIS 实验必须绑定 CloudWatch Alarm
- **最小爆炸半径**：不超过预设约束限制
- **渐进式**：Staging → Production，单故障 → 级联
- **可逆**：所有实验必须有回滚方案
- **人工确认**：生产实验必须双重确认
- **监控前置**：🔴 监控未就绪时阻断实验启动

## 执行模式

| 模式 | 说明 |
|------|------|
| Interactive | 每步暂停确认（首次运行/生产环境） |
| Semi-auto | 关键节点确认（Staging 推荐） |
| Dry-run | 只走流程不注入故障 |
| Game Day | 跨团队演练，详见 [references/gameday.md](references/gameday.md) |

## 参考场景示例

- [EC2 实例终止 — ASG 恢复验证](examples/01-ec2-terminate.md)
- [RDS Aurora 故障转移 — 数据库 HA 验证](examples/02-rds-failover.md)
- [EKS Pod Kill — 微服务自愈验证](examples/03-eks-pod-kill.md)（Chaos Mesh）
- [AZ 网络隔离 — 多 AZ 容错验证](examples/04-az-network-disrupt.md)
- [组合 AZ 降级 — 多 Action FIS 实验](examples/05-composite-az-degradation_zh.md)（FIS 多 Action + `startAfter`）

## 目录结构

```
chaos-engineering-on-aws/
├── SKILL.md                    # Agent Skill 定义（语言路由）
├── SKILL_EN.md / SKILL_ZH.md  # 完整指令（英文/中文）
├── README.md                   # 英文版
├── README_zh.md                # 本文件（中文版）
├── MCP_SETUP_GUIDE.md          # MCP Server 配置指南
├── examples/                   # 实验场景示例
├── references/
│   ├── fault-catalog.yaml      # 统一故障类型注册表：41 个动作（23 FIS + 14 CM + 4 Scenario）
│   ├── workflow-guide_zh.md    # 6 步流程详细指令
│   ├── scenario-library_zh.md  # FIS Scenario Library JSON skeleton 与要求
│   ├── templates/              # 参数化 FIS 多 Action 模板（{{placeholder}} 格式）
│   │   ├── az-power-interruption.json       # AZ 断电（4 action，并行）
│   │   ├── cascade-db-to-app.json           # DB 级联故障（3 action，串行 + 延迟）
│   │   └── progressive-network-degradation.json  # 渐进式退化（6 action，3 波次）
│   ├── prerequisites-checklist_zh.md  # 按架构模式分类的前置条件
│   ├── emergency-procedures_zh.md     # 应急停止程序（三级升级方案）
│   ├── fis-actions_zh.md       # FIS actions 参考
│   ├── chaosmesh-crds_zh.md    # Chaos Mesh CRD 参考
│   ├── report-templates_zh.md  # 报告生成模板
│   └── gameday_zh.md           # Game Day 演练指南
├── scripts/
│   ├── README.md               # 脚本使用指南（参数、退出码）
│   ├── experiment-runner.sh    # 实验执行（FIS + Chaos Mesh）
│   ├── log-collector.sh        # Pod 日志采集 + 错误分类
│   ├── monitor.sh              # CloudWatch 指标采集
│   └── setup-prerequisites.sh  # 可选的前置环境准备
├── doc/                        # 内部开发文档（Agent 不加载）
│   ├── prd.md                  # 产品需求
│   ├── decisions.md            # 架构决策
│   └── ...                     # 其他内部文档
├── scripts/
│   ├── monitor.sh              # 监控脚本模板
│   ├── log-collector.sh        # Pod 日志收集 + 错误分类
│   └── setup-prerequisites.sh  # 可选的前置环境准备脚本
└── e2e-tests/                  # 端到端测试
```

## 近期变更

### v1.3.0 — 2026-04-14

**组合实验支持（P0）**
- `SKILL_EN.md` / `SKILL_ZH.md` — 新增 §3.6：组合实验设计（FIS 多 Action 模板 + `startAfter` 编排：并行、串行、定时延迟）
- `SKILL_EN.md` / `SKILL_ZH.md` — 新增 §3.7：混合后端实验（FIS + Chaos Mesh 同时注入，定义熔断顺序）
- `examples/05-composite-az-degradation.md` / `_zh.md` — 新增：完整组合 AZ 降级示例（EC2 停止 + EBS 暂停 + RDS failover，含完整 FIS JSON）
- `references/fault-catalog.yaml` — 修正 `fis_scenarios` 注释：明确三种创建路径（Console 导出、Content tab + API、直接 JSON skeleton）

**参数化模板（P1）**
- `references/templates/az-power-interruption.json` — 新增：AZ 断电模板（EC2 + EBS + RDS + ElastiCache，4 action 并行）
- `references/templates/cascade-db-to-app.json` — 新增：DB 级联故障模板（RDS failover → 30s wait → 网络中断，3 action 串行）
- `references/templates/progressive-network-degradation.json` — 新增：渐进式网络退化模板（3 波次，6 action，含 Lambda 延迟）

**鲁棒性修复（P1）**
- `scripts/experiment-runner.sh` — Chaos Mesh 轮询新增 CR 存在性检查；CR 被删除时优雅退出并写入 ABORTED 状态

**Duration 覆盖（P2）**
- `SKILL_EN.md` / `SKILL_ZH.md` — 新增：步骤 5 的 Duration 覆盖指引（jq 修改 FIS 模板、kubectl patch 修改 Chaos Mesh）

### v1.2.0 — 2026-04-05

**安全与运营**
- `references/emergency-procedures_zh.md` — 新增：三级应急停止程序，覆盖 FIS、Chaos Mesh 及核弹级 CRD 删除方案
- `references/fault-catalog.yaml` — 为全部 23 种故障类型新增 `safe_first_run_params`（首次实验保守参数；`pod_kill` 默认改为固定 1 个 Pod，而非 50%）

**IAM 与权限**
- `references/prerequisites-checklist_zh.md` — 新增三级 FIS IAM Policy 模板（Tier 1：仅 EC2；Tier 2：+RDS；Tier 3：完整版），附权限边界配置指南

**可观测性与可靠性**
- `scripts/monitor.sh` — `metric-queries.json` 缺失时写入 warning 到 JSONL，而非硬失败
- `SKILL_EN.md` / `SKILL_ZH.md` — 步骤 3 明确要求 Agent 生成 `metric-queries.json`；步骤 4 前置检查清单新增 `metric-queries.json` 存在性检查

**文档**
- `references/report-templates_zh.md` — 步骤 6 报告新增"清理状态"章节，含 FIS 模板、Chaos Mesh CR、临时告警的 checkbox 清单
- `references/scenario-library_zh.md` — 所有 JSON 骨架标注"Last verified: 2026-04-05 against FIS API version 2024-05-01"
- `SKILL_EN.md` / `SKILL_ZH.md` — 顶部新增"Last sync: 2026-04-05"标记
