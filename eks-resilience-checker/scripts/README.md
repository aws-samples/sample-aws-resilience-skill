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
./scripts/assess.sh --cluster my-cluster --region ap-northeast-1

# Specify target namespaces (comma-separated)
./scripts/assess.sh --cluster my-cluster --region ap-northeast-1 --namespaces "app1,app2,app3"

# Output to custom directory
./scripts/assess.sh --cluster my-cluster --output-dir ./my-output
```

## Parameters

| Parameter | Required | Default | Description |
|-----------|----------|---------|-------------|
| `--cluster` | No | Auto-detect from kubeconfig context | EKS cluster name |
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

---

# multi-cluster-assess.sh — Multi-Cluster Orchestration

Wraps `assess.sh` to assess many EKS clusters in the same account without tripping account-level EKS API throttling.

Why not just loop over `assess.sh` yourself: EKS control-plane APIs (`describe-cluster`, `list-access-entries`, `describe-addon`) share an **account-level** rate limit, not a per-cluster one. `assess.sh` swallows throttling errors silently (falls back to `unknown`/empty results instead of failing), so unmanaged concurrency across 10-30+ clusters can silently produce misleading results.

## Usage

```bash
# Explicit cluster list
./scripts/multi-cluster-assess.sh --clusters "prod-a,prod-b,staging-a" --region us-west-2

# Auto-discover every cluster in the account/region
./scripts/multi-cluster-assess.sh --discover --region us-west-2

# Tune concurrency/delay (default concurrency: 2, default delay: 5s)
./scripts/multi-cluster-assess.sh --discover --region us-west-2 --concurrency 3 --delay 10
```

## Parameters

| Parameter | Required | Default | Description |
|-----------|----------|---------|-------------|
| `--clusters "c1,c2"` | One of `--clusters`/`--discover` | — | Explicit comma-separated cluster list |
| `--discover` | One of `--clusters`/`--discover` | — | Auto-discover via `aws eks list-clusters` |
| `--region` | Yes | — | AWS region |
| `--namespaces` | No | All non-system namespaces | Passed through to `assess.sh` |
| `--output-dir` | No | `./output` | Base directory; each cluster gets `output/<cluster-name>/` |
| `--concurrency` | No | `2` | Max clusters assessed in parallel (values above ~5 risk throttling) |
| `--delay` | No | `5` | Seconds to sleep between clusters/batches |
| `--skip-kubeconfig-update` | No | off | Skip automatic `aws eks update-kubeconfig` per cluster |

## Output Files

In addition to each cluster's own `output/<cluster-name>/assessment*.{json,md,html}` and `remediation-commands.sh`:

| File | Description |
|------|-------------|
| `rollup-summary.json` | Per-cluster compliance score/summary, sorted ascending by score |
| `rollup-summary.md` | Human-readable version of the rollup, flags clusters with errors/incomplete results |
