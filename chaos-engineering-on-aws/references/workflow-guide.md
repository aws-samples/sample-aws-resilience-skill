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
│   ├── step2-assessment.json     # Weak points, experiment recommendations
│   ├── step3-experiment.json     # FIS experiment template definition
│   ├── step4-validation.json     # Pre-flight checks, user confirmation
│   └── step5-experiment.json     # FIS experiment state, ID, timeline
├── monitoring/
│   ├── step5-metrics.jsonl       # Monitoring script streaming metrics
│   ├── step5-logs.jsonl          # Raw application log JSONL
│   ├── step5-log-summary.json    # Classified log summary
│   ├── metric-queries.json       # CloudWatch metric query definitions
│   └── experiment_id.txt         # FIS experiment ID
├── templates/                    # Generated FIS / Chaos Mesh templates
├── step6-report.md           # Final report (Markdown)
├── step6-report.html         # Final report (HTML, inline CSS)
├── baseline-{timestamp}.json # Steady-state baseline snapshots
└── state.json                # Progress metadata
```

On startup, check `output/state.json` — if it exists and is incomplete → prompt to continue or start fresh.

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
6. Detect Chaos Mesh: `kubectl get crd | grep chaos-mesh` — if installed, include CM scenarios in recommendations

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

**Output**: `output/checkpoints/step2-assessment.json`

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

Consult the **unified fault catalog** ([references/fault-catalog.yaml](references/fault-catalog.yaml)) for the full list of available fault types, default parameters, and prerequisites:

- **AZ/Region compound faults** → FIS Scenario Library → [references/scenario-library.md](references/scenario-library.md)
- **AWS infrastructure layer** → AWS FIS single action → [references/fis-actions.md](references/fis-actions.md)
- **K8s Pod/container layer** → Chaos Mesh → [references/chaosmesh-crds.md](references/chaosmesh-crds.md)

> ⚠️ For Pod-level faults, **prefer Chaos Mesh** over FIS `aws:eks:pod-*` actions (faster, simpler RBAC).

> ⚠️ FIS Scenario Library has **three creation paths**: (1) Console → export; (2) Content tab → API; (3) JSON skeletons from [references/scenario-library.md](references/scenario-library.md) directly via API. See that file for details.

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

Example: [Composite AZ Degradation](examples/05-composite-az-degradation.md)

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
□ Stop Condition Alarms ready
□ output/monitoring/metric-queries.json exists (generated in Step 3)

Safety:
□ Blast radius ≤ maximum limit
□ Rollback plan verified
□ Data backup confirmed (if data layer involved)

Team:
□ Stakeholders notified
□ On-call personnel in position
```

Automatic remediation: FIS Role missing → generate creation command; Alarm missing → generate `put-metric-alarm`; Monitoring 🔴 → Block.

**Output**: `output/checkpoints/step4-validation.json`

## Step 5: Run Controlled Experiment

**Scripts**: See [scripts/README.md](../scripts/README.md) for all parameters.

### Phase 0: Baseline Collection (T-5min)
Collect steady-state baseline, save as `output/baseline-{timestamp}.json`.

### Phase 1: Fault Injection + Observation

> ⚠️ **CRITICAL**: Do NOT poll experiment status in the agent loop. Use `experiment-runner.sh` which handles injection, polling, timeout, and state output in a background process.

Launch all background processes, then `wait`:
```bash
nohup bash scripts/experiment-runner.sh --mode fis --template-id "$TEMPLATE_ID" ... &
RUNNER_PID=$!
nohup bash scripts/monitor.sh &
nohup bash scripts/log-collector.sh --namespace {NS} --services "{svcs}" --mode live ... &
wait $RUNNER_PID
```

Exit codes: 0=completed, 1=failed, 2=timeout

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
| Game Day | Cross-team exercise, see [references/gameday.md](references/gameday.md) |

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

### 6.1 Analysis

Include in report:
1. Result summary: `Total: {N} = Passed: {P} + Failed: {F} + Aborted: {A}`
2. Steady-state hypothesis vs. actual performance comparison table
3. SLO/RTO Compliance Table (target vs. actual)
4. MTTR phased analysis (Detection → Triage → Response → Recovery)
5. Application Log Analysis (error timeline, patterns, propagation, recovery)
6. Resilience score update (compare with 9 dimensions)
7. Backfill newly discovered risks
8. Improvement recommendations (P0/P1/P2)
9. Cleanup Status (FIS templates, CM CRs, temporary alarms)

Report template details: [references/report-templates.md](references/report-templates.md)

**Output**: `output/step6-report.md` + `output/step6-report.html`
