# AWS MCP Server Setup Guide

This guide explains how to configure MCP servers for the AWS Resilience Assessment Skill, for
**Kiro**, **Claude Code** and Cursor / VS Code.

> **What changed (2026-11)**: `awslabs.aws-api-mcp-server` is superseded by the AWS-managed
> [AWS MCP Server](https://docs.aws.amazon.com/agent-toolkit/latest/userguide/mcp-server.html)
> ([migration guide](https://github.com/awslabs/mcp/blob/main/src/aws-api-mcp-server/MIGRATION.md)),
> and `awslabs.iam-mcp-server` is deprecated in favour of it. Remove the old entries: running the
> old and new servers together causes tool conflicts.

| Server | Status | Required | Used for |
|--------|--------|----------|----------|
| `aws-mcp` — [AWS MCP Server](https://docs.aws.amazon.com/agent-toolkit/latest/userguide/mcp-server.html) | AWS-managed, **preview** | Yes | Every Describe/Get/List call of the assessment (EC2, RDS, ELB, S3, Lambda, DynamoDB, ElastiCache, IAM, CloudWatch, CloudTrail…), AWS documentation lookup |
| `eks-mcp` — [Amazon EKS MCP Server](https://docs.aws.amazon.com/eks/latest/userguide/eks-mcp-introduction.html) | AWS-managed, **preview** | If EKS | Cluster and Kubernetes resource inspection |
| `ecs-mcp` — [Amazon ECS MCP Server](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/ecs-mcp-introduction.html) | AWS-managed, **preview** | If ECS / Fargate | Cluster, service and task inspection |
| `cloudwatch-mcp` — `awslabs.cloudwatch-mcp-server` | Open source, local | No | Its log-anomaly and alarm-recommendation tools (monitoring readiness, SLI/SLO analysis) |
| `aws-pricing-mcp` — `awslabs.aws-pricing-mcp-server` | Open source, local | No | Cost estimates for remediation options |

The single-service servers this guide used to list (`dynamodb`, `lambda-tool`, `elasticache`,
`cloudtrail`, `iam`) are no longer needed: the AWS MCP Server reaches the same APIs.

---

## Read-only: enforce it with IAM, not with `--read-only`

The assessment must not change anything. With the AWS MCP Server that guarantee comes from **the
IAM permissions of the profile you connect with**, because the server calls AWS with your
credentials.

- Connect with a profile that only has read permissions (the
  [minimum read-only policy](#minimum-iam-permission-policy-read-only-access) below, or `ReadOnlyAccess`).
- **Do not** add `--read-only` to the proxy for this Skill. That flag hides every tool not annotated
  `readOnlyHint=true`, and `aws___call_aws` / `aws___run_script` cannot carry that annotation
  because what they do depends on IAM — so the agent would lose all AWS API access (confirmed by
  AWS in [agent-toolkit-for-aws#45](https://github.com/aws/agent-toolkit-for-aws/issues/45)).
- Optionally, add a guardrail that denies non-read actions only when called through MCP, using the
  global condition keys `aws:ViaAWSMCPService` / `aws:CalledViaAWSMCP` in an identity policy or SCP.
- Every call is recorded in CloudTrail, separately attributable to the MCP server.

---

## 1. AWS MCP Server (required)

**Prerequisites**: Python 3.10+ with [uv](https://docs.astral.sh/uv/getting-started/installation/)
(for `uvx`), and AWS credentials (`aws login`, `aws configure sso`, or a profile).

The client runs a thin local proxy, [`mcp-proxy-for-aws`](https://pypi.org/project/mcp-proxy-for-aws/),
that signs requests with your credentials (SigV4) and forwards them to the AWS-hosted endpoint.

- **Endpoint Region**: `us-east-1`, `us-west-2`, `ap-southeast-1`, `ap-southeast-2`,
  `ap-northeast-1`, `eu-central-1`, `eu-west-1`, `eu-west-2` — `https://aws-mcp.<region>.api.aws/mcp`.
- **Operation Region** (default for the AWS calls): `--metadata AWS_REGION=<region>`; without it,
  operations default to `us-east-1`.
- **Pin the proxy version**. This guide uses `1.8.0` (latest on 2026-11-09).

### Kiro

`.kiro/settings/mcp.json` (workspace) or `~/.kiro/settings/mcp.json` (user):

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

Same JSON as Kiro, in `.cursor/mcp.json` or `.vscode/mcp.json`.

---

## 2. Container servers (as needed)

Both are AWS-managed (preview) and reached through the same proxy. Check availability in your Region.

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

IAM: `eks-mcp:InvokeMcp` + `eks-mcp:CallReadOnlyTool`, or the managed policy
`AmazonEKSMCPReadOnlyAccess`. Do not grant `eks-mcp:CallPrivilegedTool` for an assessment.
The principal also needs a Kubernetes identity in each cluster (EKS access entry).
If the managed server is not available to you, the open-source `awslabs.eks-mcp-server`
(`uvx awslabs.eks-mcp-server@latest`) runs locally and is read-only unless started with `--allow-write`.

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

IAM: `ecs-mcp:UseMcp` + `ecs-mcp:InvokeReadOnlyTools` (see the
[ECS MCP getting-started guide](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/ecs-mcp-getting-started.html)).

---

## 3. Optional local servers

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

## Complete Configuration Example

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

> Remove the servers you don't need. The minimum configuration is `aws-mcp` alone.

---

## Configure AWS Credentials

```bash
aws login                                       # browser sign-in, credentials rotate automatically
aws configure sso --profile resilience-readonly # IAM Identity Center with a read-only permission set
aws sts get-caller-identity --profile resilience-readonly
```

### Minimum IAM Permission Policy (Read-Only Access)

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

Add `eks-mcp:InvokeMcp`, `eks-mcp:CallReadOnlyTool` and/or `ecs-mcp:UseMcp`,
`ecs-mcp:InvokeReadOnlyTools` when you configure the container servers.

> `logs:StartQuery` / `logs:StopQuery` start and stop CloudWatch Logs Insights queries; they do
> not modify resources.

---

## Verify Configuration

| Tool | Verification Method |
|------|-------------------|
| Kiro | `/mcp` or `/tools` (Kiro CLI), or the MCP Server view in the IDE |
| Claude Code | `claude mcp list`, or `/mcp` in a conversation |

You should see `aws___call_aws`, `aws___run_script`, `aws___search_documentation` … from `aws-mcp`.
If they are missing, check that the proxy was **not** started with `--read-only`.

---

## Troubleshooting

| Symptom | Cause | Fix |
|---------|-------|-----|
| No `aws___call_aws` tool | Proxy started with `--read-only` | Remove the flag; enforce read-only through IAM |
| `ExpiredTokenException` | Session credentials expired | `aws login` / `aws sso login --profile …`, then restart the MCP client |
| `AccessDenied` on a call | The profile lacks that permission, or an SCP denies `aws:ViaAWSMCPService` | Grant the read permission; old `aws-mcp:*` IAM actions have no effect anymore |
| Server not starting | `uv` missing or proxy cannot be downloaded | `uv --version`; `timeout 15s uvx mcp-proxy-for-aws@1.8.0 --help` |

### Graceful Degradation Without MCP

If no MCP server is available, the Skill falls back to these alternatives (**without directly
scanning AWS resources**):
- Analyze IaC code (Terraform/CloudFormation)
- Analyze architecture documentation
- Interactive Q&A

> **Note**: In fallback mode, direct execution of `aws` CLI commands via Bash to scan or operate on
> AWS resources is **NOT permitted**. All AWS resource access must go through MCP servers.

---

## Multiple AWS Accounts

One `aws-mcp` entry can serve several accounts: pass several profiles, the first one is the
default and the agent can switch per call.

```json
"args": [
  "mcp-proxy-for-aws@1.8.0",
  "https://aws-mcp.us-east-1.api.aws/mcp",
  "--profile", "prod-readonly", "staging-readonly",
  "--metadata", "AWS_REGION=us-east-1"
]
```

---

## Migrating from older servers

| Former server | Replacement |
|---------------|-------------|
| `awslabs.aws-api-mcp-server` | `aws-mcp` (AWS MCP Server) |
| `aws-knowledge-mcp-server` | `aws-mcp` (documentation tools are built in) |
| `awslabs.iam-mcp-server` (deprecated) | `aws-mcp` |
| `awslabs.dynamodb-mcp-server`, `lambda-tool-mcp-server`, `elasticache-mcp-server`, `cloudtrail-mcp-server` | `aws-mcp` covers the Describe/List APIs the assessment uses |
| `awslabs.eks-mcp-server` / `awslabs.ecs-mcp-server` | AWS-managed `eks-mcp` / `ecs-mcp` (the local servers remain valid alternatives) |
| `awslabs.core-mcp-server` (deprecated) | the servers above |

---

## Configuration File Quick Reference

| Item | Claude Code | Kiro |
|------|-------------|------|
| Workspace config path | `.mcp.json` (project) | `.kiro/settings/mcp.json` |
| User-level config | `claude mcp add --scope user …` | `~/.kiro/settings/mcp.json` |
| Check MCP status | `claude mcp list` or `/mcp` | `/mcp`, `/tools` or the MCP Server view |

---

## Reference Resources

- [AWS MCP Server](https://docs.aws.amazon.com/agent-toolkit/latest/userguide/mcp-server.html) and its [setup guide](https://docs.aws.amazon.com/aws-mcp/latest/userguide/getting-started-aws-mcp-server.html)
- [Migrating from AWS API MCP to AWS MCP](https://github.com/awslabs/mcp/blob/main/src/aws-api-mcp-server/MIGRATION.md)
- [mcp-proxy-for-aws](https://github.com/aws/mcp-proxy-for-aws)
- [Amazon EKS MCP Server](https://docs.aws.amazon.com/eks/latest/userguide/eks-mcp-introduction.html) / [Amazon ECS MCP Server](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/ecs-mcp-introduction.html)
- [AWS MCP Servers (open-source repository)](https://github.com/awslabs/mcp)
- [Model Context Protocol Documentation](https://modelcontextprotocol.io/)

---

**Updated: 2026-11-09**
