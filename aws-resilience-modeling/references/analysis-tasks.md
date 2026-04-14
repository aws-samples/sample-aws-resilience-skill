# Analysis Tasks — Detailed Instructions

## Task 1: System Component Mapping and Dependency Analysis

**Tools Used**: Read-only API calls via MCP servers (`aws-api-mcp-server`) if available, Mermaid diagrams. Do not use Bash to execute any `aws` CLI commands to access AWS resources.

**Output**:
1. **System Architecture Overview** (Mermaid, showing Region/AZ/component hierarchy)
2. **Component Dependency Diagram** (marking synchronous/asynchronous dependencies, strong/weak dependencies, critical paths)
3. **Data Flow Diagram** (request paths, data flows, integration points)
4. **Network Topology Diagram** (VPC, subnets, security groups, route tables, NAT gateways, VPN/Direct Connect)

**Multi-Account Considerations** (if the architecture spans multiple AWS accounts):
- AWS Organizations SCP (Service Control Policy) impact on resilience
- Cross-account resource sharing and DR strategy (e.g., shared VPC, cross-account backup vaults)
- Centralized vs. decentralized backup and monitoring strategy
- Cross-account IAM trust relationships and failover permissions

## Task 2: Failure Mode Identification and Classification (Based on AWS Resilience Analysis Framework)

**Reference Resources**:
- AWS Prescriptive Guidance - Resilience Analysis Framework
- See [resilience-framework.md](resilience-framework.md) for the index of all reference files. Load only the specific sub-file relevant to your current task:
  - [waf-reliability-pillar.md](waf-reliability-pillar.md) — DR strategies, Multi-AZ/Multi-Region
  - [resilience-analysis-core.md](resilience-analysis-core.md) — Error budget, SLI/SLO, golden signals, postmortem
  - [chaos-engineering-methodology.md](chaos-engineering-methodology.md) — Experiment process, FIS templates
  - [observability-standards.md](observability-standards.md) — OpenTelemetry, logs/metrics/traces
  - [cloud-design-patterns.md](cloud-design-patterns.md) — Bulkhead, circuit breaker, retry

**Identify the following failure mode categories**:

| Failure Category | Description | Inspection Points |
|-----------------|-------------|-------------------|
| **Single Point of Failure (SPOF)** | Critical components lacking redundancy | Single-AZ deployment, single-instance database, no failover configured |
| **Excessive Latency** | Performance bottlenecks and latency issues | Network latency, database queries, API timeouts |
| **Excessive Load** | Capacity limits and traffic spikes | Auto Scaling configuration, service quotas, traffic peaks |
| **Misconfiguration** | Non-compliance with best practices | Security groups, IAM policies, backup policies |
| **Shared Fate** | Tight coupling and lack of isolation | Cross-service dependencies, regional dependencies, quota sharing |

**For each failure mode provide**: Detailed technical description, current configuration issues, involved AWS services and resource ARNs, trigger conditions and scenarios, business impact assessment.

**Risk Classification**: Infrastructure / Middleware & Database / Container Platform / Network / Data / Security & Compliance.

## Task 3: Resilience Assessment (5-Star Rating System)

Rate each critical component (1 star = inadequate, 5 stars = excellent):

**Assessment Dimensions**:

| Dimension | Assessment Question | Rating Criteria |
|-----------|-------------------|-----------------|
| **Redundancy Design** | Does the component have sufficient redundancy? | 1: Single point / 2: Same-AZ redundancy / 3: Multi-AZ manual failover / 4: Multi-AZ auto failover + cross-region backup / 5: Multi-region active-active |
| **AZ Fault Tolerance** | Can it withstand a single AZ failure? | 1: Single AZ / 2: Multi-AZ without auto failover / 3: Multi-AZ with auto failover / 4: Multi-AZ + periodic DR drills / 5: Multi-AZ + multi-region failover tested |
| **Timeout & Retry** | Are there appropriate timeout and retry strategies? | 1: Not configured / 2: Basic fixed timeouts / 3: Configurable timeouts + simple retry / 4: Exponential backoff + jitter / 5: Exponential backoff + circuit breaker + bulkhead |
| **Circuit Breaker** | Is there a mechanism to prevent cascading failures? | 1: None / 2: Basic health checks / 3: Circuit breaker on critical paths / 4: Circuit breaker + graceful degradation / 5: Full circuit breaker + degradation + load shedding |
| **Auto Scaling** | Can it handle load increases? | 1: Fixed capacity / 2: Manual scaling / 3: Target tracking Auto Scaling / 4: Predictive + reactive Auto Scaling / 5: Multi-dimensional Auto Scaling + capacity reservations |
| **Configuration Safeguards** | Are there measures to prevent misconfiguration? | 1: Manual / 2: Documented procedures / 3: IaC templates / 4: IaC + automated validation + drift detection / 5: IaC + policy-as-code + automated rollback |
| **Fault Isolation** | Are fault isolation boundaries clearly defined? | 1: Monolith / 2: Basic service separation / 3: Service-level isolation / 4: Cell-based architecture / 5: Cell architecture + bulkhead + shuffle sharding |
| **Backup & Recovery** | Is there a data backup and recovery mechanism? | 1: No backup / 2: Manual backups / 3: Automated backups + tested restore / 4: Cross-region backup + periodic DR testing / 5: Cross-region + automated recovery testing + PITR |
| **Best Practices** | Does it comply with Well-Architected? | 1: Multiple violations / 2: Partial compliance / 3: Mostly compliant + known gaps / 4: Fully compliant + optimization in progress / 5: Fully compliant + continuous improvement |

#### Mapping: Modeling 9 Dimensions ↔ RMA 10 Domains

If the user has also completed an RMA Assessment (aws-rma-assessment skill), use this mapping to cross-reference results:

| Modeling Dimension | RMA Domain(s) | Mapping Notes |
|-------------------|---------------|---------------|
| **Redundancy Design** | D2: Design for Multi-Location (Q7-Q9) | Modeling rates per-component; RMA rates organizational approach |
| **AZ Fault Tolerance** | D2: Design for Multi-Location (Q7-Q9), D10: Disaster Recovery (Q46-Q52) | Modeling focuses on technical AZ config; RMA includes DR governance |
| **Timeout & Retry** | D3: Design Interactions (Q10-Q13) | Direct mapping — both assess timeout/retry/backoff strategies |
| **Circuit Breaker** | D3: Design Interactions (Q10-Q13), D8: Fault Isolation (Q36-Q39) | Modeling covers circuit breaker specifically; RMA is broader (interactions + isolation) |
| **Auto Scaling** | D1: Design Your Workload (Q1-Q6) | Modeling rates scaling capability; RMA rates overall workload design maturity |
| **Configuration Safeguards** | D4: Design Distributed Systems (Q14-Q17), D5: Change Management (Q18-Q22) | Modeling focuses on IaC/validation; RMA adds change management process |
| **Fault Isolation** | D8: Fault Isolation (Q36-Q39) | Direct mapping |
| **Backup & Recovery** | D10: Disaster Recovery (Q46-Q52) | Direct mapping |
| **Best Practices** | All Domains (aggregate) | Modeling rates WAF compliance; RMA provides granular domain-level maturity |

**Score Conversion Guide** (approximate):

| Modeling Star Rating | Approximate RMA Level | Interpretation |
|---------------------|----------------------|----------------|
| ⭐ (1 star) | Level 0-1 | Not implemented or ad-hoc |
| ⭐⭐ (2 stars) | Level 1-2 | Basic implementation, manual processes |
| ⭐⭐⭐ (3 stars) | Level 2-3 | Standardized, partially automated |
| ⭐⭐⭐⭐ (4 stars) | Level 3-4 | Well-automated, regularly tested |
| ⭐⭐⭐⭐⭐ (5 stars) | Level 4-5 | Optimized, continuously improving |

> ⚠️ This mapping is approximate. Modeling scores reflect technical implementation depth for specific components; RMA levels reflect organizational maturity across people, process, and tools.

## Task 4: Business Impact Analysis

1. **Identify Critical Business Processes** (user registration/login, order processing, payment transactions, data analytics, etc.)
2. **Assess Component Failure Impact** (component -> failure scenario -> affected business functions -> impact severity -> user impact -> current/target RTO)
3. **RTO/RPO Compliance Analysis** (can the current architecture meet business objectives, gap analysis, priority improvement areas)

## Task 5: Risk Prioritization

**Risk Scoring Matrix**: Risk Score = (Probability x Business Impact x Detection Difficulty) / Remediation Complexity

| Risk ID | Failure Mode | Probability (1-5) | Impact (1-5) | Detection Difficulty (1-5) | Remediation Complexity (1-5) | Risk Score | Priority |
|---------|-------------|-------------------|--------------|---------------------------|-----------------------------|-----------|---------|
| R-001 | RDS Single AZ | 3 | 5 | 2 | 2 | 15 | High |
| R-002 | Missing Auto Scaling | 4 | 4 | 1 | 3 | 5.3 | Medium |

**Risk Score Severity Thresholds**:

| Severity | Score Range | Action Required |
|----------|-----------|-----------------|
| **Critical** | >= 20 | Immediate remediation required |
| **High** | 10 - 19 | Remediation within current sprint |
| **Medium** | 4 - 9 | Plan remediation in next quarter |
| **Low** | < 4 | Monitor and address as capacity allows |

Also perform **Cascading Effect Analysis**: Identify correlations between risks, assess multi-point failure scenarios, worst-case impact analysis.

## Task 6: Mitigation Strategy Recommendations

For high-priority risks, provide specific, actionable recommendations. Each risk should include:

1. **Architecture Improvement**: Before/after comparison (Mermaid diagrams) showing the improvement plan
2. **Configuration Optimization**: Specific AWS CLI commands or IaC code
3. **Monitoring & Alerting**: CloudWatch alarm configuration (metrics, thresholds, alarm levels, response SLA)
4. **AWS Service Recommendations**: Recommended services, value proposition, cost impact
5. **Implementation Assessment**: Complexity, expected outcomes, implementation risks, cost range, priority

See [example-report-template.md](../assets/example-report-template.md) for complete mitigation strategy examples.

## Task 7: Implementation Roadmap

**Phased Implementation Plan** (based on risk priority and dependencies), using Mermaid Gantt charts:

- **Phase 1: Foundational Resilience** -- Multi-AZ deployment, automated backup, basic monitoring and alerting
- **Phase 2: Automation** -- IaC migration, CI/CD pipelines, Auto Scaling
- **Phase 3: DR and Chaos Engineering** -- Aurora Global Database, Route 53 failover, AWS FIS
- **Phase 4: Continuous Improvement** -- SLO/SLI definition, postmortem process, quarterly resilience reviews

Each phase should include **detailed task cards** (task ID, effort, dependencies, owner, milestones, success criteria), **resource requirements**, and **implementation risk mitigation strategies**.

## Task 8: Continuous Improvement Mechanisms

**1. Regular Resilience Assessments**: Quarterly execution including automated scanning, manual architecture review, risk inventory updates, priority adjustments.

**2. Continuous Resilience Metrics Monitoring**: Define SLI/SLO, establish error budget policies (freeze non-critical releases when budget is exhausted; accelerate feature releases and chaos experiments when budget is ample).

**3. Postmortem Process**: Follow blameless culture principles, use a standard postmortem template (timeline, root cause, impact, action items). See [example-report-template.md](../assets/example-report-template.md) for postmortem template examples.

**4. Resilience Knowledge Base**: Build a centralized knowledge base including Runbooks/, Postmortems/, Architecture/, Playbooks/ directories.

**5. Team Skill Development**: AWS Well-Architected certification, SRE practice training, Chaos Engineering workshops, DR drills, Wheel of Misfortune exercises.
