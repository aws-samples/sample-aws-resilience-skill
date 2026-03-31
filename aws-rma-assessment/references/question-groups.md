# Batch Interactive Q&A Group Details

> This file contains the detailed grouping strategy and question lists for RMA assessment batch Q&A.
> See [SKILL_EN.md](../SKILL_EN.md) Step 4 for the main workflow overview.

---

## Compact Version (P0+P1, 36 Qs) -> 8-12 interactions

### Group 1 - Recovery Objectives & SLOs (P0: 3 Qs) - 1 interaction
- Q1: How do you define recovery objectives (RTO/RPO/MTTR)?
- Q2: How do you define SLOs (uptime and latency)?
- Q3: How do you determine application criticality?
- **Why grouped**: These three questions all relate to business requirement definitions; users typically define them in the same document

### Group 2 - DR Strategy & Testing (P0: 3 Qs + P1: 4 Qs) - 2 interactions
- Interaction 1 (P0 core):
  - Q27: DR strategy selection criteria?
  - Q30: How do you validate data recovery strategies?
  - Q34: Failover testing frequency?
- Interaction 2 (P1 details):
  - Q28: Incident communication protocol?
  - Q29: Is data recovery automated?
  - Q31: How detailed is the DR plan?
  - Q32: How do you manage primary-secondary site drift?

### Group 3 - High Availability Design (P0: 3 Qs + P1: 2 Qs) - 2 interactions
- Interaction 1 (P0 core):
  - Q35: How do you plan for hard dependency failures?
  - Q36: How do you define fault isolation boundaries?
  - Q38: When do you evaluate HA control effectiveness?
- Interaction 2 (P1 details):
  - Q37: How do you evacuate fault isolation boundaries?
  - Q39: How do you avoid AWS service limits?

### Group 4 - Change Management & Deployment (P0: 1 Q + P1: 6 Qs) - 2 interactions
- Interaction 1 (Deployment process):
  - Q40: How do you evaluate code deployment methods? [P0]
  - Q41: What environments are used for testing?
  - Q42: Production deployment frequency?
  - Q43: Automation integration level?
- Interaction 2 (Quality assurance):
  - Q44: How do you roll back failed deployments?
  - Q45: How do you verify change success?
  - Q46: How do you manage version control?

### Group 5 - Incident Management (P0: 2 Qs + P1: 6 Qs) - 2 interactions
- Interaction 1 (P0 core):
  - Q48: How do you plan for incident response?
  - Q51: Incident escalation procedure?
- Interaction 2 (P1 details):
  - Q49: Are incident playbooks automated?
  - Q50: Team training methods?
  - Q52: How detailed are incident reports?
  - Q54: How do you apply incident insights?
  - Q55: How do you notify customers?
  - Q56: Do teams own their incident processes?

### Group 6 - Observability (P1: 6 Qs) - 2 interactions
- Interaction 1 (Monitoring fundamentals):
  - Q13: How do you establish instrumentation (logs/metrics/traces/alerts)?
  - Q14: How do you ensure log accessibility?
  - Q16: How do you leverage tracing data?
- Interaction 2 (Advanced monitoring):
  - Q18: How do you align metrics with fault domains?
  - Q19: How do you track availability and latency?
  - Q21: How do you track dependencies?

---

## Full Version (+P2+P3, 44 Qs) -> additional 7-8 interactions

### Compact Version Group Extensions (+9 Qs, distributed into existing groups)

In full assessment, the following P2/P3 questions are appended to corresponding compact version groups (no additional standalone interactions; merged at the end of existing groups):

| Append To | Added Questions | Priority | Notes |
|-----------|-----------------|----------|-------|
| Group 1 (Recovery Objectives) | Q4: Resilience requirement constraints? Q5: Control selection? | P2 | Recovery objectives deep-dive |
| Group 1 (Recovery Objectives) | Q6: Resilience learning vs. new features? | P3 | Organizational level |
| Group 1 (Recovery Objectives) | Q11: High-load performance prediction? Q12: Load change readiness? | P2 | Resilience capacity |
| Group 2 (DR) | Q33: Failover site service limits? | P3 | DR supplement |
| Group 4 (Change Mgmt) | Q47: Code organizational standards compliance? | P2 | Change management supplement |
| Group 5 (Incident Mgmt) | Q53: Report repository usage? Q57: Response team authorization? | P2 | Incident management supplement |

### Group 7 - Resilience Analysis (P2: 6 Qs) - 2 interactions

- Interaction 1 (Requirements & modeling):
  - Q4: What are the documented resilience requirement constraints?
  - Q5: How do you consider likelihood, impact, and cost for control selection?
  - Q10: What methods do you use to model failure scenarios?
- Interaction 2 (Dependencies & inventories):
  - Q7: How comprehensive is dependency documentation?
  - Q8: How do you address coupling with dependencies?
  - Q9: How do you create and leverage inventories?
- **Why grouped**: All about pre-analysis of system resilience -- requirement definition, risk modeling, and dependency management

### Group 8 - Advanced Observability (P2: 8 Qs) - 2 interactions

- Interaction 1 (Logs & synthetic monitoring):
  - Q15: How do you set up log data retrieval?
  - Q17: How do you use synthetic traffic monitoring?
  - Q20: In what areas do metrics provide reporting?
  - Q22: When do metrics provide failure scenario info?
- Interaction 2 (Alert strategy):
  - Q23: What is the alert selection strategy?
  - Q24: How adaptive are alert thresholds?
  - Q25: What methods relay alert notifications?
  - Q26: How do you automate alert responses?
- **Why grouped**: Interaction 1 focuses on data collection and analysis; Interaction 2 focuses on alert design and response automation

### Group 9 - Chaos Engineering (P2: 7 Qs + P3: 5 Qs) - 2 interactions

- Interaction 1 (P2 core experiment capabilities):
  - Q62: How well does experiment load reflect production traffic?
  - Q63: How realistic are chaos experiment conditions?
  - Q64: In what environment are chaos experiments conducted?
  - Q65: How repeatable are chaos experiments?
  - Q66: How frequently are chaos experiments conducted?
  - Q67: How do you test fault isolation boundaries?
  - Q68: What types of testing are being conducted?
- Interaction 2 (P3 organizational maturity):
  - Q69: Is an experiment catalog maintained?
  - Q70: What chaos engineering guidance is provided?
  - Q71: How is monitoring implemented during experiments?
  - Q72: How are experiments integrated into the SDLC?
  - Q73: How does the organization learn from team experiments?
- **Why grouped**: Interaction 1 evaluates chaos engineering technical practices; Interaction 2 evaluates organization-level adoption and maturity

### Group 10 - Ops Reviews, Game Days & Org Learning (P2: 4 Qs + P3: 7 Qs) - 2 interactions

- Interaction 1 (Ops reviews + Game Days):
  - Q58: Who participates in operational reviews?
  - Q59: How frequently are operational reviews conducted?
  - Q60: How thorough are operational reviews?
  - Q61: How do you monitor operational performance?
  - Q74: How well do Game Days simulate real environments?
  - Q75: How realistic are Game Day scenarios?
- Interaction 2 (Game Days continued + Org learning):
  - Q76: How reproducible are Game Days?
  - Q77: How do you foster a resilience community?
  - Q78: How do you define resilience roles and responsibilities?
  - Q79: How do you keep teams up to date on resilience concepts?
  - Q80: How do you customize resilience training?
- **Why grouped**: Interaction 1 covers operational review and drill practices; Interaction 2 covers organizational culture and continuous learning

---

## Batch Question Format

Each group uses conversational format (not using AskUserQuestion tool, reducing interaction complexity):

```markdown
## Group N: {Group Name} ({Priority}, {Count} questions)

**This group covers**: {Brief topic description}

---

### Question X [P0/P1/P2/P3]: {Question title}

**Question**: {Full question description}

**Why it matters**: {Brief explanation}

**AWS Best Practice**: {Recommendation}

**Smart Recommendation**: Based on your architecture analysis, suggesting [Level 2] - {reason}

**Please select maturity level (1-3):**
- [Level 1] {description}
- [Level 2] {description}  <- Recommended
- [Level 3] {description}

**Your answer**: Level ___ (optional notes: ___)

---

**Please answer all questions in this group at once**, example format:
Q1: Level 2 - RTO/RPO defined but not regularly tested
Q2: Level 3 - 99.99% availability, <100ms latency
Q3: Level 2 - Criticality assessed based on revenue
```

---

## Batch Q&A Optimization Tips

1. **Pre-fill recommended answers**: Pre-fill suggested levels based on auto-analysis results
2. **Allow quick confirmation**: Users can reply "accept recommendations" to accept all suggestions
3. **Support partial answers**: Users can answer only some questions; the rest use recommended answers
4. **Real-time feedback**: Show group scores and key findings immediately after each group

---

## Efficiency Comparison

| Mode | Compact (36 Qs) | Full (80 Qs) |
|------|-----------------|--------------|
| **Traditional** | 36 interactions, 2 hours | 80 interactions, 3.5 hours |
| **AI Batch** | 8-12 interactions, 20-30 min | 15-20 interactions, 40-60 min |
| **Efficiency Gain** | 85% time saved | 75% time saved |

---

## Question Group Overview (by Topic Domain)

1. **Recovery Objectives**
   - P0: Questions 1, 2, 3
   - P2: Questions 4, 5

2. **Observability**
   - P1: Questions 13, 14, 16, 18, 19, 21
   - P2: Questions 15, 17, 20, 22, 23, 24, 25, 26

3. **Disaster Recovery**
   - P0: Questions 27, 30, 34
   - P1: Questions 28, 29, 31, 32
   - P3: Question 33

4. **High Availability**
   - P0: Questions 35, 36, 38
   - P1: Questions 37, 39

5. **Change Management**
   - P0: Question 40
   - P1: Questions 41, 42, 43, 44, 45, 46
   - P2: Question 47

6. **Incident Management**
   - P0: Questions 48, 51
   - P1: Questions 49, 50, 52, 54, 55, 56
   - P2: Questions 53, 57

7. **Operations Reviews**
   - P2: Questions 58, 59, 60, 61

8. **Chaos Engineering**
   - P2: Questions 62, 63, 64, 65, 66, 67, 68
   - P3: Questions 69, 70, 71, 72, 73

9. **Game Days**
   - P3: Questions 74, 75, 76

10. **Organizational Learning**
    - P2: Questions 6, 11, 12
    - P3: Questions 77, 78, 79, 80
