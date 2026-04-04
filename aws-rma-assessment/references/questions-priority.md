# RMA Question Priority Classification

## Priority Definitions

- **P0 - Critical**: Directly impacts system availability, RTO/RPO, and customer experience; must answer
- **P1 - Important**: Impacts system resilience and recovery capability; strongly recommended
- **P2 - Recommended**: Best practices and continuous improvement; recommended
- **P3 - Optional**: Maturity uplift and organizational culture; optional

## Compact Version (36 Questions)

Includes all P0 + P1 priority questions

### Full Version (82 Questions)

Includes all P0 + P1 + P2 + P3 questions

---

## P0 - Critical Questions (12)

### Recovery Objectives (3)
1. **Q1**: How do you define recovery objectives for your application? (RTO/RPO/MTTR)
2. **Q2**: How do you define SLOs for your application?
3. **Q3**: How do you determine application criticality?

### Disaster Recovery (3)
27. **Q27**: What criteria do you use to select DR strategy?
30. **Q30**: How do you validate data recovery strategies meet RPO/RTO?
34. **Q34**: What is the frequency of testing your failover strategy?

### High Availability (3)
35. **Q35**: How do you plan for hard dependency failures?
36. **Q36**: How do you define and implement fault isolation boundaries?
38. **Q38**: Under what circumstances should you evaluate HA control effectiveness?

### Change Management (1)
40. **Q40**: How do you evaluate code deployment methods?

### Incident Management (2)
48. **Q48**: How do you plan for incident response?
51. **Q51**: What is the procedure for escalating an incident?

---

## P1 - Important Questions (24)

### Observability (6)
13. **Q13**: How do you establish instrumentation (logs, metrics, traces, alerts)?
14. **Q14**: How do you ensure logs are accessible and functional?
16. **Q16**: How do you leverage tracing to extract data?
18. **Q18**: How do you align metrics with fault domains?
19. **Q19**: How do you track availability and latency metrics?
21. **Q21**: How do you track dependencies and alert when at risk?

### Disaster Recovery (4)
28. **Q28**: What is the communication protocol during incidents?
29. **Q29**: Is data recovery automated?
31. **Q31**: How detailed is the DR plan?
32. **Q32**: How do you manage primary-secondary site drift?

### High Availability (2)
37. **Q37**: How do you evacuate fault isolation boundaries?
39. **Q39**: How do you avoid reaching AWS service limits?

### Change Management (6)
41. **Q41**: What environments are used to test deployments?
42. **Q42**: How frequently is code deployed to production?
43. **Q43**: To what extent is automation integrated into the release pipeline?
44. **Q44**: How do you roll back failed deployments?
45. **Q45**: How do you verify that changes are successful?
46. **Q46**: How do you manage version control for the system?

### Incident Management (6)
49. **Q49**: Are incident playbooks automated?
50. **Q50**: What methods are used to train teams on incident management?
52. **Q52**: How detailed are incident reports?
54. **Q54**: How do you apply insights gained from incidents?
55. **Q55**: How do you notify customers and third parties about incidents?
56. **Q56**: Do teams own their incident management processes?

---

## P2 - Recommended Questions (32)

### Resilience Analysis (6)
4. **Q4**: What are the documented resilience requirement constraints?
5. **Q5**: How do you consider likelihood, impact, and cost when selecting controls?
7. **Q7**: How comprehensive is dependency documentation?
8. **Q8**: How do you address coupling with dependencies?
9. **Q9**: How do you create and leverage inventories?
10. **Q10**: What methods do you use to model failure scenarios?

### Resilience Capacity (2)
11. **Q11**: How do you forecast application performance under high-load conditions?
12. **Q12**: How do you prepare your application to handle load changes?

### Observability (8)
15. **Q15**: How do you set up log data retrieval?
17. **Q17**: How do you use synthetic traffic to monitor your application?
20. **Q20**: In what areas do metrics provide reporting?
22. **Q22**: When do metrics provide information about failure scenarios?
23. **Q23**: What is the strategy for selecting alerts?
24. **Q24**: How adaptive are alert thresholds?
25. **Q25**: What methods are used to relay alert notifications?
26. **Q26**: How do you automate alert responses?


### Disaster Recovery (1)
81. **Q81**: Does your DR strategy meet regulatory compliance requirements (e.g., data residency, retention periods)?
### Change Management (1)
47. **Q47**: How do you ensure code complies with organizational standards?

### Incident Management (3)
53. **Q53**: Do you track how teams use the report repository?
57. **Q57**: Does the response team have authority to take action?
82. **Q82**: How do you ensure audit log retention meets compliance requirements?

### Operations Reviews (4)
58. **Q58**: Who participates in operational reviews?
59. **Q59**: How frequently are operational reviews conducted?
60. **Q60**: How thorough are operational reviews?
61. **Q61**: How do you monitor operational performance?

### Chaos Engineering (7)
62. **Q62**: To what extent does experiment load reflect production traffic?
63. **Q63**: How realistic are chaos experiment conditions?
64. **Q64**: In what environment are chaos experiments conducted?
65. **Q65**: How repeatable are chaos experiments?
66. **Q66**: How frequently are chaos experiments conducted?
67. **Q67**: How do you test fault isolation boundaries?
68. **Q68**: What types of testing are being conducted?

---

## P3 - Optional Questions (14)

### Resilience Requirements (1)
6. **Q6**: How do you ensure resilience learning is prioritized over new features?

### Disaster Recovery (1)
33. **Q33**: How do you prevent the failover site from reaching AWS service limits?

### Chaos Engineering (5)
69. **Q69**: Is an experiment catalog maintained?
70. **Q70**: What chaos engineering guidance is provided to application teams?
71. **Q71**: How is monitoring implemented during experiments?
72. **Q72**: How are experiments integrated into the SDLC?
73. **Q73**: How does the organization learn from individual team experiments?

### Game Days (3)
74. **Q74**: How well do Game Days simulate the real environment?
75. **Q75**: How realistic are Game Day scenarios?
76. **Q76**: How reproducible are Game Days?

### Organizational Learning (4)
77. **Q77**: How do you foster a community that supports resilience?
78. **Q78**: How do you define roles and responsibilities for resilience?
79. **Q79**: How do you keep teams up to date on resilience concepts?
80. **Q80**: How do you customize resilience training for unique circumstances?

---

## Version Comparison

| Version | Questions Included | Count | Estimated Time |
|---------|-------------------|-------|----------------|
| **Compact** | P0 (12) + P1 (24) | 36 | 30-40 min |
| **Full** | P0 (12) + P1 (24) + P2 (32) + P3 (14) | 82 | 60-90 min |

## Recommendations

- **First assessment**: Choose the compact version for a quick view of critical risks
- **Deep assessment**: After addressing P0/P1 issues, run the full version for maturity uplift
- **Periodic review**: Quarterly compact assessment, annual full assessment recommended
