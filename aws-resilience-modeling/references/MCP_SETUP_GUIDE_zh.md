# AWS MCP 服务器设置指南

本指南介绍如何为 AWS 韧性评估 Skill 配置 MCP 服务器，支持 **Claude Code** 和 **Kiro**。

> ⚠️ `awslabs.core-mcp-server` 已废弃（DEPRECATED）。请直接配置独立 MCP Server。
> 迁移指南：https://github.com/awslabs/mcp/blob/main/docs/migration-core.md

---

## 必需的 MCP Server

### 1. aws-api-mcp-server

**用途**：通用 AWS API 访问 — EC2、RDS、ELB、S3、Lambda 等资源的 Describe/List 操作，覆盖韧性评估中的资源发现和配置检查。

**安装**：需要 Python 3.10+ 和 [uv](https://docs.astral.sh/uv/getting-started/installation/)

#### Claude Code

```bash
claude mcp add awslabs-aws-api-mcp-server \
  -e AWS_REGION=us-east-1 \
  -e AWS_PROFILE=default \
  -e FASTMCP_LOG_LEVEL=ERROR \
  -- uvx awslabs.aws-api-mcp-server@latest
```

#### Kiro

编辑 `.kiro/settings/mcp.json`：

```json
{
  "mcpServers": {
    "awslabs.aws-api-mcp-server": {
      "command": "uvx",
      "args": ["awslabs.aws-api-mcp-server@latest"],
      "env": {
        "AWS_REGION": "us-east-1",
        "AWS_PROFILE": "default",
        "FASTMCP_LOG_LEVEL": "ERROR"
      },
      "disabled": false,
      "autoApprove": []
    }
  }
}
```

---

### 2. cloudwatch-mcp-server

**用途**：CloudWatch 指标读取、告警查询、日志分析 — 韧性评估中的监控就绪度检查和 SLI/SLO 分析。

#### Claude Code

```bash
claude mcp add awslabs-cloudwatch-mcp-server \
  -e AWS_REGION=us-east-1 \
  -e AWS_PROFILE=default \
  -e FASTMCP_LOG_LEVEL=ERROR \
  -- uvx awslabs.cloudwatch-mcp-server@latest
```

#### Kiro

同上格式，替换包名为 `awslabs.cloudwatch-mcp-server@latest`。

---

## 推荐的 MCP Server（按需配置）

根据你的 AWS 架构，按需添加以下服务器：

### 3. eks-mcp-server

**条件**：目标系统为 EKS 架构时配置
**用途**：EKS 集群管理、K8s 资源操作、Pod 日志查看

#### Claude Code

```bash
claude mcp add awslabs-eks-mcp-server \
  -e AWS_REGION=us-east-1 \
  -e AWS_PROFILE=default \
  -e FASTMCP_LOG_LEVEL=ERROR \
  -- uvx awslabs.eks-mcp-server@latest
```

#### Kiro

同必需服务器的 JSON 格式，替换包名为 `awslabs.eks-mcp-server@latest`。

---

### 4. ecs-mcp-server

**条件**：目标系统为 ECS/Fargate 架构时配置
**用途**：ECS 集群、服务、任务管理

#### Claude Code

```bash
claude mcp add awslabs-ecs-mcp-server \
  -e AWS_REGION=us-east-1 \
  -e AWS_PROFILE=default \
  -e FASTMCP_LOG_LEVEL=ERROR \
  -- uvx awslabs.ecs-mcp-server@latest
```

#### Kiro

同必需服务器的 JSON 格式，替换包名为 `awslabs.ecs-mcp-server@latest`。

---

### 5. dynamodb-mcp-server

**条件**：目标系统使用 DynamoDB 时配置
**用途**：DynamoDB 表操作和查询

#### Claude Code

```bash
claude mcp add awslabs-dynamodb-mcp-server \
  -e AWS_REGION=us-east-1 \
  -e AWS_PROFILE=default \
  -e FASTMCP_LOG_LEVEL=ERROR \
  -- uvx awslabs.dynamodb-mcp-server@latest
```

#### Kiro

同必需服务器的 JSON 格式，替换包名为 `awslabs.dynamodb-mcp-server@latest`。

---

### 6. lambda-tool-mcp-server

**条件**：目标系统使用 Lambda 时配置
**用途**：Lambda 函数操作

#### Claude Code

```bash
claude mcp add awslabs-lambda-tool-mcp-server \
  -e AWS_REGION=us-east-1 \
  -e AWS_PROFILE=default \
  -e FASTMCP_LOG_LEVEL=ERROR \
  -- uvx awslabs.lambda-tool-mcp-server@latest
```

#### Kiro

同必需服务器的 JSON 格式，替换包名为 `awslabs.lambda-tool-mcp-server@latest`。

---

### 7. elasticache-mcp-server

**条件**：目标系统使用 ElastiCache 时配置
**用途**：ElastiCache 集群管理

#### Claude Code

```bash
claude mcp add awslabs-elasticache-mcp-server \
  -e AWS_REGION=us-east-1 \
  -e AWS_PROFILE=default \
  -e FASTMCP_LOG_LEVEL=ERROR \
  -- uvx awslabs.elasticache-mcp-server@latest
```

#### Kiro

同必需服务器的 JSON 格式，替换包名为 `awslabs.elasticache-mcp-server@latest`。

---

### 8. iam-mcp-server

**条件**：需要 IAM 策略和角色审计时配置
**用途**：IAM List/Get 操作（只读）

#### Claude Code

```bash
claude mcp add awslabs-iam-mcp-server \
  -e AWS_REGION=us-east-1 \
  -e AWS_PROFILE=default \
  -e FASTMCP_LOG_LEVEL=ERROR \
  -- uvx awslabs.iam-mcp-server@latest
```

#### Kiro

同必需服务器的 JSON 格式，替换包名为 `awslabs.iam-mcp-server@latest`。

---

### 9. cloudtrail-mcp-server

**条件**：需要审计日志查询时配置
**用途**：CloudTrail 事件查询

#### Claude Code

```bash
claude mcp add awslabs-cloudtrail-mcp-server \
  -e AWS_REGION=us-east-1 \
  -e AWS_PROFILE=default \
  -e FASTMCP_LOG_LEVEL=ERROR \
  -- uvx awslabs.cloudtrail-mcp-server@latest
```

#### Kiro

同必需服务器的 JSON 格式，替换包名为 `awslabs.cloudtrail-mcp-server@latest`。

---

## 完整配置示例

以下是韧性评估的推荐完整 MCP 配置（覆盖常见场景）：

```json
{
  "mcpServers": {
    "awslabs.aws-api-mcp-server": {
      "command": "uvx",
      "args": ["awslabs.aws-api-mcp-server@latest"],
      "env": {
        "AWS_REGION": "us-east-1",
        "AWS_PROFILE": "default",
        "FASTMCP_LOG_LEVEL": "ERROR"
      }
    },
    "awslabs.cloudwatch-mcp-server": {
      "command": "uvx",
      "args": ["awslabs.cloudwatch-mcp-server@latest"],
      "env": {
        "AWS_REGION": "us-east-1",
        "AWS_PROFILE": "default",
        "FASTMCP_LOG_LEVEL": "ERROR"
      }
    },
    "awslabs.eks-mcp-server": {
      "command": "uvx",
      "args": ["awslabs.eks-mcp-server@latest"],
      "env": {
        "AWS_REGION": "us-east-1",
        "AWS_PROFILE": "default",
        "FASTMCP_LOG_LEVEL": "ERROR"
      }
    },
    "awslabs.ecs-mcp-server": {
      "command": "uvx",
      "args": ["awslabs.ecs-mcp-server@latest"],
      "env": {
        "AWS_REGION": "us-east-1",
        "AWS_PROFILE": "default",
        "FASTMCP_LOG_LEVEL": "ERROR"
      }
    },
    "awslabs.dynamodb-mcp-server": {
      "command": "uvx",
      "args": ["awslabs.dynamodb-mcp-server@latest"],
      "env": {
        "AWS_REGION": "us-east-1",
        "AWS_PROFILE": "default",
        "FASTMCP_LOG_LEVEL": "ERROR"
      }
    },
    "awslabs.iam-mcp-server": {
      "command": "uvx",
      "args": ["awslabs.iam-mcp-server@latest"],
      "env": {
        "AWS_REGION": "us-east-1",
        "AWS_PROFILE": "default",
        "FASTMCP_LOG_LEVEL": "ERROR"
      }
    },
    "awslabs.cloudtrail-mcp-server": {
      "command": "uvx",
      "args": ["awslabs.cloudtrail-mcp-server@latest"],
      "env": {
        "AWS_REGION": "us-east-1",
        "AWS_PROFILE": "default",
        "FASTMCP_LOG_LEVEL": "ERROR"
      }
    }
  }
}
```

> 按需删除不需要的服务器。最小配置只需 `aws-api-mcp-server` + `cloudwatch-mcp-server`。

---

## 只读安全说明

韧性评估只需要**只读访问**。各 MCP Server 的只读特性：

| MCP Server | 只读行为 |
|-----------|---------|
| aws-api-mcp-server | 默认只读（仅 Describe/Get/List 操作） |
| cloudwatch-mcp-server | 默认只读（仅 Describe/Get/List 操作） |
| cloudtrail-mcp-server | 默认只读（仅查询事件） |
| iam-mcp-server | 默认只读（仅 List/Get 操作） |
| eks-mcp-server | 默认只读（仅 Describe/List 操作） |
| ecs-mcp-server | 默认只读（仅 Describe/List 操作） |
| dynamodb-mcp-server | 默认只读（仅 Describe/List/Query 操作） |

---

## 配置 AWS 凭证

```bash
# 方式 1：使用 AWS CLI 配置
aws configure

# 方式 2：使用 AWS SSO
aws configure sso

# 验证凭证
aws sts get-caller-identity
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
        "elbv2:Describe*",
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

---

## 验证配置

| 工具 | 验证方式 |
|------|---------|
| Kiro | Kiro 功能面板 -> MCP Server 视图，确认状态为 "running" |
| Claude Code | 运行 `claude mcp list` 或在对话中输入 `/mcp` |

```bash
# 验证 AWS 凭证
aws sts get-caller-identity

# 验证 CloudWatch 权限
aws cloudwatch describe-alarms --max-items 1

# 验证 EKS（如配置）
aws eks list-clusters

# 验证 ECS（如配置）
aws ecs list-clusters
```

---

## 故障排查

### MCP 服务器未连接

```bash
# 验证 uv 已安装
uv --version

# 手动测试 MCP 服务器启动（15 秒超时）
timeout 15s uvx awslabs.aws-api-mcp-server@latest 2>&1 || echo "Command completed or timed out"

# 验证 AWS 凭证
aws sts get-caller-identity
```

### 无 MCP 降级

如果 MCP Server 未配置或不可用，Skill 自动降级为以下备用方式：
- 分析 IaC 代码（Terraform/CloudFormation）
- 分析架构文档
- 交互式问答
- 直接使用 AWS CLI 命令

---

## 高级配置

### 多 AWS 账户

为不同账户创建独立的 MCP 服务器实例：

```json
{
  "mcpServers": {
    "aws-api-production": {
      "command": "uvx",
      "args": ["awslabs.aws-api-mcp-server@latest"],
      "env": {
        "AWS_PROFILE": "production",
        "AWS_REGION": "us-east-1",
        "FASTMCP_LOG_LEVEL": "ERROR"
      }
    },
    "aws-api-staging": {
      "command": "uvx",
      "args": ["awslabs.aws-api-mcp-server@latest"],
      "env": {
        "AWS_PROFILE": "staging",
        "AWS_REGION": "us-west-2",
        "FASTMCP_LOG_LEVEL": "ERROR"
      }
    }
  }
}
```

---

## 从 core-mcp-server 迁移

如果之前使用 `awslabs.core-mcp-server`，以下是角色到独立服务器的映射：

| 原 core-mcp-server 角色 | 替代的独立 MCP Server |
|------------------------|---------------------|
| `aws-foundation` | aws-api-mcp-server |
| `monitoring-observability` | cloudwatch-mcp-server, cloudtrail-mcp-server |
| `solutions-architect` | aws-pricing-mcp-server |
| `security-identity` | iam-mcp-server |
| `container-orchestration` | eks-mcp-server, ecs-mcp-server |
| `serverless-architecture` | lambda-tool-mcp-server |
| `nosql-db-specialist` | dynamodb-mcp-server |
| `caching-performance` | elasticache-mcp-server |

完整迁移指南：https://github.com/awslabs/mcp/blob/main/docs/migration-core.md

---

## 配置文件速查表

| 项目 | Claude Code | Kiro |
|------|-------------|------|
| 工作区配置路径 | `.claude/settings.local.json` | `.kiro/settings/mcp.json` |
| 用户级配置路径 | `~/.config/claude/settings.json` | `~/.kiro/settings/mcp.json` |
| 查看 MCP 状态 | `claude mcp list` 或 `/mcp` | 功能面板 -> MCP Server 视图 |

---

## 参考资源

- [AWS MCP Servers（官方仓库）](https://github.com/awslabs/mcp)
- [core-mcp-server 迁移指南](https://github.com/awslabs/mcp/blob/main/docs/migration-core.md)
- [CloudWatch MCP Server](https://github.com/awslabs/mcp/tree/main/src/cloudwatch-mcp-server)
- [AWS API MCP Server](https://github.com/awslabs/mcp/tree/main/src/aws-api-mcp-server)
- [EKS MCP Server](https://github.com/awslabs/mcp/tree/main/src/eks-mcp-server)
- [Model Context Protocol 文档](https://modelcontextprotocol.io/)
- [AWS CLI 配置文档](https://docs.aws.amazon.com/cli/latest/userguide/cli-configure-files.html)
- [uv 安装指南](https://docs.astral.sh/uv/getting-started/installation/)

---

**更新日期：** 2026-03-24
