# AWS Resilience Analysis Framework - Reference Index

This document serves as an index to the detailed resilience analysis reference materials. Each section is maintained as a separate file for efficient access.

## Reference Files

| # | File | Description | Key Topics |
|---|------|-------------|------------|
| 1 | [waf-reliability-pillar.md](waf-reliability-pillar.md) | AWS Well-Architected Framework - Reliability Pillar (2025) | 5 design principles, 4 DR strategies, Multi-AZ/Multi-Region, change management |
| 2 | [resilience-analysis-core.md](resilience-analysis-core.md) | AWS Resilience Analysis Core Principles | Error budget, SLI/SLO/SLA, 4 golden signals, alerting, postmortem culture, troubleshooting |
| 3 | [chaos-engineering-methodology.md](chaos-engineering-methodology.md) | Chaos Engineering Methodology | 4-step experiment process, AWS FIS templates, common scenarios |
| 4 | [observability-standards.md](observability-standards.md) | Modern Observability Standards | OpenTelemetry, logs/metrics/traces, health models |
| 5 | [cloud-design-patterns.md](cloud-design-patterns.md) | Cloud Design Patterns (Resilience-Related) | Bulkhead, circuit breaker, retry, queue-based load leveling, throttling |

## How to Use

Load only the specific reference file relevant to your current analysis task. For example:
- Analyzing failure modes → `resilience-analysis-core.md`
- Reviewing DR strategies → `waf-reliability-pillar.md`
- Designing chaos experiments → `chaos-engineering-methodology.md`
- Assessing monitoring gaps → `observability-standards.md`
- Evaluating design patterns → `cloud-design-patterns.md`
