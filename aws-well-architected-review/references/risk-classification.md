# Risk Classification Guide

## Severity Levels (per finding)

| Level | Description | Examples |
|-------|-------------|---------|
| **CRITICAL** | Immediate security/reliability threat. Exploitable now. | GuardDuty disabled, SSH open to internet, root no MFA |
| **HIGH** | Significant risk, needs attention within days. | Unencrypted databases, no backups, stale access keys |
| **MEDIUM** | Notable gap, address within weeks. | Missing log retention, single-AZ databases, no lifecycle policies |
| **LOW** | Minor improvement opportunity. | Old instance types, unused Elastic IPs |
| **INFO** | Informational — passing check or recommendation. | Everything configured correctly |

## Risk Issue Classification (aggregated)

### HRI — High Risk Issue
- Any CRITICAL finding
- Any HIGH finding with blast radius > 1 service
- Cluster of 3+ MEDIUM findings in the same pillar
- Cross-pillar issue (affects 2+ pillars)

### MRI — Medium Risk Issue
- Isolated HIGH findings (single service impact)
- MEDIUM findings with cost or performance impact
- Missing best practices in non-critical areas

### LRI — Low Risk Issue
- LOW findings
- Optimization opportunities
- Informational recommendations

## Priority Scoring Matrix

```
Priority Score = Impact Score × (1 / Fix Effort Score)

Impact Score (1-5):
  5 = Data loss or security breach potential
  4 = Service outage potential
  3 = Degraded performance or high cost waste
  2 = Non-compliance or operational friction
  1 = Minor improvement

Fix Effort Score (1-5):
  1 = One CLI command / console toggle (minutes)
  2 = Configuration change (hours)
  3 = Architecture modification (days)
  4 = Multi-service redesign (weeks)
  5 = Major migration (months)

Quick Wins = High Impact (4-5) + Low Effort (1-2)
```

## Cross-Pillar Impact Map

| Primary Pillar | Commonly Affects | Example |
|---------------|-----------------|---------|
| Security | All pillars | Missing encryption affects reliability + compliance |
| Reliability | Performance, Cost | Under-provisioned = poor performance AND cost spikes |
| Performance | Cost, Reliability | Over-provisioned = cost waste; under = reliability risk |
| Cost | Sustainability | Idle resources = wasted energy |
| Ops Excellence | Reliability | No monitoring = slow incident response |
| Sustainability | Cost | Energy-inefficient = higher cloud bill |
