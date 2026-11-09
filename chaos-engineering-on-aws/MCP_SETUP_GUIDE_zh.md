# MCP Server 配置指南

本 Skill 通过 **AWS MCP Server**（由 AWS 托管的远程 MCP Server）访问 AWS。
Kubernetes 侧的 Server 为可选项。没有任何 MCP Server 时，Skill 退回到直接使用 AWS CLI 和
`kubectl`（见 [无 MCP 降级](#无-mcp-降级)）。

> **变更说明（2026-11）**：`awslabs.aws-api-mcp-server` 已被
> [AWS MCP Server](https://docs.aws.amazon.com/agent-toolkit/latest/userguide/mcp-server.html) 取代
> （[迁移指南](https://github.com/awslabs/mcp/blob/main/src/aws-api-mcp-server/MIGRATION.md)）。
> 本指南以前要求设置的 `ALLOW_WRITE_OPERATIONS=true` 在 `aws-api-mcp-server` 中**从来不存在**
> （真正的开关是 `READ_OPERATIONS_ONLY`，默认 `false`），设置它没有任何效果。请把旧 Server 条目和这个变量
> 一起从配置中删除；新旧 Server 同时运行会造成工具冲突。

| Server | 状态 | 是否必需 | 用途 |
|--------|------|----------|------|
| `aws-mcp` — [AWS MCP Server](https://docs.aws.amazon.com/agent-toolkit/latest/userguide/mcp-server.html) | AWS 托管，**预览** | 是 | 所有 AWS API 调用（FIS、CloudWatch、EC2、RDS、EKS、IAM 等），以及 AWS 文档检索 |
| `eks-mcp` — [Amazon EKS MCP Server](https://docs.aws.amazon.com/eks/latest/userguide/eks-mcp-introduction.html) | AWS 托管，**预览** | 目标运行在 EKS 上时 | 集群与 Kubernetes 资源查询、Pod 日志、事件 |
| `awslabs.cloudwatch-mcp-server` | 开源，本地运行 | 否 | 只在需要它的告警建议、日志分析工具时使用。普通 CloudWatch API 调用已经走 `aws-mcp` |
| `chaosmesh-mcp` — [RadiumGu/Chaosmesh-MCP](https://github.com/RadiumGu/Chaosmesh-MCP) | 社区项目（非 AWS） | 已安装 Chaos Mesh 时 | 创建 Chaos Mesh CRD、查询状态 |

---

## 1. AWS MCP Server（必需）

**前置条件**：Python 3.10+ 与 [uv](https://docs.astral.sh/uv/getting-started/installation/)（提供
`uvx`），以及本机上的 AWS 凭证（`aws login`、`aws configure sso` 或 profile）。

客户端只运行一个轻量的本地代理 [`mcp-proxy-for-aws`](https://pypi.org/project/mcp-proxy-for-aws/)，
它用你的凭证做 SigV4 签名，再把请求转发到 AWS 托管的端点。

- **端点 Region**（MCP Server 运行的位置）：`us-east-1`、`us-west-2`、`ap-southeast-1`、
  `ap-southeast-2`、`ap-northeast-1`、`eu-central-1`、`eu-west-1`、`eu-west-2`，地址为
  `https://aws-mcp.<region>.api.aws/mcp`。
- **操作 Region**（AWS 调用的默认 Region）：`--metadata AWS_REGION=<region>`。
  两者可以不同；不传 metadata 时，操作默认落在 `us-east-1`。
- **锁定代理版本**（AWS 建议的供应链控制措施）。本指南使用 2026-11-09 的最新版 `1.8.0`；
  升级时请有意识地修改版本号。

### Kiro

`.kiro/settings/mcp.json`（工作区）或 `~/.kiro/settings/mcp.json`（用户级）：

```json
{
  "mcpServers": {
    "aws-mcp": {
      "command": "uvx",
      "timeout": 100000,
      "args": [
        "mcp-proxy-for-aws@1.8.0",
        "https://aws-mcp.ap-northeast-1.api.aws/mcp",
        "--profile", "default",
        "--metadata", "AWS_REGION=ap-northeast-1"
      ]
    }
  }
}
```

### Claude Code

```bash
claude mcp add aws-mcp -- uvx mcp-proxy-for-aws@1.8.0 \
  https://aws-mcp.ap-northeast-1.api.aws/mcp \
  --profile default --metadata AWS_REGION=ap-northeast-1
```

### Cursor / VS Code

与 Kiro 相同的 JSON，写入 `.cursor/mcp.json` 或 `.vscode/mcp.json`。

### 权限

AWS MCP Server **用你的凭证**调用 AWS：所需的 IAM 权限与在 CLI 中执行同样的 API 调用完全相同。
混沌实验需要写权限（`fis:CreateExperimentTemplate`、`fis:StartExperiment`、`fis:StopExperiment`、
`cloudwatch:PutMetricAlarm`，以及对 FIS 角色的 `iam:PassRole`），因此本 Skill **不要**给代理加
`--read-only`。

- 旧的 `aws-mcp:InvokeMcp` / `aws-mcp:Call*` IAM 动作已不再生效，请删除。
- 如需区别对待 agent 流量与人工流量，可在身份策略或 SCP 中使用全局条件键
  `aws:ViaAWSMCPService` / `aws:CalledViaAWSMCP`（例如在生产账号中禁止经 MCP 调用 `fis:StartExperiment`）。
- 每次调用都会记录到 CloudTrail，Server 也会发布 CloudWatch 指标，便于单独审计 agent 活动。

---

## 2. Amazon EKS MCP Server（EKS 目标）

由 AWS 托管，通过同一个代理连接。请确认你的 Region 已提供该服务；该服务处于预览阶段，可能变化。

```json
{
  "mcpServers": {
    "eks-mcp": {
      "command": "uvx",
      "timeout": 100000,
      "args": [
        "mcp-proxy-for-aws@1.8.0",
        "https://eks-mcp.ap-northeast-1.api.aws/mcp",
        "--service", "eks-mcp",
        "--profile", "default",
        "--region", "ap-northeast-1"
      ]
    }
  }
}
```

```bash
claude mcp add eks-mcp -- uvx mcp-proxy-for-aws@1.8.0 \
  https://eks-mcp.ap-northeast-1.api.aws/mcp \
  --service eks-mcp --profile default --region ap-northeast-1
```

**IAM**：`eks-mcp:InvokeMcp`（初始化、列出工具）、`eks-mcp:CallReadOnlyTool`（只读工具）、
`eks-mcp:CallPrivilegedTool`（写工具），或直接使用托管策略 `AmazonEKSMCPReadOnlyAccess`。
本 Skill 只需要只读工具：故障注入本身通过 FIS 或 Chaos Mesh 完成。
该 IAM 主体还需要在集群中有 Kubernetes 身份（EKS access entry）。

> 无法使用托管 Server 时，开源、本地运行的 `awslabs.eks-mcp-server` 依然可用
> （`uvx awslabs.eks-mcp-server@latest`；不加 `--allow-write` 启动时为只读）。

---

## 3. cloudwatch-mcp-server（可选）

只在需要它的高层工具（告警建议、日志组分析）时配置。指标查询和用于停止条件的 `put-metric-alarm`
已经可以通过 `aws-mcp` 完成，`scripts/monitor.sh` 也是用 AWS CLI 读取指标。

```json
{
  "mcpServers": {
    "cloudwatch-mcp": {
      "command": "uvx",
      "args": ["awslabs.cloudwatch-mcp-server@latest"],
      "env": { "AWS_PROFILE": "default", "AWS_REGION": "ap-northeast-1", "FASTMCP_LOG_LEVEL": "ERROR" }
    }
  }
}
```

---

## 4. chaosmesh-mcp（可选，社区项目）

**条件**：EKS 集群已安装 Chaos Mesh。**仓库**：
[RadiumGu/Chaosmesh-MCP](https://github.com/RadiumGu/Chaosmesh-MCP)——社区项目，不是 AWS 服务；
面向客户使用时请明确说明。

EKS 认证（详见该项目的
[EKS Authentication Methods](https://github.com/RadiumGu/Chaosmesh-MCP#eks-authentication-methods)）：

- **静态 ServiceAccount Token（推荐）**：运行一次它的 `setup-eks-permissions.sh`，会创建仅限
  Chaos Mesh 的最小权限 RBAC 和一个自包含的 kubeconfig。运行时不需要 AWS 凭证；Token 会过期（默认 1 年）。
- **管理员 kubeconfig**：由 `aws eks update-kubeconfig` 生成的 kubeconfig（通过 exec 调用
  `aws eks get-token`）；适合快速测试，权限等同于管理员。

```json
{
  "mcpServers": {
    "chaosmesh-mcp": {
      "command": "python3",
      "args": ["/path/to/Chaosmesh-MCP/server.py", "--kubeconfig", "/path/to/chaos-mesh-mcp-kubeconfig"]
    }
  }
}
```

---

## 完整配置示例

```json
{
  "mcpServers": {
    "aws-mcp": {
      "command": "uvx",
      "timeout": 100000,
      "args": [
        "mcp-proxy-for-aws@1.8.0",
        "https://aws-mcp.ap-northeast-1.api.aws/mcp",
        "--profile", "default",
        "--metadata", "AWS_REGION=ap-northeast-1"
      ]
    },
    "eks-mcp": {
      "command": "uvx",
      "timeout": 100000,
      "args": [
        "mcp-proxy-for-aws@1.8.0",
        "https://eks-mcp.ap-northeast-1.api.aws/mcp",
        "--service", "eks-mcp",
        "--profile", "default",
        "--region", "ap-northeast-1"
      ]
    },
    "chaosmesh-mcp": {
      "command": "python3",
      "args": ["/path/to/Chaosmesh-MCP/server.py", "--kubeconfig", "/path/to/chaos-mesh-mcp-kubeconfig"]
    }
  }
}
```

---

## AWS 凭证

代理和 CLI 降级路径都使用标准凭证链：

```bash
aws login                         # 推荐：浏览器登录，凭证自动轮换
aws configure sso                 # IAM Identity Center
aws configure --profile default   # 长期或临时密钥
aws sts get-caller-identity       # 验证
```

同一会话访问多个账号：`--profile prod-readonly staging`（第一个为默认，agent 可按次切换）。
出现 `ExpiredTokenException` 表示会话已过期：刷新凭证后重启 MCP 客户端。

---

## FIS IAM Role

FIS 需要独立的执行角色。缺失时，Skill 的步骤 4 会生成创建命令。快速上手参考（生产环境请使用最小权限）：

```bash
aws iam create-role \
  --role-name FISExperimentRole \
  --assume-role-policy-document '{
    "Version": "2012-10-17",
    "Statement": [{
      "Effect": "Allow",
      "Principal": {"Service": "fis.amazonaws.com"},
      "Action": "sts:AssumeRole"
    }]
  }'

# FIS 的 AWS 托管策略，按实验需要附加
aws iam attach-role-policy --role-name FISExperimentRole \
  --policy-arn arn:aws:iam::aws:policy/service-role/AWSFaultInjectionSimulatorEC2Access
aws iam attach-role-policy --role-name FISExperimentRole \
  --policy-arn arn:aws:iam::aws:policy/service-role/AWSFaultInjectionSimulatorRDSAccess
aws iam attach-role-policy --role-name FISExperimentRole \
  --policy-arn arn:aws:iam::aws:policy/service-role/AWSFaultInjectionSimulatorEKSAccess
aws iam attach-role-policy --role-name FISExperimentRole \
  --policy-arn arn:aws:iam::aws:policy/service-role/AWSFaultInjectionSimulatorNetworkAccess
```

> `references/fis-templates/` 下可直接部署的模板自带收窄过的角色策略，优先使用它们而不是宽泛的托管策略。

---

## 验证配置

```bash
# MCP Server 已加载（Kiro CLI：/mcp 或 /tools；Claude Code：/mcp 或 `claude mcp list`）
# aws-mcp 应提供 aws___call_aws、aws___run_script、aws___search_documentation 等工具

aws sts get-caller-identity
aws fis list-experiment-templates --max-results 1
aws cloudwatch describe-alarms --max-items 1
aws eks list-clusters                 # 如为 EKS
kubectl get crd | grep chaos-mesh     # 如已安装 Chaos Mesh
```

---

## 无 MCP 降级

没有可用的 MCP Server 时，Skill 直接使用 AWS CLI 和 `kubectl`；后台脚本
（`experiment-runner.sh`、`monitor.sh`、`log-collector.sh`、`discover-dependencies.sh`）始终使用 CLI。

| 操作 | 有 MCP | CLI 降级 |
|------|--------|----------|
| FIS 实验 | `aws-mcp` | `aws fis create-experiment-template` / `start-experiment` |
| 指标与告警 | `aws-mcp` | `aws cloudwatch get-metric-data` / `put-metric-alarm` |
| Kubernetes 查询 | `eks-mcp` | `kubectl` |
| Chaos Mesh | `chaosmesh-mcp` | `kubectl apply -f` |

功能保持完整；只是 agent 需要自己构造 JSON/YAML，而不是使用带类型约束的工具。
