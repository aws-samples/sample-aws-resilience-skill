[**中文**](README_zh.md) | English

# Chaos Engineering on AWS

An AI-powered Agent Skill for running controlled chaos engineering experiments on AWS, covering the full lifecycle: scope definition → resource validation → experiment design → safety checks → controlled execution → analysis & reporting.

## Overview

This skill enables you to systematically validate system resilience through controlled fault injection using **AWS FIS** and optional **Chaos Mesh**, guided by assessment reports from the `aws-resilience-modeling` skill.

## Installation

**Option A: npx skills (Recommended)**
```bash
# Install this skill
npx skills add aws-samples/sample-aws-resilience-skill --skill chaos-engineering-on-aws

# Install all 4 resilience skills
npx skills add aws-samples/sample-aws-resilience-skill --skill '*'
```

**Option B: Git clone**
```bash
git clone https://github.com/aws-samples/sample-aws-resilience-skill.git
```

## Prerequisites

- Completed assessment report from `aws-resilience-modeling` skill (recommended)
- AWS credentials with FIS permissions
- MCP servers configured (see below)
- Prerequisites checklist completed (see [references/prerequisites-checklist.md](references/prerequisites-checklist.md))

## MCP Server Setup

> `awslabs.aws-api-mcp-server` is superseded by the AWS-managed **AWS MCP Server** ([migration guide](https://github.com/awslabs/mcp/blob/main/src/aws-api-mcp-server/MIGRATION.md)). Remove the old entry, and the `ALLOW_WRITE_OPERATIONS` variable earlier versions of this README asked for: it never existed in that server.

### Required

| Server | How to connect | Purpose |
|--------|----------------|---------|
| `aws-mcp` — [AWS MCP Server](https://docs.aws.amazon.com/agent-toolkit/latest/userguide/mcp-server.html) (AWS-managed, preview) | `uvx mcp-proxy-for-aws@<pinned> https://aws-mcp.<region>.api.aws/mcp --metadata AWS_REGION=<region>` | All AWS API calls: FIS create/run/stop, CloudWatch metrics and alarms, resource validation; AWS documentation lookup. Runs with your IAM permissions (no `--read-only`: FIS needs writes) |

### Optional

| Server | How to connect | When |
|--------|----------------|------|
| `eks-mcp` — [Amazon EKS MCP Server](https://docs.aws.amazon.com/eks/latest/userguide/eks-mcp-introduction.html) (AWS-managed, preview) | same proxy, `https://eks-mcp.<region>.api.aws/mcp --service eks-mcp` | EKS-based architectures (open-source `awslabs.eks-mcp-server` as a local alternative) |
| `awslabs.cloudwatch-mcp-server` | `uvx awslabs.cloudwatch-mcp-server@latest` | Only for its alarm-recommendation / log-analysis tools |
| `chaosmesh-mcp` | [RadiumGu/Chaosmesh-MCP](https://github.com/RadiumGu/Chaosmesh-MCP) (community project, not AWS) | Cluster has Chaos Mesh installed |

### Configuration

> Full setup guide with examples (Kiro, Claude Code, Cursor/VS Code), IAM and verification: [MCP_SETUP_GUIDE.md](MCP_SETUP_GUIDE.md)

No MCP? The skill falls back to AWS CLI (`aws fis`, `aws cloudwatch`, `kubectl`); the background scripts always use the CLI.

### Chaos Mesh MCP: EKS Authentication

Two methods: **Static ServiceAccount Token** (recommended for production) or **Admin kubeconfig** (quick testing). See [MCP_SETUP_GUIDE.md § chaosmesh-mcp](MCP_SETUP_GUIDE.md#4-chaosmesh-mcp-optional-community) and the project's [EKS Authentication Methods](https://github.com/RadiumGu/Chaosmesh-MCP#eks-authentication-methods).

## Six-Step Workflow

| Step | Name | Output |
|------|------|--------|
| 1 | Define Experiment Scope | `output/step1-scope.json` |
| 2 | Select Target Resources | `output/step2-assessment.json` |
| 3 | Design Hypothesis & Experiment | `output/step3-experiment.json` |
| 4 | Pre-flight Validation | `output/step4-validation.json` |
| 5 | Run Controlled Experiment | `output/step5-experiment.json` + `step5-metrics.jsonl` + `step5-logs.jsonl` + `state.json` + `dashboard.md` |
| 6 | Analysis & Report | `output/step6-report.md` + `step6-report.html` |

## Fault Injection Tools

> 📋 Full structured catalog: [references/fault-catalog.yaml](references/fault-catalog.yaml)

### Fault Catalog Summary: 54 Fault Actions

| Backend | Count | Coverage |
|---------|-------|----------|
| **AWS FIS** | 24 | EC2, RDS, Lambda, EBS, DynamoDB, S3, API Gateway, ECS, Network |
| **Chaos Mesh** | 14 | Pod lifecycle, Network, HTTP, CPU/Memory stress, IO, DNS |
| **FIS + SSM Automation** | 12 | Faults with no native FIS action, from the FIS Template Library: MSK broker reboot, ElastiCache primary reboot/failover, Redis connection failure, DB connection/lock/IO exhaustion, SQS/CloudFront impairment, Aurora global failover |
| **FIS Scenario** | 4 | AZ Power Interruption, AZ App Slowdown, Cross-AZ Traffic, Cross-Region |

```
AZ/Region-level Compound Faults  →  FIS Scenario Library
  ├── AZ Power Interruption (EC2 + RDS + EBS + ElastiCache)
  ├── AZ Application Slowdown (network latency injection)
  ├── Cross-AZ Traffic Slowdown (inter-AZ packet loss)
  └── Cross-Region Connectivity (TGW + route table disruption)
  Three creation paths:
    (1) Console Scenario Library → export with `aws fis get-experiment-template`
    (2) Console Content tab → manually add missing params → API create
    (3) Use JSON skeletons from references/scenario-library.md directly via API

Composite Multi-Action Experiments  →  FIS Native (startAfter)
  ├── Parallel: multiple actions with no startAfter (simultaneous)
  ├── Sequential: startAfter dependencies between actions
  ├── Timed delays: aws:fis:wait action for gaps between actions
  └── Parameterized templates: references/templates/ ({{placeholder}} format)
  See examples/05-composite-az-degradation.md for a complete walkthrough

AWS Managed Services / Infrastructure  →  AWS FIS (single action)
  ├── Node level:    eks:terminate-nodegroup-instances
  ├── Instance:      ec2:terminate/stop/reboot
  ├── Database:      rds:failover, rds:reboot
  ├── Network:       network:disrupt-connectivity
  └── Serverless:    lambda:invocation-add-delay/error

Mixed-Backend Experiments  →  FIS + Chaos Mesh (orchestrated)
  Run both FIS and Chaos Mesh simultaneously for infra + Pod-layer faults.
  CM injects first → verify → FIS injects → parallel monitoring → abort: FIS first, CM second.

K8s Pod / Container Layer  →  Chaos Mesh (preferred)
  ├── Pod lifecycle: PodChaos (kill/failure)
  ├── Network:       NetworkChaos (delay/loss/partition)
  ├── HTTP:          HTTPChaos (abort/delay)
  └── Resources:     StressChaos (cpu/memory)
```

## Key Features

- Dual-channel observability: CloudWatch metrics (`monitor.sh`) + application logs (`log-collector.sh`)
- 5-category error classification (timeout, connection, 5xx, oom, other)
- AI-guided experiment design with automatic safety validation
- Progressive fault injection with mandatory stop conditions
- Multi-tool support: AWS FIS + Chaos Mesh + FIS Scenario Library
- **Composite experiments**: FIS native multi-action templates with `startAfter` orchestration (parallel, sequential, timed delays)
- **Mixed-backend orchestration**: Run FIS + Chaos Mesh simultaneously with defined abort ordering
- **Parameterized templates**: Reusable `{{placeholder}}` templates for standardized scenarios
- **FIS Template Library integration**: 27-scenario index from [aws-samples/fis-template-library](https://github.com/aws-samples/fis-template-library) (synced to ee74d58) with 8 embedded ready-to-deploy templates
- **Resource–action compatibility gate**: the FIS action's target type is checked against the real resource before any template is generated
- **Impact Target discovery**: `discover-dependencies.sh` finds the EKS workloads (all clusters in the Region) that reference the resources under test; `log-collector.sh --app-map` then collects exactly those
- **3 advanced injection patterns**: SSM Automation orchestration (dynamic resource injection), Security Group manipulation, Resource Policy denial (progressive)
- **Three-layer state management**: `state.json` v2 state machine + `dashboard.md` Markdown board + terminal ASCII dashboard
- **Session interruption recovery**: Resume experiments after agent session interruption via `state.json` checkpoint

## State Management & Observability

The skill uses a three-layer status architecture for long-running experiments:

### Layer 1: `output/state.json` (v2)

Machine-readable state file, updated by `experiment-runner.sh` via `flock` for concurrent safety.

```json
{
  "version": 2,
  "workflow": { "current_step": 5, "status": "in_progress" },
  "experiments": [
    { "id": "EXP-001", "status": "completed", "elapsed_seconds": 74, "result": "PASSED" }
  ],
  "background_pids": { "runner": 12345, "monitor": 12346, "log_collector": 12347 }
}
```

On startup, the agent checks `state.json`:
- **Not found** → fresh start
- **Found with `status: in_progress`** → recovery mode: check PIDs, query FIS/CM status, resume or restart

### Layer 2: `output/dashboard.md`

Markdown dashboard auto-generated by `monitor.sh` every collection cycle (via `update-dashboard.sh`). Viewable in IDE Markdown Preview for real-time progress tracking.

### Layer 3: Terminal ASCII Dashboard

Colored ASCII dashboard for terminal monitoring:

```bash
watch -n 5 -c bash scripts/render-dashboard.sh
```

```
╔══════════════════════════════════════════════════════════════╗
║  🔬  Chaos Engineering Dashboard                            ║
╠══════════════════════════════════════════════════════════════╣
║  Progress: [████████████████████] 100%  Step 6/6  (completed)
║  EXP-001 EKS Pod Kill   ✅ done  74s   PASS
║  Monitor: ✅ Active  samples=20
╚══════════════════════════════════════════════════════════════╝
```

## Safety Principles

- **Mandatory stop conditions**: Every FIS experiment must bind a CloudWatch Alarm
- **Minimum blast radius**: Never exceed defined constraints
- **Progressive escalation**: Staging → Production, single fault → cascading
- **Reversible**: All experiments require a rollback plan
- **Human confirmation**: Production experiments require double confirmation
- **Monitoring-first**: 🔴 Unready monitoring blocks experiment start

## Execution Modes

| Mode | Description |
|------|-------------|
| Interactive | Pause for confirmation at each step (first run / production) |
| Semi-auto | Confirm at critical checkpoints (staging) |
| Dry-run | Walk through the flow without injecting faults |
| Game Day | Cross-team drill, see [references/gameday.md](references/gameday.md) |

## Example Scenarios

- [EC2 Instance Termination — ASG Recovery](examples/01-ec2-terminate.md)
- [RDS Aurora Failover — Database HA](examples/02-rds-failover.md)
- [EKS Pod Kill — Microservice Self-healing](examples/03-eks-pod-kill.md) (Chaos Mesh)
- [AZ Network Isolation — Multi-AZ Fault Tolerance](examples/04-az-network-disrupt.md)
- [Composite AZ Degradation — Multi-Action FIS Experiment](examples/05-composite-az-degradation.md) (FIS multi-action + `startAfter`)
- [Database Connection Exhaustion — Connection Pool Resilience](examples/06-database-connection-exhaustion.md) (SSM Automation orchestration)
- [Redis Connection Failure — Cache Layer Resilience](examples/07-redis-connection-failure.md) (Security Group manipulation)
- [SQS Queue Impairment — Message Queue Resilience](examples/08-sqs-queue-impairment.md) (Progressive resource policy denial)

## Directory Structure

```
chaos-engineering-on-aws/
├── SKILL.md                    # Agent skill definition (language router)
├── SKILL_EN.md / SKILL_ZH.md  # Full instructions (bilingual, ~97 lines each)
├── README.md / README_zh.md    # Documentation (bilingual)
├── MCP_SETUP_GUIDE.md / _zh.md # MCP server setup guide
├── references/                 # Progressive-disclosure reference docs (loaded on demand)
│   ├── workflow-guide.md / _zh.md  # Detailed 6-step workflow instructions
│   ├── fault-catalog.yaml      # Unified fault type registry: 54 actions (24 FIS + 14 CM + 12 FIS-SSM + 4 Scenario)
│   ├── scenario-library.md / _zh.md  # FIS Scenario Library JSON skeletons & requirements
│   ├── fis-template-library-index.md / _zh.md  # 27-scenario index from aws-samples/fis-template-library
│   ├── fis-templates/              # 8 embedded ready-to-deploy FIS templates
│   │   ├── database-connection-exhaustion/  # SSM Automation: dynamic EC2 load generator
│   │   ├── redis-connection-failure/        # SSM Automation: Security Group manipulation
│   │   ├── sqs-queue-impairment/           # SSM Automation: progressive policy denial
│   │   ├── cloudfront-impairment/          # SSM Automation: S3 origin deny policy
│   │   ├── aurora-global-failover/         # SSM Automation: cross-region switchover
│   │   ├── msk-broker-reboot/              # SSM Automation: MSK broker reboot
│   │   ├── elasticache-redis-primary-node-reboot/    # SSM Automation: primary node reboot
│   │   └── elasticache-redis-primary-node-failover/  # SSM Automation: TestFailover
│   ├── templates/              # Parameterized FIS multi-action templates ({{placeholder}} format)
│   │   ├── az-power-interruption.json       # AZ power interruption (official 8 sub-actions, prunable)
│   │   ├── cascade-db-to-app.json           # DB cascade fault (3 actions, serial with delay)
│   │   └── progressive-network-degradation.json  # Progressive degradation (6 actions, 3 waves)
│   ├── prerequisites-checklist.md / _zh.md  # Pre-flight checklist by architecture pattern
│   ├── emergency-procedures.md / _zh.md     # Emergency stop procedures (3-level escalation)
│   ├── fis-actions.md / _zh.md # FIS actions reference
│   ├── chaosmesh-crds.md / _zh.md  # Chaos Mesh CRD reference
│   ├── report-templates.md / _zh.md # Report generation templates
│   └── gameday.md / _zh.md     # Game Day exercise guide
├── examples/                   # Experiment scenario examples (01-08, EN/ZH pairs)
├── scripts/
│   ├── README.md               # Script usage guide (parameters, exit codes, examples)
│   ├── discover-dependencies.sh  # Step 2 Impact Target discovery across all EKS clusters
│   ├── experiment-runner.sh    # Experiment execution (FIS + Chaos Mesh, --one-shot for pod-kill)
│   ├── log-collector.sh        # Pod log collection + 5-category error classification (--app-map)
│   ├── monitor.sh              # CloudWatch metric collection (FIS mode + Chaos Mesh mode)
│   ├── update-dashboard.sh     # Auto-generate output/dashboard.md from state.json
│   ├── render-dashboard.sh     # Colored ASCII terminal dashboard (use with `watch -n 5 -c`)
│   ├── setup-prerequisites.sh  # Optional pre-flight setup
│   ├── custom-metrics-sample.conf  # Custom metrics configuration example
│   └── tests/                  # Offline tests (bash + jq, stubbed aws/kubectl)
└── validate-skill.sh          # Validation: static checks, offline script tests, EN/ZH parity, FIS ID check (280+ checks)
```

## Recent Changes

### v1.6.1 — 2026-11-09

**MCP configuration (all three skills: chaos-engineering-on-aws, aws-resilience-modeling, eks-resilience-checker)**
- Required server is now the AWS-managed **AWS MCP Server** (`aws-mcp`, via a pinned `mcp-proxy-for-aws`), replacing the superseded `awslabs.aws-api-mcp-server`; EKS uses the AWS-managed **Amazon EKS MCP Server** (`eks-mcp`); `cloudwatch-mcp-server` is optional.
- Removed `ALLOW_WRITE_OPERATIONS=true`: that variable never existed in `aws-api-mcp-server` (its switch is `READ_OPERATIONS_ONLY`, default `false`).
- Read-only skills enforce read-only through the IAM profile; the proxy's `--read-only` flag hides `aws___call_aws` / `aws___run_script` and must not be used for them.
- `MCP_SETUP_GUIDE.md` / `_zh.md` rewritten (Kiro, Claude Code, Cursor/VS Code, IAM, multi-account, troubleshooting); FIS role examples use the `AWSFaultInjectionSimulator*Access` managed policies; read-only policy uses the valid `elasticloadbalancing:` prefix instead of `elbv2:`.
- `validate-all-skills.sh` link check fixed: it mis-parsed links with anchors and never counted failures (pipe subshell).

### v1.6.0 — 2026-11-09

**Impact Target discovery (P0)**
- `scripts/discover-dependencies.sh` — New: resolves the real endpoints of the resources under test (Aurora/RDS cluster and member endpoints, ElastiCache node endpoints, MSK brokers, OpenSearch, EC2 IP/DNS) and scans every EKS cluster in the Region in parallel, each through an isolated kubeconfig, for workloads that reference them: env values, ConfigMaps via keyRef/envFrom/volumes/projected volumes, ExternalName Services and their callers, and (opt-in) Secret key names — never values. Anchored matching with near misses reported separately; credentials masked in evidence. Writes `checkpoints/step2-dependencies.json` and `monitoring/app-map.json`. Ported from the dependency discovery in [aws-samples/sample-fis-skills](https://github.com/aws-samples/sample-fis-skills) `app-service-log-analysis`.
- `scripts/log-collector.sh` — New `--app-map`: collects every verified/confirmed Impact Target across namespaces and clusters (Deployment, StatefulSet, DaemonSet, Job, bare Pod); each log line now carries `namespace` (and `cluster`).
- `scripts/log-collector.sh` — Fix: without `--services`, the last deployment of the namespace was silently dropped (kubectl jsonpath output has no trailing newline).
- `scripts/tests/` — New offline tests (bash + jq, stubbed aws/kubectl), run by `validate-skill.sh`.
- `references/workflow-guide.md` — Step 2.2 Impact Target discovery; Step 5 launches log-collector with `--app-map`; Step 6 data completeness lists unscanned clusters.

**Resource–action compatibility gate (P0)**
- `references/workflow-guide.md` — Step 2.1: `aws fis get-action` target type vs. the real resource fields (`Engine`, `DBClusterIdentifier`, `InstanceLifecycle`, …); mismatch blocks Step 3 and is recorded in `step2-assessment.json`.

**FIS correctness fixes (P0)** — checked against the official FIS actions reference and the four Scenario Library pages
- Non-existent action IDs replaced: `aws:ec2:disrupt-network-connectivity` → `aws:network:disrupt-connectivity`; `aws:elasticache:interrupt-cluster-az-power` → `aws:elasticache:replicationgroup-interrupt-az-power`; `aws:memorydb:interrupt-cluster-az-power` (MemoryDB only has `multi-region-cluster-pause-replication`); `aws:kinesis:add-put-record-throttle` → `aws:kinesis:stream-provisioned-throughput-exception` / `stream-expired-iterator-exception`; `aws:directconnect:disrupt-connectivity` → `aws:directconnect:virtual-interface-disconnect`.
- `references/scenario-library.md` / `_zh.md` — All four scenarios rewritten from the official Scenario Content JSON: sub-actions, per-target tags (the `IceQualified` tag value used before does not exist), permissions; AZ Application Slowdown and Cross-AZ Traffic Slowdown are pod/ECS/SSM latency and packet-loss scenarios, not NACL + Lambda. New: service-scoped sub-action pruning for AZ Power Interruption (never prunes the stop condition).
- `references/templates/az-power-interruption.json` — Aligned to the official 8 sub-actions/targets, one target per sub-action so any pair can be pruned; keeps an alarm stop condition.
- `references/fis-actions.md` / `_zh.md` — 20 missing official actions added.
- Lambda actions: `AWS_FIS_CONFIGURATION_LOCATION` is the ARN of an S3 configuration folder (e.g. `arn:aws:s3:::bucket/FisConfigs/`) plus `AWS_LAMBDA_EXEC_WRAPPER=/opt/aws-fis/bootstrap`, per the [official guide](https://docs.aws.amazon.com/fis/latest/userguide/use-lambda-actions.html). The v1.4.0 note saying "experiment ARN" was wrong.

**FIS Template Library sync to ee74d58 (P1)**
- `references/fis-template-library-index.md` / `_zh.md` — 19 → 27 scenarios (new: agentcore-strands-agent-faults, database-blocking-locks, database-io-exhaustion, ecs-fargate-az-evacuation, ecs-fargate-az-impairment, eks-automode-az-impairment, elasticache-az-power-interruption, msk-broker-reboot) and updated facts for existing entries.
- `references/fis-templates/` — 5 embedded templates resynced byte-for-byte with upstream fixes (SQS deny now scoped so cleanup can't be blocked, confused-deputy trust condition; DB connection exhaustion now cleans up on failure/cancel, IMDSv2); 3 new embedded templates: `msk-broker-reboot`, `elasticache-redis-primary-node-reboot`, `elasticache-redis-primary-node-failover` (upstream defects of the last one documented in its README).
- `references/fault-catalog.yaml` — New `fis_ssm` section (12 SSM-based faults); Scenario sub-actions/tags corrected; 42 → 54 entries.

**Chinese docs**
- `references/workflow-guide_zh.md` — Re-translated in full; it had lost INSUFFICIENT_DATA handling, the Verdict Decision Tree, section-by-section report writing and other guardrails present in English.
- `validate-skill.sh` — New EN/ZH structure parity check (headings, code blocks, tables) so this drift fails validation.

### v1.5.0 — 2026-04-16

**FIS Template Library Integration (P1)**
- `references/fis-template-library-index.md` / `_zh.md` — New: Full 19-scenario index from [aws-samples/fis-template-library](https://github.com/aws-samples/fis-template-library), organized by service category (Compute, Database, Cache, CDN, NoSQL, Messaging, Networking, SAP)
- `references/fis-templates/` — New: 5 embedded ready-to-deploy FIS templates with IAM policies, SSM Automation documents, and deployment READMEs:
  - `database-connection-exhaustion/` — Dynamic EC2 load generator pattern (SSM Automation)
  - `redis-connection-failure/` — Security Group manipulation pattern
  - `sqs-queue-impairment/` — Progressive resource policy denial (4 escalating rounds)
  - `cloudfront-impairment/` — S3 origin deny policy pattern
  - `aurora-global-failover/` — Cross-region switchover/failover
- `references/scenario-library.md` / `_zh.md` — Added External Template Library section linking to embedded templates and full index
- `references/workflow-guide.md` / `_zh.md` — Added SSM Automation Orchestrated Experiments section (3 patterns: Dynamic Resource Injection, Security Group Manipulation, Resource Policy Denial)

**New Examples (P2)**
- `examples/06-database-connection-exhaustion.md` / `_zh.md` — New: Database connection pool exhaustion experiment (SSM Automation orchestration)
- `examples/07-redis-connection-failure.md` / `_zh.md` — New: Redis connection failure experiment (Security Group manipulation)
- `examples/08-sqs-queue-impairment.md` / `_zh.md` — New: SQS queue progressive impairment experiment (resource policy denial)

**Hypothesis Enhancement (P2)**
- `examples/01-05` (all 10 files) — Added "What does this enable you to verify?" / "验证要点" checklists to all existing examples

**Skill Reference Updates**
- `SKILL_EN.md` / `SKILL_ZH.md` — Added fis-templates and fis-template-library-index references to Tool Selection section

### v1.4.0 — 2026-04-15

**Three-Layer State Management (P0)**
- `scripts/experiment-runner.sh` — `state.json` v2 schema with workflow tracking, experiments array, background PIDs, and `flock`-based concurrent write protection
- `scripts/update-dashboard.sh` — New: auto-generates `output/dashboard.md` from state.json (called by monitor.sh each cycle)
- `scripts/render-dashboard.sh` — New: colored ASCII terminal dashboard (`watch -n 5 -c bash scripts/render-dashboard.sh`)
- `references/workflow-guide.md` — Session interruption recovery procedure (check state.json → PIDs → FIS/CM status → resume)

**Monitor & Runner Improvements (P0)**
- `scripts/monitor.sh` — `EXPERIMENT_ID` now optional; omit for Chaos Mesh experiments (metrics-only mode with `DURATION` timeout)
- `scripts/monitor.sh` — Default `INTERVAL` changed from 30s to 15s for higher data density
- `scripts/experiment-runner.sh` — New `--one-shot` + `--pod-label` + `--deployment` flags for pod-kill experiments; completes on AllInjected=True + Pods Ready instead of waiting for timeout
- `scripts/experiment-runner.sh` — New `--state-exp-id` flag to auto-update state.json experiment status on all terminal states (completed/failed/timeout/aborted)

**Log Collector Improvements (P1)**
- `scripts/log-collector.sh` — `cleanup()` writes summary before killing child processes (prevents data loss on SIGTERM)
- `scripts/log-collector.sh` — Interruptible sleep (`sleep N & wait $!`) for immediate SIGTERM response
- `references/workflow-guide.md` — Marked log-collector launch as MANDATORY for all experiments (FIS and CM)

**Safety & Documentation (P1)**
- `scripts/monitor.sh` — `OUTPUT_DIR` variable properly initialized (was undefined, causing monitor crash)
- `references/fault-catalog.yaml` — `aws:fis:inject-api-throttle-error` limited to ec2/kinesis only (NOT dynamodb/s3/etc.)
- `references/fault-catalog.yaml` — Lambda FIS actions: `AWS_FIS_CONFIGURATION_LOCATION` format clarified (must be experiment ARN, not S3 path) — **superseded in v1.6.0: this was wrong; the official format is an S3 folder ARN**
- `references/fis-actions.md` — Added common mistake warning for Lambda env var format
- `references/workflow-guide.md` — Verdict Decision Tree: 4-level data completeness → verdict mapping (PASSED/FAILED, OBSERVED, BLOCKED)
- `references/report-templates.md` — Report Section 6.0.5: Data Completeness Check mandatory before verdict
- `SKILL_EN.md` / `SKILL_ZH.md` — Stop condition alarms must use `--treat-missing-data notBreaching`
- `scripts/update-dashboard.sh` / `scripts/render-dashboard.sh` — Temp files use PID (`$$`) for concurrent safety

### v1.3.0 — 2026-04-14

**Composite Experiment Support (P0)**
- `SKILL_EN.md` / `SKILL_ZH.md` — New §3.6: Composite Experiment Design (FIS multi-action templates with `startAfter` orchestration: parallel, sequential, timed delays)
- `SKILL_EN.md` / `SKILL_ZH.md` — New §3.7: Mixed-Backend Experiments (FIS + Chaos Mesh simultaneous injection with defined abort ordering)
- `examples/05-composite-az-degradation.md` / `_zh.md` — New: Complete composite AZ degradation example (EC2 stop + EBS pause + RDS failover, full FIS JSON)
- `references/fault-catalog.yaml` — Fixed `fis_scenarios` comment: clarified three creation paths (Console export, Content tab + API, direct JSON skeleton)

**Parameterized Templates (P1)**
- `references/templates/az-power-interruption.json` — New: AZ power interruption (EC2 + EBS + RDS + ElastiCache, 4 parallel actions)
- `references/templates/cascade-db-to-app.json` — New: DB-to-App cascade fault (RDS failover → 30s wait → network disruption, 3 serial actions)
- `references/templates/progressive-network-degradation.json` — New: Progressive network degradation (3 waves, 6 actions, includes Lambda delay)

**Robustness (P1)**
- `scripts/experiment-runner.sh` — Chaos Mesh polling now checks CR existence before querying status; gracefully exits with ABORTED state if CR is deleted

**Duration Override (P2)**
- `SKILL_EN.md` / `SKILL_ZH.md` — New: Duration Override section in Step 5 (jq for FIS templates, kubectl patch for Chaos Mesh)

### v1.2.0 — 2026-04-05

**Safety & Operations**
- `references/emergency-procedures.md` — New: 3-level emergency stop procedures covering FIS, Chaos Mesh, and nuclear CRD deletion option
- `references/fault-catalog.yaml` — Added `safe_first_run_params` to all 23 fault types (conservative parameters for first-run experiments; `pod_kill` defaults to 1 fixed pod instead of 50%)

**IAM & Permissions**
- `references/prerequisites-checklist.md` — Added 3-tier FIS IAM Policy templates (Tier 1: EC2 only, Tier 2: +RDS, Tier 3: Full) with Permission Boundary guidance

**Observability & Reliability**
- `scripts/monitor.sh` — Graceful warning (written to JSONL) when `metric-queries.json` is missing, instead of hard failure
- `SKILL_EN.md` / `SKILL_ZH.md` — Step 3 now requires Agent to generate `metric-queries.json`; Step 4 pre-flight checklist adds `metric-queries.json` existence check

**Documentation**
- `references/report-templates.md` — Step 6 report now includes "Cleanup Status" section with checkboxes for FIS templates, Chaos Mesh CRs, and temporary alarms
- `references/scenario-library.md` — All JSON skeletons stamped with "Last verified: 2026-04-05 against FIS API version 2024-05-01"
- `SKILL_EN.md` / `SKILL_ZH.md` — Added "Last sync: 2026-04-05" header
