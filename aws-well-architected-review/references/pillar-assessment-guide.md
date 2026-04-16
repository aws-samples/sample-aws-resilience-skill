# Pillar Assessment Guide

## Per-Pillar Output Structure

After each pillar's programmatic checks complete, produce this structured output:

```markdown
## {Pillar Name} Assessment

### Summary
- Checks executed: {N}
- Findings: {critical} CRITICAL, {high} HIGH, {medium} MEDIUM, {low} LOW
- Pillar health: {★★★★☆} ({score}/5)

### Findings

| ID | Check | Severity | Finding | Recommendation |
|----|-------|----------|---------|---------------|
| SEC-01 | GuardDuty | CRITICAL | Not enabled | Enable GuardDuty: `aws guardduty create-detector --enable` |

### Pillar Score Rationale
{Brief explanation of why this score was given}
```

## Scoring Rubric (5-Star)

| Stars | Rating | Criteria |
|-------|--------|----------|
| ★★★★★ | Excellent | 0 CRITICAL, 0 HIGH, ≤2 MEDIUM |
| ★★★★☆ | Good | 0 CRITICAL, ≤1 HIGH, ≤4 MEDIUM |
| ★★★☆☆ | Adequate | 0 CRITICAL, ≤3 HIGH, any MEDIUM |
| ★★☆☆☆ | Needs Improvement | ≤1 CRITICAL, any HIGH |
| ★☆☆☆☆ | Critical Risk | 2+ CRITICAL findings |

## Radar Chart Data

After all pillars complete, generate a Mermaid radar-like visualization:

```markdown
### Overall Health Score

| Pillar | Score | Rating |
|--------|-------|--------|
| Security | 3/5 | ★★★☆☆ |
| Ops Excellence | 4/5 | ★★★★☆ |
| Reliability | 2/5 | ★★☆☆☆ |
| Performance | 4/5 | ★★★★☆ |
| Cost Optimization | 3/5 | ★★★☆☆ |
| Sustainability | 3/5 | ★★★☆☆ |
| **Overall** | **3.2/5** | **★★★☆☆** |
```

## Assessment Adaptations

### When Check Cannot Execute
- API permission denied → mark as `UNABLE_TO_ASSESS` (not a finding)
- Service not in region → mark as `NOT_APPLICABLE`
- Timeout → retry once, then `UNABLE_TO_ASSESS`

### When Service Not Present
- No RDS → skip REL-01, PERF-04 → mark as `NOT_APPLICABLE`
- No EKS → skip REL-06 → mark as `NOT_APPLICABLE`
- No Lambda → skip PERF-07, SUS-03 → mark as `NOT_APPLICABLE`

### Quick Scan Mode
If user requests "quick scan" or "security only":
- Execute only Security pillar
- Skip all other pillars
- Generate abbreviated report
