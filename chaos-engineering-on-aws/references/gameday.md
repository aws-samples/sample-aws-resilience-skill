# Game Day Facilitator Guide

## Overview
A Game Day is a structured team exercise simulating real failures to validate resilience, incident response processes, and team readiness.

## Preparation Phase (1-2 weeks before)

### Scenario Selection
1. Select 1-3 high-impact scenarios from Step 1 experiment targets
2. Ensure all scenarios have been individually validated (no untested experiments in Game Day)
3. Rate scenarios by complexity: Green (single service), Yellow (multi-service), Red (cross-AZ/region)

### Communication Templates

#### Announcement Email/Message
Subject: [Game Day] {Date} — EKS Resilience Exercise

Team,

We will conduct a resilience Game Day on {date} from {start_time} to {end_time}.

**Purpose**: Validate our incident response and system resilience for {application_name}.
**Scope**: {scenario_summary}
**Impact**: {expected_blast_radius} — production traffic will NOT be affected / will be partially affected
**Preparation**: Please review the runbook at {runbook_link} before the session.

Questions? Contact {facilitator_name}.

#### Incident Channel Setup
Create a dedicated channel: #gameday-{date}-{app_name}
Pin the following:
- Scenario briefing document
- Kill Switch commands
- Emergency escalation contacts
- Runbook links

### Role Cards

| Role | Responsibilities | Skills Required | Materials to Prepare |
|------|-----------------|-----------------|---------------------|
| **Facilitator** | Drive agenda, manage time, inject scenario updates | Senior SA / SRE | This guide, scenarios, timer |
| **Incident Commander** | Coordinate response, make escalation decisions | Senior SRE / on-call lead | Runbook, escalation matrix |
| **Chaos Operator** | Execute fault injection, manage Kill Switch | Engineer with FIS/CM access | FIS console access, scripts |
| **Scribe** | Record every action with timestamps | Any team member | Shared doc, template |
| **Observer** | Observe without intervening, note process gaps | Management / external SA | Scoring card |

### Pre-Game Day Checklist
- [ ] All participants confirmed and roles assigned
- [ ] Scenarios validated individually in staging/pre-prod
- [ ] Kill Switch tested and documented
- [ ] Monitoring dashboards prepared and shared
- [ ] Communication channel created
- [ ] Runbooks reviewed and accessible
- [ ] Baseline metrics collected (Phase 0 equivalent)
- [ ] Management approval obtained (if production)

## Execution Day Agenda

### Agenda Template (3 hours)

| Time | Activity | Lead | Notes |
|------|----------|------|-------|
| 00:00-00:15 | Kickoff: Review scenarios, confirm Kill Switch, roles | Facilitator | Screen-share scenario doc |
| 00:15-00:30 | Baseline check (Phase 0) | Operator | Verify all systems green |
| 00:30-01:30 | Fault injection + team response (Phase 1-3) | Operator + IC | Scribe records all actions |
| 01:30-01:45 | Stop injection, confirm full recovery (Phase 4) | Operator | Verify baseline restored |
| 01:45-02:30 | Hot debrief | Facilitator | Use structured questions below |
| 02:30-03:00 | Action Items + wrap-up | Facilitator | Each item → owner + due date |

### Hot Debrief Questions
1. What surprised you during the exercise?
2. Where were the blind spots in our monitoring?
3. Was the runbook sufficient? What was missing?
4. How long did detection take? Was it fast enough?
5. Were escalation paths clear?
6. What would have happened if this were a real incident during peak traffic?

### Scoring Card

| Dimension | Score (1-5) | Notes |
|-----------|-------------|-------|
| **Detection Speed** | | How quickly was the fault detected? |
| **Triage Accuracy** | | Was the root cause correctly identified? |
| **Communication** | | Were updates timely and clear? |
| **Runbook Quality** | | Did the runbook cover the scenario? |
| **Recovery Time** | | Actual MTTR vs. target RTO |
| **Team Coordination** | | Did roles work smoothly? |
| **Tool Effectiveness** | | Were monitoring/alerting tools adequate? |
| **Overall Readiness** | | Overall team preparedness |

## Deliverables

### Executive Briefing Template (1 page)

**Game Day Summary — {Date}**

**Participants**: {count} engineers from {teams}
**Scenarios Tested**: {count} ({brief list})
**Key Findings**:
1. {finding_1}
2. {finding_2}
3. {finding_3}

**Metrics**:
| Scenario | Target RTO | Actual MTTR | Detection Time | Status |
|----------|-----------|-------------|----------------|--------|
| {name} | {target}s | {actual}s | {detection}s | ✅/❌ |

**Top 3 Action Items**:
1. {action_1} — Owner: {name}, Due: {date}
2. {action_2} — Owner: {name}, Due: {date}
3. {action_3} — Owner: {name}, Due: {date}

**Recommendation**: {next Game Day date and expanded scope}

### Full Deliverables List
- Updated Runbooks (with gaps filled)
- Action Items list (with owner and due date)
- MTTR baseline data (for future comparison)
- Scoring card results
- Executive briefing
- Automation decisions: which experiments to automate for continuous validation
