# Report Templates

## Single Experiment Report

```markdown
# Chaos Engineering Experiment Report

## Experiment Overview
- Experiment name: {name}
- Risk ID: {risk_id} (from Assessment 2.4)
- Execution time: {timestamp}
- Environment: {env}
- Result: {PASSED ✅ / FAILED ❌ / ABORTED ⚠️}

## Input Source
- Assessment report: {filename}
- Risk description: {description}
- Assessment suggested injection method: {suggestion}
- Actual injection method: {actual}

## Steady-State Hypothesis vs. Actual Performance

| Metric | Baseline | Hypothesis Threshold | During Experiment | After Recovery | Verdict |
|------|--------|---------|-----------|---------|------|
| Success rate | 99.98% | >= 99.5% | {value} | {value} | ✅/❌ |
| P99 latency | 120ms | <= 500ms | {value} | {value} | ✅/❌ |
| Recovery time | N/A | <= {RTO}s | {value} | N/A | ✅/❌ |

## Timeline
- T+0s: Fault injection started
- T+{X}s: Impact detected
- T+{Y}s: Recovery started
- T+{Z}s: Service fully recovered

## MTTR Phased Analysis

| Phase | Duration | Description | Improvement Direction |
|------|------|------|---------|
| Detection (fault → alarm) | {X}s | {description} | {suggestion} |
| Triage (alarm → root cause) | {X}s | {description} | {suggestion} |
| Response (root cause → fix) | {X}s | {description} | {suggestion} |
| Recovery (fix → restored) | {X}s | {description} | {suggestion} |
| **Total MTTR** | {X}s | | |

## Key Findings
1. ...

## Improvement Recommendations
1. **[P0]** ...
2. **[P1]** ...

## Resilience Score Update

| Dimension | Before Experiment (2.7) | After Experiment | Change |
|------|-------------|--------|------|
| Redundancy Design | ⭐ X/5 | ⭐ X/5 | — |
| ... | | | |

## Newly Discovered Risks

| Risk ID | Description | Severity | Recommendation |
|---------|------|--------|------|
| R-NEW-001 | ... | 🟠 High | ... |
```

## Summary Report

```markdown
# Chaos Engineering Summary Report

## Overview
- Project: {name}
- Architecture pattern: {pattern}
- Experiment period: {range}
- Total experiments: {N} | Passed: {P} | Failed: {F} | Aborted: {A}

## Resilience Maturity Change
- Before experiments: {score}/5.0 (Assessment evaluation)
- After experiments: {score}/5.0 (Experiment validation)

## Risk Validation Status

| Risk ID | Description | Severity | Result | Validation Status | Improvement Priority |
|---------|------|--------|------|---------|-----------|
| R-XXX | ... | 🔴 | FAILED | Risk confirmed ⚠️ | P0 |
| R-YYY | ... | 🔴 | PASSED | Impact manageable ✅ | P2 (downgraded) |

## Improvement Roadmap
1. ...
```

## HTML Report

The HTML version is generated from Markdown content with additional features:
- Inline CSS (no external dependencies, single file works offline)
- Color coding: PASSED=green, FAILED=red, ABORTED=orange
- Metric comparison visualization (CSS bar chart or embedded SVG)
- Experiment timeline diagram
- Responsive layout
