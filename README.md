[**中文**](README_zh.md) | English

# AWS Resilience Skills

A collection of AI-powered Agent Skills for comprehensive AWS system resilience — from maturity assessment through risk analysis to chaos engineering validation. Built for [Claude Code](https://docs.anthropic.com/en/docs/agents-and-tools/claude-code/overview), [Kiro](https://kiro.dev/), [OpenClaw](https://openclaw.dev/), and any AI coding assistant that supports the skill/prompt framework.

## How the Four Skills Fit Together

These skills map to the [AWS Resilience Lifecycle Framework](https://docs.aws.amazon.com/prescriptive-guidance/latest/resilience-lifecycle-framework/overview.html), forming a complete resilience improvement pipeline:

```
┌──────────────────────────────────────────────────────────────────────────────────────────────────┐
│                              AWS Resilience Lifecycle Framework                                    │
│                                                                                                   │
│  Stage 1: Set Objectives    Stage 2: Design & Implement    Stage 3: Evaluate & Test               │
│  ┌───────────────────┐      ┌───────────────────────┐      ┌─────────────────────┐               │
│  │  aws-rma-          │      │  resilience-            │      │  chaos-engineering-  │               │
│  │  assessment        │─────►│  modeling               │─────►│  on-aws              │               │
│  │                    │      │                        │      │                      │               │
│  │  "Where are we?"   │      │  "What could go wrong?"│      │  "Does it actually   │               │
│  │                    │      │                        │      │   break?"             │               │
│  └───────────────────┘      └───────────────────────┘      └──────────┬───────────┘               │
│                                        ▲                              │                            │
│                                        └──────── Feedback Loop ───────┘                            │
│                                                                                                   │
│                                        Stage 3: Evaluate & Test                                   │
│                                        ┌─────────────────────┐                                    │
│                                        │  eks-resilience-      │                                    │
│                                        │  checker              │──── feeds into chaos-engineering   │
│                                        │                      │                                    │
│                                        │  "Is EKS resilient?" │                                    │
│                                        └─────────────────────┘                                    │
└──────────────────────────────────────────────────────────────────────────────────────────────────┘
```

| # | Skill | Lifecycle Stage | Input | Output |
|---|-------|----------------|-------|--------|
| 1 | **aws-rma-assessment** | Stage 1: Set Objectives | Guided Q&A with stakeholders | Resilience maturity score + improvement roadmap |
| 2 | **aws-resilience-modeling** | Stage 2: Design & Implement | AWS account access or architecture docs | Risk inventory + resource scan + mitigation strategies |
| 3 | **chaos-engineering-on-aws** | Stage 3: Evaluate & Test | Assessment report from Skill #2 | Experiment results + validation report + updated resilience score |
| 4 | **eks-resilience-checker** | Stage 3: Evaluate & Test | EKS cluster kubectl access | 26-check compliance report + experiment recommendations |

### Recommended Workflow

0. **Run EKS Resilience Check** (optional) — Establish K8s-level baseline and identify cluster-specific risks
1. **Start with RMA** — Understand your organization's resilience maturity level and set improvement objectives
2. **Run Resilience Assessment** — Deep-dive into your AWS infrastructure to identify specific risks and failure modes
3. **Execute Chaos Engineering** — Validate findings through controlled fault injection experiments on real infrastructure
4. **Close the Loop** — Feed experiment results back into the assessment to update risk scores and track improvement

## Skills Overview

### 1. RMA Assessment Assistant (`aws-rma-assessment`)

**What it does:** Interactive Resilience Maturity Assessment through guided Q&A, based on the [AWS Resilience Maturity Assessment](https://docs.aws.amazon.com/prescriptive-guidance/latest/resilience-lifecycle-framework/stage-1.html) methodology.

**Best for:** Initial engagement — understanding where your organization stands on the resilience maturity spectrum.

**Key features:**
- Structured questionnaire covering resilience dimensions
- Maturity scoring aligned with AWS Well-Architected Framework
- Improvement roadmap with prioritized recommendations
- Interactive HTML report with visualizations

**Invoke:** Mention "RMA assessment" or "resilience maturity" in conversation.

### 2. Resilience Modeling (`aws-resilience-modeling`)

**What it does:** Comprehensive technical resilience analysis of AWS infrastructure — maps components, identifies failure modes, rates risks, and generates actionable mitigation strategies.

**Best for:** Deep technical analysis — finding specific vulnerabilities in your AWS architecture.

**Key features:**
- Automated AWS resource scanning via CLI/MCP
- Failure mode identification and classification (SPOF, latency, load, misconfiguration, shared fate)
- 9-dimension resilience scoring (5-star rating)
- Risk-prioritized inventory with mitigation strategies
- Structured output consumed by the Chaos Engineering skill

**Invoke:** Mention "AWS resilience assessment" or "韧性评估" in conversation.

### 3. Chaos Engineering on AWS (`chaos-engineering-on-aws`)

**What it does:** Executes the complete chaos engineering lifecycle — from experiment design through controlled fault injection to results analysis — using AWS FIS and optional Chaos Mesh.

**Best for:** Validation through action — proving (or disproving) that your system handles failures as expected.

**Key features:**
- Six-step workflow: Target → Resources → Hypothesis → Pre-flight → Execute → Report
- Dual engine: **AWS FIS** for infrastructure faults (node termination, AZ isolation, DB failover) + **Chaos Mesh** for Pod/container faults
- Hybrid monitoring: background metric collection + agent-driven FIS status polling
- State persistence across long-running experiments
- Dual-channel observability: CloudWatch metrics (`monitor.sh`) + application logs (`log-collector.sh`) running in parallel
- 5-category error classification in logs (timeout, connection, 5xx, oom, other)
- Post-experiment log analysis mode
- Application log analysis section in reports (error timeline, cross-service correlation, recovery detection)
- Markdown + HTML dual-format reports with MTTR analysis
- Game Day mode for team exercises

**Invoke:** Mention "chaos engineering", "fault injection", or "混沌工程" in conversation.

### 4. EKS Resilience Checker (`eks-resilience-checker`)

**What it does:** Evaluates Amazon EKS cluster resilience against 26 best practice checks covering application workloads, control plane, and data plane — then outputs structured recommendations that feed directly into the Chaos Engineering skill.

**Best for:** EKS-specific baseline — identifying Kubernetes-level resilience gaps before running chaos experiments.

**Key features:**
- 26 resilience checks across 3 categories: Application (A1-A14), Control Plane (C1-C5), Data Plane (D1-D7)
- Automated `assess.sh` script — one command, 4 output files (JSON + Markdown + HTML + remediation script)
- Compliance scoring with critical failure count
- Experiment recommendations mapping failed checks to chaos experiments (feeds into `chaos-engineering-on-aws`)
- Portable: auto-detects cluster name, region, and Kubernetes version

**Invoke:** Mention "EKS resilience check", "cluster assessment", or "集群韧性评估" in conversation.

## Fault Injection Tool Selection

Based on E2E testing, the chaos engineering skill enforces a clear division:

| Layer | Tool | Examples |
|-------|------|---------|
| **Infrastructure** (nodes, network, databases) | AWS FIS | `eks:terminate-nodegroup-instances`, `network:disrupt-connectivity`, `rds:failover-db-cluster` |
| **Pod/Container** (application-level) | Chaos Mesh | `PodChaos`, `NetworkChaos`, `HTTPChaos`, `StressChaos` |

> ⚠️ FIS `aws:eks:pod-*` actions are **not recommended** for Pod-level faults — they require additional K8s ServiceAccount/RBAC setup and have slow initialization (>2 min). Use Chaos Mesh instead.

## Features

- Based on **AWS Well-Architected Framework** Reliability Pillar (2025)
- Integrates **AWS Resilience Analysis Framework** (Error Budgets, SLO/SLI/SLA)
- Full **Chaos Engineering** lifecycle (AWS FIS + Chaos Mesh)
- **AWS Observability Best Practices** (CloudWatch, X-Ray, Distributed Tracing)
- **Cloud Design Patterns** (Circuit Breaker, Bulkhead, Retry)
- **Interactive HTML reports** with Chart.js visualizations and Mermaid architecture diagrams

## Prerequisites

### 1. AI Coding Assistant

Any AI coding assistant that supports custom skills: [Claude Code](https://docs.anthropic.com/en/docs/agents-and-tools/claude-code/overview), [Kiro](https://kiro.dev/), [Cursor](https://cursor.sh/), [OpenClaw](https://openclaw.dev/), or similar.

### 2. Installation

**Option A: npx skills (Recommended)**
```bash
# Install a single skill
npx skills add aws-samples/sample-aws-resilience-skill --skill eks-resilience-checker

# Install all 4 resilience skills
npx skills add aws-samples/sample-aws-resilience-skill --skill '*'
```

**Option B: Git clone**
```bash
git clone https://github.com/aws-samples/sample-aws-resilience-skill.git
```
Copy the skill directories into your project's `.kiro/skills/`, `.claude/skills/`, or equivalent folder.

**Option C: Direct download**
Download individual skill folders from the [GitHub repository](https://github.com/aws-samples/sample-aws-resilience-skill).

### 3. AWS Access (Recommended)

- AWS account with read-only access (assessment) or experiment permissions (chaos engineering)
- AWS CLI configured with appropriate credentials
- Optional: MCP servers for enhanced automation (see `MCP_SETUP_GUIDE.md` in each skill folder)

## Project Structure

```
.
├── aws-rma-assessment/                # Resilience Maturity Assessment
│   ├── SKILL.md                       # Skill definition
│   ├── README.md                      # Skill documentation
│   └── references/                    # Reference documents
│       ├── questions-data.json        # 80 assessment questions (JSON)
│       ├── questions-priority.md      # Priority classification (P0-P3)
│       ├── question-groups.md         # Batch Q&A grouping strategy
│       └── report-template.md         # Report generation template
│
├── aws-resilience-modeling/               # Technical Resilience Assessment
│   ├── SKILL.md                       # Skill definition
│   ├── README.md                      # Skill documentation
│   ├── references/                    # Reference documents
│   │   ├── resilience-framework.md    # AWS best practices reference
│   │   ├── common-risks-reference.md  # 50+ common AWS risk patterns
│   │   ├── report-generation.md       # Report generation guide
│   │   ├── MCP_SETUP_GUIDE.md        # MCP server configuration
│   │   └── ...
│   ├── scripts/
│   │   └── generate-html-report.py    # HTML report generation script
│   └── assets/
│       ├── html-report-template.html  # Interactive HTML report template
│       └── example-report-template.md # Markdown report example
│
├── eks-resilience-checker/             # EKS Resilience Best Practice Checks
│   ├── SKILL.md                       # Skill definition
│   ├── SKILL_EN.md                    # English skill instructions
│   ├── SKILL_ZH.md                    # Chinese skill instructions
│   ├── README.md                      # Skill documentation
│   ├── scripts/
│   │   └── assess.sh                  # Automated 26-check assessment script
│   ├── references/                    # Reference documents
│   │   ├── EKS-Resiliency-Checkpoints.md  # 26 check definitions
│   │   ├── check-commands.md          # Exact kubectl/aws commands per check
│   │   └── remediation-templates.md   # Fix templates with YAML examples
│   └── examples/
│       └── petsite-assessment.md      # Example assessment report
│
├── chaos-engineering-on-aws/          # Chaos Engineering Experiments
│   ├── SKILL.md                       # Skill definition (6-step workflow)
│   ├── MCP_SETUP_GUIDE.md             # MCP server configuration
│   ├── references/                    # Progressive-disclosure reference docs
│   │   ├── fis-actions.md             # AWS FIS actions reference
│   │   ├── chaosmesh-crds.md          # Chaos Mesh CRD reference
│   │   ├── report-templates.md        # Report templates (MD + HTML)
│   │   └── gameday.md                 # Game Day execution guide
│   ├── examples/                      # Experiment scenario examples
│   │   ├── 01-ec2-terminate.md        # EC2 instance termination
│   │   ├── 02-rds-failover.md         # RDS Aurora failover
│   │   ├── 03-eks-pod-kill.md         # EKS Pod kill (Chaos Mesh)
│   │   └── 04-az-network-disrupt.md   # AZ network isolation
│   ├── scripts/
│   │   ├── monitor.sh                 # CloudWatch metric collection script
│   │   ├── log-collector.sh           # Pod log collection + error classification
│   │   └── setup-prerequisites.sh     # FIS role, Chaos Mesh, resource tagging setup
│   └── doc/                           # Design documents (PRD, decisions)
│
├── README.md                          # This file
└── README_zh.md                       # Chinese version
```

## Security

See [CONTRIBUTING](CONTRIBUTING.md#security-issue-notifications) for more information.

## License

This library is licensed under the MIT-0 License. See the [LICENSE](LICENSE) file.
