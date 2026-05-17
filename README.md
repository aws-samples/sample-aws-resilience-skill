[**中文**](README_zh.md) | English

# AWS Resilience Skills

A collection of AI-powered Agent Skills for comprehensive AWS system resilience — from maturity assessment through risk analysis to chaos engineering validation. Built for [Claude Code](https://docs.anthropic.com/en/docs/agents-and-tools/claude-code/overview), [Kiro](https://kiro.dev/), [OpenClaw](https://openclaw.dev/), and any AI coding assistant that supports the skill/prompt framework.

## How the Skills Fit Together

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
| 5 | **aws-well-architected-review** | Cross-cutting | AWS account with read-only access | 6-pillar WA review report + risk portfolio + improvement roadmap |
| 6 | **cjis-reviewer** | Compliance Readiness | AWS account with read-only access | CJIS gap assessment + remediation roadmap |
| 7 | **ferpa-reviewer** | Compliance Readiness | AWS account with read-only access | FERPA gap assessment + remediation roadmap |

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
- **19-scenario FIS Template Library** index with 5 embedded ready-to-deploy templates (database connection exhaustion, Redis connection failure, SQS queue impairment, CloudFront impairment, Aurora global failover)
- 3 advanced injection patterns: SSM Automation orchestration, Security Group manipulation, Resource Policy denial

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

### 5. Well-Architected Review (`aws-well-architected-review`)

**What it does:** Automated AWS Well-Architected Framework Review across all 6 pillars using 49 read-only programmatic checks. Runs in autopilot mode — confirm credentials, then fully automated assessment with Markdown + HTML reports.

**Best for:** Comprehensive architecture review — identifying security, reliability, performance, cost, and sustainability gaps across your entire AWS environment.

**Key features:**
- 49 programmatic checks across 6 WAF pillars (Security-First order)
- Strict read-only: only Describe/Get/List API calls, blocks write-capable credentials
- HRI/MRI/LRI risk classification with priority matrix
- 4-phase improvement roadmap (immediate → long-term)
- Dual report output: Markdown + HTML with pillar scorecards
- Optional sync to AWS WA Tool console

**Invoke:** Mention "WA review", "Well-Architected assessment", "architecture review", or "架构评审" in conversation.

### 6. CJIS Reviewer (`cjis-reviewer`)

**What it does:** Assesses AWS environments against the FBI CJIS Security Policy (v5.9.5), identifies gaps across 13 policy areas, and produces a prioritized remediation roadmap.

**Best for:** Law enforcement and criminal justice workloads — preparing for triennial CJSA/FBI audits or evaluating new CJI deployments on AWS.

**Key features:**
- 4-phase automated assessment (Bootstrap → Discover → Analyze → Report)
- Programmatic checks for 6 technical policy areas (PA 4, 5, 6, 7, 8, 10)
- Audit-heat prioritized scanning — most-cited findings surface first
- Organizational questionnaire for non-technical PAs (1, 2, 3, 9, 11, 12, 13)
- Quick Scan (~10 min), Standard (~25 min), and Full (~40 min) modes
- Markdown + HTML dual-format reports

**Invoke:** Mention "CJIS assessment", "CJIS readiness", "criminal justice on AWS", or any CJIS policy area (PA 1-13).

> ⚠️ **Assessment aid only** — does not certify or guarantee CJIS compliance. A qualified CSO or auditor must validate findings.

### 7. FERPA Reviewer (`ferpa-reviewer`)

**What it does:** Assesses AWS environments against FERPA (Family Educational Rights and Privacy Act) and common state student-privacy laws, identifies gaps, and produces a remediation roadmap.

**Best for:** Education technology workloads — K-12 and higher-ed institutions evaluating AWS environments that handle student education records.

**Key features:**
- 4-phase automated assessment (Bootstrap → Discover → Analyze → Report)
- Programmatic checks across FERPA control domains (disclosure controls, auditing, access control, authentication, encryption, retention/destruction)
- State law addenda coverage (COPPA, state-specific student privacy laws)
- Strict read-only credential boundary enforcement
- Markdown + HTML dual-format reports

**Invoke:** Mention "FERPA assessment", "FERPA readiness", "student data on AWS", or "education records compliance".

> ⚠️ **Assessment aid only** — does not certify or guarantee FERPA compliance. Qualified legal counsel and institutional compliance officers must validate findings.

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
├── aws-rma-assessment/                # Skill 1: Resilience Maturity Assessment
│   ├── SKILL.md / SKILL_EN.md / SKILL_ZH.md  # Skill definition (bilingual)
│   ├── README.md / README_zh.md       # Skill documentation
│   ├── references/                    # Reference documents (loaded on demand)
│   │   ├── questions-index.json       # Question index — load first
│   │   ├── questions-group-{1-10}.json # 82 questions split by domain (load per group)
│   │   ├── questions-priority.md      # Priority classification (P0-P3)
│   │   ├── question-groups.md         # Batch Q&A grouping strategy
│   │   ├── assessment-workflow.md     # Step-by-step workflow details
│   │   ├── auto-analysis-rules.md     # Auto-inference & confidence rules
│   │   ├── scoring-guide.md           # Scoring formulas & domain ratings
│   │   └── report-template.md         # Report generation template
│   ├── scripts/
│   │   └── merge-questions.py         # Question data merge utility
│   └── assets/
│       ├── html-report-template.html  # Interactive HTML report template
│       └── example-report-snippet.md  # Example report output
│
├── aws-resilience-modeling/           # Skill 2: Technical Resilience Assessment
│   ├── SKILL.md / SKILL_EN.md / SKILL_ZH.md  # Skill definition (bilingual)
│   ├── README.md / README_zh.md       # Skill documentation
│   ├── references/                    # Reference documents (loaded on demand)
│   │   ├── analysis-tasks.md          # 8 analysis task details
│   │   ├── resilience-framework.md    # Framework index & references map
│   │   ├── resilience-analysis-core.md # 9-dimension scoring methodology
│   │   ├── waf-reliability-pillar.md  # WAF Reliability Pillar + DR cost baselines
│   │   ├── common-risks-reference.md  # 50+ common AWS risk patterns
│   │   ├── assessment-output-spec.md  # Chaos skill bridge: 8-section output spec
│   │   ├── compliance-mapping.md      # SOC2/ISO/NIST framework mapping
│   │   ├── report-generation.md       # Report generation guide
│   │   ├── MCP_SETUP_GUIDE.md        # MCP server configuration
│   │   └── ...                        # (EN/ZH pairs for each file)
│   ├── scripts/
│   │   └── generate-html-report.py    # HTML report generation script
│   └── assets/
│       ├── html-report-template.html  # Interactive HTML report template
│       └── example-report-template.md # Markdown report example
│
├── eks-resilience-checker/            # Skill 3: EKS Resilience Best Practice Checks
│   ├── SKILL.md / SKILL_EN.md / SKILL_ZH.md  # Skill definition (bilingual)
│   ├── README.md / README_zh.md       # Skill documentation
│   ├── references/                    # Reference documents (loaded on demand)
│   │   ├── EKS-Resiliency-Checkpoints.md  # 26 check descriptions & rationale
│   │   ├── check-commands.md          # Exact kubectl/aws commands per check
│   │   ├── eks-resiliency-checks-mcp.md   # MCP-based check execution
│   │   ├── remediation-templates.md   # Fix command templates with YAML examples
│   │   ├── fail-to-experiment-mapping.md  # FAIL → chaos experiment mapping
│   │   └── eks-auth-setup.md          # EKS authentication setup guide
│   ├── scripts/
│   │   └── assess.sh                  # Automated 26-check assessment script
│   └── examples/
│       └── petsite-assessment.md      # Example assessment report
│
├── chaos-engineering-on-aws/          # Skill 4: Chaos Engineering Experiments
│   ├── SKILL.md / SKILL_EN.md / SKILL_ZH.md  # Skill definition (bilingual)
│   ├── MCP_SETUP_GUIDE.md             # MCP server configuration
│   ├── references/                    # Progressive-disclosure reference docs
│   │   ├── workflow-guide.md          # Detailed 6-step workflow instructions
│   │   ├── fault-catalog.yaml         # Unified fault type catalog (3-tier)
│   │   ├── fis-actions.md             # AWS FIS actions reference
│   │   ├── chaosmesh-crds.md          # Chaos Mesh CRD reference
│   │   ├── scenario-library.md        # FIS Scenario Library templates
│   │   ├── fis-template-library-index.md  # 19-scenario index from aws-samples/fis-template-library
│   │   ├── fis-templates/             # 5 embedded ready-to-deploy FIS templates (DB conn, Redis, SQS, CF, Aurora Global)
│   │   ├── templates/                 # Parameterized FIS multi-action templates
│   │   ├── report-templates.md        # Report templates (MD + HTML)
│   │   ├── emergency-procedures.md    # Emergency rollback procedures
│   │   └── gameday.md                 # Game Day execution guide
│   ├── examples/                      # Experiment scenario examples (01-08)
│   ├── scripts/
│   │   ├── experiment-runner.sh       # FIS/ChaosMesh experiment executor
│   │   ├── monitor.sh                 # CloudWatch metric collection
│   │   ├── log-collector.sh           # Pod log collection + error classification
│   │   └── setup-prerequisites.sh     # FIS role, Chaos Mesh, resource tagging
│   └── validate-skill.sh             # Static validation (105 checks)
│
├── quickstart/                        # Quick start guide with sample app
│   ├── README.md / README_zh.md
│   ├── sample-app/                    # Sample K8s deployments for testing
│   └── expected-output/               # Reference assessment output
│
├── cjis-reviewer/                     # Skill 6: CJIS Readiness Reviewer
│   ├── SKILL.md                       # Skill definition
│   ├── references/                    # Reference documents (loaded on demand)
│   │   ├── aws-service-mapping.md     # CJIS requirement → AWS service matrix
│   │   ├── credential-boundary.md     # Read-only IAM gate logic
│   │   ├── policy-areas.md            # Deep-dive on all 13 CJIS policy areas
│   │   ├── programmatic-checks/       # Per-PA automated check definitions
│   │   ├── readiness-checklist.md     # Full readiness checklist by PA
│   │   ├── report-template.md         # Fixed report structure
│   │   ├── severity-classification.md # Audit-aligned severity levels
│   │   └── workflow-overview.md       # 4-phase flow details
│   └── scripts/
│       └── generate-html-report.py    # HTML report renderer
│
├── ferpa-reviewer/                    # Skill 7: FERPA Readiness Reviewer
│   ├── README.md                      # Skill documentation
│   ├── SKILL.md                       # Skill definition
│   ├── references/                    # Reference documents (loaded on demand)
│   │   ├── aws-service-mapping.md     # FERPA requirement → AWS service matrix
│   │   ├── control-domains.md         # FERPA control domain definitions
│   │   ├── credential-boundary.md     # Read-only IAM gate logic
│   │   ├── programmatic-checks/       # Per-domain automated check definitions
│   │   ├── readiness-checklist.md     # Full readiness checklist
│   │   ├── report-template.md         # Fixed report structure
│   │   ├── severity-classification.md # Severity levels
│   │   ├── state-law-addenda.md       # State-specific student privacy laws
│   │   └── workflow-overview.md       # 4-phase flow details
│   └── scripts/
│       └── generate-html-report.py    # HTML report renderer
│
├── .kiro/skills/                      # Kiro skill registration (auto-synced)
├── README.md                          # This file
└── README_zh.md                       # Chinese version
```

## Security

See [CONTRIBUTING](CONTRIBUTING.md#security-issue-notifications) for more information.

## License

This library is licensed under the MIT-0 License. See the [LICENSE](LICENSE) file.
