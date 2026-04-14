# assess.sh — EKS Resilience Assessment Script

Automated script that runs all 26 EKS resilience checks and generates reports.

## Prerequisites

- `kubectl` configured with access to the target EKS cluster
- `aws` CLI configured with valid credentials
- `jq` installed
- Permissions: Kubernetes RBAC `get`/`list` on workload resources; IAM `eks:DescribeCluster`, `eks:ListAddons`

## Usage

```bash
# Basic usage (auto-detect cluster from current context)
./scripts/assess.sh

# Specify cluster and region
./scripts/assess.sh --cluster-name my-cluster --region ap-northeast-1

# Specify target namespaces (comma-separated)
./scripts/assess.sh --cluster-name my-cluster --region ap-northeast-1 --namespaces "app1,app2,app3"

# Output to custom directory
./scripts/assess.sh --cluster-name my-cluster --output-dir ./my-output
```

## Parameters

| Parameter | Required | Default | Description |
|-----------|----------|---------|-------------|
| `--cluster-name` | No | Auto-detect from kubeconfig context | EKS cluster name |
| `--region` | No | Auto-detect from AWS config | AWS region |
| `--namespaces` | No | All non-system namespaces | Comma-separated target namespaces |
| `--output-dir` | No | `./output` | Directory for output files |

## Output Files

| File | Description |
|------|-------------|
| `step1-cluster.json` | Cluster discovery metadata |
| `assessment.json` | Structured check results (26 checks) — input for chaos-engineering-on-aws |
| `assessment-report.md` | Human-readable Markdown report |
| `assessment-report.html` | HTML report with color-coded results |
| `remediation-commands.sh` | Fix commands for FAIL items (requires manual review before execution) |

## Exit Codes

| Code | Meaning |
|------|---------|
| 0 | All checks passed |
| 1 | One or more checks failed |
| 2 | Script error (missing tools, connectivity, permissions) |
