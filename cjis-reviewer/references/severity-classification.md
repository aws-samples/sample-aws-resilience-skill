# Severity Classification (CJIS v6.0 — Priority-Aligned)

> Based on CJIS Security Policy v6.0 (effective December 2024).
> Last verified against official source: 2025-05-21.
> Check https://le.fbi.gov/cjis-division/cjis-security-policy-resource-center for newer versions.

Findings from CJIS checks are classified by the control's priority rating in v6.0 and how non-compliance affects an actual audit. The classes below are what the skill uses in reports and priority lists — they align directly with what a CSA auditor would flag.

## Per-finding severity

| Level | Priority Mapping | Meaning | Examples |
|---|---|---|---|
| **AUDIT BLOCKER** | P1 controls non-compliant | Will halt a triennial audit or cause a formal finding on day 1. Must be fixed before the auditor arrives. | No MFA on CJI access (IA-2), unencrypted CJI at rest (SC-28), no FIPS endpoints (SC-13), GuardDuty disabled (SC-7/SI-4), CloudTrail disabled (AU-2 escalated), public CJI resources (AC-3), Inspector not enabled (SI-2) |
| **FINDING RISK** | P2 controls non-compliant | Likely to be cited as a formal finding. Usually fixable in days-to-weeks. | Access keys >90 days old (IA-5), partial log retention (AU-11), VPC Flow Logs disabled (AU-12), no backup plans (CP-9), KMS CMKs without rotation (SC-12), patch non-compliance (SI-2), Security Hub not enabled (SI-4) |
| **GAP** | P3 controls non-compliant | Best-practice gap. Unlikely to fail the audit alone but accumulates. | No VPC endpoints (AC-4), no cross-region replication (CP-10), no security alarms (SI-4 partial), Lambda without code signing (SI-7), no conformance packs (CM-6) |
| **INFO** | P4 controls or passing checks | Passing check, optional hardening, or P4 recommendation. | All resources encrypted, flow logs in place, GuardDuty enabled, etc. |

## Aggregate assessment status

At the end of a full assessment, each control family gets an aggregate status:

| Status | Rule |
|---|---|
| **Non-Compliant** | >= 1 Audit Blocker in this family |
| **At Risk** | 0 Audit Blockers but >= 2 Finding Risks, OR >= 1 Finding Risk + >= 3 Gaps |
| **Substantially Compliant** | 0 Audit Blockers, <= 1 Finding Risk, any number of Gaps |
| **Compliant** | 0 Audit Blockers, 0 Finding Risks |
| **Not Assessed** | Check could not run (see `UNABLE_TO_ASSESS`) or family is organizational-only |

Do not use a numeric score or stars — control families are categorically different (PS personnel screening is not comparable to SC network protection), and averaging them misleads the reader.

## "Cannot assess" vs "no finding"

These must be distinguished in the report. They mean very different things to an auditor.

| Result code | When to use |
|---|---|
| `NOT_APPLICABLE` | The service/resource type being checked doesn't exist in this environment (e.g., no RDS -> skip RDS encryption check) |
| `UNABLE_TO_ASSESS` | The check couldn't complete (AccessDenied, timeout, API error). Retry once; if still failing, mark as this and include the error |
| `INHERITED` | The requirement is satisfied by AWS (PE physical protection, parts of MP media sanitization). Reference AWS Artifact documents as evidence |
| `ORGANIZATIONAL` | The requirement is procedural and cannot be assessed technically (AT training, PS background checks, SA/SR acquisition). Surface as a questionnaire item |
| `COMPLIANT` / `NON_COMPLIANT` | Check ran and produced a definite answer |

## Priority matrix (for the remediation roadmap)

Within a given family, order remediation by:

```
Priority = Severity weight x (1 / Fix effort)

Severity weight:
  AUDIT BLOCKER = 5
  FINDING RISK  = 3
  GAP           = 1

Fix effort:
  1 = single CLI command or console toggle (minutes)
  2 = configuration change across multiple resources (hours)
  3 = architectural change (days)
  4 = multi-account / multi-region rework (weeks)
  5 = organizational change — agreements, training, screening (months)
```

This produces a natural Quick Wins list (Audit Blockers with effort 1-2) that should go to the top of the roadmap.

## Audit-heat map (which families fail audits most)

When summarizing, weight attention toward the families most often cited in real CJIS audits:

| Family | Typical audit failure rate | Notes |
|---|---|---|
| IA — Identification & Authentication | **Very high** | Advanced Authentication (MFA) is the #1 finding nationwide |
| SC — Systems & Communications | **High** | Non-FIPS endpoints, unencrypted resources, boundary gaps |
| AC — Access Control | **High** | Least privilege, session timeouts, public exposure |
| AU — Audit & Accountability | **High** | Log retention, application-level CJI access logging gaps |
| SI — System Integrity | **High** | Unpatched systems, no vulnerability scanning |
| PS — Personnel Security | **High** | Admins without current background checks |
| CM — Configuration Management | **Medium** | Patch timeliness, missing baselines |
| CP — Contingency Planning | **Medium** | Missing backup verification, no DR testing |
| Section 5.1 — Agreements | **Medium** | Missing state-specific CJIS Security Addendum |
| IR — Incident Response | **Medium** | No tested IR plan |
| AT / PE / SA / SR / MA / PL | Low-to-Medium | Mostly organizational or inherited from AWS |

The skill's Quick Scan mode (IA + SC + AC) targets the three P1 families that account for the bulk of real-world audit findings.
