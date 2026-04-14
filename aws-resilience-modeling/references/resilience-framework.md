# AWS Resilience Analysis Framework - Reference Index

This document serves as an index to the detailed resilience analysis reference materials. Each section is maintained as a separate file for efficient access.

## Reference Files

| # | File | When to Read | Description | Size |
|---|------|-------------|-------------|------|
| 1 | [analysis-tasks.md](analysis-tasks.md) | Executing any Task 1-8 | Detailed instructions for all 8 analysis tasks, including scoring dimensions, RMA cross-mapping, risk matrices | ~200 lines |
| 2 | [waf-reliability-pillar.md](waf-reliability-pillar.md) | Task 2, Task 3 DR assessment, cost estimation | AWS WAF Reliability Pillar, 4 DR strategies, Multi-AZ/Multi-Region, DR cost baselines | ~510 lines |
| 3 | [resilience-analysis-core.md](resilience-analysis-core.md) | Task 2 failure modes, Task 3 scoring, Task 8 postmortem | Error budget, SLI/SLO/SLA, 4 golden signals, alerting, postmortem culture | ~509 lines |
| 4 | [chaos-engineering-methodology.md](chaos-engineering-methodology.md) | Chaos Engineering test plan output | 4-step experiment process, AWS FIS templates, common scenarios | ~212 lines |
| 5 | [observability-standards.md](observability-standards.md) | Task 1 monitoring gaps, Task 3 observability assessment | OpenTelemetry, logs/metrics/traces, health models | ~392 lines |
| 6 | [cloud-design-patterns.md](cloud-design-patterns.md) | Task 2 design pattern evaluation, Task 6 mitigation | Bulkhead, circuit breaker, retry, queue-based load leveling, throttling | ~243 lines |
| 7 | [compliance-mapping.md](compliance-mapping.md) | When compliance requirements are in scope | SOC2, ISO 27001, NIST CSF mapping to analysis tasks | ~25 lines |
| 8 | [common-risks-reference.md](common-risks-reference.md) | Task 2, Task 5 risk identification | Common AWS resilience risks and patterns | ~305 lines |
| 9 | [assessment-output-spec.md](assessment-output-spec.md) | Generating Chaos Engineering Ready Data output | 8-section structured output format for chaos-engineering-on-aws consumption | ~471 lines |
| 10 | [report-generation.md](report-generation.md) | Final report generation step | Report workflow, Python template code, quality checklist | ~367 lines |
| 11 | [HTML-TEMPLATE-USAGE.md](HTML-TEMPLATE-USAGE.md) | Generating HTML interactive report | HTML template usage, data population, Chart.js configuration | ~487 lines |
| 12 | [MCP_SETUP_GUIDE.md](MCP_SETUP_GUIDE.md) | MCP server installation and configuration | Detailed MCP server setup instructions, region/profile configuration | ~506 lines |

## How to Use

Load only the specific reference file relevant to your current analysis task. Do not load all files at once.

**Quick lookup by task**:
- **Task 1** (Architecture Mapping) → `observability-standards.md` for monitoring gaps
- **Task 2** (Failure Modes) → `resilience-analysis-core.md`, `common-risks-reference.md`, `cloud-design-patterns.md`
- **Task 3** (Resilience Rating) → `analysis-tasks.md` for scoring dimensions and RMA cross-mapping
- **Task 4** (Business Impact) → `waf-reliability-pillar.md` for RTO/RPO and DR strategies
- **Task 5** (Risk Prioritization) → `analysis-tasks.md` for risk scoring matrix
- **Task 6** (Mitigation) → `cloud-design-patterns.md`, `waf-reliability-pillar.md`
- **Task 7** (Roadmap) → `analysis-tasks.md` for phased plan structure
- **Task 8** (Continuous Improvement) → `resilience-analysis-core.md` for SLI/SLO and postmortem
- **Chaos Engineering Output** → `assessment-output-spec.md`
- **Compliance** → `compliance-mapping.md`
- **Report Generation** → `report-generation.md`, `HTML-TEMPLATE-USAGE.md`
