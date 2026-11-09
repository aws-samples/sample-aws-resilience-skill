# MCP Server Setup Guide

This Skill talks to AWS through the **AWS MCP Server**, a remote MCP server managed by AWS.
Kubernetes-side servers are optional. Without any MCP server the Skill falls back to the
AWS CLI and `kubectl` (see [Fallback Without MCP](#fallback-without-mcp)).

> **What changed (2026-11)**: `awslabs.aws-api-mcp-server` is superseded by the
> [AWS MCP Server](https://docs.aws.amazon.com/agent-toolkit/latest/userguide/mcp-server.html)
> ([migration guide](https://github.com/awslabs/mcp/blob/main/src/aws-api-mcp-server/MIGRATION.md)).
> The `ALLOW_WRITE_OPERATIONS=true` setting this guide used to require **never existed** in
> `aws-api-mcp-server` (its real switch is `READ_OPERATIONS_ONLY`, default `false`), so it had
> no effect. Remove both the old server entry and that variable from your configuration;
> running the old and the new server together causes tool conflicts.

| Server | Status | Required | Used for |
|--------|--------|----------|----------|
| `aws-mcp` — [AWS MCP Server](https://docs.aws.amazon.com/agent-toolkit/latest/userguide/mcp-server.html) | AWS-managed, **preview** | Yes | All AWS API calls (FIS, CloudWatch, EC2, RDS, EKS, IAM…), AWS documentation lookup |
| `eks-mcp` — [Amazon EKS MCP Server](https://docs.aws.amazon.com/eks/latest/userguide/eks-mcp-introduction.html) | AWS-managed, **preview** | If the target runs on EKS | Cluster and Kubernetes resource queries, pod logs, events |
| `awslabs.cloudwatch-mcp-server` | Open source, local | No | Its alarm-recommendation and log-analysis tools. Plain CloudWatch API calls already go through `aws-mcp` |
| `chaosmesh-mcp` — [RadiumGu/Chaosmesh-MCP](https://github.com/RadiumGu/Chaosmesh-MCP) | Community project (not AWS) | If Chaos Mesh is installed | Chaos Mesh CRD creation and status |

---

## 1. AWS MCP Server (required)

**Prerequisites**: Python 3.10+ with [uv](https://docs.astral.sh/uv/getting-started/installation/)
(for `uvx`), and AWS credentials on the machine (`aws login`, `aws configure sso`, or a profile).

The client runs only a thin local proxy, [`mcp-proxy-for-aws`](https://pypi.org/project/mcp-proxy-for-aws/),
which signs requests with your credentials (SigV4) and forwards them to the AWS-hosted endpoint.

- **Endpoint Region** (where the MCP server runs): `us-east-1`, `us-west-2`, `ap-southeast-1`,
  `ap-southeast-2`, `ap-northeast-1`, `eu-central-1`, `eu-west-1`, `eu-west-2` —
  `https://aws-mcp.<region>.api.aws/mcp`.
- **Operation Region** (default Region for the AWS calls): `--metadata AWS_REGION=<region>`.
  The two can differ; without the metadata, operations default to `us-east-1`.
- **Pin the proxy version** (AWS recommends it as a supply-chain control). This guide uses
  `1.8.0`, the latest release on 2026-11-09; update the pin deliberately.

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

Same JSON as Kiro, in `.cursor/mcp.json` or `.vscode/mcp.json`.

### Permissions

The AWS MCP Server calls AWS **with your credentials**: you need exactly the IAM permissions
you would need for the same API calls from the CLI. Chaos experiments need write access
(`fis:CreateExperimentTemplate`, `fis:StartExperiment`, `fis:StopExperiment`,
`cloudwatch:PutMetricAlarm`, `iam:PassRole` on the FIS role), so **do not** add `--read-only`
to the proxy for this Skill.

- Older `aws-mcp:InvokeMcp` / `aws-mcp:Call*` IAM actions no longer have any effect; remove them.
- To treat agent traffic differently from human traffic, use the global condition keys
  `aws:ViaAWSMCPService` / `aws:CalledViaAWSMCP` in identity policies or SCPs (for example,
  deny `fis:StartExperiment` via MCP in production accounts).
- Every call is recorded in CloudTrail and the server publishes CloudWatch metrics, so agent
  activity can be audited separately.

---

## 2. Amazon EKS MCP Server (EKS targets)

Managed by AWS, reached through the same proxy. Check that it is offered in your Region; the
service is in preview and subject to change.

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

**IAM**: `eks-mcp:InvokeMcp` (initialize, list tools), `eks-mcp:CallReadOnlyTool` (read tools),
`eks-mcp:CallPrivilegedTool` (write tools), or the managed policy `AmazonEKSMCPReadOnlyAccess`.
This Skill only needs the read-only tools: fault injection itself goes through FIS or Chaos Mesh.
The IAM principal also needs a Kubernetes identity in the cluster (EKS access entry).

> The open-source, locally run `awslabs.eks-mcp-server` still works if the managed server is not
> available to you (`uvx awslabs.eks-mcp-server@latest`; read-only unless started with `--allow-write`).

---

## 3. cloudwatch-mcp-server (optional)

Only needed for its higher-level tools (alarm recommendations, log-group analysis). Metric
queries and `put-metric-alarm` for stop conditions already work through `aws-mcp`, and
`scripts/monitor.sh` reads metrics with the AWS CLI.

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

## 4. chaosmesh-mcp (optional, community)

**Condition**: the EKS cluster has Chaos Mesh installed. **Repository**:
[RadiumGu/Chaosmesh-MCP](https://github.com/RadiumGu/Chaosmesh-MCP) — a community project, not
an AWS service; call this out when using it with customers.

EKS authentication (details in the project's
[EKS Authentication Methods](https://github.com/RadiumGu/Chaosmesh-MCP#eks-authentication-methods)):

- **Static ServiceAccount token (recommended)**: run its `setup-eks-permissions.sh` once; it
  creates least-privilege RBAC for Chaos Mesh and a self-contained kubeconfig. No AWS
  credentials needed at runtime; the token expires (default 1 year).
- **Admin kubeconfig**: a kubeconfig from `aws eks update-kubeconfig` (exec-based
  `aws eks get-token`); quick for testing, carries the admin's permissions.

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

## Complete Configuration Example

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

## AWS Credentials

The proxy and the CLI fallback both use the standard credential chain:

```bash
aws login                         # recommended: browser sign-in, credentials rotate automatically
aws configure sso                 # IAM Identity Center
aws configure --profile default   # long-term or temporary keys
aws sts get-caller-identity       # verify
```

Several accounts in one session: `--profile prod-readonly staging` (the first is the default; the
agent can switch per call). `ExpiredTokenException` means the session expired: refresh it, then
restart the MCP client.

---

## FIS IAM Role

FIS needs its own execution role. Step 4 of the Skill generates the creation command when it is
missing. Quick-start reference (use least privilege in production):

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

# AWS managed policies for FIS, attach the ones your experiment needs
aws iam attach-role-policy --role-name FISExperimentRole \
  --policy-arn arn:aws:iam::aws:policy/service-role/AWSFaultInjectionSimulatorEC2Access
aws iam attach-role-policy --role-name FISExperimentRole \
  --policy-arn arn:aws:iam::aws:policy/service-role/AWSFaultInjectionSimulatorRDSAccess
aws iam attach-role-policy --role-name FISExperimentRole \
  --policy-arn arn:aws:iam::aws:policy/service-role/AWSFaultInjectionSimulatorEKSAccess
aws iam attach-role-policy --role-name FISExperimentRole \
  --policy-arn arn:aws:iam::aws:policy/service-role/AWSFaultInjectionSimulatorNetworkAccess
```

> The ready-to-deploy templates under `references/fis-templates/` ship their own scoped role
> policies; prefer those over broad managed policies.

---

## Verify Configuration

```bash
# MCP servers loaded (Kiro CLI: /mcp or /tools; Claude Code: /mcp or `claude mcp list`)
# Expect aws___call_aws, aws___run_script, aws___search_documentation … from aws-mcp

aws sts get-caller-identity
aws fis list-experiment-templates --max-results 1
aws cloudwatch describe-alarms --max-items 1
aws eks list-clusters                 # if EKS
kubectl get crd | grep chaos-mesh     # if Chaos Mesh
```

---

## Fallback Without MCP

If no MCP server is available, the Skill uses the AWS CLI and `kubectl` directly; the background
scripts (`experiment-runner.sh`, `monitor.sh`, `log-collector.sh`, `discover-dependencies.sh`)
always use the CLI.

| Operation | With MCP | CLI fallback |
|-----------|----------|--------------|
| FIS experiments | `aws-mcp` | `aws fis create-experiment-template` / `start-experiment` |
| Metrics and alarms | `aws-mcp` | `aws cloudwatch get-metric-data` / `put-metric-alarm` |
| Kubernetes queries | `eks-mcp` | `kubectl` |
| Chaos Mesh | `chaosmesh-mcp` | `kubectl apply -f` |

Functionality stays complete; the agent just builds JSON/YAML itself instead of using typed tools.
