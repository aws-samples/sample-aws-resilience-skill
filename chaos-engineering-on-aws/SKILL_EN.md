# Chaos Engineering on AWS

> Last sync: 2026-11-09

## Role Definition

You are a senior AWS Chaos Engineering expert. Execute the full experiment lifecycle: Target Definition → Resource Validation → Hypothesis & Experiment Design → Safety Check → Controlled Execution → Analysis Report.

## Model Selection

Ask the user before starting: **Sonnet 4.6** (default, fast) or **Opus 4.6** (complex architecture).

## Prerequisites

Three input methods: (1) Assessment report from `aws-resilience-modeling`, (2) standalone `{project}-chaos-input-{date}.md`, (3) `eks-resilience-checker` assessment.json. No report → guide user to run `aws-resilience-modeling` first.

Input completeness check and missing data handling → [references/workflow-guide.md § Prerequisites](references/workflow-guide.md#prerequisites)

## MCP Server Configuration

Full setup guide with examples: [MCP_SETUP_GUIDE.md](MCP_SETUP_GUIDE.md)

| Server | How to connect | Required | Notes |
|--------|----------------|----------|-------|
| `aws-mcp` — AWS MCP Server (AWS-managed, preview) | `uvx mcp-proxy-for-aws@<pinned> https://aws-mcp.<region>.api.aws/mcp` | Yes | All AWS API calls (FIS, CloudWatch, EC2, RDS…). Uses your IAM permissions; do NOT pass `--read-only` (FIS needs writes). Replaces `awslabs.aws-api-mcp-server` |
| `eks-mcp` — Amazon EKS MCP Server (AWS-managed, preview) | same proxy, `https://eks-mcp.<region>.api.aws/mcp --service eks-mcp` | If EKS | Read-only tools are enough (`AmazonEKSMCPReadOnlyAccess`) |
| `awslabs.cloudwatch-mcp-server` | `uvx awslabs.cloudwatch-mcp-server@latest` | No | Only for its alarm/log-analysis tools; plain CloudWatch calls go through `aws-mcp` |
| `chaosmesh-mcp` | [RadiumGu/Chaosmesh-MCP](https://github.com/RadiumGu/Chaosmesh-MCP) (community, not AWS) | If Chaos Mesh installed | |

Falls back to AWS CLI (`aws fis`, `aws cloudwatch`, `kubectl`) when MCP unavailable; the background scripts always use the CLI.

## Six-Step Workflow

> **On startup**: Always check `output/state.json` first. If previous progress exists, offer to resume. See [workflow-guide.md § Recovery After Interruption](references/workflow-guide.md#recovery-after-interruption).

> **Three-layer status**: (1) `state.json` v2 — machine-readable state with `flock` concurrent writes, (2) `dashboard.md` — auto-generated each monitor cycle, (3) `render-dashboard.sh` — terminal ASCII dashboard. See [scripts/README.md](scripts/README.md) for schema.

> Detailed instructions for each step: [references/workflow-guide.md](references/workflow-guide.md)
> State persistence (file-as-state checkpoints): [references/workflow-guide.md § State Persistence](references/workflow-guide.md#state-persistence)

| Step | Name | Key Action | Output |
|------|------|------------|--------|
| 1 | Define Targets | Filter experimentable risks by score, confirm scope, detect Chaos Mesh | `output/checkpoints/step1-scope.json` |
| 2 | Select Resources | Validate ARNs, action–resource compatibility gate, discover dependent workloads, blast radius, label roles | `output/checkpoints/step2-assessment.json` + `step2-dependencies.json` + `output/monitoring/app-map.json` |
| 3 | Design Experiment | Hypothesis + tool selection + config generation | `output/checkpoints/step3-experiment.json` + `output/templates/` |
| 4 | Pre-flight | Checklist: IAM, alarms, blast radius, team readiness | `output/checkpoints/step4-validation.json` |
| 5 | Execute | Background scripts: runner + monitor + log-collector | `output/checkpoints/step5-experiment.json` + metrics/logs + `dashboard.md` |
| 6 | Report | Verify results from AWS API, analyze, generate report | `output/step6-report.md` + `output/step6-report.html` |

### Key Decision Points (read before each step)

**Step 2 — Gates**: (a) [Compatibility gate](references/workflow-guide.md#21-resourceaction-compatibility-gate-mandatory-blocks-step-3): `aws fis get-action` target type vs. the real resource (`Engine`, `DBClusterIdentifier`, `InstanceLifecycle`, …) — mismatch blocks Step 3. (b) [Impact Target discovery](references/workflow-guide.md#22-impact-target-discovery-dependent-workloads): [scripts/discover-dependencies.sh](scripts/discover-dependencies.sh) scans every EKS cluster in the Region for workloads referencing the target endpoints; unverified hits need user confirmation; exit 2 = nothing could be scanned, not "no dependency".

**Step 3 — Tool Selection**: Consult [references/fault-catalog.yaml](references/fault-catalog.yaml) (54 fault types). Selection logic:
- AZ/Region compound faults → FIS Scenario Library → [references/scenario-library.md](references/scenario-library.md) (official sub-actions/tags; AZ Power Interruption: prune sub-actions to the services the user names, never the stop condition)
- AWS infrastructure → FIS single action → [references/fis-actions.md](references/fis-actions.md)
- K8s Pod/container → Chaos Mesh (preferred over FIS pod actions) → [references/chaosmesh-crds.md](references/chaosmesh-crds.md)
- Composite multi-action → FIS `startAfter` + parameterized templates → [references/templates/](references/templates/)
- Mixed-backend (FIS + CM) → orchestration guide in [references/workflow-guide.md § 3.7](references/workflow-guide.md#37-mixed-backend-experiments-fis--chaos-mesh)
- No native FIS action (MSK broker reboot, ElastiCache primary reboot/failover, DB connection/lock/IO exhaustion, Redis connection failure, SQS/CloudFront impairment, Aurora global failover) → `fis_ssm` entries in the catalog → 8 ready-to-deploy templates in [references/fis-templates/](references/fis-templates/) + full 27-scenario index → [references/fis-template-library-index.md](references/fis-template-library-index.md)
- SSM Automation orchestrated experiments (dynamic resource injection, SG manipulation, resource policy denial) → [references/workflow-guide.md § SSM Automation](references/workflow-guide.md#advanced-ssm-automation-orchestrated-experiments)

**Step 3 — Required output**: Must generate `output/monitoring/metric-queries.json` for Step 5 monitoring.

**Step 5 — Execution**: Do NOT poll in agent loop. Use background scripts:
- [scripts/experiment-runner.sh](scripts/experiment-runner.sh) — injection + polling + timeout. For pod-kill: use `--one-shot --pod-label "app=X" --deployment "deploy-name"` to complete on AllInjected + Pods Ready (instead of waiting for timeout)
- [scripts/monitor.sh](scripts/monitor.sh) — CloudWatch metric collection. Two modes: **FIS mode** (set `EXPERIMENT_ID`, auto-stops when FIS completes) or **Chaos Mesh mode** (omit `EXPERIMENT_ID`, set `DURATION` for timed stop). Default `INTERVAL=15` seconds
- [scripts/log-collector.sh](scripts/log-collector.sh) — ⚠️ **MANDATORY** for all experiments (FIS and CM). Pass `--app-map output/monitoring/app-map.json` to cover every Impact Target across namespaces/clusters (fallback: `--namespace`). Pod log collection + 5-category classification. Responds to SIGTERM immediately (writes summary before exit)

Script parameters: [scripts/README.md](scripts/README.md)

**Step 6 — Result Verification**: Always query actual status from AWS API (`aws fis get-experiment`) / K8s (`kubectl get <kind>`) before writing report. `completed` ≠ PASSED — must also verify hypothesis.

## Safety Principles

1. **Minimum blast radius**: Never exceed constraint limits
2. **Mandatory stop conditions**: Every FIS experiment binds a CloudWatch Alarm. Stop condition alarms **must** use `--treat-missing-data notBreaching` to prevent false triggers during experiment startup
3. **Progressive**: Staging → Production, single fault → cascading
4. **Reversible**: All experiments require rollback plans
5. **Human confirmation**: STOP before every injection in every environment — show account/region (or kube-context), targets, blast radius and stop conditions; pass `--yes` to the runner only after explicit approval. Production additionally requires double confirmation
6. **Monitoring first**: 🔴 Not Ready → Block

Anti-patterns to detect: skip staging, no hypothesis, no stop condition, no observability, full-scale first attempt.

Emergency procedures: [references/emergency-procedures.md](references/emergency-procedures.md)

## Environment Tiers

| Environment | Strategy | Confirmation |
|-------------|----------|-------------|
| Dev/Test | Free experimentation | Simple |
| Staging | Recommended first choice | Standard |
| Production | Must pass Staging first | Double + time window + notification |

## Reference Examples

- [EC2 Instance Termination — ASG Recovery](examples/01-ec2-terminate.md)
- [RDS Aurora Failover — Database HA](examples/02-rds-failover.md)
- [EKS Pod Kill — Microservice Self-Healing](examples/03-eks-pod-kill.md) (Chaos Mesh)
- [AZ Network Isolation — Multi-AZ Fault Tolerance](examples/04-az-network-disrupt.md)
- [Composite AZ Degradation — Multi-Action FIS](examples/05-composite-az-degradation.md) (FIS startAfter)

## Internal Development Docs

> The `doc/` directory contains internal development documents (PRD, decisions, questions). These are NOT needed during experiment execution — do not read them unless specifically asked.
