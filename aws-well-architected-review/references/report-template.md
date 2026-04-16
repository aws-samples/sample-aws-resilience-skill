# Report Template

## Assessment Metadata

| Field | Value |
|-------|-------|
| **Assessment Date** | {YYYY-MM-DD} |
| **Account ID** | {account_id} |
| **Region** | {region} |
| **Framework** | AWS Well-Architected Framework (General) |
| **Pillars Assessed** | {pillar_list} |
| **Assessment Mode** | Autopilot (Programmatic) |
| **Assessor** | AI-Powered WA Review Skill v1.0 |
| **Credential** | {role_arn} (ReadOnly) |

---

## Executive Summary

### Overall Health: {overall_score}/5 {star_rating}

{2-3 sentence summary of the environment's health. Highlight the strongest and weakest pillars.}

### Top 5 Risks

| # | Risk | Pillar | Severity | Quick Fix? |
|---|------|--------|----------|-----------|
| 1 | {risk} | {pillar} | CRITICAL | {yes/no} |
| 2 | {risk} | {pillar} | HIGH | {yes/no} |
| 3 | {risk} | {pillar} | HIGH | {yes/no} |
| 4 | {risk} | {pillar} | MEDIUM | {yes/no} |
| 5 | {risk} | {pillar} | MEDIUM | {yes/no} |

### Key Recommendations
1. {Recommendation 1 — immediate action}
2. {Recommendation 2 — short-term}
3. {Recommendation 3 — strategic}

---

## Pillar Scorecards

| Pillar | Score | CRITICAL | HIGH | MEDIUM | LOW |
|--------|-------|----------|------|--------|-----|
| 🔒 Security | {x}/5 | {n} | {n} | {n} | {n} |
| ⚙️ Ops Excellence | {x}/5 | {n} | {n} | {n} | {n} |
| 🔄 Reliability | {x}/5 | {n} | {n} | {n} | {n} |
| ⚡ Performance | {x}/5 | {n} | {n} | {n} | {n} |
| 💰 Cost Optimization | {x}/5 | {n} | {n} | {n} | {n} |
| 🌱 Sustainability | {x}/5 | {n} | {n} | {n} | {n} |

---

## Detailed Findings

### 🔒 Security Pillar ({score}/5)

{Per-check findings table from security-checks.md execution}

### ⚙️ Operational Excellence Pillar ({score}/5)

{Per-check findings table from ops-excellence-checks.md execution}

### 🔄 Reliability Pillar ({score}/5)

{Per-check findings table from reliability-checks.md execution}

### ⚡ Performance Efficiency Pillar ({score}/5)

{Per-check findings table from performance-checks.md execution}

### 💰 Cost Optimization Pillar ({score}/5)

{Per-check findings table from cost-checks.md execution}

### 🌱 Sustainability Pillar ({score}/5)

{Per-check findings table from sustainability-checks.md execution}

---

## Risk Portfolio

### HRI — High Risk Issues ({count})

| ID | Risk | Pillar(s) | Impact | Fix Effort | Priority |
|----|------|----------|--------|-----------|----------|
{HRI rows}

### MRI — Medium Risk Issues ({count})

| ID | Risk | Pillar(s) | Impact | Fix Effort | Priority |
|----|------|----------|--------|-----------|----------|
{MRI rows}

### LRI — Low Risk Issues ({count})

{Summary list — not full table}

---

## Improvement Roadmap

```mermaid
gantt
    title WA Improvement Roadmap
    dateFormat  YYYY-MM-DD
    section Immediate (0-2 weeks)
    {task1}           :crit, t1, {start}, 7d
    {task2}           :crit, t2, {start}, 7d
    section Short-term (2-8 weeks)
    {task3}           :t3, after t1, 21d
    {task4}           :t4, after t2, 21d
    section Medium-term (2-6 months)
    {task5}           :t5, after t3, 60d
    section Long-term (6-12 months)
    {task6}           :t6, after t5, 120d
```

### Phase 1: Immediate (0-2 weeks)
{Critical security + reliability fixes with specific commands}

### Phase 2: Short-term (2-8 weeks)
{High-priority improvements}

### Phase 3: Medium-term (2-6 months)
{Architecture enhancements}

### Phase 4: Long-term (6-12 months)
{Strategic transformations}

---

## Implementation Guide (Top 10 Fixes)

### Fix 1: {Title}
- **Pillar**: {pillar}
- **Severity**: {severity}
- **Estimated time**: {time}
- **Steps**:
```bash
{specific aws cli commands}
```

{Repeat for top 10}

---

## Appendix

### A. Full Check Results
{Complete raw output from all checks}

### B. Checks Unable to Assess
{List of checks that failed due to permissions or unavailability}

### C. Assessment Methodology
- Framework: AWS Well-Architected Framework (2025)
- Assessment type: Programmatic (API-based, read-only)
- Total checks: {N} across 6 pillars
- Checks executed: {N} | Skipped: {N} | Failed: {N}
