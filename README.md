[**中文**](README_zh.md) | English

# AWS Resilience Assessment Skills for Claude Code

A collection of [Claude Code](https://docs.anthropic.com/en/docs/claude-code) custom skills for comprehensive AWS system resilience analysis and risk assessment, built on 2025 industry best practices.

## Skills

This project includes two complementary skills:

### 1. AWS Resilience Assessment (`aws-resilience-assessment`)

A full-scope AWS infrastructure resilience analysis skill. It maps system components, identifies failure modes, performs risk-prioritized assessments, and generates detailed reports with actionable mitigation strategies.

**Invoke:** `/aws-resilience-assessment` or mention keywords like "AWS resilience assessment" in conversation.

### 2. RMA Assessment Assistant (`aws-rma-assessment`)

An interactive Reliability, Maintainability, and Availability (RMA) assessment skill. It evaluates application resilience maturity through guided Q&A based on the AWS Well-Architected Framework, and generates assessment reports with improvement roadmaps.

**Invoke:** `/rma-assessment-assistant` or mention keywords like "RMA assessment" in conversation.

## Features

- Based on **AWS Well-Architected Framework** Reliability Pillar (2025)
- Integrates **AWS Resilience Analysis Framework** (Error Budgets, SLO/SLI/SLA)
- Incorporates **Chaos Engineering** methodology (AWS FIS)
- Applies **AWS Observability Best Practices** (CloudWatch, X-Ray, Distributed Tracing)
- Utilizes **Cloud Design Patterns** (Circuit Breaker, Bulkhead, Retry)
- Generates **interactive HTML reports** with Chart.js visualizations and Mermaid architecture diagrams

## Analysis Framework

### Failure Mode Classification

| Category | Description |
|----------|-------------|
| Single Point of Failure (SPOF) | Critical components lacking redundancy |
| Excessive Latency | Performance bottlenecks and latency issues |
| Excessive Load | Capacity limits and traffic spikes |
| Misconfiguration | Deviations from best practices |
| Shared Fate | Tight coupling and lack of isolation |

### Resilience Dimensions (5-Star Rating)

- Redundancy Design
- AZ Fault Tolerance
- Timeout & Retry Strategies
- Circuit Breaker Mechanisms
- Auto Scaling Capability
- Configuration Protection
- Fault Isolation
- Backup & Recovery
- AWS Best Practice Compliance

### Risk Prioritization

```
Risk Score = (Probability x Impact x Detection Difficulty) / Remediation Complexity
```

## Output

Each assessment generates:

1. **Executive Summary** - Top risks, resilience maturity score, priority recommendations
2. **Architecture Visualizations** - Mermaid diagrams (architecture overview, dependency graphs, data flow, network topology)
3. **Risk Inventory** - Prioritized table with scores, impact, and mitigation recommendations
4. **Detailed Risk Analysis** - Deep dive into each high-priority risk with failure scenarios and business impact
5. **Business Impact Analysis** - Critical function mapping, RTO/RPO compliance analysis
6. **Mitigation Strategies** - Architecture improvements, configuration optimization (with CLI commands), monitoring/alerting setup
7. **Implementation Roadmap** - Gantt chart, task breakdown (WBS), resource requirements, budget estimates
8. **Continuous Improvement Plan** - SLI/SLO definitions, post-mortem processes, chaos engineering plans
9. **Chaos Engineering Test Plan** (optional) - AWS FIS experiment templates targeting top 10 risks

## Prerequisites

### 1. Claude Code

Install [Claude Code](https://docs.anthropic.com/en/docs/claude-code) CLI.

### 2. Setup

Clone this repository and add the skills to your Claude Code project:

```bash
git clone https://github.com/aws-samples/sample-gcr-resilience-skill.git
```

Copy the skill directories into your project's `.claude/skills/` folder, or reference them directly.

### 3. AWS Access (Recommended)

- AWS account with read-only access for automated resource scanning
- AWS CLI configured with appropriate credentials
- Optional: MCP servers for enhanced automation (see `MCP_SETUP_GUIDE.md` in each skill folder)

## Project Structure

```
.
├── aws-resilience-assessment/        # Full resilience analysis skill
│   ├── SKILL.md                      # Skill definition
│   ├── README.md                     # Detailed usage guide
│   ├── resilience-framework.md       # AWS best practices reference (2025)
│   ├── MCP_SETUP_GUIDE.md            # MCP server configuration
│   ├── html-report-template.html     # Interactive HTML report template
│   ├── HTML-TEMPLATE-USAGE.md        # HTML report guide
│   ├── example-report-template.md    # Example Markdown report
│   └── generate-html-report.py       # HTML report generation script
├── aws-rma-assessment/               # RMA assessment skill
│   ├── SKILL.md                      # Skill definition
│   ├── README.md                     # Detailed usage guide
│   ├── resilience-framework.md       # AWS best practices reference (2025)
│   ├── MCP_SETUP_GUIDE.md            # MCP server configuration
│   ├── html-report-template.html     # Interactive HTML report template
│   ├── HTML-TEMPLATE-USAGE.md        # HTML report guide
│   ├── example-report-template.md    # Example Markdown report
│   └── generate-html-report.py       # HTML report generation script
└── README.md
```

## Security

See [CONTRIBUTING](CONTRIBUTING.md#security-issue-notifications) for more information.

## License

This library is licensed under the MIT-0 License. See the [LICENSE](LICENSE) file.
