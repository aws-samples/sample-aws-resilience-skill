# Scoring Guide — Formulas, Levels, and Domain Ratings

## Overall Maturity Score

**Formula**: (sum of all question scores / total questions / 3) × 100

**Rating Criteria**:
- 90-100%: Excellent
- 75-89%: Good
- 60-74%: Fair
- 45-59%: Needs Improvement
- <45%: Critical

## Domain Maturity Scores

- Calculate averages for each of the 10 topic domains
- Identify the 3 lowest-scoring domains as priority improvement areas

## P0 Critical Risk Summary (must appear in Executive Summary)

- Calculate P0 questions average score separately: (sum of P0 scores / P0 count / 3) × 100
- If any P0 question is scored Level 1, add a **"Critical Risk Warning"** banner in the Executive Summary
- List all P0 questions at Level 1 in a dedicated table with domain, question, current level, and recommended action
- This ensures critical risks are never masked by high scores in lower-priority areas

## Critical Risk Identification

- All P0 questions scored at Level 1 → High Risk
- All P1 questions scored at Level 1 → Medium Risk
- Sorted by business impact

## Strength Area Identification

- All questions scored at Level 3
- Can be shared as organizational best practices

---

## Maturity Level Definitions

### Level 1 - Ad-hoc
- Processes are informal or non-existent
- Primarily reliant on manual operations
- Lacking documentation and automation
- High risk, low predictability

### Level 2 - Defined
- Basic processes and documentation exist
- Partial automation
- Regularly executed but may be inconsistent
- Medium risk, partially predictable

### Level 3 - Managed/Optimized
- Fully documented and automated processes
- Regularly tested and validated through drills and reviews
- Continuous improvement mechanisms with measurable outcomes
- Low risk, high predictability
- Aligned with AWS best practices
- Note: Level 3 is assessed by **process maturity** (documented, automated, tested, continuously improved), NOT by specific numeric thresholds (e.g., a specific RTO value). Numeric targets vary by business context.

---

## Domain-Specific Scoring Guide

| Domain | Level 1 | Level 2 | Level 3 |
|--------|---------|---------|---------|
| **Recovery Objectives** | Not defined or documented | Defined but not regularly validated | Defined, tested, and continuously monitored |
| **Disaster Recovery** | No DR plan or untested | DR plan exists, tested periodically | Automated DR with verified failover, regularly tested (quarterly+) |
| **Monitoring & Observability** | Basic monitoring, no unified logs | Centralized logs, basic metrics and alerts | Complete observability (logs, metrics, traces), proactive alerts |
| **High Availability** | Single-AZ, no redundancy | Multi-AZ deployment, basic health checks | Multi-AZ with auto failover, fault isolation boundaries verified |
| **Change Management** | Manual deployment, no rollback strategy | Partial automation, basic rollback | Fully automated CI/CD, blue-green/canary deployment |
| **Incident Management** | No incident process, ad-hoc response | Documented runbooks, basic escalation | Automated incident detection, structured response, blameless postmortems |
| **Operations Reviews** | No regular reviews | Periodic reviews (quarterly), basic metrics | Regular reviews with action tracking, data-driven decision making |
| **Chaos Engineering & Game Days** | No fault injection or drills | Occasional drills in non-production | Regular chaos experiments in production, automated steady-state verification |
| **Organizational Learning** | No resilience culture or training | Basic training, informal knowledge sharing | Resilience community of practice, continuous training, knowledge base |
| **Resilience Analysis** | No dependency docs or failure modeling | Basic dependency mapping, some failure scenarios | Comprehensive dependency docs, failure scenario modeling, capacity planning |

---

## Cross-Skill Scoring Alignment

When used alongside `aws-resilience-modeling`:

| RMA Level | Approximate Modeling Stars | Interpretation |
|-----------|---------------------------|----------------|
| Level 1 (Ad-hoc) | 1-2 stars | Not implemented or ad-hoc |
| Level 2 (Defined) | 2.5-3.5 stars | Standardized, partially automated |
| Level 3 (Managed) | 4-5 stars | Optimized, continuously improving |

> Note: This is an approximate mapping, not an exact equivalence. RMA assesses organizational maturity (people, process, tools); Modeling assesses technical implementation depth per component.

### Relationship with AWS Resilience Hub

| Aspect | RMA Assessment (this Skill) | AWS Resilience Hub |
|--------|---------------------------|-------------------|
| **Focus** | Organizational/process maturity (people, process, tools) | Technical configuration compliance |
| **Scope** | 10 domains × 52 questions covering culture, governance, testing | Per-application RTO/RPO policy, resource configuration |
| **Output** | Maturity levels (1-5) + improvement roadmap | Compliance status + recommended actions |
| **When to use** | First-time resilience strategy, maturity benchmarking | Ongoing automated compliance monitoring |

**Recommended approach**: Start with RMA Assessment to understand organizational gaps, then use Resilience Hub for continuous automated monitoring of the technical improvements you implement.
