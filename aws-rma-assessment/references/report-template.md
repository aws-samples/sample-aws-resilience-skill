# RMA Assessment Report Template

> This file contains the complete report template structure and HTML generation guide for RMA assessments.
> See [SKILL_EN.md](../SKILL_EN.md) Steps 6 and 7 for the main workflow overview.

---

## Report Filename Format

`{application-name}-rma-assessment-{date}.md`

---

## Report Structure

```markdown
# RMA Resilience Assessment Report
## {Application Name}

## Assessment Metadata

| Field | Value |
|-------|-------|
| **Evaluator** | {evaluator name/role} |
| **Assessment Date** | {YYYY-MM-DD} |
| **Scope** | {application name, AWS account(s), region(s)} |
| **Methodology Version** | RMA Assessment v2.0 |
| **Assessment Type** | {Compact (36 Qs) / Full (80 Qs)} |
| **Confidentiality** | {as specified by user} |

**Overall Maturity**: {score}% - {rating}

---

## Executive Summary

### Overall Assessment
- Total questions: {count}
- Average maturity level: {level}
- Overall score: {score}% - {rating}
- **AI-assisted efficiency**: Saved {percentage}% time, auto-analyzed {count} questions

### Maturity Radar Chart

Use Mermaid charts to display maturity across 10 domains:

\`\`\`mermaid
---
config:
  themeVariables:
    xyChart:
      plotColorPalette: "#2563eb"
---
%%{init: {'theme':'base'}}%%
graph TD
    subgraph Resilience Maturity Radar
        A[Recovery Objectives: 85%]
        B[Observability: 72%]
        C[Disaster Recovery: 65%]
        D[High Availability: 78%]
        E[Change Management: 88%]
        F[Incident Management: 70%]
        G[Operations Reviews: 60%]
        H[Chaos Engineering: 45%]
        I[Game Days: 40%]
        J[Organizational Learning: 55%]
    end
\`\`\`

**Or use table format:**

| Domain | Score | Rating | Trend |
|--------|-------|--------|-------|
| Recovery Objectives | 85% | Good | 🟢 |
| Observability | 72% | Fair | 🟡 |
| Disaster Recovery | 65% | Fair | 🟡 |
| High Availability | 78% | Good | 🟢 |
| Change Management | 88% | Good | 🟢 |
| Incident Management | 70% | Fair | 🟡 |
| Operations Reviews | 60% | Fair | 🟡 |
| Chaos Engineering | 45% | Needs Improvement | 🔴 |
| Game Days | 40% | Critical | 🔴 |
| Organizational Learning | 55% | Needs Improvement | 🟡 |

### Gap Heatmap

**Gap distribution by priority and domain:**

| Domain | P0 Gaps | P1 Gaps | P2 Gaps | P3 Gaps | Total |
|--------|---------|---------|---------|---------|-------|
| Recovery Objectives | 🟢 0 | 🟢 0 | 🟡 1 | - | 1 |
| Observability | - | 🟡 2 | 🟡 3 | - | 5 |
| Disaster Recovery | 🔴 2 | 🟡 1 | - | 🟢 0 | 3 |
| High Availability | 🟡 1 | 🟢 0 | - | - | 1 |
| Change Management | 🟢 0 | 🟢 0 | 🟡 1 | - | 1 |
| Incident Management | 🟡 1 | 🟡 2 | 🟢 0 | - | 3 |
| Chaos Engineering | - | - | 🔴 5 | 🔴 3 | 8 |
| Game Days | - | - | - | 🔴 3 | 3 |

**Legend:**
- 🔴 Gaps >= 3 questions (Critical)
- 🟡 Gaps 1-2 questions (Moderate)
- 🟢 Gaps 0 questions (Good)

### P0 Critical Risk Summary

**P0 Average Score**: {P0 score}% — {P0 rating}

> **⚠ Critical Risk Warning** (shown if any P0 question is Level 1)
> The following critical questions scored Level 1, indicating immediate action is required:

| Domain | Question | Current Level | Recommended Action |
|--------|----------|---------------|-------------------|
| {domain} | {question summary} | Level 1 | {recommended action} |

### Top 5 Key Findings

1. **[Domain] - Question X**: {description}
   - Current state: Level {1/2/3}
   - Risk level: High/Medium/Low
   - Business impact: {description}
   - **AI analysis basis**: {auto-analysis source}

### Strength Areas

List domains scoring Level 3, noting whether auto-identified

---

## Domain Assessment Details

### 1. Recovery Objectives
**Domain Score**: {score}% - {rating}

| Q ID | Question | Current Level | Target Level | Gap |
|------|----------|---------------|--------------|-----|
| 1 | ... | 2 | 3 | Needs Improvement |

**Domain Analysis:**
{Analysis and recommendations based on answers}

### 2. Observability
...

{Repeat for all domains}

---

## Improvement Roadmap

### Phase 1 (0-3 months): Critical Risk Mitigation

**Priority**: P0

| Q ID | Improvement Item | Current->Target | AWS Service Recommendation | Est. Effort | Est. Cost |
|------|-----------------|-----------------|---------------------------|-------------|-----------|
| 27 | Implement DR strategy | 1->3 | Aurora Global DB, Route 53 | 2-3 weeks | +$1500/mo |

### Phase 2 (3-6 months): Important Improvements

**Priority**: P1

{Similar format}

### Phase 3 (6-12 months): Maturity Uplift

**Priority**: P2 + P3

{Similar format}

---

## AWS Service Recommendations

Based on gap analysis, the following AWS services are recommended:

| Service | Purpose | Addresses | Est. Monthly Cost |
|---------|---------|-----------|-------------------|
| AWS Resilience Hub | Automated resilience assessment | Q38 | $0 (per-assessment billing) |
| AWS FIS | Chaos engineering testing | Q62-68 | ~$100/mo |
| CloudWatch Synthetics | Synthetic monitoring | Q17 | ~$50/mo |

---

## Detailed Q&A Records

### P0 - Critical Questions

#### Question 1: How do you define recovery objectives for your application?
- **Answer**: {user's answer}
- **Maturity Level**: {1/2/3}
- **Assessment Basis**: {rationale for the level}
- **Improvement Recommendation**: {specific advice if not Level 3}

{Detailed records for all questions}

---

## Next Steps

For domains scoring Level 1, the following deep-dive analyses are recommended using `aws-resilience-modeling`:

| Domain at Level 1 | Recommended Modeling Task | Focus Area |
|-------------------|--------------------------|------------|
| Disaster Recovery | Task 2 (Failure Modes) + Task 4 (Business Impact) | DR strategy validation and business impact analysis |
| High Availability | Task 1 (Component Mapping) + Task 2 (Failure Modes) | Architecture dependency and fault tolerance analysis |
| Observability | Task 1 (Component Mapping) + Task 3 (Resilience Assessment) | Monitoring gap identification and scoring |

This assessment should be paired with `aws-resilience-modeling` for a complete risk mitigation lifecycle.

## Scoring Alignment Reference

| RMA Level | Approximate Modeling Stars | Description |
|-----------|--------------------------|-------------|
| Level 1 (Ad-hoc) | 1-2 stars | Informal/no process |
| Level 2 (Defined) | 2.5-3.5 stars | Basic processes exist |
| Level 3 (Managed) | 4-5 stars | Mature, automated, continuously improved |

*Note: This is an approximate mapping. The two assessments evaluate different dimensions and granularity.*

---

## Reference Resources

- [AWS Well-Architected Framework - Reliability Pillar](https://docs.aws.amazon.com/wellarchitected/latest/reliability-pillar/)
- [AWS Resilience Hub](https://aws.amazon.com/resilience-hub/)
- [AWS Fault Injection Simulator](https://aws.amazon.com/fis/)

---

**Report generated**: {datetime}
**Assessment tool**: RMA Assessment Assistant v2.0
```

---

## HTML Report Generation (Optional)

If the user needs an HTML version, use pandoc to convert:

```bash
# Check if pandoc is available
if command -v pandoc &> /dev/null; then
    pandoc {report-file}.md \
      -f gfm \
      -t html5 \
      --standalone \
      --toc \
      --toc-depth=3 \
      --css=https://cdn.jsdelivr.net/npm/github-markdown-css@5/github-markdown.min.css \
      --metadata title="RMA Resilience Assessment Report" \
      -o {report-file}.html
fi
```
