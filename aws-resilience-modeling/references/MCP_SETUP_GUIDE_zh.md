# AWS MCP Server 配置指南

本指南说明如何为 AWS 韧性评估 Skill 配置 MCP 服务器，适用于 **Kiro**、**Claude Code** 和 Cursor / VS Code。

> **变更说明（2026-11）**：`awslabs.aws-api-mcp-server` 已被 AWS 托管的
> [AWS MCP Server](https://docs.aws.amazon.com/agent-toolkit/latest/userguide/mcp-server.html) 取代
> （[迁移指南](https://github.com/awslabs/mcp/blob/main/src/aws-api-mcp-server/MIGRATION.md)），
> `awslabs.iam-mcp-server` 也已弃用并由其替代。请删除旧条目：新旧 Server 同时运行会造成工具冲突。

| Server | 状态 | 是否必需 | 用途 |
|--------|------|----------|------|
| `aws-mcp` — [AWS MCP Server](https://docs.aws.amazon.com/agent-toolkit/latest/userguide/mcp-server.html) | AWS 托管，**预览** | 是 | 评估中所有 Describe/Get/List 调用（EC2、RDS、ELB、S3、Lambda、DynamoDB、ElastiCache、IAM、CloudWatch、CloudTrail 等），以及 AWS 文档检索 |
| `eks-mcp` — [Amazon EKS MCP Server](https://docs.aws.amazon.com/eks/latest/userguide/eks-mcp-introduction.html) | AWS 托管，**预览** | EKS 架构时 | 集群与 Kubernetes 资源检查 |
| `ecs-mcp` — [Amazon ECS MCP Server](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/ecs-mcp-introduction.html) | AWS 托管，**预览** | ECS / Fargate 架构时 | 集群、服务与任务检查 |
| `cloudwatch-mcp` — `awslabs.cloudwatch-mcp-server` | 开源，本地运行 | 否 | 它的日志异常与告警建议工具（监控就绪度、SLI/SLO 分析） |
| `aws-pricing-mcp` — `awslabs.aws-pricing-mcp-server` | 开源，本地运行 | 否 | 改进方案的成本估算 |

本指南以前列出的单服务 Server（`dynamodb`、`lambda-tool`、`elasticache`、`cloudtrail`、`iam`）已不再需要：
AWS MCP Server 可以调用相同的 API。

---

## 只读：靠 IAM 保证，而不是 `--read-only`

评估不得修改任何东西。使用 AWS MCP Server 时，这一点由**连接所用 profile 的 IAM 权限**保证，
因为 Server 用你的凭证调用 AWS。

- 用只有读权限的 profile 连接（下文的[最小只读策略](#最小-iam-权限策略只读访问)，或 `ReadOnlyAccess`）。
- 本 Skill **不要**给代理加 `--read-only`。该参数会隐藏所有未标注 `readOnlyHint=true` 的工具，而
  `aws___call_aws` / `aws___run_script` 的行为取决于 IAM，无法带上这个标注——结果是 agent 失去全部 AWS API 访问能力
  （AWS 已在 [agent-toolkit-for-aws#45](https://github.com/aws/agent-toolkit-for-aws/issues/45) 中确认）。
- 可选：在身份策略或 SCP 中用全局条件键 `aws:ViaAWSMCPService` / `aws:CalledViaAWSMCP`，只对经 MCP 发起的
  非读操作加一道拒绝护栏。
- 每次调用都会记录到 CloudTrail，可单独归因到 MCP Server。

---

## 1. AWS MCP Server（必需）

**前置条件**：Python 3.10+ 与 [uv](https://docs.astral.sh/uv/getting-started/installation/)（提供 `uvx`），
以及 AWS 凭证（`aws login`、`aws configure sso` 或 profile）。

客户端只运行一个轻量的本地代理 [`mcp-proxy-for-aws`](https://pypi.org/project/mcp-proxy-for-aws/)，
用你的凭证做 SigV4 签名后转发到 AWS 托管的端点。

- **端点 Region**：`us-east-1`、`us-west-2`、`ap-southeast-1`、`ap-southeast-2`、`ap-northeast-1`、
  `eu-central-1`、`eu-west-1`、`eu-west-2`，地址为 `https://aws-mcp.<region>.api.aws/mcp`。
- **操作 Region**（AWS 调用的默认 Region）：`--metadata AWS_REGION=<region>`；不传时默认 `us-east-1`。
- **锁定代理版本**。本指南使用 `1.8.0`（2026-11-09 的最新版）。

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
        "https://aws-mcp.us-east-1.api.aws/mcp",
        "--profile", "resilience-readonly",
        "--metadata", "AWS_REGION=us-east-1"
      ]
    }
  }
}
```

### Claude Code

```bash
claude mcp add aws-mcp -- uvx mcp-proxy-for-aws@1.8.0 \
  https://aws-mcp.us-east-1.api.aws/mcp \
  --profile resilience-readonly --metadata AWS_REGION=us-east-1
```

### Cursor / VS Code

与 Kiro 相同的 JSON，写入 `.cursor/mcp.json` 或 `.vscode/mcp.json`。

---

## 2. 容器类 Server（按需）

两者均由 AWS 托管（预览），通过同一个代理连接。请确认你的 Region 已提供。

### Amazon EKS MCP Server

```json
{
  "mcpServers": {
    "eks-mcp": {
      "command": "uvx",
      "timeout": 100000,
      "args": [
        "mcp-proxy-for-aws@1.8.0",
        "https://eks-mcp.us-east-1.api.aws/mcp",
        "--service", "eks-mcp",
        "--profile", "resilience-readonly",
        "--region", "us-east-1"
      ]
    }
  }
}
```

IAM：`eks-mcp:InvokeMcp` + `eks-mcp:CallReadOnlyTool`，或托管策略 `AmazonEKSMCPReadOnlyAccess`。
评估场景不要授予 `eks-mcp:CallPrivilegedTool`。该主体还需要在每个集群中有 Kubernetes 身份（EKS access entry）。
无法使用托管 Server 时，开源的 `awslabs.eks-mcp-server`（`uvx awslabs.eks-mcp-server@latest`）可在本地运行，
不加 `--allow-write` 启动时为只读。

### Amazon ECS MCP Server

```json
{
  "mcpServers": {
    "ecs-mcp": {
      "command": "uvx",
      "timeout": 100000,
      "args": [
        "mcp-proxy-for-aws@1.8.0",
        "https://ecs-mcp.us-east-1.api.aws/mcp",
        "--service", "ecs-mcp",
        "--profile", "resilience-readonly",
        "--region", "us-east-1"
      ]
    }
  }
}
```

IAM：`ecs-mcp:UseMcp` + `ecs-mcp:InvokeReadOnlyTools`（见
[ECS MCP 入门指南](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/ecs-mcp-getting-started.html)）。

---

## 3. 可选的本地 Server

```json
{
  "mcpServers": {
    "cloudwatch-mcp": {
      "command": "uvx",
      "args": ["awslabs.cloudwatch-mcp-server@latest"],
      "env": { "AWS_PROFILE": "resilience-readonly", "AWS_REGION": "us-east-1", "FASTMCP_LOG_LEVEL": "ERROR" }
    },
    "aws-pricing-mcp": {
      "command": "uvx",
      "args": ["awslabs.aws-pricing-mcp-server@latest"],
      "env": { "AWS_PROFILE": "resilience-readonly", "AWS_REGION": "us-east-1", "FASTMCP_LOG_LEVEL": "ERROR" }
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
        "https://aws-mcp.us-east-1.api.aws/mcp",
        "--profile", "resilience-readonly",
        "--metadata", "AWS_REGION=us-east-1"
      ]
    },
    "eks-mcp": {
      "command": "uvx",
      "timeout": 100000,
      "args": [
        "mcp-proxy-for-aws@1.8.0",
        "https://eks-mcp.us-east-1.api.aws/mcp",
        "--service", "eks-mcp",
        "--profile", "resilience-readonly",
        "--region", "us-east-1"
      ]
    },
    "cloudwatch-mcp": {
      "command": "uvx",
      "args": ["awslabs.cloudwatch-mcp-server@latest"],
      "env": { "AWS_PROFILE": "resilience-readonly", "AWS_REGION": "us-east-1", "FASTMCP_LOG_LEVEL": "ERROR" }
    }
  }
}
```

> 删除不需要的 Server。最小配置只需 `aws-mcp`。

---

## 配置 AWS 凭证

```bash
aws login                                       # 浏览器登录，凭证自动轮换
aws configure sso --profile resilience-readonly # IAM Identity Center，使用只读权限集
aws sts get-caller-identity --profile resilience-readonly
```

### 最小 IAM 权限策略（只读访问）

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ec2:Describe*",
        "rds:Describe*",
        "s3:List*",
        "s3:GetBucket*",
        "lambda:List*",
        "lambda:Get*",
        "dynamodb:List*",
        "dynamodb:Describe*",
        "cloudwatch:Describe*",
        "cloudwatch:Get*",
        "cloudwatch:List*",
        "logs:Describe*",
        "logs:Get*",
        "logs:StartQuery",
        "logs:GetQueryResults",
        "logs:StopQuery",
        "logs:ListLogAnomalyDetectors",
        "logs:ListAnomalies",
        "eks:List*",
        "eks:Describe*",
        "ecs:List*",
        "ecs:Describe*",
        "elasticloadbalancing:Describe*",
        "apigateway:GET",
        "iam:List*",
        "iam:Get*",
        "cloudtrail:LookupEvents",
        "cloudtrail:GetTrailStatus",
        "ce:GetCostAndUsage",
        "ce:GetCostForecast",
        "pricing:GetProducts",
        "pricing:DescribeServices",
        "elasticache:Describe*",
        "elasticache:List*"
      ],
      "Resource": "*"
    }
  ]
}
```

配置容器类 Server 时，再加上 `eks-mcp:InvokeMcp`、`eks-mcp:CallReadOnlyTool` 和/或 `ecs-mcp:UseMcp`、
`ecs-mcp:InvokeReadOnlyTools`。

> `logs:StartQuery` / `logs:StopQuery` 只是启动和停止 CloudWatch Logs Insights 查询，不会修改资源。

---

## 验证配置

| 工具 | 验证方法 |
|------|---------|
| Kiro | `/mcp` 或 `/tools`（Kiro CLI），或 IDE 中的 MCP Server 视图 |
| Claude Code | `claude mcp list`，或在对话中输入 `/mcp` |

应能看到 `aws-mcp` 提供的 `aws___call_aws`、`aws___run_script`、`aws___search_documentation` 等工具。
如果没有，检查代理是否**误加了** `--read-only`。

---

## 故障排查

| 现象 | 原因 | 处理 |
|------|------|------|
| 没有 `aws___call_aws` 工具 | 代理以 `--read-only` 启动 | 去掉该参数；只读改由 IAM 保证 |
| `ExpiredTokenException` | 会话凭证已过期 | `aws login` / `aws sso login --profile …`，然后重启 MCP 客户端 |
| 调用返回 `AccessDenied` | profile 缺少该权限，或 SCP 拒绝了 `aws:ViaAWSMCPService` | 补充读权限；旧的 `aws-mcp:*` IAM 动作已不再生效 |
| Server 无法启动 | 缺少 `uv` 或无法下载代理 | `uv --version`；`timeout 15s uvx mcp-proxy-for-aws@1.8.0 --help` |

### 无 MCP 时的优雅降级

没有可用的 MCP Server 时，Skill 退回到以下方式（**不直接扫描 AWS 资源**）：
- 分析 IaC 代码（Terraform/CloudFormation）
- 分析架构文档
- 交互式问答

> **注意**：降级模式下**不允许**通过 Bash 直接执行 `aws` CLI 命令扫描或操作 AWS 资源。所有 AWS 资源访问都必须经过 MCP Server。

---

## 多个 AWS 账号

一个 `aws-mcp` 条目即可服务多个账号：传入多个 profile，第一个为默认，agent 可按次切换。

```json
"args": [
  "mcp-proxy-for-aws@1.8.0",
  "https://aws-mcp.us-east-1.api.aws/mcp",
  "--profile", "prod-readonly", "staging-readonly",
  "--metadata", "AWS_REGION=us-east-1"
]
```

---

## 从旧 Server 迁移

| 原 Server | 替代方案 |
|-----------|----------|
| `awslabs.aws-api-mcp-server` | `aws-mcp`（AWS MCP Server） |
| `aws-knowledge-mcp-server` | `aws-mcp`（已内置文档工具） |
| `awslabs.iam-mcp-server`（已弃用） | `aws-mcp` |
| `awslabs.dynamodb-mcp-server`、`lambda-tool-mcp-server`、`elasticache-mcp-server`、`cloudtrail-mcp-server` | `aws-mcp` 已覆盖评估所用的 Describe/List API |
| `awslabs.eks-mcp-server` / `awslabs.ecs-mcp-server` | AWS 托管的 `eks-mcp` / `ecs-mcp`（本地版仍可作为替代） |
| `awslabs.core-mcp-server`（已弃用） | 上述各 Server |

---

## 配置文件速查

| 项目 | Claude Code | Kiro |
|------|-------------|------|
| 工作区配置路径 | `.mcp.json`（项目级） | `.kiro/settings/mcp.json` |
| 用户级配置 | `claude mcp add --scope user …` | `~/.kiro/settings/mcp.json` |
| 查看 MCP 状态 | `claude mcp list` 或 `/mcp` | `/mcp`、`/tools` 或 MCP Server 视图 |

---

## 参考资源

- [AWS MCP Server](https://docs.aws.amazon.com/agent-toolkit/latest/userguide/mcp-server.html) 及其[配置指南](https://docs.aws.amazon.com/aws-mcp/latest/userguide/getting-started-aws-mcp-server.html)
- [从 AWS API MCP 迁移到 AWS MCP](https://github.com/awslabs/mcp/blob/main/src/aws-api-mcp-server/MIGRATION.md)
- [mcp-proxy-for-aws](https://github.com/aws/mcp-proxy-for-aws)
- [Amazon EKS MCP Server](https://docs.aws.amazon.com/eks/latest/userguide/eks-mcp-introduction.html) / [Amazon ECS MCP Server](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/ecs-mcp-introduction.html)
- [AWS MCP Servers（开源仓库）](https://github.com/awslabs/mcp)
- [Model Context Protocol 文档](https://modelcontextprotocol.io/)

---

**更新时间：2026-11-09**
