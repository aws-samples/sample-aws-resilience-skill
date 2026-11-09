# Chaos Engineering Workflow Guide — Detailed Instructions

> This file contains the detailed step-by-step instructions for running chaos experiments.
> The main SKILL file (SKILL_EN.md) provides the overview and pointers.
> Read this file when you need the full procedure for a specific step.

## Prerequisites

### Input Methods (M1 supports three)

1. **Method 1**: Specify Assessment report file path → Parse Markdown structured sections
2. **Method 2**: Specify standalone chaos-input file → Parse `{project}-chaos-input-{date}.md`
3. **Method 3**: Specify `eks-resilience-checker` assessment.json → Parse K8s resilience check results

If the user has no report → Guide them to run `aws-resilience-modeling` Skill first.
If the user wants EKS-specific resilience checks → Guide them to run `eks-resilience-checker` Skill first.

#### Method 3: eks-resilience-checker Integration

When the user provides an `assessment.json` from `eks-resilience-checker`:

1. Read the `experiment_recommendations` array
2. Sort by `priority` (P0 → P1 → P2)
3. Each recommendation contains:
   - `suggested_fault_type` — maps to `fault-catalog.yaml` types (e.g., `pod_kill`, `network_delay`)
   - `target_resources` — specific K8s resources that failed the check
   - `hypothesis` — what to verify
4. If Method 1 or 2 is also provided, merge and deduplicate experiment targets
5. Present combined list to user for confirmation

### Input Completeness Check

Check the Assessment report against the following checklist at startup:

```
✅/❌ Project metadata (account, region, env type, architecture pattern, resilience score)
✅/❌ AWS resource inventory with full ARNs
✅/❌ Business function table with dependency chains and RTO/RPO (seconds)
✅/❌ Risk inventory with "Experimentable" and "Suggested injection method" columns
✅/❌ Experimentable risk details with affected resources and suggested experiments
✅/❌ Monitoring readiness (status + alarms + metrics + gaps)
✅/❌ Resilience score — all 9 dimensions complete
✅/❌ Constraints and preferences recorded (if any)
```

Missing data handling: ARN missing → AWS CLI supplementary scan; Experimentable flag missing → Self-assess; Monitoring readiness missing → Assume 🔴 Not Ready.

## State Persistence

File-as-state approach — each step's output serves as a checkpoint:

```
output/
├── checkpoints/
│   ├── step1-scope.json          # Target system, resource inventory
│   ├── step2-assessment.json     # Weak points, experiment recommendations, compatibility[]
│   ├── step2-dependencies.json   # Impact Target discovery evidence (§ 2.2)
│   ├── step3-experiment.json     # FIS experiment template definition
│   ├── step4-validation.json     # Pre-flight checks, user confirmation
│   └── step5-experiment.json     # FIS experiment state, ID, timeline
├── monitoring/
│   ├── step5-metrics.jsonl       # Monitoring script streaming metrics
│   ├── step5-logs.jsonl          # Raw application log JSONL
│   ├── step5-log-summary.json    # Classified log summary
│   ├── metric-queries.json       # CloudWatch metric query definitions
│   ├── app-map.json              # Workloads to collect logs from (§ 2.2 → log-collector --app-map)
│   └── experiment_id.txt         # FIS experiment ID
├── templates/                    # Generated FIS / Chaos Mesh templates
├── kubeconfigs/                  # One isolated kubeconfig per scanned EKS cluster
├── step6-report.md           # Final report (Markdown)
├── step6-report.html         # Final report (HTML, inline CSS)
├── baseline-{timestamp}.json # Steady-state baseline snapshots
└── state.json                # Progress metadata
```

On startup, check `output/state.json` — if it exists and is incomplete → prompt to continue or start fresh.

### state.json Schema (v2)

```json
{
  "version": 2,
  "created_at": "2026-04-15T17:20:00Z",
  "updated_at": "2026-04-15T17:30:00Z",
  "workflow": {
    "current_step": 5,
    "current_phase": "executing",
    "status": "in_progress"
  },
  "steps": {
    "1": {"status": "completed", "started_at": "...", "completed_at": "..."},
    "2": {"status": "completed", "started_at": "...", "completed_at": "..."},
    "3": {"status": "completed", "started_at": "...", "completed_at": "..."},
    "4": {"status": "completed", "started_at": "...", "completed_at": "..."},
    "5": {"status": "in_progress", "started_at": "...", "phase": "executing"},
    "6": {"status": "pending"}
  },
  "experiments": [
    {
      "id": "EXP-001",
      "name": "EC2 Instance Termination",
      "status": "completed",
      "result": "PASSED",
      "fis_id": "EXP-abcdef",
      "started_at": "...",
      "completed_at": "...",
      "elapsed_seconds": 323
    },
    {
      "id": "EXP-002",
      "name": "EKS Node Termination",
      "status": "running",
      "fis_id": "EXP-123456",
      "started_at": "...",
      "background_pids": {
        "runner": 12345,
        "monitor": 12346,
        "log_collector": 12347
      }
    }
  ],
  "recovery_info": {
    "can_resume": true,
    "resume_from": "EXP-002",
    "last_agent_action": "launched background scripts for EXP-002",
    "background_processes_running": true
  }
}
```

### Recovery After Interruption

When the user resumes (new conversation, context reset, IDE restart):

1. **First action**: Read `output/state.json`
   ```bash
   cat output/state.json 2>/dev/null || echo '{"status":"not_started"}'
   ```
   - Not found → fresh start
   - `status: completed` → inform user, offer to view report
   - `status: in_progress` → enter recovery flow

2. **Recovery flow**:
   a. Check background PIDs: `kill -0 <pid> 2>/dev/null`
      - Alive → read latest output files, continue waiting
      - Dead → check experiment result files
   b. For running experiments, query actual status:
      - FIS: `aws fis get-experiment --id <id>`
      - Chaos Mesh: `kubectl get <kind> <name> -n <ns>`
   c. Map actual status to recovery action:

      | Actual Status | Action |
      |--------------|--------|
      | running | Restart monitor.sh, continue observing |
      | completed | Record result, move to next experiment |
      | failed | Record failure, move to next experiment |
      | not found | Mark as ABORTED, move to next |

   d. Update state.json with recovery results
   e. Report to user:
      ```
      📋 Session Recovery:
      ✅ EXP-001 EC2 Terminate — PASSED (5m 23s)
      ⚠️ EXP-002 Node Kill — was running, FIS shows completed → recording result
      ⬜ EXP-003 Pod Kill — queued
      Resuming from EXP-002 result analysis...
      ```

3. Continue workflow from recovered position

## Step 1: Define Experiment Targets

**Consumes**: Risk inventory (2.4) + Project metadata (2.1)

1. Read risk inventory, filter risks with `Experimentable = ✅` and `⚠️ Has prerequisites`
2. Sort by risk score, recommend Top N
3. `⚠️ Has prerequisites` → List preconditions, ask the user
4. Adjust strategy focus by architecture pattern:
   - EKS microservices → Pod/network/inter-service faults
   - Serverless → Lambda latency/throttling
   - Traditional EC2 → Instance/AZ/database faults
   - Multi-region → Cross-region replication/failover
5. Confirm scope and priorities with the user
6. Detect Chaos Mesh (mandatory for EKS targets):
   ```bash
   # Primary check
   CM_INSTALLED=$(kubectl get crd podchaos.chaos-mesh.org >/dev/null 2>&1 && echo "true" || echo "false")
   # If primary fails, try namespace check
   if [[ "$CM_INSTALLED" != "true" ]]; then
       CM_INSTALLED=$(kubectl get ns chaos-mesh >/dev/null 2>&1 && echo "true" || echo "false")
   fi
   # If still not found, try helm
   if [[ "$CM_INSTALLED" != "true" ]]; then
       CM_INSTALLED=$(helm list -A 2>/dev/null | grep -q chaos-mesh && echo "true" || echo "false")
   fi
   ```
   **Persist result to step1-scope.json**: `"chaos_mesh_installed": true/false, "chaos_mesh_namespace": "...", "chaos_mesh_version": "..."`
   All subsequent steps MUST read `chaos_mesh_installed` from step1-scope.json.
   Step 6 recommendations MUST NOT suggest "Install Chaos Mesh" if already detected.

**Output**: `output/checkpoints/step1-scope.json`

**User Interaction**: Confirm experiment targets, environment, and time window

## Step 2: Select Target Resources

**Consumes**: Resource inventory (2.2) + Risk detail resource tables (2.5)

1. Extract resource ARNs for target risks from section 2.5
2. Validate ARN availability:
   ```bash
   aws ec2 describe-instances --instance-ids <id>
   aws eks describe-cluster --name <name>
   aws rds describe-db-clusters --db-cluster-identifier <id>
   ```
3. Supplement missing related resources (SG, TG, etc.)
4. Calculate blast radius (based on dependency chains in 2.3)
5. Label resource roles: `Injection Target` / `Observation Target` / `Impact Target`
6. Discover the workloads that depend on every Injection Target (§ 2.2) — they are the
   Impact Targets, and the log sources for Step 5

### 2.1 Resource–Action Compatibility Gate (MANDATORY, blocks Step 3)

An ARN that exists is not an ARN the chosen action can target. For every candidate
FIS action (including each sub-action of a Scenario Library scenario that survives
pruning), check that the action's target resource type matches the real resource
**before** generating any template:

```bash
# 1. What does the action actually target?
aws fis get-action --id "<ACTION_ID>" --region "$REGION" \
  --query 'action.targets' --output json
# 2. What is the resource, really? (pick the row for the resource type)
```

| Resource | Command | Fields that decide compatibility |
|---|---|---|
| RDS instance | `aws rds describe-db-instances --db-instance-identifier <ID>` | `Engine`, `DBClusterIdentifier`, `MultiAZ` |
| Aurora / RDS cluster | `aws rds describe-db-clusters --db-cluster-identifier <ID>` | `Engine`, `EngineMode`, `MultiAZ`, number of readers |
| EC2 instance | `aws ec2 describe-instances --instance-ids <ID>` | `InstanceLifecycle`, `Placement.AvailabilityZone` |
| ElastiCache | `aws elasticache describe-replication-groups --replication-group-id <ID>` | `MultiAZ`, `AutomaticFailover`, `ClusterEnabled` |
| EKS cluster | `aws eks describe-cluster --name <NAME>` | `accessConfig.authenticationMode` (FIS `aws:eks:pod-*` needs `API` or `API_AND_CONFIG_MAP`) |
| ASG | `aws autoscaling describe-auto-scaling-groups --auto-scaling-group-names <NAME>` | `AvailabilityZones`, instance count per AZ |

Known incompatibilities:

| Action | Target type | Incompatible with | Detect by | Use instead |
|---|---|---|---|---|
| `aws:rds:failover-db-cluster` | `aws:rds:cluster` | Standalone RDS (non-Aurora, non-Multi-AZ-cluster) | `DBClusterIdentifier` is null | `aws:rds:reboot-db-instances` with `forceFailover=true` (Multi-AZ instance) |
| `aws:rds:reboot-db-instances` | `aws:rds:db` | Expecting a cluster-level failover on Aurora | `Engine` starts with `aurora` | `aws:rds:failover-db-cluster` |
| `aws:elasticache:replicationgroup-interrupt-az-power` | `aws:elasticache:replicationgroup` | Standalone cache node, single-AZ group | no replication group / `MultiAZ` disabled | Fix the topology first; or SSM template `elasticache-redis-primary-node-reboot` |
| `aws:ec2:stop-instances` | `aws:ec2:instance` | Spot instances | `InstanceLifecycle` = `spot` | `aws:ec2:send-spot-instance-interruptions` |
| `aws:ec2:send-spot-instance-interruptions` | `aws:ec2:spot-instance` | On-Demand instances | `InstanceLifecycle` absent | `aws:ec2:stop-instances` / `terminate-instances` |
| `aws:fis:inject-api-*` | `aws:iam:role` | Any service other than `ec2` / `kinesis` | `service` parameter | The service's dedicated action (see `fault-catalog.yaml` `NOT_supported`) |
| Aurora MySQL fault-injection SQL (`ALTER SYSTEM CRASH`, …) | — | `aurora-postgresql` | `Engine` | `aws:rds:reboot-db-instances` / `failover-db-cluster` |

Also check targeting syntax ([FIS targets](https://docs.aws.amazon.com/fis/latest/userguide/targets.html)):
one target cannot combine `resourceArns` with `resourceTags`, nor `resourceArns` with
`filters`. To scope an AZ, either list only that AZ's ARNs, or use `resourceTags` + a
`Placement.AvailabilityZone`-style filter.

Decision: compatible → continue. Incompatible → explain the mismatch with the field
value you read, propose the replacement action from the table, and let the user confirm
or drop the experiment. Never "fix" it by changing the action silently. Record each
check in `step2-assessment.json` under `compatibility[]` as
`{action_id, target_type, resource_arn, decisive_field, value, result}`.

### 2.2 Impact Target Discovery (dependent workloads)

The dependency chains in the assessment report say which *services* depend on a
resource; they rarely say which *pods*. Before the blast radius is confirmed, find every
EKS workload in the Region that actually points at the Injection Targets:

```bash
bash scripts/discover-dependencies.sh --region "$REGION" \
    --resource rds-cluster:<db-cluster-id> \
    --resource elasticache:<replication-group-id> \
    --output-dir output/
# Other types: rds-instance:<id>  msk:<cluster-arn>  opensearch:<domain>  ec2:<instance-id>
# Extra strings (a CNAME in front of the resource): --match label=db.internal.example.com
# Secret KEY NAMES too (needs RBAC list on secrets, values are never read out): --scan-secret-keys
```

What it does:
- Resolves every real endpoint of each resource through the AWS API (cluster writer,
  reader and custom endpoints plus member instances; every ElastiCache node endpoint;
  all MSK bootstrap brokers; OpenSearch domain and VPC endpoints; EC2 private IPs and DNS).
- Scans **all** EKS clusters in the Region in parallel (other clusters often share the
  same database), each with its own kubeconfig under `output/kubeconfigs/` — the user's
  `~/.kube/config` is never touched.
- Looks in container and init-container env values, ConfigMaps reached through
  `configMapKeyRef` / `envFrom` / volumes / projected volumes, ExternalName Services (and
  the workloads that call those Services by name), and optionally Secret key names.
- Resolves each pod to its owning Deployment / StatefulSet / DaemonSet / Job.
- Matching is anchored: `orders-db` does not match `orders-db-replica`, `10.0.1.25` does
  not match `10.0.1.250`. Such near misses are listed separately and never counted.
- Credentials in URLs and `password=` style values are masked in the evidence.

Exit code 2 means **no cluster could be scanned**: the impact list is empty because
nothing was read, not because nothing depends on the resource. Report it that way.

Handling the result:
1. Show the user the summary the script prints (✅ verified / ⚠️ unverified / ✖ near miss,
   plus clusters that were skipped and why).
2. `unverified` entries (Secret key names, or a bare Service name) need the user's
   confirmation. Mark a confirmed one in `output/monitoring/app-map.json`:
   ```bash
   jq '(.[] | select(.namespace=="billing" and .workload=="billing-api") | .status) = "confirmed"' \
      output/monitoring/app-map.json > output/monitoring/app-map.json.tmp \
      && mv output/monitoring/app-map.json.tmp output/monitoring/app-map.json
   ```
   Add workloads the scan cannot see (for example ones that read the endpoint from
   Secrets Manager at runtime) as extra entries with `"status": "confirmed"`.
3. Label every confirmed workload `Impact Target` in `step2-assessment.json`, and use
   the list for the blast-radius statement and the Step 3 hypothesis ("these N workloads
   recover within RTO").
4. A ConfigMap that matches but has no consumer (`unreferenced_configmaps`) is worth one
   question to the user: it may be read through the Kubernetes API, or it may be stale.

**Output**: `output/checkpoints/step2-assessment.json`, plus from § 2.2
`output/checkpoints/step2-dependencies.json` (full evidence, cited by the report) and
`output/monitoring/app-map.json` (consumed by `log-collector.sh --app-map` in Step 5).

**User Interaction**: Confirm blast radius is acceptable; ARN failure → update or skip

## Step 3: Define Hypothesis and Experiment

**Consumes**: Business functions (2.3) + Suggested experiments (2.5) + Monitoring readiness (2.6)

### 3.1 Steady-State Hypothesis

Auto-generated based on RTO/RPO from section 2.3:

```
Hypothesis: After {fault}, the system should recover within {target_RTO}s,
with request success rate >= {threshold}% and zero data loss.
```

Key metrics: Request success rate, P99 latency, recovery time, data integrity.

### 3.2 Experiment Design

Starting from the suggested experiments in section 2.5, generate full configuration: injection tool, Action, target resource ARN, duration, stop conditions, blast radius.

> **Required output**: Agent **must** generate `output/monitoring/metric-queries.json` alongside `output/checkpoints/step3-experiment.json`. This file contains the CloudWatch `GetMetricData` query definitions used by `monitor.sh` during Step 5. Without it, metric collection will be skipped and the experiment will run blind. Do not proceed to Step 4 without generating this file.

### 3.3 Monitoring Readiness

| Status | Handling |
|------|------|
| 🟢 Ready | Use existing CloudWatch Alarms as Stop Conditions |
| 🟡 Partial | Create missing alarms |
| 🔴 Not Ready | **Block** — Must create baseline monitoring first |

### 3.4 Tool Selection

Consult the **unified fault catalog** ([references/fault-catalog.yaml](fault-catalog.yaml)) for the full list of available fault types, default parameters, and prerequisites:

- **AZ/Region compound faults** → FIS Scenario Library → [references/scenario-library.md](scenario-library.md)
- **AWS infrastructure layer** → AWS FIS single action → [references/fis-actions.md](fis-actions.md)
- **K8s Pod/container layer** → Chaos Mesh → [references/chaosmesh-crds.md](chaosmesh-crds.md)

> ⚠️ For Pod-level faults, **prefer Chaos Mesh** over FIS `aws:eks:pod-*` actions (faster, simpler RBAC).

> ⚠️ **API Fault Injection Guard**: When selecting `api_throttle` / `api_internal_error` / `api_unavailable_error`,
> MUST verify target service is `ec2` or `kinesis`. These are the ONLY supported services.
> If target is any other service (DynamoDB, Lambda, S3, RDS, EBS, etc.) → use the dedicated FIS Action instead.
> See `fault-catalog.yaml` `NOT_supported` field for the mapping.

> ⚠️ FIS Scenario Library has **three creation paths**: (1) Console → export; (2) Content tab → API; (3) JSON skeletons from [references/scenario-library.md](scenario-library.md) directly via API. See that file for details.

### 3.5 Configuration Generation Strategy

MCP first → Fall back to Schema + CLI:
- **MCP available**: Call MCP tool directly with parameters (type-constrained)
- **MCP unavailable**: `aws fis get-action` to get schema → fill → `aws fis create-experiment-template`

Validation chain: Config generation → API validation → Dry-run → User confirmation → Execution

### 3.6 Composite Experiment Design (Multi-Action FIS Templates)

For compound failure scenarios, use **FIS native multi-action templates** with `startAfter`:

| Pattern | `startAfter` | Effect |
|---------|-------------|--------|
| Parallel (default) | _(not set)_ | Simultaneous |
| Sequential | `["action-A"]` | After action-A begins |
| Multi-dependency | `["action-A", "action-B"]` | After both begin |
| Timed delay | `aws:fis:wait` | Insert gap |

Design steps: select actions from fault-catalog → define in single template's `actions` → set `startAfter` → add shared `stopConditions` → create via API → execute with `experiment-runner.sh` (no changes needed).

For parameterized templates with `{{placeholder}}`, see `references/templates/`.

Example: [Composite AZ Degradation](../examples/05-composite-az-degradation.md)

### 3.7 Mixed-Backend Experiments (FIS + Chaos Mesh)

Orchestration order:
1. CM injects first (`kubectl apply`) → confirm AllInjected=True
2. FIS injects second (`aws fis start-experiment`)
3. Parallel monitoring (two `experiment-runner.sh` processes)
4. Abort order: FIS first (immediate), CM second (kubectl delete propagation delay)
5. Verify full cleanup

See scripts usage: [scripts/README.md](../scripts/README.md)

### 3.8 Stop Conditions (mandatory)

Every experiment must bind: CloudWatch Alarm + time limit + manual override capability.

#### Handling INSUFFICIENT_DATA State

FIS requires all Stop Condition alarms to be in `OK` state before experiment start.
Alarms bound to low-traffic resources (e.g., Lambda, infrequently-used APIs) often show
`INSUFFICIENT_DATA` because CloudWatch has no recent data points.

**Resolution order (try in sequence):**

1. **Set `TreatMissingData` to `notBreaching`** (recommended for most chaos alarms):
   ```bash
   aws cloudwatch put-metric-alarm \
     --alarm-name "chaos-{service}-sr-critical" \
     --treat-missing-data notBreaching \
     ... (other params unchanged)
   ```
   This makes alarms report OK when data is missing, which is correct for chaos stop
   conditions — no data means no errors.

2. **Generate traffic to warm up the alarm** (if alarm already exists and you don't want to modify it):
   ```bash
   # Lambda example: invoke a few times to produce data points
   for i in {1..5}; do
     aws lambda invoke --function-name <FUNCTION_NAME> --region <REGION> /tmp/out.json
     sleep 10
   done
   # Wait 1-2 minutes for alarm to transition to OK
   aws cloudwatch describe-alarms --alarm-names "chaos-..." \
     --query 'MetricAlarms[0].StateValue'
   ```

3. **Temporarily remove the alarm as Stop Condition** (last resort):
   - Remove from FIS template, run experiment, add back after.
   - ⚠️ Only for non-production environments.

### FIS Cost Estimation

| Cost Component | Pricing | Example (3 exp × 5 min) |
|---------------|---------|-------------------------|
| FIS action-minutes | $0.10/action-minute | $1.50 |
| Chaos Mesh | Free (cluster resources ~0.5 vCPU) | $0.00 |
| CloudWatch custom metrics | $0.30/metric/month | ~$1-5/month |

See [AWS FIS Pricing](https://aws.amazon.com/fis/pricing/).

**Output**: `output/checkpoints/step3-experiment.json` + `output/templates/`

## Step 4: Ensure Experiment Readiness (Pre-flight)

**Consumes**: Monitoring readiness (2.6) + Constraints (2.8)

```
Environment:
□ AWS credentials valid with sufficient permissions
□ FIS IAM Role created (verify with `aws iam get-role`)
□ Target resources in healthy state

Monitoring:
□ Stop Condition Alarms ready **and in OK state**
  - Check: `aws cloudwatch describe-alarms --alarm-names <names> --query 'MetricAlarms[].StateValue'`
  - If any alarm shows `INSUFFICIENT_DATA`:
    → Auto-fix: `aws cloudwatch put-metric-alarm ... --treat-missing-data notBreaching`
    → Re-check state after 60 seconds
    → If still not OK: warn user, suggest traffic warmup or temporary removal
□ output/monitoring/metric-queries.json exists (generated in Step 3)

Safety:
□ Blast radius ≤ maximum limit
□ Rollback plan verified
□ Data backup confirmed (if data layer involved)
□ Lambda FIS Extension (if lambda_delay or lambda_error experiments planned)
  - Check: `aws lambda get-function-configuration --function-name <name> --query 'Layers[].Arn'`
  - If no FIS Extension Layer → generate setup commands from fault-catalog.yaml `setup_commands`
  - Check env var: `aws lambda get-function-configuration --function-name <name> --query 'Environment.Variables.AWS_FIS_CONFIGURATION_LOCATION'`

Team:
□ Stakeholders notified
□ On-call personnel in position
```

Automatic remediation: FIS Role missing → generate creation command; Alarm missing → generate `put-metric-alarm`; Monitoring 🔴 → Block.

**Output**: `output/checkpoints/step4-validation.json`

## Step 5: Run Controlled Experiment

**Scripts**: See [scripts/README.md](../scripts/README.md) for all parameters.

> **MCP Write Access Check**: Before first experiment execution, verify MCP can perform write operations.
> Try a harmless write (e.g., `fis:TagResource` on an existing template).
> If MCP connection drops → configure `ALLOW_WRITE_OPERATIONS=true` in aws-api-mcp-server env and restart.
> Or switch to AWS CLI fallback for all FIS operations.

### Phase 0: Baseline Collection (T-5min)
Collect steady-state baseline, save as `output/baseline-{timestamp}.json`.

### Phase 1: Fault Injection + Observation

> ⚠️ **CRITICAL**: Do NOT poll experiment status in the agent loop. Use `experiment-runner.sh` which handles injection, polling, timeout, and state output in a background process.
>
> **Immediate Failure Detection**: After launching `experiment-runner.sh`, wait 5 seconds then check `$STATE_FILE`.
> If `immediate_failure: true`, read `reason` and report to user immediately.
> Common immediate failures:
> - "Stop condition alarm is in ALARM or INSUFFICIENT_DATA state"
> - "Access denied" (IAM permission issue)
> - "Resource not found" (target ARN invalid)
>
> Do NOT silently wait for timeout — check early and fail fast.

Launch all background processes, then `wait`:

> ⚠️ **MANDATORY**: Launch ALL three background processes for every experiment,
> regardless of experiment type (FIS or Chaos Mesh) or expected duration:
> 1. `experiment-runner.sh` — manages experiment lifecycle
> 2. `monitor.sh` — collects CloudWatch metrics + heartbeat (set `EXPERIMENT_ID` for FIS, omit for CM)
> 3. `log-collector.sh` — collects Pod logs for post-analysis
>
> Do NOT skip log-collector even for short experiments. Pod logs during the
> injection window are essential for error classification and MTTR calculation
> in the report (Section 4: Log Analysis).

```bash
# FIS experiment:
nohup bash scripts/experiment-runner.sh --mode fis --template-id "$TEMPLATE_ID" \
    --region "$REGION" --state-exp-id "EXP-001" --output-dir output/ &
RUNNER_PID=$!

# Chaos Mesh experiment (one-shot actions like pod-kill):
nohup bash scripts/experiment-runner.sh --mode chaosmesh \
    --manifest output/templates/pod-kill.yaml --namespace "$NAMESPACE" \
    --one-shot --pod-label "app=petsite" --deployment "petsite-deployment" \
    --state-exp-id "EXP-001" --output-dir output/ &
RUNNER_PID=$!

# Monitor — FIS: experiment-runner writes the ID; monitor stops when FIS completes
sleep 5; EXPERIMENT_ID=$(cat output/monitoring/experiment_id.txt) NAMESPACE="$CW_NAMESPACE" REGION="$REGION" \
    nohup bash scripts/monitor.sh &
# Monitor — Chaos Mesh: no EXPERIMENT_ID, so DURATION is REQUIRED (default 0 = runs until killed)
# NAMESPACE="$CW_NAMESPACE" REGION="$REGION" DURATION=600 nohup bash scripts/monitor.sh &
# Log collector (MANDATORY for all experiments).
# Preferred: every Impact Target from Step 2.2, across namespaces and clusters:
nohup bash scripts/log-collector.sh --app-map output/monitoring/app-map.json \
    --duration "$DURATION_SECONDS" --mode live --output-dir output/ &
# Fallback when discovery was not run: one namespace
# nohup bash scripts/log-collector.sh --namespace {NS} --services "{svcs}" --mode live ... &
wait $RUNNER_PID
```

> 💡 Default monitor interval is 15s. For experiments >30 minutes, set `INTERVAL=30` or `INTERVAL=60`.

Exit codes: 0=completed, 1=failed, 2=timeout

> **Monitor Health Check**: After launching, periodically check
> `output/monitoring/monitor-status.json`. If `last_collect` timestamp
> is older than 2× INTERVAL (30s at the default `INTERVAL=15`), monitor may be stuck — report to user.
>
> **Dashboard**: After launching background scripts, inform the user:
> "📊 **Dashboard options:**
>  1. **IDE Preview**: Open `output/dashboard.md` in Markdown Preview
>  2. **Terminal (real-time)**: Run in a separate terminal:
>     ```bash
>     watch -n 5 -c bash scripts/render-dashboard.sh
>     ```
>  3. **Quick check**: `cat output/dashboard.md`
>
> The dashboard updates automatically every monitoring cycle (every `INTERVAL`, 15s by default).
> You can safely close this chat — experiments continue in background."

### Phase 2: Log Classification
5 categories: timeout, connection, 5xx, oom, other

### Duration Override
```bash
# FIS: jq
jq '.actions[].parameters.duration = "PT2M"' template.json > template-short.json
# CM: kubectl patch
kubectl patch networkchaos my-exp -n ns --type merge -p '{"spec":{"duration":"2m"}}'
```

### Phase 3: Recovery (T+duration → T+recovery)
Wait for auto-recovery → record recovery time → compare with target RTO.
Log-based detection: errors return to zero for 30s → mark recovery.

### Phase 4: Steady-State Validation
Re-collect metrics → compare with baseline → confirm full recovery.

### Execution Modes

| Mode | Description |
|------|-------------|
| Interactive | Pause at each step (first run / production) |
| Semi-auto | Confirm at critical checkpoints (staging) |
| Dry-run | Walk through without injection |
| Game Day | Cross-team exercise, see [references/gameday.md](gameday.md) |

**Output**: `output/checkpoints/step5-experiment.json` + monitoring files

## Step 6: Learning and Report

### 6.0 Result Verification (MANDATORY — do this FIRST)

> ⚠️ Before writing any report, verify actual experiment status from AWS/K8s.

**FIS Result Mapping**:
| FIS `state.status` | Report Result |
|---------------------|---------------|
| `completed` | Check hypothesis → PASSED ✅ or FAILED ❌ |
| `failed` | **FAILED ❌** (FIS error) |
| `stopped` / `cancelled` | **ABORTED ⚠️** |

For `completed`: also check hypothesis violation and RTO exceedance → if either → FAILED ❌.

**Chaos Mesh Result Mapping**:
| Scenario | Report Result |
|----------|---------------|
| `AllInjected=True` + `AllRecovered=True` | Check hypothesis |
| `AllInjected=False` | **FAILED ❌** |
| `AllRecovered=False` (after timeout) | **FAILED ❌** |
| CR not found | **ABORTED ⚠️** |

Post-experiment cleanup check:
```bash
kubectl get podchaos,networkchaos,httpchaos,stresschaos,iochaos -n {NAMESPACE} 2>/dev/null
```

### 6.0.5 Data Completeness Check (MANDATORY)

Before generating the report, verify that observation data exists:

| File | Required | If Missing |
|------|----------|-----------|
| `output/monitoring/step5-metrics.jsonl` | ✅ | ⚠️ Report MUST include warning: "No CloudWatch metrics collected — RTO/performance data unavailable" |
| `output/monitoring/step5-logs.jsonl` | Recommended | Warning: "No application logs collected" |
| `output/checkpoints/step2-dependencies.json` | Recommended | Warning: "Impact Targets not discovered — application impact limited to the services named in the assessment". If it exists, list every cluster with `accessible: false` as "not scanned" |
| `output/baseline-*.json` | ✅ | ⚠️ Report MUST include warning: "No baseline data — cannot compare pre/post performance" |
| `output/checkpoints/step5-experiment.json` | ✅ | ❌ BLOCK report generation — experiment status unknown |

If metrics or baseline files are missing:
1. Report header MUST include: `⚠️ LIMITED DATA: This report lacks quantitative metrics. Experiment execution was observed, but RTO/performance claims are not data-backed.`
2. All RTO/latency/success-rate fields MUST show "No data" instead of "N/A (idle)"
3. Verdict can only be "OBSERVED (not validated)" — not "PASSED"

> A report that claims PASSED without metric data is worse than no report.

#### Verdict Decision Tree (Agent MUST follow)

```
有完整指标 + baseline
  └── Probe 验证假设 → PASSED ✅ 或 FAILED ❌

有指标但无 baseline
  └── OBSERVED (baseline unknown) ⚠️

无指标数据（monitor.sh 未运行或数据丢失）
  └── OBSERVED (not validated) ⚠️

无实验结果文件（step5-experiment.json 缺失）
  └── BLOCKED (no data) ❌ — 不生成报告
```

Agent 不得自行判断 verdict，必须按决策树选择。

### 6.1 Analysis

Include in report:
1. Result summary: `Total: {N} = Passed: {P} + Failed: {F} + Aborted: {A}`
2. Steady-state hypothesis vs. actual performance comparison table
3. SLO/RTO Compliance Table (target vs. actual)
4. MTTR phased analysis (Detection → Triage → Response → Recovery)
5. Application Log Analysis (error timeline, patterns, propagation, recovery) — per Impact Target from `step2-dependencies.json`, including those that showed **no** errors (a dependent workload that stayed clean is a finding too)
6. Resilience score update (compare with 9 dimensions)
7. Backfill newly discovered risks
8. Improvement recommendations (P0/P1/P2)
9. Cleanup Status (FIS templates, CM CRs, temporary alarms)

Report template details: [references/report-templates.md](report-templates.md)

### Report Generation Strategy: Section-by-Section

Generate the report in sections, writing each to file before proceeding:

1. **Header + Summary** → write to `output/step6-report.md`
   - Experiment list, pass/fail summary, date, environment
2. **Append: Experiment Details** → for each experiment:
   - Hypothesis, configuration, timeline, result
3. **Append: Metrics Analysis** → read `step5-metrics.jsonl`
   - Baseline vs actual table, time-series summary
4. **Append: Log Analysis** → read `step5-logs.jsonl` / `step5-log-summary.json`
   - Error timeline, patterns, recovery markers
5. **Append: MTTR Analysis** → calculate from metrics + logs
   - Detection → Triage → Response → Recovery breakdown
6. **Append: Recommendations** → P0/P1/P2 improvements
7. **Append: Cleanup Status** → verify all experiments cleaned up

> Between each section, use `edit` (append mode) to write to the report file.
> This ensures partial progress is saved even if the session is interrupted.
>
> After writing each section, confirm progress:
> "✅ Section N ({section_name}) written ({byte_count} bytes) — {N}/7 complete"

**Output**: `output/step6-report.md` + `output/step6-report.html`

---

## Advanced: SSM Automation Orchestrated Experiments

The examples in Steps 1-5 use single FIS actions (terminate instance, failover cluster, etc.).
For more complex fault injection scenarios, FIS can trigger SSM Automation documents that orchestrate
multi-step experiments. Three key patterns from [aws-samples/fis-template-library](https://github.com/aws-samples/fis-template-library):

### Pattern 1: Dynamic Resource Injection

Create ephemeral infrastructure to inject faults, then automatically clean up.

**Flow:**
1. FIS triggers SSM Automation document
2. SSM creates ephemeral resources (e.g., EC2 instance as load generator)
3. SSM installs tools and executes fault injection on the ephemeral resource
4. SSM waits for specified duration
5. SSM cleans up (releases resources, terminates ephemeral instances)

**Example**: `database-connection-limit-exhaustion` — dynamically creates EC2, installs DB client,
opens connections to exhaust the connection pool, holds them, then releases and terminates the instance.

**When to use**: When the fault requires a load generator or intermediary that doesn't exist in
the target environment (e.g., generating connection pressure, traffic flooding).

See: `references/fis-templates/database-connection-exhaustion/`

### Pattern 2: Security Group Manipulation

Block specific service-to-service traffic by modifying Security Group rules.

**Flow:**
1. SSM discovers target resources and their Security Groups
2. SSM records original SG rules (for rollback)
3. SSM removes/modifies inbound rules to block specific traffic
4. Disruption maintained for specified duration
5. SSM restores original SG rules

**Example**: `elasticache-redis-connection-failure` — removes SG inbound rules to block
application → Redis traffic, simulating network partition at the service level.

**Advantage over FIS native network actions**: FIS `aws:network:disrupt-connectivity` operates
at the subnet level (via NACL). SG manipulation targets specific service connections, allowing
more surgical fault injection (e.g., block Redis but not DynamoDB from the same subnet).

See: `references/fis-templates/redis-connection-failure/`

### Pattern 3: Resource Policy Denial

Simulate service unavailability by applying deny policies at the IAM/resource policy level.

**Flow:**
1. SSM discovers target resources by tag
2. SSM adds deny-all statement to the resource's access policy
3. All API operations on the resource return `AccessDenied`
4. After duration, SSM removes the deny statement
5. Service resumes normal operation

**Example**: `sqs-queue-impairment` — attaches deny policy to SQS queue policy.
`cloudfront-impairment` — applies deny policy to S3 origin bucket policy.

**Advantage**: Works for any AWS service that supports resource-based policies. Can simulate
service unavailability without network-level disruption. Supports progressive impairment
(escalating denial rounds with recovery windows).

See: `references/fis-templates/sqs-queue-impairment/`, `references/fis-templates/cloudfront-impairment/`

### Choosing the Right Pattern

| Pattern | Best For | Complexity | Rollback Safety |
|---------|----------|-----------|----------------|
| Dynamic Resource Injection | Load/connection pressure testing | High | High (ephemeral resources auto-cleaned) |
| Security Group Manipulation | Service-level network isolation | Medium | Medium (must restore exact original rules) |
| Resource Policy Denial | Service unavailability simulation | Low | High (remove deny statement) |

> **Note**: All three patterns require both FIS and SSM IAM roles. The embedded templates
> in `references/fis-templates/` include the required IAM policies and trust relationships.
