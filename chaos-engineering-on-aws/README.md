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

### Required

| Server | Package | Purpose |
|--------|---------|---------|
| aws-api-mcp-server | `awslabs.aws-api-mcp-server` | FIS experiment create/run/stop, resource validation |
| cloudwatch-mcp-server | `awslabs.cloudwatch-mcp-server` | Metrics, alarms, stop conditions |

### Optional

| Server | Package | When |
|--------|---------|------|
| eks-mcp-server | `awslabs.eks-mcp-server` | EKS-based architectures |
| chaosmesh-mcp | [RadiumGu/Chaosmesh-MCP](https://github.com/RadiumGu/Chaosmesh-MCP) | Cluster has Chaos Mesh installed |

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

> No MCP? The skill falls back to AWS CLI (`aws fis`, `aws cloudwatch`, `kubectl`).

### Chaos Mesh MCP: EKS Authentication Methods

When using the optional Chaos Mesh MCP server, there are two ways to authenticate with your EKS cluster:

#### Method 1: Static ServiceAccount Token (Recommended)

Run the setup script once to create RBAC permissions and generate a self-contained kubeconfig with a long-lived ServiceAccount token. **No AWS CLI or IAM credentials required at runtime.**

```bash
# One-time setup: create RBAC + generate kubeconfig (expires in 1 year)
cd /path/to/Chaosmesh-MCP
./setup-eks-permissions.sh

# Start Chaos Mesh MCP server with the generated kubeconfig
python server.py --kubeconfig ./chaos-mesh-mcp-kubeconfig
```

MCP config:
```json
{
  "mcpServers": {
    "chaosmesh-mcp": {
      "command": "python",
      "args": ["/path/to/Chaosmesh-MCP/server.py", "--kubeconfig", "/path/to/chaos-mesh-mcp-kubeconfig"]
    }
  }
}
```

✅ Portable — no AWS dependency at runtime  
✅ Least-privilege permissions (Chaos Mesh only)  
⚠️ Token expires after 1 year — re-run the script to renew

#### Method 2: Admin kubeconfig (exec-based Auth)

If a cluster admin provides a kubeconfig (typically from `aws eks update-kubeconfig`), the server can use it directly. It calls `aws eks get-token` on each request to obtain a temporary token.

```bash
# Start with an admin-provided kubeconfig
python server.py --kubeconfig /path/to/admin-kubeconfig

# Or via environment variable
export KUBECONFIG=/path/to/admin-kubeconfig
python server.py
```

**Requirements:** `aws` CLI installed + valid AWS credentials (IAM role / `~/.aws/credentials`) + IAM identity mapped in the EKS `aws-auth` ConfigMap.

✅ No extra setup — reuse existing admin credentials  
⚠️ Depends on AWS CLI + IAM at runtime  
⚠️ Admin-level permissions (broader than necessary)

> **Recommendation:** Use Method 1 for production. Use Method 2 for quick testing when an admin kubeconfig is already available.

Full setup guide: [MCP_SETUP_GUIDE.md](MCP_SETUP_GUIDE.md)

## Six-Step Workflow

| Step | Name | Output |
|------|------|--------|
| 1 | Define Experiment Scope | `output/step1-scope.json` |
| 2 | Select Target Resources | `output/step2-assessment.json` |
| 3 | Design Hypothesis & Experiment | `output/step3-experiment.json` |
| 4 | Pre-flight Validation | `output/step4-validation.json` |
| 5 | Run Controlled Experiment | `output/step5-experiment.json` + `step5-metrics.jsonl` |
| 6 | Analysis & Report | `output/step6-report.md` + `step6-report.html` |

## Fault Injection Tools

> 📋 Full structured catalog: [references/fault-catalog.yaml](references/fault-catalog.yaml)

```
AZ/Region-level Compound Faults  →  FIS Scenario Library
  ├── AZ Power Interruption (EC2 + RDS + EBS + ElastiCache)
  ├── AZ Application Slowdown (network latency injection)
  ├── Cross-AZ Traffic Slowdown (inter-AZ packet loss)
  └── Cross-Region Connectivity (TGW + route table disruption)
  ⚠️ Scenarios are not complete templates — create via Console then export, or copy Content tab and add missing params via API

AWS Managed Services / Infrastructure  →  AWS FIS (single action)
  ├── Node level:    eks:terminate-nodegroup-instances
  ├── Instance:      ec2:terminate/stop/reboot
  ├── Database:      rds:failover, rds:reboot
  ├── Network:       network:disrupt-connectivity
  └── Serverless:    lambda:invocation-add-delay/error

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

## Directory Structure

```
chaos-engineering-on-aws/
├── SKILL.md                    # Agent skill definition (language router)
├── SKILL_EN.md / SKILL_ZH.md  # Full instructions (EN/ZH)
├── README.md                   # This file (English)
├── README_zh.md                # Chinese version
├── MCP_SETUP_GUIDE.md          # MCP server setup
├── examples/                   # Experiment scenario examples
├── references/
│   ├── fault-catalog.yaml      # Unified fault type registry (ChaosMesh + FIS + Scenarios)
│   ├── scenario-library.md     # FIS Scenario Library templates & requirements
│   ├── prerequisites-checklist.md  # Pre-flight checklist by architecture pattern
│   ├── emergency-procedures.md # Emergency stop procedures (3-level escalation)
│   ├── fis-actions.md          # FIS actions reference
│   ├── chaosmesh-crds.md       # Chaos Mesh CRD reference
│   ├── report-templates.md     # Report generation templates
│   └── gameday.md              # Game Day exercise guide
├── scripts/
│   ├── monitor.sh              # Monitoring script template
│   ├── log-collector.sh        # Pod log collection + error classification
│   └── setup-prerequisites.sh  # Optional pre-flight setup script
└── e2e-tests/                  # End-to-end tests
```

## Recent Changes

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
