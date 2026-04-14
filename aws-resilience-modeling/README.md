**English** | [中文](README_zh.md)

---

# AWS System Resilience Analysis Skill

A comprehensive AWS system resilience assessment and risk analysis skill, incorporating the latest 2025 industry best practices.

## Installation

**Option A: npx skills (Recommended)**
```bash
# Install this skill
npx skills add aws-samples/sample-aws-resilience-skill --skill aws-resilience-modeling

# Install all 4 resilience skills
npx skills add aws-samples/sample-aws-resilience-skill --skill '*'
```

**Option B: Git clone**
```bash
git clone https://github.com/aws-samples/sample-aws-resilience-skill.git
```

## Features

- ✅ Based on the **AWS Well-Architected Framework** Reliability Pillar
- ✅ Integrates the **AWS Resilience Analysis Framework** (error budgets, SLO/SLI)
- ✅ Includes **Chaos Engineering** methodology (AWS FIS)
- ✅ Adopts **AWS Observability Best Practices** (CloudWatch, X-Ray, distributed tracing)
- ✅ Applies **Cloud Design Patterns** (Circuit Breaker, Bulkhead, Retry)
- ✅ Built-in **AWS Common Service Risk Reference Library** (50+ risk points covering storage/database/EKS/EC2/networking)

## Usage

### Method 1: Direct Invocation

```bash
/aws-resilience-modeling
```

Claude will first ask for your environment information and business context, then begin a comprehensive resilience analysis.

### Method 2: Automatic Trigger

The skill activates automatically when you mention the following keywords in conversation:
- "AWS resilience analysis"
- "system risk assessment"
- "AWS resilience assessment"

Example:
```
User: I want to perform a resilience analysis on our AWS production environment
Claude: [auto-loads aws-resilience-modeling skill]
```

## Prerequisites

Before starting the analysis, prepare the following information:

### MCP Server Configuration
For detailed MCP server setup instructions (required for automated AWS environment scanning), see [references/MCP_SETUP_GUIDE.md](references/MCP_SETUP_GUIDE.md).

### 1. Environment Information
- AWS account ID and region
- Access credentials (read-only access recommended)
- Existing architecture documentation (if available)

### 2. Business Context
- List of critical business processes
- Current RTO/RPO targets
- Existing SLA/SLO (if available)
- Compliance requirements (e.g., SOC2, HIPAA, PCI DSS)

### 3. Analysis Scope
- Applications and services to be analyzed
- Whether multi-account/multi-region is included
- Budget and time constraints

## Output

Upon completion of the analysis, you will receive:

### Main Report
1. **Executive Summary** (2 pages)
   - Key findings (Top 5 risks)
   - Resilience maturity score
   - Priority improvement recommendations

2. **System Architecture Visualization**
   - Architecture overview diagram (Mermaid)
   - Dependency diagram
   - Data flow diagram
   - Network topology diagram

3. **Risk Inventory** (table)
   - Sorted by priority
   - Includes risk scores, impact, and mitigation recommendations

4. **Detailed Risk Analysis**
   - In-depth analysis of each high-priority risk
   - Failure scenarios
   - Business impact
   - Improvement recommendations (architecture, configuration, monitoring)

5. **Business Impact Analysis**
   - Critical business function mapping
   - RTO/RPO compliance analysis

6. **Mitigation Strategy Recommendations**
   - Specific architecture improvements
   - Configuration optimizations (with parameters and commands)
   - Monitoring and alerting configuration
   - AWS service recommendations

7. **Implementation Roadmap**
   - Gantt chart
   - Detailed task breakdown
   - Resource requirements and budget

8. **Continuous Improvement Plan**
   - SLI/SLO definitions
   - Postmortem process
   - Chaos engineering plan

### Additional Files

**references/common-risks-reference.md** - AWS Common Service Risk Reference Manual ([中文](references/common-risks-reference_zh.md))
- Covers five categories: storage (EBS/S3/EFS/FSx), databases, containers (EKS), compute (EC2), and networking
- 50+ common risk points, each with root cause and improvement recommendations
- Assessment checklist organized by service type

**references/assessment-output-spec.md** - Chaos Engineering Input Specification ([中文](references/assessment-output-spec_zh.md))
- Defines the structured input format required by the `chaos-engineering-on-aws` skill
- Contains 8 sections including AWS resource inventory, risk experiment-readiness flags, and monitoring readiness
- Fill-in examples for different architecture patterns (EKS/Serverless/EC2/multi-region)

> All reference files are available in both English and Chinese. Chinese versions use the `_zh.md` suffix (e.g., `resilience-framework_zh.md`).

## Directory Structure

```
aws-resilience-modeling/
├── SKILL.md                                    # Language router (loads EN/ZH)
├── SKILL_EN.md                                 # Skill instructions (English)
├── SKILL_ZH.md                                 # Skill instructions (Chinese)
├── README.md                                   # This file (English)
├── README_zh.md                                # Readme (Chinese)
├── references/
│   ├── resilience-framework.md                 # Resilience analysis reference framework (English)
│   ├── resilience-framework_zh.md              # Resilience analysis reference framework (Chinese)
│   ├── common-risks-reference.md               # AWS common service risk manual (English)
│   ├── common-risks-reference_zh.md            # AWS common service risk manual (Chinese)
│   ├── assessment-output-spec.md               # Chaos engineering input specification (English)
│   ├── assessment-output-spec_zh.md            # Chaos engineering input specification (Chinese)
│   ├── report-generation.md                    # Report generation process and code (English)
│   ├── report-generation_zh.md                 # Report generation process and code (Chinese)
│   ├── HTML-TEMPLATE-USAGE.md                  # HTML template usage guide (English)
│   ├── HTML-TEMPLATE-USAGE_zh.md               # HTML template usage guide (Chinese)
│   ├── MCP_SETUP_GUIDE.md                      # MCP server configuration guide (English)
│   └── MCP_SETUP_GUIDE_zh.md                   # MCP server configuration guide (Chinese)
├── scripts/
│   └── generate-html-report.py                 # Python report generator
└── assets/
    ├── html-report-template.html               # HTML interactive report template
    ├── example-report-template.md              # Markdown report example (English)
    └── example-report-template_zh.md           # Markdown report example (Chinese)
```

## Analysis Framework

### Failure Mode Classification

| Category | Description |
|----------|-------------|
| Single Point of Failure (SPOF) | Critical components lacking redundancy |
| Excessive Latency | Performance bottlenecks and latency issues |
| Excessive Load | Capacity limits and traffic spikes |
| Misconfiguration | Non-compliance with best practices |
| Shared Fate | Tight coupling and lack of isolation |

### Resilience Assessment Dimensions

Uses a **5-star rating system** (1 star = inadequate, 5 stars = excellent) to assess:

- Redundancy design
- AZ fault tolerance
- Timeout and retry strategy
- Circuit breaker mechanism
- Auto-scaling capability
- Configuration safeguards
- Fault isolation
- Backup and recovery mechanism
- AWS best practices compliance

### Risk Priority Scoring

```
Risk Score = (Probability × Business Impact × Detection Difficulty) / Remediation Complexity
```

## Example Scenarios

### Scenario 1: E-Commerce Platform
```
Environment:
- Multi-AZ RDS (PostgreSQL)
- ECS Fargate application
- CloudFront + S3 static assets
- ElastiCache Redis

Key Findings:
- RDS single-region (no Aurora Global Database)
- Missing Auto Scaling policies
- No Circuit Breaker configured
- Insufficient monitoring coverage

Recommendations:
- Migrate to Aurora Global Database
- Implement Target Tracking Auto Scaling
- Integrate AWS X-Ray distributed tracing
- Establish quarterly DR drills
```

### Scenario 2: Financial API
```
Environment:
- API Gateway + Lambda
- DynamoDB Global Tables
- Aurora Serverless
- Route 53 health checks

Key Findings:
- Lambda without Reserved Concurrency
- Missing API throttling policies
- SLO/SLI not defined
- No chaos engineering practices

Recommendations:
- Configure Lambda Reserved Concurrency
- Implement API Gateway Usage Plans
- Define 99.99% availability SLO
- Establish weekly chaos experiments
```

## Disaster Recovery Strategy Selection

| Strategy | RTO | RPO | Cost | Applicable Scenarios |
|----------|-----|-----|------|----------------------|
| Backup & Restore | Hours–Days | Hours–Days | $ | Non-critical systems |
| Pilot Light | 10 min–Hours | Minutes | $$ | Important systems |
| Warm Standby | Minutes | Seconds–Minutes | $$$ | Critical business |
| Multi-Site Active-Active | Seconds–Minutes | Seconds | $$$$ | Mission-critical |

## Reference Resources

### AWS Official Documentation
- [AWS Resilience Analysis Framework](https://docs.aws.amazon.com/prescriptive-guidance/latest/resilience-analysis-framework/)
- [AWS Well-Architected - Reliability Pillar](https://docs.aws.amazon.com/wellarchitected/latest/reliability-pillar/)
- [AWS Fault Injection Simulator](https://docs.aws.amazon.com/fis/latest/userguide/)
- [AWS Resilience Hub](https://docs.aws.amazon.com/resilience-hub/latest/userguide/)

### External Resources
- [AWS Observability Best Practices](https://aws-observability.github.io/observability-best-practices/)
- [Principles of Chaos Engineering](https://principlesofchaos.org/)
- [Chaos Engineering on AWS](https://docs.aws.amazon.com/prescriptive-guidance/latest/chaos-engineering-on-aws/)

## Advanced Features

### Error Budget Management

Based on AWS resilience best practices, calculate and track error budgets:

```
Error Budget = (1 - SLO) × Time Period

Example:
SLO = 99.9% (monthly)
Error Budget = 43.2 minutes/month
```

### Chaos Engineering Experiments

Use AWS FIS for fault injection:

- EC2 instance termination
- Network latency/packet loss
- RDS failover
- AZ unavailability simulation
- CPU/memory stress tests

### Three Pillars of Observability

- **Logs**: CloudWatch Logs + structured logging
- **Metrics**: CloudWatch Metrics + key monitoring indicators
- **Traces**: AWS X-Ray + distributed tracing

## FAQ

### Q: How long does the analysis take?
A: Depends on environment complexity:
- Simple environment (single region, < 10 services): 1–2 hours
- Medium environment (multi-AZ, 10–50 services): 3–5 hours
- Complex environment (multi-region, > 50 services): 1–2 days

### Q: Is AWS account access required?
A: Recommended but not mandatory:
- **With access**: Resources can be scanned automatically for more accurate analysis
- **Without access**: Analysis is based on provided architecture documentation

### Q: Will the analysis incur AWS charges?
A: The analysis itself incurs no charges, but implementing recommendations may include:
- AWS Resilience Hub (free)
- AWS FIS chaos experiments (billed per minute)
- Additional AWS services (e.g., Aurora Global Database)

### Q: How do I implement the recommendations?
A: The analysis report includes:
- Specific architecture improvement diagrams
- AWS CLI commands
- CloudFormation/Terraform code snippets
- Phased implementation roadmap

### Q: Is multi-cloud supported?
A: Currently focused on AWS environments, providing professional resilience assessments based on the AWS Well-Architected Framework.

## Changelog

### v1.1.0 (2026-03-14)
- ✅ Added `common-risks-reference.md` — AWS Common Service Risk Reference Manual
- ✅ Integrated 50+ common risk points (storage/database/EKS/EC2/networking)
- ✅ Added assessment checklist organized by service type
- ✅ SKILL.md failure mode identification task references the risk reference
- ✅ Risk classification refined to align with actual AWS services

### v1.0.0 (2025-02-17)
- ✅ Initial release
- ✅ Integrated AWS Well-Architected Framework (2025)
- ✅ Integrated AWS Resilience Analysis Framework
- ✅ Integrated chaos engineering methodology
- ✅ Integrated AWS observability best practices
- ✅ Includes detailed resilience-framework.md reference

## Feedback and Contributions

For questions or suggestions, please provide feedback by:
- Raising them directly in conversation
- Updating your local skill files

## License

This skill is written based on the AWS Well-Architected Framework and chaos engineering best practices, for learning and use.
