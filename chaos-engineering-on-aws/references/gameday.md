# Game Day Execution Mode

When the user selects Game Day mode, a team collaboration layer is added on top of the standard Phase 0-4.

## Preparation Phase (1-2 weeks before Game Day)

1. Select 1-3 high-impact scenarios from Step 1 experiment targets
2. Generate participant briefing: scenario description, blast radius, emergency contacts
3. Confirm roles:

| Role | Responsibility | Personnel Requirements |
|------|------|---------|
| Incident Commander | Coordinate overall, escalate decisions | Senior SRE / Architect |
| Chaos Operator | Operate fault injection and Kill Switch | Engineer familiar with FIS/CM |
| Scribe | Record every action and timestamp | Any team member |
| Observer | Do not intervene, focus on observing response | Management / external advisor |

4. Confirm notification channels and dedicated incident channel

## Execution Day Agenda (3 hours)

```
00:00 - 00:15  Kickoff: Review scenarios, confirm Kill Switch, roles
00:15 - 00:30  Baseline check (Phase 0)
00:30 - 01:30  Fault injection + team response (Phase 1-2)
               - Operator injects per plan
               - Team responds as if handling a real incident
               - Scribe records all actions
01:30 - 01:45  Stop injection, confirm recovery (Phase 3-4)
01:45 - 02:30  Hot debrief:
               - Timeline replay
               - What surprised you? Where were the blind spots?
               - MTTR phased analysis
02:30 - 03:00  Action Items:
               - Each gap → ticket + owner + due date
               - Which experiments should be repeated regularly
```

## Deliverables

- Updated Runbook
- Action Items list (with owner and due date)
- MTTR baseline data (for next comparison)
- Automation decisions: which experiments to run continuously
