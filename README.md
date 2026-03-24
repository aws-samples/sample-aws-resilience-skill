[**中文**](README_zh.md) | English

# AWS Resilience Skills

A collection of AI-powered Agent Skills for comprehensive AWS system resilience — from maturity assessment through risk analysis to chaos engineering validation. Built for [Claude Code](https://docs.anthropic.com/en/docs/agents-and-tools/claude-code/overview), [Kiro](https://kiro.dev/), and any AI coding assistant that supports the skill/prompt framework.

## How the Three Skills Fit Together

These skills map to the [AWS Resilience Lifecycle Framework](https://docs.aws.amazon.com/prescriptive-guidance/latest/resilience-lifecycle-framework/overview.html), forming a complete resilience improvement pipeline:

```
┌─────────────────────────────────────────────────────────────────────────────────────┐
│                        AWS Resilience Lifecycle Framework                            │
│                                                                                     │
│  Stage 1: Set Objectives    Stage 2: Design & Implement    Stage 3: Evaluate & Test │
│  ┌───────────────────┐      ┌───────────────────────┐      ┌─────────────────────┐  │
│  │  aws-rma-          │      │  aws-resilience-       │      │  chaos-engineering-  │  │
│  │  assessment        │─────►│  assessment            │─────►│  on-aws              │  │
│  │                    │      │                        │      │                      │  │
│  │  "Where are we?"   │      │  "What could go wrong?"│      │  "Does it actually   │  │
│  │                    │      │                        │      │   break?"             │  │
│  └───────────────────┘      └───────────────────────┘      └──────────┬───────────┘  │
│                                        ▲                              │              │
│                                        └──────── Feedback Loop ───────┘              │
└─────────────────────────────────────────────────────────────────────────────────────┘
```

| # | Skill | Lifecycle Stage | Input | Output |
|---|-------|----------------|-------|--------|
| 1 | **aws-rma-assessment** | Stage 1: Set Objectives | Guided Q&A with stakeholders | Resilience maturity score + improvement roadmap |
| 2 | **aws-resilience-assessment** | Stage 2: Design & Implement | AWS account access or architecture docs | Risk inventory + resource scan + mitigation strategies |
| 3 | **chaos-engineering-on-aws** | Stage 3: Evaluate & Test | Assessment report from Skill #2 | Experiment results + validation report + updated resilience score |

### Recommended Workflow

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

### 2. AWS Resilience Assessment (`aws-resilience-assessment`)

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
- Markdown + HTML dual-format reports with MTTR analysis
- Game Day mode for team exercises

**Invoke:** Mention "chaos engineering", "fault injection", or "混沌工程" in conversation.

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

Any AI coding assistant that supports custom skills: [Claude Code](https://docs.anthropic.com/en/docs/agents-and-tools/claude-code/overview), [Kiro](https://kiro.dev/), [Cursor](https://cursor.sh/), or similar.

### 2. Setup

```bash
git clone https://github.com/aws-samples/sample-gcr-resilience-skill.git
```

Copy the skill directories into your project's skills folder, or reference them directly.

### 3. AWS Access (Recommended)

- AWS account with read-only access (assessment) or experiment permissions (chaos engineering)
- AWS CLI configured with appropriate credentials
- Optional: MCP servers for enhanced automation (see `MCP_SETUP_GUIDE.md` in each skill folder)

## Project Structure

```
.
├── aws-rma-assessment/                # Resilience Maturity Assessment
│   ├── SKILL.md                       # Skill definition
│   ├── MCP_SETUP_GUIDE.md             # MCP server configuration
│   ├── resilience-framework.md        # AWS best practices reference
│   ├── html-report-template.html      # Interactive HTML report template
│   └── generate-html-report.py        # HTML report generation script
│
├── aws-resilience-assessment/         # Technical Resilience Assessment
│   ├── SKILL.md                       # Skill definition
│   ├── MCP_SETUP_GUIDE.md             # MCP server configuration
│   ├── resilience-framework.md        # AWS best practices reference
│   ├── html-report-template.html      # Interactive HTML report template
│   └── generate-html-report.py        # HTML report generation script
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
│   │   └── monitor.sh                 # CloudWatch metric collection script
│   └── doc/                           # Design documents (PRD, decisions)
│
├── README.md                          # This file
└── README_zh.md                       # Chinese version
```

## Security

See [CONTRIBUTING](CONTRIBUTING.md#security-issue-notifications) for more information.

## License

This library is licensed under the MIT-0 License. See the [LICENSE](LICENSE) file.
