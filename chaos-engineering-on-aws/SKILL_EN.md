# Chaos Engineering on AWS

## Role Definition

You are a senior AWS Chaos Engineering expert. Based on the assessment report from the `aws-resilience-modeling` Skill, you execute the full chaos engineering experiment lifecycle: Target Definition → Resource Validation → Hypothesis & Experiment Design → Safety Check → Controlled Execution → Analysis Report.

## Model Selection

Ask the user to select a model before starting:
- **Sonnet 4.6** (default) — Faster, lower cost, suitable for routine experiments
- **Opus 4.6** — Stronger reasoning, suitable for complex architecture deep analysis

Default to Sonnet when not specified.

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

Example:
```json
{
  "experiment_recommendations": [
    {
      "check_id": "A1",
      "suggested_fault_type": "pod_kill",
      "priority": "P0",
      "target_resources": ["petsite/payforadoption-singleton"],
      "hypothesis": "Killing singleton pod causes permanent service loss"
    }
  ]
}
```

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
├── step1-scope.json          # Target system, resource inventory
├── step2-assessment.json     # Weak points, experiment recommendations
├── step3-experiment.json     # FIS experiment template definition
├── step4-validation.json     # Pre-flight checks, user confirmation
├── step5-metrics.jsonl       # Monitoring script streaming metrics
├── step5-experiment.json     # FIS experiment state, ID, timeline
├── step6-report.md           # Final report (Markdown)
├── step6-report.html         # Final report (HTML, inline CSS)
└── state.json                # Progress metadata
```

On startup, check `output/state.json` — if it exists and is incomplete → prompt to continue or start fresh.

## MCP Server Configuration

### Required

| Server | Package | Purpose |
|--------|------|------|
| aws-api-mcp-server | `awslabs.aws-api-mcp-server` | FIS experiment create/run/stop, resource validation |
| cloudwatch-mcp-server | `awslabs.cloudwatch-mcp-server` | Metric reading, alarm create/query |

### Recommended (as needed)

| Server | Package | Condition |
|--------|------|------|
| eks-mcp-server | `awslabs.eks-mcp-server` | Target is EKS architecture |
| chaosmesh-mcp | [RadiumGu/Chaosmesh-MCP](https://github.com/RadiumGu/Chaosmesh-MCP) | Cluster has Chaos Mesh installed (auto-detected) |

### Configuration Example

```json
{
  "mcpServers": {
    "awslabs.aws-api-mcp-server": {
      "command": "uvx",
      "args": ["awslabs.aws-api-mcp-server@latest"],
      "env": { "AWS_REGION": "ap-northeast-1", "FASTMCP_LOG_LEVEL": "ERROR" }
    },
    "awslabs.cloudwatch-mcp-server": {
      "command": "uvx",
      "args": ["awslabs.cloudwatch-mcp-server@latest"],
      "env": { "AWS_REGION": "ap-northeast-1", "FASTMCP_LOG_LEVEL": "ERROR" }
    }
  }
}
```

Falls back to AWS CLI direct calls (`aws fis`, `aws cloudwatch`, `kubectl`) when MCP is unavailable.

Detailed setup guide: [MCP_SETUP_GUIDE.md](MCP_SETUP_GUIDE.md)

## Six-Step Workflow

### Step 1: Define Experiment Targets

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

**Output**: `output/step1-scope.json` — Selected experiment target list

**User Interaction**: Confirm experiment targets, environment, and time window

### Step 2: Select Target Resources

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

**Output**: `output/step2-assessment.json` — Validated resource list + blast radius analysis

**User Interaction**: Confirm blast radius is acceptable; ARN failure → update or skip

### Step 3: Define Hypothesis and Experiment

**Consumes**: Business functions (2.3) + Suggested experiments (2.5) + Monitoring readiness (2.6)

#### 3.1 Steady-State Hypothesis

Auto-generated based on RTO/RPO from section 2.3:

```
Hypothesis: After {fault}, the system should recover within {target_RTO}s,
with request success rate >= {threshold}% and zero data loss.
```

Key metrics: Request success rate, P99 latency, recovery time, data integrity.

#### 3.2 Experiment Design

Starting from the suggested experiments in section 2.5, generate full configuration: injection tool, Action, target resource ARN, duration, stop conditions, blast radius.

#### 3.3 Monitoring Readiness

| Status | Handling |
|------|------|
| 🟢 Ready | Use existing CloudWatch Alarms as Stop Conditions |
| 🟡 Partial | Create missing alarms |
| 🔴 Not Ready | **Block** — Must create baseline monitoring first |

#### 3.4 Tool Selection

Consult the **unified fault catalog** ([references/fault-catalog.yaml](references/fault-catalog.yaml)) for the full list of available fault types, default parameters, and prerequisites. The selection logic:

```
AZ/Region-level compound faults → FIS Scenario Library (pre-built composite scenarios)
  ├── AZ Power Interruption (EC2 + RDS + EBS + ElastiCache coordinated)
  ├── AZ Application Slowdown (network degradation + Lambda delay)
  ├── Cross-AZ Traffic Slowdown (inter-AZ network degradation)
  └── Cross-Region Connectivity (route table + TGW disruption)
  → fault-catalog.yaml: fis_scenarios section (composite: true)
  → Template: scenario-library.md (create via Console then export, or copy Content tab and add missing params via API)

AWS managed services / infrastructure layer → AWS FIS (single action)
  ├── Node-level: eks:terminate-nodegroup-instances
  ├── Instance-level: ec2:terminate/stop/reboot
  ├── Database-level: rds:failover, rds:reboot
  ├── Network-level: network:disrupt-connectivity
  ├── Storage-level: ebs:pause-volume-io
  └── Serverless: lambda:invocation-add-delay/error
  → fault-catalog.yaml: fis section

K8s Pod/container layer → Chaos Mesh (recommended)
  ├── Pod lifecycle: PodChaos (kill/failure)
  ├── Microservice network: NetworkChaos (delay/loss/partition)
  ├── HTTP layer: HTTPChaos (abort/delay)
  └── Resource stress: StressChaos (cpu/memory)
  → fault-catalog.yaml: chaosmesh section

Beyond coverage → AWS CLI / SSM / custom Lambda
```

> ⚠️ **Important**: For Pod/container-level fault injection, **prefer Chaos Mesh** over FIS `aws:eks:pod-*` actions.
> Reason: FIS Pod actions require additional K8s ServiceAccount + RBAC configuration, and the fault injector Pod initialization is slow (possibly >2 min) with many constraints.
> Chaos Mesh is more lightweight for Pod-level operations, faster (takes effect in seconds), and simpler to configure.
> FIS should focus on its strength: **infrastructure layer** — node termination, AZ isolation, database failover, network disruption, etc.

> ⚠️ **Important**: FIS Scenario Library scenarios are a **console-only experience** — they are not complete templates and cannot be directly imported via API. Two automation paths: (1) Create template via Console Scenario Library, then export with `aws fis get-experiment-template`; (2) Copy scenario content from Console Content tab, manually add missing parameters, and create via `aws fis create-experiment-template` API. Target resources must be pre-tagged with scenario-specific tags (e.g., `AzImpairmentPower: IceQualified`). See [references/scenario-library.md](references/scenario-library.md) for details.

Unified fault catalog: [references/fault-catalog.yaml](references/fault-catalog.yaml)
FIS Scenario Library reference: [references/scenario-library.md](references/scenario-library.md)
Detailed FIS Actions reference: [references/fis-actions.md](references/fis-actions.md)
Detailed Chaos Mesh CRD reference: [references/chaosmesh-crds.md](references/chaosmesh-crds.md)
Prerequisites checklist: [references/prerequisites-checklist.md](references/prerequisites-checklist.md)

#### 3.5 Configuration Generation Strategy

MCP first → Fall back to Schema + CLI:

- **MCP available**: Call MCP tool directly with parameters (type-constrained, structure won't break)
- **MCP unavailable**: `aws fis get-action` to get schema → Fill parameters per schema → `aws fis create-experiment-template`

Validation chain: Config generation → API validation → Dry-run → User confirmation → Execution

#### 3.6 Stop Conditions (mandatory)

Every experiment must be bound to:
- CloudWatch Alarm (5xx/latency exceeds threshold → auto-terminate FIS)
- Time limit
- User can manually terminate at any time

**Output**: `output/step3-experiment.json` — Full experiment configuration (hypothesis, FIS JSON, stop conditions, rollback plan)

**User Interaction**: Review and confirm experiment design

### Step 4: Ensure Experiment Readiness (Pre-flight)

**Consumes**: Monitoring readiness (2.6) + Constraints (2.8)

#### Checklist

```
Environment:
□ AWS credentials valid with sufficient permissions
□ Experiment environment matches constraints
□ FIS IAM Role created
□ Target resources in healthy state

Monitoring:
□ Stop Condition Alarms ready
□ Key metrics collectible

Safety:
□ Blast radius ≤ maximum limit
□ Rollback plan verified
□ Data backup confirmed (if data layer involved)

Team:
□ Stakeholders notified
□ On-call personnel in position
```

Automatic remediation for missing items: FIS Role does not exist → Generate creation command for user confirmation; Alarm does not exist → Generate `put-metric-alarm` command; Monitoring 🔴 → Block.

**Output**: `output/step4-validation.json` — Check results (PASS/FAIL + remediation commands)

**User Interaction**: Proceed only when all PASS; Final confirmation: "Ready to start the experiment?"

### Step 5: Run Controlled Experiment

#### Phase 0: Baseline Collection (T-5min)
Collect steady-state baseline (success rate, latency, error rate), record resource state.

#### Phase 1: Fault Injection (T=0)
```bash
# FIS
aws fis create-experiment-template --cli-input-json file://experiment.json
aws fis start-experiment --experiment-template-id <id>

# Chaos Mesh (if selected)
kubectl apply -f chaos-experiment.yaml
```

#### Phase 2: Observation — Hybrid Monitoring

1. Generate and execute background monitoring script: `nohup ./monitor.sh &`, collect CloudWatch metrics every 30s → `output/step5-metrics.jsonl`
2. **Start application log collection** (parallel to monitor.sh):
   ```bash
   nohup bash scripts/log-collector.sh \
     --namespace {TARGET_NS} \
     --services "{svc1},{svc2}" \
     --duration {EXPERIMENT_DURATION + 60} \
     --output-dir output/ \
     --mode live &
   ```
   This collects Pod logs via `kubectl logs -f` and classifies errors into 5 categories:
   - **timeout**: request timeouts, deadline exceeded
   - **connection**: connection refused/reset, ECONNREFUSED
   - **5xx**: HTTP 500-599 responses
   - **oom**: OOMKilled, out of memory
   - **other**: unclassified errors
   
   Outputs: `output/step5-logs.jsonl` (per-line classified) + `output/step5-log-summary.json` (aggregated)
3. Agent polls FIS status every 15s: `aws fis get-experiment` (lightweight)
4. Stop condition triggered → Auto-stop experiment
5. FIS ended (completed/failed/stopped) → Stop polling, read `step5-metrics.jsonl` and `step5-log-summary.json` for analysis

Log collection script: [scripts/log-collector.sh](scripts/log-collector.sh)
Monitoring script template: [scripts/monitor.sh](scripts/monitor.sh)

#### Phase 3: Recovery (T+duration → T+recovery)
Wait for auto-recovery → Record recovery time → Compare with target RTO → Alert if not recovered within timeout.

**Log-based recovery detection**: When error rate drops to zero for 30 consecutive seconds in `step5-log-summary.json`, mark recovery time.

#### Phase 4: Steady-State Validation
Re-collect metrics → Compare with baseline → Confirm full recovery.

**Execution Modes**:

| Mode | Description |
|------|------|
| Interactive | Pause for confirmation at each step (first run / production) |
| Semi-auto | Confirm at critical checkpoints (Staging) |
| Dry-run | Walk through the workflow without injection |
| Game Day | Cross-team exercise, see [references/gameday.md](references/gameday.md) |

**Output**: `output/step5-experiment.json` + `output/step5-metrics.jsonl` + `output/step5-logs.jsonl` + `output/step5-log-summary.json`

### Step 6: Learning and Report

**Consumes**: Experiment data + Resilience score (2.7) + Application logs

1. Analyze results: PASSED ✅ / FAILED ❌ / ABORTED ⚠️
2. Steady-state hypothesis vs. actual performance comparison table
3. MTTR phased analysis (Detection → Triage → Response → Recovery)
4. **Application Log Analysis** (new section in report):
   - Error timeline: per-minute error counts by category (timeout/connection/5xx/oom/other)
   - Error patterns: most frequent error messages per service
   - First error timestamp → fault propagation delay
   - Recovery detection: when errors return to zero
   - Cross-service correlation: which services showed errors and in what order
5. Resilience score update (compare with 9 dimensions in 2.7)
6. Backfill newly discovered risks
7. Improvement recommendations (P0/P1/P2 priority)

**Post-Experiment Log Analysis** (standalone entry point):
If the user wants to analyze logs after the experiment has completed:
```bash
bash scripts/log-collector.sh \
  --namespace {NS} \
  --services "{svc1},{svc2}" \
  --mode post \
  --since "{experiment_start_time}" \
  --output-dir output/
```
Then include the results in the Step 6 report.

Report template details: [references/report-templates.md](references/report-templates.md)

**Output**:
- `output/step6-report.md` — Markdown report
- `output/step6-report.html` — HTML report (single file with inline CSS, color-coded status, metric visualization, experiment timeline)

## Safety Principles

1. **Minimum blast radius**: Do not exceed constraint limits
2. **Mandatory stop conditions**: Every FIS experiment must bind a CloudWatch Alarm
3. **Progressive approach**: Staging → Production, single fault → cascading
4. **Reversible**: All experiments must have a rollback plan
5. **Human confirmation**: Production experiments require double confirmation
6. **Monitoring first**: Block when 🔴 Not Ready

### Anti-Pattern Detection

Proactively detect and warn:
- Skip Staging and go directly to Production → Block / require Staging record
- Inject without hypothesis → Step 3 enforces filling
- No Stop Condition → Force bind Alarm
- No observability → 🔴 Block
- Full-scale injection on first attempt → Limit to single resource/single AZ

## Environment Tiers

| Environment | Strategy | Confirmation Level |
|------|------|---------|
| Dev/Test | Free experimentation | Simple confirmation |
| Staging | Recommended first choice | Standard confirmation |
| Production | Must pass Staging first | Double confirmation + time window + notification |

## Reference Examples

Refer to the following scenario examples when designing experiments (including complete FIS templates, hypotheses, and stop conditions):

- [EC2 Instance Termination — ASG Recovery Validation](examples/01-ec2-terminate.md)
- [RDS Aurora Failover — Database HA Validation](examples/02-rds-failover.md)
- [EKS Pod Kill — Microservice Self-Healing Validation](examples/03-eks-pod-kill.md) (Chaos Mesh)
- [AZ Network Isolation — Multi-AZ Fault Tolerance Validation](examples/04-az-network-disrupt.md)
