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

> `awslabs.aws-api-mcp-server` 已被 AWS 托管的 **AWS MCP Server** 取代（[迁移指南](https://github.com/awslabs/mcp/blob/main/src/aws-api-mcp-server/MIGRATION.md)）。请删除旧条目，以及本 README 旧版要求设置的 `ALLOW_WRITE_OPERATIONS` 变量：该 Server 中从来没有这个变量。

### 必需

| Server | 连接方式 | 用途 |
|--------|----------|------|
| `aws-mcp` — [AWS MCP Server](https://docs.aws.amazon.com/agent-toolkit/latest/userguide/mcp-server.html)（AWS 托管，预览） | `uvx mcp-proxy-for-aws@<锁定版本> https://aws-mcp.<region>.api.aws/mcp --metadata AWS_REGION=<region>` | 所有 AWS API 调用：FIS 创建/执行/停止、CloudWatch 指标与告警、资源验证；AWS 文档检索。使用你的 IAM 权限运行（不加 `--read-only`：FIS 需要写操作） |

### 可选

| Server | 连接方式 | 适用场景 |
|--------|----------|----------|
| `eks-mcp` — [Amazon EKS MCP Server](https://docs.aws.amazon.com/eks/latest/userguide/eks-mcp-introduction.html)（AWS 托管，预览） | 同一代理，`https://eks-mcp.<region>.api.aws/mcp --service eks-mcp` | EKS 架构（开源的 `awslabs.eks-mcp-server` 可作为本地替代） |
| `awslabs.cloudwatch-mcp-server` | `uvx awslabs.cloudwatch-mcp-server@latest` | 仅在需要它的告警建议/日志分析工具时 |
| `chaosmesh-mcp` | [RadiumGu/Chaosmesh-MCP](https://github.com/RadiumGu/Chaosmesh-MCP)（社区项目，非 AWS） | 集群已安装 Chaos Mesh |

### 配置

> 完整配置指南与示例（Kiro、Claude Code、Cursor/VS Code）、IAM 与验证方法：[MCP_SETUP_GUIDE_zh.md](MCP_SETUP_GUIDE_zh.md)

无 MCP 时自动降级为 AWS CLI（`aws fis`、`aws cloudwatch`、`kubectl`）；后台脚本始终使用 CLI。

### Chaos Mesh MCP：EKS 认证

两种方式：**静态 ServiceAccount Token**（生产推荐）或**管理员 kubeconfig**（快速测试）。详见 [MCP_SETUP_GUIDE_zh.md § chaosmesh-mcp](MCP_SETUP_GUIDE_zh.md#4-chaosmesh-mcp可选社区项目) 及该项目的 [EKS Authentication Methods](https://github.com/RadiumGu/Chaosmesh-MCP#eks-authentication-methods)。

## 六步流程

| 步骤 | 名称 | 输出文件 |
|------|------|---------|
| 1 | 定义实验目标 | `output/step1-scope.json` |
| 2 | 选择目标资源 | `output/step2-assessment.json` |
| 3 | 定义假设和实验 | `output/step3-experiment.json` |
| 4 | 实验准备就绪检查 | `output/step4-validation.json` |
| 5 | 运行受控实验 | `output/step5-experiment.json` + `step5-metrics.jsonl` + `step5-logs.jsonl` + `state.json` + `dashboard.md` |
| 6 | 学习与报告 | `output/step6-report.md` + `step6-report.html` |

## 故障注入工具选择

> 📋 完整结构化目录：[references/fault-catalog.yaml](references/fault-catalog.yaml)

### 故障目录概览：54 个故障动作

| 后端 | 数量 | 覆盖范围 |
|------|------|---------|
| **AWS FIS** | 24 | EC2、RDS、Lambda、EBS、DynamoDB、S3、API Gateway、ECS、Network |
| **Chaos Mesh** | 14 | Pod 生命周期、网络、HTTP、CPU/内存压力、IO、DNS |
| **FIS + SSM 自动化** | 12 | 没有原生 FIS action 的故障，来自 FIS 模板库：MSK broker 重启、ElastiCache 主节点重启/故障转移、Redis 连接故障、数据库连接/锁/IO 耗尽、SQS/CloudFront 不可用、Aurora 全局故障转移 |
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
- **FIS 模板库集成**：来自 [aws-samples/fis-template-library](https://github.com/aws-samples/fis-template-library) 的 27 场景索引（同步到 ee74d58）+ 8 个内嵌可直接部署模板
- **资源与 action 兼容性检查**：生成任何模板前，先核对 FIS action 的目标类型与真实资源是否匹配
- **影响目标发现**：`discover-dependencies.sh` 在本 Region 所有 EKS 集群中找出引用被测资源的工作负载，`log-collector.sh --app-map` 再精确采集这些工作负载的日志
- **3 种进阶注入模式**：SSM 自动化编排（动态资源注入）、安全组操作、资源策略拒绝（渐进式）
- **三层状态管理**：`state.json` v2 状态机 + `dashboard.md` Markdown 看板 + 终端 ASCII 看板
- **会话中断恢复**：Agent 会话中断后可通过 `state.json` 检查点自动恢复

## 状态管理与可观测性

本 Skill 为长时间运行的实验提供三层状态架构：

### 第一层：`output/state.json`（v2）

机器可读的状态文件，由 `experiment-runner.sh` 通过 `flock` 保证并发写入安全。

```json
{
  "version": 2,
  "workflow": { "current_step": 5, "status": "in_progress" },
  "experiments": [
    { "id": "EXP-001", "status": "completed", "elapsed_seconds": 74, "result": "PASSED" }
  ],
  "background_pids": { "runner": 12345, "monitor": 12346, "log_collector": 12347 }
}
```

Agent 启动时检查 `state.json`：
- **不存在** → 全新开始
- **存在且 `status: in_progress`** → 恢复模式：检查 PID、查询 FIS/CM 状态、恢复或重新开始

### 第二层：`output/dashboard.md`

Markdown 看板，由 `monitor.sh` 每个采集周期自动生成（通过 `update-dashboard.sh`）。可在 IDE Markdown 预览中实时查看进度。

### 第三层：终端 ASCII 看板

彩色 ASCII 终端看板：

```bash
watch -n 5 -c bash scripts/render-dashboard.sh
```

```
╔══════════════════════════════════════════════════════════════╗
║  🔬  混沌工程看板                                            ║
╠══════════════════════════════════════════════════════════════╣
║  进度: [████████████████████] 100%  Step 6/6  (completed)
║  EXP-001 EKS Pod Kill   ✅ done  74s   PASS
║  Monitor: ✅ Active  samples=20
╚══════════════════════════════════════════════════════════════╝
```

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
- [数据库连接池耗尽 — 连接池韧性验证](examples/06-database-connection-exhaustion_zh.md)（SSM 自动化编排）
- [Redis 连接中断 — 缓存层韧性验证](examples/07-redis-connection-failure_zh.md)（安全组操作）
- [SQS 队列不可用 — 消息队列韧性验证](examples/08-sqs-queue-impairment_zh.md)（渐进式资源策略拒绝）

## 目录结构

```
chaos-engineering-on-aws/
├── SKILL.md                    # Agent Skill 定义（语言路由）
├── SKILL_EN.md / SKILL_ZH.md  # 完整指令（双语，各 ~97 行）
├── README.md / README_zh.md    # 说明文档（双语）
├── MCP_SETUP_GUIDE.md / _zh.md # MCP Server 配置指南
├── references/                 # 渐进式加载参考文档（Agent 按需加载）
│   ├── workflow-guide.md / _zh.md  # 6 步流程详细指令
│   ├── fault-catalog.yaml      # 统一故障类型注册表：54 个动作（24 FIS + 14 CM + 12 FIS-SSM + 4 Scenario）
│   ├── scenario-library.md / _zh.md  # FIS Scenario Library JSON skeleton 与要求
│   ├── fis-template-library-index.md / _zh.md  # aws-samples/fis-template-library 27 场景索引
│   ├── fis-templates/              # 8 个内嵌的可直接部署 FIS 模板
│   │   ├── database-connection-exhaustion/  # SSM 自动化：动态 EC2 负载生成器
│   │   ├── redis-connection-failure/        # SSM 自动化：安全组操作
│   │   ├── sqs-queue-impairment/           # SSM 自动化：渐进式策略拒绝
│   │   ├── cloudfront-impairment/          # SSM 自动化：S3 源站拒绝策略
│   │   ├── aurora-global-failover/         # SSM 自动化：跨区域切换
│   │   ├── msk-broker-reboot/              # SSM 自动化：MSK broker 重启
│   │   ├── elasticache-redis-primary-node-reboot/    # SSM 自动化：主节点重启
│   │   └── elasticache-redis-primary-node-failover/  # SSM 自动化：TestFailover
│   ├── templates/              # 参数化 FIS 多 Action 模板（{{placeholder}} 格式）
│   │   ├── az-power-interruption.json       # AZ 断电（官方 8 个子动作，可裁剪）
│   │   ├── cascade-db-to-app.json           # DB 级联故障（3 action，串行 + 延迟）
│   │   └── progressive-network-degradation.json  # 渐进式退化（6 action，3 波次）
│   ├── prerequisites-checklist.md / _zh.md  # 按架构模式分类的前置条件
│   ├── emergency-procedures.md / _zh.md     # 应急停止程序（三级升级方案）
│   ├── fis-actions.md / _zh.md # FIS actions 参考
│   ├── chaosmesh-crds.md / _zh.md  # Chaos Mesh CRD 参考
│   ├── report-templates.md / _zh.md # 报告生成模板
│   └── gameday.md / _zh.md     # Game Day 演练指南
├── examples/                   # 实验场景示例（01-08，中英文对）
├── scripts/
│   ├── README.md               # 脚本使用指南（参数、退出码、示例）
│   ├── discover-dependencies.sh  # 步骤 2 影响目标发现（扫描全部 EKS 集群）
│   ├── experiment-runner.sh    # 实验执行（FIS + Chaos Mesh，--one-shot 支持 pod-kill）
│   ├── log-collector.sh        # Pod 日志采集 + 5 类错误自动分类（--app-map）
│   ├── monitor.sh              # CloudWatch 指标采集（FIS 模式 + Chaos Mesh 模式）
│   ├── update-dashboard.sh     # 自动生成 output/dashboard.md（monitor.sh 每周期调用）
│   ├── render-dashboard.sh     # 彩色 ASCII 终端看板（配合 `watch -n 5 -c` 使用）
│   ├── setup-prerequisites.sh  # 可选的前置环境准备
│   ├── custom-metrics-sample.conf  # 自定义指标配置示例
│   └── tests/                  # 离线测试（bash + jq，aws/kubectl 用桩替代）
└── validate-skill.sh          # 校验：静态检查、脚本离线测试、中英文结构对齐、FIS ID 对照（280+ 项）
```

## 近期变更

### v1.6.1 — 2026-11-09

**MCP 配置（三个 skill 一起更新：chaos-engineering-on-aws、aws-resilience-modeling、eks-resilience-checker）**
- 必需 Server 改为 AWS 托管的 **AWS MCP Server**（`aws-mcp`，经锁定版本的 `mcp-proxy-for-aws` 连接），取代已被替代的 `awslabs.aws-api-mcp-server`；EKS 使用 AWS 托管的 **Amazon EKS MCP Server**（`eks-mcp`）；`cloudwatch-mcp-server` 改为可选。
- 删除 `ALLOW_WRITE_OPERATIONS=true`：`aws-api-mcp-server` 中从来没有这个变量（真正的开关是 `READ_OPERATIONS_ONLY`，默认 `false`）。
- 只读类 skill 通过 IAM profile 保证只读；代理的 `--read-only` 参数会隐藏 `aws___call_aws` / `aws___run_script`，这类 skill 不能使用。
- 重写 `MCP_SETUP_GUIDE.md` / `_zh.md`（Kiro、Claude Code、Cursor/VS Code、IAM、多账号、故障排查）；FIS 角色示例改用 `AWSFaultInjectionSimulator*Access` 托管策略；只读策略中无效的 `elbv2:` 前缀改为 `elasticloadbalancing:`。
- 修复 `validate-all-skills.sh` 的链接检查：此前会误解析带锚点的链接，且因管道子 shell 从不计入失败数。

### v1.6.0 — 2026-11-09

**影响目标发现（P0）**
- `scripts/discover-dependencies.sh` — 新增：通过 AWS API 解析被测资源的全部真实端点（Aurora/RDS 集群与成员实例端点、ElastiCache 各节点端点、MSK broker、OpenSearch、EC2 IP/DNS），并行扫描本 Region 所有 EKS 集群（每个集群一份独立 kubeconfig），找出引用这些端点的工作负载：env 值、经 keyRef/envFrom/volume/projected volume 引用的 ConfigMap、ExternalName Service 及其调用方，以及（可选）Secret 键名，从不读取值。匹配带锚点，近似匹配单独列出，证据中的凭证会打码。输出 `checkpoints/step2-dependencies.json` 与 `monitoring/app-map.json`。移植自 [aws-samples/sample-fis-skills](https://github.com/aws-samples/sample-fis-skills) `app-service-log-analysis` 的依赖发现。
- `scripts/log-collector.sh` — 新增 `--app-map`：跨命名空间、跨集群采集所有 verified/confirmed 影响目标（Deployment、StatefulSet、DaemonSet、Job、裸 Pod）；每条日志新增 `namespace`（及 `cluster`）字段。
- `scripts/log-collector.sh` — 修复：不传 `--services` 时，命名空间里最后一个 deployment 会被静默漏掉（kubectl jsonpath 输出没有结尾换行）。
- `scripts/tests/` — 新增离线测试（bash + jq，aws/kubectl 用桩替代），由 `validate-skill.sh` 调用。
- `references/workflow-guide.md` — 步骤 2.2 影响目标发现；步骤 5 用 `--app-map` 启动 log-collector；步骤 6 数据完整性检查列出未扫描的集群。

**资源与 action 兼容性检查（P0）**
- `references/workflow-guide.md` — 步骤 2.1：`aws fis get-action` 的目标类型对照真实资源字段（`Engine`、`DBClusterIdentifier`、`InstanceLifecycle` 等），不匹配则阻断步骤 3，结果记入 `step2-assessment.json`。

**FIS 事实错误修正（P0）** — 对照官方 FIS actions 参考与 4 个 Scenario Library 页面
- 替换不存在的 action ID：`aws:ec2:disrupt-network-connectivity` → `aws:network:disrupt-connectivity`；`aws:elasticache:interrupt-cluster-az-power` → `aws:elasticache:replicationgroup-interrupt-az-power`；`aws:memorydb:interrupt-cluster-az-power`（MemoryDB 只有 `multi-region-cluster-pause-replication`）；`aws:kinesis:add-put-record-throttle` → `aws:kinesis:stream-provisioned-throughput-exception` / `stream-expired-iterator-exception`；`aws:directconnect:disrupt-connectivity` → `aws:directconnect:virtual-interface-disconnect`。
- `references/scenario-library.md` / `_zh.md` — 4 个场景按官方 Scenario Content JSON 重写：子动作、各 target 的标签（此前使用的 `IceQualified` 标签值并不存在）、权限；AZ 应用减速与跨 AZ 流量减速是 pod/ECS/SSM 的延迟与丢包场景，不是 NACL + Lambda。新增 AZ 断电按服务裁剪子动作（停止条件永不裁剪）。
- `references/templates/az-power-interruption.json` — 对齐官方 8 个子动作与 target，每个子动作配独立 target，任意一对都可裁剪；保留告警停止条件。
- `references/fis-actions.md` / `_zh.md` — 补充 20 个缺失的官方 action。
- Lambda action：按[官方指南](https://docs.aws.amazon.com/fis/latest/userguide/use-lambda-actions.html)，`AWS_FIS_CONFIGURATION_LOCATION` 是 S3 配置目录的 ARN（如 `arn:aws:s3:::bucket/FisConfigs/`），并需设置 `AWS_LAMBDA_EXEC_WRAPPER=/opt/aws-fis/bootstrap`。v1.4.0 中“必须是实验 ARN”的说法是错误的。

**FIS 模板库同步到 ee74d58（P1）**
- `references/fis-template-library-index.md` / `_zh.md` — 19 → 27 个场景（新增 agentcore-strands-agent-faults、database-blocking-locks、database-io-exhaustion、ecs-fargate-az-evacuation、ecs-fargate-az-impairment、eks-automode-az-impairment、elasticache-az-power-interruption、msk-broker-reboot），并更新已有条目的事实。
- `references/fis-templates/` — 5 套内嵌模板按上游逐字节同步，吸收上游修复（SQS 的 deny 收窄范围、清理不会被自己拦住、信任策略加防混淆代理条件；数据库连接耗尽在失败/取消时也会清理、强制 IMDSv2）；新增 3 套内嵌模板：`msk-broker-reboot`、`elasticache-redis-primary-node-reboot`、`elasticache-redis-primary-node-failover`（最后一套的上游缺陷写在其 README 中）。
- `references/fault-catalog.yaml` — 新增 `fis_ssm` 段（12 个基于 SSM 的故障）；修正 Scenario 子动作与标签；条目 42 → 54。

**中文文档**
- `references/workflow-guide_zh.md` — 完整重译；此前缺失英文版里的 INSUFFICIENT_DATA 处理、判定决策树、逐节写报告等护栏。
- `validate-skill.sh` — 新增中英文结构对齐检查（标题、代码块、表格），此类漂移今后会直接导致校验失败。

### v1.5.0 — 2026-04-16

**FIS 模板库集成（P1）**
- `references/fis-template-library-index.md` / `_zh.md` — 新增：来自 [aws-samples/fis-template-library](https://github.com/aws-samples/fis-template-library) 的全量 19 场景索引，按服务分类
- `references/fis-templates/` — 新增：5 个内嵌可直接部署的 FIS 模板（含 IAM 策略、SSM 自动化文档、部署 README）
- `references/scenario-library.md` / `_zh.md` — 新增外部模板库章节
- `references/workflow-guide.md` / `_zh.md` — 新增 SSM 自动化编排实验章节（3 种模式）

**新增示例（P2）**
- `examples/06-database-connection-exhaustion.md` / `_zh.md` — 数据库连接池耗尽实验
- `examples/07-redis-connection-failure.md` / `_zh.md` — Redis 连接中断实验
- `examples/08-sqs-queue-impairment.md` / `_zh.md` — SQS 队列渐进式故障实验

**假设验证增强（P2）**
- `examples/01-05`（10 个文件）— 所有现有示例新增验证要点清单

### v1.4.0 — 2026-04-15

**三层状态管理（P0）**
- `scripts/experiment-runner.sh` — `state.json` v2 schema：工作流追踪、实验数组、后台 PID、`flock` 并发写入保护
- `scripts/update-dashboard.sh` — 新增：从 state.json 自动生成 `output/dashboard.md`（monitor.sh 每周期调用）
- `scripts/render-dashboard.sh` — 新增：彩色 ASCII 终端看板（`watch -n 5 -c bash scripts/render-dashboard.sh`）
- `references/workflow-guide.md` — 会话中断恢复流程（检查 state.json → PID → FIS/CM 状态 → 恢复或重启）

**Monitor 与 Runner 改进（P0）**
- `scripts/monitor.sh` — `EXPERIMENT_ID` 改为可选；Chaos Mesh 实验不传即可（metrics-only 模式 + `DURATION` 超时）
- `scripts/monitor.sh` — 默认 `INTERVAL` 从 30s 改为 15s，提升数据密度
- `scripts/experiment-runner.sh` — 新增 `--one-shot` + `--pod-label` + `--deployment` 参数；pod-kill 实验在 AllInjected=True + Pods Ready 时自动完成，不再等到超时
- `scripts/experiment-runner.sh` — 新增 `--state-exp-id` 参数，在所有终态（completed/failed/timeout/aborted）自动更新 state.json

**日志采集器改进（P1）**
- `scripts/log-collector.sh` — `cleanup()` 先写 summary 再 kill 子进程（防止 SIGTERM 时数据丢失）
- `scripts/log-collector.sh` — 可中断 sleep（`sleep N & wait $!`），SIGTERM 立即响应
- `references/workflow-guide.md` — log-collector 启动标记为 MANDATORY（FIS 和 CM 实验均强制启动）

**安全与文档（P1）**
- `scripts/monitor.sh` — 修复 `OUTPUT_DIR` 变量未初始化导致 monitor 崩溃
- `references/fault-catalog.yaml` — `aws:fis:inject-api-throttle-error` 限定仅支持 ec2/kinesis（不含 dynamodb/s3 等）
- `references/fault-catalog.yaml` — Lambda FIS actions：`AWS_FIS_CONFIGURATION_LOCATION` 格式说明（必须是实验 ARN，非 S3 路径）—— **已在 v1.6.0 更正：该说法错误，官方格式是 S3 配置目录 ARN**
- `references/fis-actions.md` — Lambda 环境变量格式常见错误警告
- `references/workflow-guide.md` — Verdict Decision Tree：4 级数据完整性 → 判定映射（PASSED/FAILED、OBSERVED、BLOCKED）
- `references/report-templates.md` — 报告 §6.0.5：Data Completeness Check 在 verdict 前必须执行
- `SKILL_EN.md` / `SKILL_ZH.md` — Stop condition alarm 必须设置 `--treat-missing-data notBreaching`
- `scripts/update-dashboard.sh` / `scripts/render-dashboard.sh` — 临时文件使用 PID（`$$`）避免并发冲突

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
