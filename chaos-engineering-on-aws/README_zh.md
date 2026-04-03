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

> 无 MCP 时自动降级为 AWS CLI（`aws fis`、`aws cloudwatch`、`kubectl`）直接调用。

### Chaos Mesh MCP：EKS 认证方式

使用可选的 Chaos Mesh MCP Server 时，有以下两种方式认证 EKS 集群：

#### 方式一：静态 ServiceAccount Token（推荐）

一次性运行 setup 脚本，创建 RBAC 权限并生成包含长期 ServiceAccount Token 的独立 kubeconfig。**运行时不依赖 AWS CLI 或 IAM 凭证。**

```bash
# 一次性执行：创建 RBAC + 生成 kubeconfig（有效期 1 年）
cd /path/to/Chaosmesh-MCP
./setup-eks-permissions.sh

# 用生成的 kubeconfig 启动 Chaos Mesh MCP Server
python server.py --kubeconfig ./chaos-mesh-mcp-kubeconfig
```

MCP 配置：
```json
{
  "mcpServers": {
    "chaosmesh-mcp": {
      "command": "python",
      "args": ["/path/to/Chaosmesh-MCP/server.py", "--kubeconfig", "/path/to/chaos-mesh-mcp-kubeconfig"]
    }
  }
}
```

✅ 可移植，运行时无 AWS 依赖  
✅ 最小权限（仅 Chaos Mesh 相关）  
⚠️ Token 1 年后过期，到期需重新执行脚本生成

#### 方式二：管理员 kubeconfig（exec 认证）

如果集群管理员直接提供 kubeconfig 文件（通常由 `aws eks update-kubeconfig` 生成），MCP Server 可以直接使用，每次请求时通过 `aws eks get-token` 获取临时 Token。

```bash
# 用管理员提供的 kubeconfig 启动
python server.py --kubeconfig /path/to/admin-kubeconfig

# 或通过环境变量设置
export KUBECONFIG=/path/to/admin-kubeconfig
python server.py
```

**前提条件：** 机器需安装 `aws` CLI + 有效 AWS 凭证（IAM Role / `~/.aws/credentials`）+ 该 IAM 身份已在 EKS `aws-auth` ConfigMap 中映射。

✅ 无需额外配置，复用已有管理员凭证  
⚠️ 运行时依赖 AWS CLI + IAM 凭证  
⚠️ 权限为 admin 级别（范围过大）

> **建议：** 生产环境使用方式一。测试时如管理员可直接提供 kubeconfig，使用方式二更快捷。

完整配置指南：[MCP_SETUP_GUIDE.md](MCP_SETUP_GUIDE.md)

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

```
AZ/Region 级复合故障  →  FIS Scenario Library
  ├── AZ 电源中断（EC2 + RDS + EBS + ElastiCache 联动）
  ├── AZ 应用延迟（网络延迟注入）
  ├── 跨 AZ 流量劣化（跨 AZ 丢包）
  └── 跨 Region 连通性（TGW + 路由表中断）
  ⚠️ 场景不是完整模板——通过 Console 创建后导出，或从 Content tab 复制并通过 API 补全参数

AWS 托管服务 / 基础设施层  →  AWS FIS（单 action）
  ├── 节点级：   eks:terminate-nodegroup-instances
  ├── 实例级：   ec2:terminate/stop/reboot
  ├── 数据库级： rds:failover, rds:reboot
  ├── 网络级：   network:disrupt-connectivity
  └── Serverless：lambda:invocation-add-delay/error

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
│   ├── fault-catalog.yaml      # 统一故障类型注册表（ChaosMesh + FIS + Scenarios）
│   ├── scenario-library_zh.md  # FIS Scenario Library 模板与要求
│   ├── prerequisites-checklist_zh.md  # 按架构模式分类的前置条件
│   ├── fis-actions_zh.md       # FIS actions 参考
│   ├── chaosmesh-crds_zh.md    # Chaos Mesh CRD 参考
│   ├── report-templates_zh.md  # 报告生成模板
│   └── gameday_zh.md           # Game Day 演练指南
├── scripts/
│   ├── monitor.sh              # 监控脚本模板
│   ├── log-collector.sh        # Pod 日志收集 + 错误分类
│   └── setup-prerequisites.sh  # 可选的前置环境准备脚本
└── e2e-tests/                  # 端到端测试
```
