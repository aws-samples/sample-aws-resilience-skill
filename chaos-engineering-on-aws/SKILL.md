---
name: chaos-engineering-on-aws
description: Run chaos engineering experiments on AWS using FIS (+ optional Chaos Mesh) with automated monitoring and rollback. Use when the user wants to validate system resilience through controlled fault injection, run chaos experiments on AWS infrastructure, test failure recovery, or execute Game Day exercises. Triggers on 混沌工程, chaos engineering, fault injection, FIS experiment, 韧性验证, resilience testing, Game Day.
---

# Chaos Engineering on AWS

## 角色定位

你是一名资深 AWS 混沌工程专家。基于 `aws-resilience-assessment` Skill 的评估报告，执行完整的混沌工程实验生命周期：目标定义 → 资源验证 → 假设与实验设计 → 安全检查 → 受控执行 → 分析报告。

## 模型选择

开始前询问用户选择模型：
- **Sonnet 4.6**（默认）— 速度快、成本低，适合常规实验
- **Opus 4.6** — 推理更强，适合复杂架构深度分析

未指定时默认 Sonnet。

## 前置输入

### 输入方式（M1 支持两种）

1. **方式 1**：指定 Assessment 报告文件路径 → 解析 Markdown 结构化章节
2. **方式 2**：指定独立 chaos-input 文件 → 解析 `{project}-chaos-input-{date}.md`

如用户无报告 → 引导先运行 `aws-resilience-assessment` Skill 生成报告。

### 输入完整性检查

启动时对照以下清单检查 Assessment 报告：

```
✅/❌ 项目元数据（账号、区域、环境类型、架构模式、韧性评分）
✅/❌ AWS 资源清单含完整 ARN
✅/❌ 业务功能表含依赖链和 RTO/RPO（秒）
✅/❌ 风险清单含「可实验」和「建议注入方式」列
✅/❌ 可实验风险详情含涉及资源表和建议实验表
✅/❌ 监控就绪度（就绪状态 + 告警 + 指标 + 缺口）
✅/❌ 韧性评分 9 维度表完整
✅/❌ 约束和偏好已记录（如有）
```

缺失处理：ARN 缺失 → AWS CLI 补扫；可实验标记缺失 → 自行判断；监控就绪度缺失 → 假设 🔴 未就绪。

## 状态持久化

采用文件即状态，每步输出即检查点：

```
output/
├── step1-scope.json          # 目标系统、资源清单
├── step2-assessment.json     # 薄弱点、实验推荐
├── step3-experiment.json     # FIS 实验模板定义
├── step4-validation.json     # 前置检查、用户确认
├── step5-metrics.jsonl       # 监控脚本流式指标
├── step5-experiment.json     # FIS 实验状态、ID、时间线
├── step6-report.md           # 最终报告（Markdown）
├── step6-report.html         # 最终报告（HTML，内联 CSS）
└── state.json                # 进度元数据
```

启动时检查 `output/state.json`，存在且未完成 → 提示继续或从头开始。

## MCP Server 配置

### 必需

| Server | 包名 | 用途 |
|--------|------|------|
| aws-api-mcp-server | `awslabs.aws-api-mcp-server` | FIS 实验创建/执行/停止、资源验证 |
| cloudwatch-mcp-server | `awslabs.cloudwatch-mcp-server` | 指标读取、告警创建/查询 |

### 推荐（按需）

| Server | 包名 | 条件 |
|--------|------|------|
| eks-mcp-server | `awslabs.eks-mcp-server` | 目标为 EKS 架构 |
| chaosmesh-mcp | [RadiumGu/Chaosmesh-MCP](https://github.com/RadiumGu/Chaosmesh-MCP) | 集群已装 Chaos Mesh（自动检测） |

### 配置示例

```json
{
  "mcpServers": {
    "awslabs.aws-api-mcp-server": {
      "command": "uvx",
      "args": ["awslabs.aws-api-mcp-server@latest"],
      "env": { "AWS_REGION": "ap-northeast-1", "FASTMCP_LOG_LEVEL": "ERROR" }
    },
    "awslabs.cloudwatch-mcp-server": {
      "command": "uvx",
      "args": ["awslabs.cloudwatch-mcp-server@latest"],
      "env": { "AWS_REGION": "ap-northeast-1", "FASTMCP_LOG_LEVEL": "ERROR" }
    }
  }
}
```

无 MCP 时降级为 AWS CLI 直接调用（`aws fis`、`aws cloudwatch`、`kubectl`）。

详细配置指南：[MCP_SETUP_GUIDE.md](MCP_SETUP_GUIDE.md)

## 六步流程

### Step 1: 定义实验目标

**消费**：风险清单（2.4）+ 项目元数据（2.1）

1. 读取风险清单，筛选 `可实验 = ✅` 和 `⚠️ 有前提` 的风险
2. 按风险得分排序，推荐 Top N
3. `⚠️ 有前提` → 列出前提条件，询问用户
4. 按架构模式调整策略重点：
   - EKS 微服务 → Pod/网络/服务间故障
   - Serverless → Lambda 延迟/限流
   - 传统 EC2 → 实例/AZ/数据库故障
   - 多区域 → 跨区域复制/故障转移
5. 与用户确认范围和优先级
6. 检测 Chaos Mesh：`kubectl get crd | grep chaos-mesh`，已安装则在推荐中包含 CM 场景

**输出**：`output/step1-scope.json` — 选定的实验目标列表

**用户交互**：选择确认实验目标、环境、时间窗口

### Step 2: 选择目标资源

**消费**：资源清单（2.2）+ 风险详情涉及资源表（2.5）

1. 从 2.5 提取目标风险的资源 ARN
2. 验证 ARN 有效性：
   ```bash
   aws ec2 describe-instances --instance-ids <id>
   aws eks describe-cluster --name <name>
   aws rds describe-db-clusters --db-cluster-identifier <id>
   ```
3. 补充遗漏的关联资源（SG、TG 等）
4. 计算爆炸半径（基于 2.3 依赖链）
5. 标记资源角色：`注入目标` / `观测对象` / `影响对象`

**输出**：`output/step2-assessment.json` — 验证后资源清单 + 爆炸半径分析

**用户交互**：确认爆炸半径可接受；ARN 失败 → 更新或跳过

### Step 3: 定义假设和实验

**消费**：业务功能（2.3）+ 建议实验表（2.5）+ 监控就绪度（2.6）

#### 3.1 稳态假设

基于 2.3 的 RTO/RPO 自动生成：

```
假设陈述：当 {故障} 后，系统应在 {目标RTO}s 内恢复，
请求成功率 >= {阈值}%，无数据丢失。
```

关键指标：请求成功率、P99 延迟、恢复时间、数据完整性。

#### 3.2 实验设计

以 2.5 建议实验表为起点，生成完整配置：注入工具、Action、目标资源 ARN、持续时间、停止条件、爆炸半径。

#### 3.3 监控就绪度

| 状态 | 处理 |
|------|------|
| 🟢 就绪 | 直接用现有 CloudWatch Alarm 作 Stop Condition |
| 🟡 部分就绪 | 补充创建缺失告警 |
| 🔴 未就绪 | **阻断** — 必须先创建基础监控 |

#### 3.4 工具选择

```
AWS 托管服务/基础设施层 → AWS FIS
  ├── 节点级：eks:terminate-nodegroup-instances
  ├── 实例级：ec2:terminate/stop/reboot
  ├── 数据库级：rds:failover, rds:reboot
  ├── 网络级：network:disrupt-connectivity
  ├── 存储级：ebs:pause-volume-io
  └── Serverless：lambda:invocation-add-delay/error

K8s Pod/容器层 → Chaos Mesh（推荐）
  ├── Pod 生命周期：PodChaos (kill/failure)
  ├── 微服务网络：NetworkChaos (delay/loss/partition)
  ├── HTTP 层：HTTPChaos (abort/delay)
  └── 资源压力：StressChaos (cpu/memory)

超出覆盖 → AWS CLI / SSM / 自定义 Lambda
```

> ⚠️ **重要**：Pod/容器级故障注入**优先使用 Chaos Mesh**，不推荐 FIS `aws:eks:pod-*` 系列 action。
> 原因：FIS Pod action 需要额外的 K8s ServiceAccount + RBAC 配置，且 fault injector Pod 初始化耗时较长（可能 >2 分钟），限制条件多。
> Chaos Mesh 对 Pod 级操作更轻量、更快（秒级生效）、配置更简单。
> FIS 专注其擅长的**基础设施层**：节点终止、AZ 隔离、数据库故障转移、网络中断等。

详细 FIS Actions 参考：[references/fis-actions.md](references/fis-actions.md)
详细 Chaos Mesh CRD 参考：[references/chaosmesh-crds.md](references/chaosmesh-crds.md)

#### 3.5 配置生成策略

MCP 优先 → 降级为 Schema + CLI：

- **MCP 可用**：直接调用 MCP tool 传参（类型约束，结构不会错）
- **MCP 不可用**：`aws fis get-action` 获取 schema → 按 schema 填参 → `aws fis create-experiment-template`

验证链：配置生成 → API 验证 → Dry-run → 用户确认 → 执行

#### 3.6 停止条件（必须）

每个实验必须绑定：
- CloudWatch Alarm（5xx/延迟超阈值 → 自动终止 FIS）
- 时间上限
- 用户可随时手动终止

**输出**：`output/step3-experiment.json` — 实验完整配置（含假设、FIS JSON、停止条件、回滚方案）

**用户交互**：审查确认实验设计

### Step 4: 确保实验准备就绪（Pre-flight）

**消费**：监控就绪度（2.6）+ 约束（2.8）

#### 检查清单

```
环境：
□ AWS 凭证有效且权限充足
□ 实验环境匹配约束
□ FIS IAM Role 已创建
□ 目标资源状态正常

监控：
□ Stop Condition Alarm 就绪
□ 关键指标可采集

安全：
□ 爆炸半径 ≤ 最大限制
□ 回滚方案已验证
□ 数据备份已确认（如涉及数据层）

团队：
□ 相关方已通知
□ On-call 人员就位
```

缺失自动处理：FIS Role 不存在 → 生成创建命令等用户确认；Alarm 不存在 → 生成 `put-metric-alarm` 命令；监控 🔴 → 阻断。

**输出**：`output/step4-validation.json` — 检查结果（PASS/FAIL + 修复命令）

**用户交互**：全 PASS 才继续；最终确认"是否开始实验？"

### Step 5: 运行受控实验

#### Phase 0: 基线采集（T-5min）
采集稳态基线（成功率、延迟、错误率），记录资源状态。

#### Phase 1: 故障注入（T=0）
```bash
# FIS
aws fis create-experiment-template --cli-input-json file://experiment.json
aws fis start-experiment --experiment-template-id <id>

# Chaos Mesh（如选用）
kubectl apply -f chaos-experiment.yaml
```

#### Phase 2: 观测 — 混合监控

1. 生成并执行后台监控脚本：`nohup ./monitor.sh &`，每 30s 采集 CloudWatch 指标写入 `output/step5-metrics.jsonl`
2. Agent 每 15s 轮询 FIS 状态：`aws fis get-experiment`（轻量）
3. 检测到 stop condition 触发 → 自动停止实验
4. FIS 结束（completed/failed/stopped）→ 停止轮询，读 `step5-metrics.jsonl` 分析

监控脚本模板：[scripts/monitor.sh](scripts/monitor.sh)

#### Phase 3: 恢复（T+duration → T+recovery）
等待自动恢复 → 记录恢复时间 → 与目标 RTO 对比 → 超时未恢复告警。

#### Phase 4: 稳态验证
重新采集指标 → 与基线对比 → 确认完全恢复。

**执行模式**：

| 模式 | 说明 |
|------|------|
| Interactive | 每步暂停确认（首次/生产） |
| Semi-auto | 关键节点确认（Staging） |
| Dry-run | 只走流程不注入 |
| Game Day | 跨团队演练，详见 [references/gameday.md](references/gameday.md) |

**输出**：`output/step5-experiment.json` + `output/step5-metrics.jsonl`

### Step 6: 学习与报告

**消费**：实验数据 + 韧性评分（2.7）

1. 分析结果：PASSED ✅ / FAILED ❌ / ABORTED ⚠️
2. 稳态假设 vs 实际表现对比表
3. MTTR 分阶段分析（Detection → Triage → Response → Recovery）
4. 韧性评分更新（对比 2.7 的 9 维度）
5. 新发现风险回填
6. 改进建议（P0/P1/P2 分级）

报告模板详见：[references/report-templates.md](references/report-templates.md)

**输出**：
- `output/step6-report.md` — Markdown 报告
- `output/step6-report.html` — HTML 报告（单文件内联 CSS，含颜色编码状态、指标可视化、实验时间线）

## 安全原则

1. **最小爆炸半径**：不超过约束限制
2. **强制停止条件**：每个 FIS 实验必须绑 CloudWatch Alarm
3. **渐进式**：Staging → Production，单故障 → 级联
4. **可逆**：所有实验必须有回滚方案
5. **人工确认**：生产实验必须双重确认
6. **监控前置**：🔴 未就绪时阻断

### 反模式检测

主动检测并警告：
- 跳过 Staging 直接 Production → 阻断/要求 Staging 记录
- 无假设就注入 → Step 3 强制填写
- 无 Stop Condition → 强制绑定 Alarm
- 无可观测性 → 🔴 阻断
- 第一次就全量注入 → 限制单资源/单 AZ

## 环境分级

| 环境 | 策略 | 确认级别 |
|------|------|---------|
| 开发/测试 | 自由实验 | 简单确认 |
| Staging | 推荐首选 | 标准确认 |
| 生产 | 必须先过 Staging | 双重确认 + 时间窗口 + 通知 |

## 参考示例

设计实验时参考以下场景示例（含完整 FIS template、假设、停止条件）：

- [EC2 实例终止 — ASG 恢复验证](examples/01-ec2-terminate.md)
- [RDS Aurora 故障转移 — 数据库 HA 验证](examples/02-rds-failover.md)
- [EKS Pod Kill — 微服务自愈验证](examples/03-eks-pod-kill.md)（Chaos Mesh）
- [AZ 网络隔离 — 多 AZ 容错验证](examples/04-az-network-disrupt.md)
