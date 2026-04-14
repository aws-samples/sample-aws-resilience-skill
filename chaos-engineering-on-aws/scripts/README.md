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

**Exit codes**: 0=completed, 1=failed, 2=timeout

**Output files**:
- `output/checkpoints/step5-experiment.json` — experiment status
- `output/experiment-runner.log` — detailed log

**CM CR existence check**: If the Chaos Mesh CR is deleted during the experiment (e.g., manual abort), the script gracefully exits with ABORTED state instead of polling to timeout.

## monitor.sh

Collects CloudWatch metrics during experiments.

```bash
export EXPERIMENT_ID="EXP..."
export REGION="ap-northeast-1"
export NAMESPACE="petadoptions"
nohup bash scripts/monitor.sh &
```

**Requires**: `output/monitoring/metric-queries.json` (generated in Step 3). If missing, writes a warning to JSONL and continues without metrics.

**Output**: `output/monitoring/step5-metrics.jsonl`

## log-collector.sh

Collects and classifies pod application logs.

```bash
bash scripts/log-collector.sh [options]
```

| Flag | Required | Default | Description |
|------|----------|---------|-------------|
| `--namespace` | Yes | — | Kubernetes namespace |
| `--services` | Yes | — | Comma-separated service names |
| `--duration` | No | `600` | Collection duration (seconds) |
| `--output-dir` | No | `output/` | Output directory |
| `--mode` | No | `live` | `live` (during experiment) or `post` (after experiment) |
| `--since` | `post` mode | — | Start time for post-experiment collection |

**5-category error classification**: timeout, connection, 5xx, oom, other

**Output**:
- `output/monitoring/step5-logs.jsonl` — raw logs
- `output/monitoring/step5-log-summary.json` — classified summary

## setup-prerequisites.sh

Optional one-time setup for FIS prerequisites (IAM role, CloudWatch alarms).

```bash
bash scripts/setup-prerequisites.sh --region <region> --cluster <name>
```

Creates: FIS IAM Role, basic CloudWatch alarms, validates permissions.
