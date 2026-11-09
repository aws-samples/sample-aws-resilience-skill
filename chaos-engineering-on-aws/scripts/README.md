# Scripts

## experiment-runner.sh

Runs FIS or Chaos Mesh experiments with automated polling, timeout, and state output.

```bash
bash scripts/experiment-runner.sh --mode <fis|chaosmesh> [options]
```

| Flag | Required | Default | Description |
|------|----------|---------|-------------|
| `--mode` | Yes | — | `fis` or `chaosmesh` |
| `--template-id` | FIS mode | — | FIS experiment template ID |
| `--manifest` | CM mode | — | Chaos Mesh YAML manifest path |
| `--namespace` | CM mode | `default` | Kubernetes namespace |
| `--region` | FIS mode | `$AWS_DEFAULT_REGION` | AWS region |
| `--timeout` | No | `600` | Max seconds before auto-stop |
| `--poll-interval` | No | `15` | Seconds between status checks |
| `--output-dir` | No | `output/` | Output directory for state files |
| `--state-exp-id` | No | — | Experiment ID in state.json (e.g., EXP-001) for dashboard/recovery updates |
| `--experiment-id` | No | — | Existing FIS experiment ID (monitor-only mode: skip creation, just poll status) |
| `--quiet` | No | false | Minimal output (for background use) |
| `--one-shot` | No | false | One-shot injection mode (pod-kill): complete when AllInjected=True + pods Ready |
| `--pod-label` | No | — | Pod label selector for `--one-shot` completion check (e.g., `app=petsite`) |
| `--deployment` | No | — | Deployment name for `--one-shot` replica count (e.g., `petsite-deployment`). If omitted, auto-discovers via selector match |

**Exit codes**: 0=completed, 1=failed, 2=timeout

**Output files**:
- `output/checkpoints/step5-experiment.json` — experiment status
- `output/experiment-runner.log` — detailed log

**CM CR existence check**: If the Chaos Mesh CR is deleted during the experiment (e.g., manual abort), the script gracefully exits with ABORTED state instead of polling to timeout.

## monitor.sh

Collects CloudWatch metrics during experiments. Works in two modes:

**FIS mode** (with EXPERIMENT_ID — auto-stops when FIS completes):
```bash
export EXPERIMENT_ID="EXP..."
export REGION="ap-northeast-1"
export NAMESPACE="petadoptions"
nohup bash scripts/monitor.sh &
```

**Chaos Mesh mode** (without EXPERIMENT_ID — stops via SIGTERM or DURATION):
```bash
export REGION="ap-northeast-1"
export NAMESPACE="petadoptions"
export DURATION=300  # stop after 5 minutes
nohup bash scripts/monitor.sh &
```

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `EXPERIMENT_ID` | No | — | FIS experiment ID. Omit for Chaos Mesh mode |
| `NAMESPACE` | Yes | — | CloudWatch metric namespace |
| `REGION` | Yes | — | AWS region |
| `INTERVAL` | No | `15` | Collection interval in seconds |
| `LOOKBACK` | No | `300` | CloudWatch query lookback window in seconds (covers metric publish latency; consumers dedup by timestamp) |
| `DURATION` | No | `0` | Max duration in seconds (0=unlimited) |

**Requires**: `output/monitoring/metric-queries.json` (generated in Step 3). If missing, writes a warning to JSONL and continues without metrics.

**Output**: `output/monitoring/step5-metrics.jsonl`

## discover-dependencies.sh

Step 2 Impact Target discovery: finds the EKS workloads that reference the AWS resources
an experiment will hit. Read-only (AWS `Describe*`/`List*`/`Get*` plus `kubectl get`).

```bash
bash scripts/discover-dependencies.sh --region us-east-1 \
    --resource rds-cluster:orders-aurora --resource elasticache:sessions-rg --output-dir output/
```

| Flag | Required | Default | Description |
|------|----------|---------|-------------|
| `--region` | Yes | — | AWS Region of the resources and EKS clusters |
| `--resource` | Yes (repeatable) | — | `TYPE:ID` — `rds-cluster`, `rds-instance`, `elasticache` (replication group), `msk` (cluster ARN), `opensearch` (domain), `ec2` (instance ID) |
| `--match` | No (repeatable) | — | `LABEL=STRING` extra literal to look for, e.g. a CNAME in front of the resource |
| `--clusters` | No | `all` | `all` EKS clusters in the Region, or `name1,name2` |
| `--scan-secret-keys` | No | off | Also match Secret **key names** (needs RBAC list on secrets). Values are never printed or stored: the listing uses a go-template that emits names only |
| `--request-timeout` | No | `15` | kubectl request timeout in seconds |
| `--output-dir` | No | `./output` | Output directory |
| `--fixtures` | No | — | Offline mode for tests: `resources.json` + `clusters/<name>/*.json` |

Sources scanned per cluster: container + init-container env values; ConfigMaps via
`configMapKeyRef`, `envFrom`, `configMap` volumes and projected volumes; ExternalName
Services and workloads that call them (`svc.ns[.svc.cluster.local]` = verified, bare name
in the same namespace = unverified); Secret key names (opt-in, unverified).

Matching is anchored per pattern type (full hostname, identifier followed by `.`, IP
with digit boundaries); substring-only hits are reported as `near_misses`, never as
dependencies. Credentials inside URLs and `password=`-style values are masked.

**IAM / RBAC**: `eks:ListClusters`, `eks:DescribeCluster`, the resource's describe call
(`rds:DescribeDBClusters`/`DescribeDBInstances`, `elasticache:DescribeReplicationGroups`,
`kafka:GetBootstrapBrokers`/`DescribeClusterV2`, `es:DescribeDomain`,
`ec2:DescribeInstances`), and in each cluster `list` on pods, replicasets, configmaps,
services (+ secrets with `--scan-secret-keys`).

**Exit codes**: 0 scan done (zero findings is a valid result), 1 usage error,
2 no cluster could be scanned (the empty list means "not read", not "no dependency").

**Output**:
- `output/checkpoints/step2-dependencies.json` — resources and patterns, cluster access, `dependencies[]` (with `sources[]` evidence and `status` verified/unverified), `near_misses[]`, `unreferenced_configmaps[]`
- `output/monitoring/app-map.json` — one entry per workload (`cluster`, `kubeconfig`, `namespace`, `kind`, `workload`, `resources`, `status`) for `log-collector.sh --app-map`
- `output/kubeconfigs/<cluster>.kubeconfig` — isolated kubeconfig per cluster

Tests (offline, bash + jq): `bash scripts/tests/test-discover-dependencies.sh`

## log-collector.sh

Collects and classifies pod application logs.

```bash
bash scripts/log-collector.sh [options]
```

| Flag | Required | Default | Description |
|------|----------|---------|-------------|
| `--namespace` | Yes, unless `--app-map` | — | Kubernetes namespace |
| `--services` | No | all deployments in the namespace | Comma-separated deployment names (with `--namespace`) |
| `--app-map` | No | — | `app-map.json` from `discover-dependencies.sh`; collects every entry with `status` `verified` or `confirmed`, each through its own namespace and kubeconfig (Deployment, StatefulSet, DaemonSet, Job or bare Pod) |
| `--duration` | No | `300` | Collection duration (seconds) |
| `--output-dir` | No | `output/` | Output directory |
| `--mode` | No | `live` | `live` (during experiment) or `post` (after experiment) |
| `--since` | `post` mode | — | Start time for post-experiment collection |

**5-category error classification**: timeout, connection, 5xx, oom, other

**Output**:
- `output/monitoring/step5-logs.jsonl` — raw logs, one JSON object per line: `timestamp`, `pod`, `service`, `namespace`, `level`, `category`, `message` (+ `cluster` when collected through `--app-map`)
- `output/monitoring/step5-log-summary.json` — classified summary

## setup-prerequisites.sh

Optional one-time setup for FIS prerequisites (IAM role, CloudWatch alarms).

```bash
bash scripts/setup-prerequisites.sh --region <region> --cluster <name>
```

Creates: FIS IAM Role, basic CloudWatch alarms, validates permissions.

## update-dashboard.sh

Generates `output/dashboard.md` from state files. Called automatically by `monitor.sh`
every collection cycle. Can also be run manually:

```bash
OUTPUT_DIR=./output bash scripts/update-dashboard.sh
```

**Output**: `output/dashboard.md` — human-readable Markdown dashboard

## render-dashboard.sh

Renders a colored ASCII dashboard in the terminal. Best used with `watch`:

```bash
# Real-time terminal dashboard (refreshes every 5 seconds)
watch -n 5 -c bash scripts/render-dashboard.sh

# Or manual refresh
bash scripts/render-dashboard.sh
```

> Note: `watch -c` enables color output. On macOS, install `watch` via `brew install watch`.

## state.json v2 Schema

All scripts share `output/state.json` for coordination. `experiment-runner.sh` uses `flock` for concurrent write safety.

```json
{
  "version": 2,
  "created_at": "2026-04-15T11:30:00Z",
  "updated_at": "2026-04-15T11:45:00Z",
  "workflow": {
    "current_step": 5,
    "current_phase": "experiment_running",
    "status": "in_progress"
  },
  "steps": {
    "1": { "status": "completed", "started_at": "...", "completed_at": "..." },
    "5": { "status": "in_progress", "started_at": "..." }
  },
  "experiments": [
    {
      "id": "EXP-001",
      "name": "EKS Pod Kill",
      "status": "completed",
      "result": "PASSED",
      "tool": "chaosmesh",
      "elapsed_seconds": 5,
      "recovery_time_seconds": 6
    }
  ],
  "background_pids": {
    "runner": 12345,
    "monitor": 12346,
    "log_collector": 12347
  },
  "recovery_info": {
    "can_resume": false
  }
}
```

### Data Flow

```
experiment-runner.sh ──flock──► state.json ◄──cp snapshot── update-dashboard.sh → dashboard.md
                                    │                              ▲
                                    │                              │
monitor.sh ─────────────────────────┘──── calls ───────────────────┘
                                                    (every INTERVAL)

render-dashboard.sh ──cp snapshot──► state.json (read-only, terminal output)
```
