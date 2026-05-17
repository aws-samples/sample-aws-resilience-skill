# Severity Classification (CJIS-specific)

Findings from CJIS checks are classified by how they affect an actual audit, not by generic security severity. The classes below are what the skill should use in reports and priority lists — they are what a CSA auditor would flag.

## Per-finding severity

| Level | Meaning | Examples |
|---|---|---|
| **AUDIT BLOCKER** | Will halt a triennial audit or cause a formal finding on day 1. Must be fixed before the auditor arrives. | No MFA on CJI access (PA 6), unencrypted CJI at rest (PA 8), no CJIS Security Addendum with AWS (PA 1), no fingerprint-based background check on admins with CJI access (PA 12), CloudTrail disabled or not logging (PA 4) |
| **FINDING RISK** | Likely to be cited as a formal finding. Usually fixable in days-to-weeks. | Access keys >90 days old (PA 6), partial log retention <1 year (PA 4), IAM users with console access missing MFA (PA 6), VPC Flow Logs disabled (PA 4), KMS CMKs without automatic rotation (PA 8) |
| **GAP** | Best-practice gap or PA sub-requirement weakly met. Unlikely to fail the audit alone but accumulates. | Password policy slightly below minimum (PA 6), EBS encryption not set as account default (PA 8), VPC endpoints not used (PA 10), stale IAM roles |
| **INFO** | Passing check, or optional hardening. | GuardDuty enabled, all resources encrypted, flow logs in place, etc. |

## Aggregate assessment status

At the end of a full assessment, each Policy Area gets an aggregate status:

| Status | Rule |
|---|---|
| **Non-Compliant** | ≥1 Audit Blocker in this PA |
| **At Risk** | 0 Audit Blockers but ≥2 Finding Risks, OR ≥1 Finding Risk + ≥3 Gaps |
| **Substantially Compliant** | 0 Audit Blockers, ≤1 Finding Risk, any number of Gaps |
| **Compliant** | 0 Audit Blockers, 0 Finding Risks |
| **Not Assessed** | Check could not run (see `UNABLE_TO_ASSESS`) or PA is organizational-only |

Do not use a numeric score or stars — CJIS policy areas are categorically different (PA 12 personnel screening is not comparable to PA 10 network protection), and averaging them misleads the reader.

## "Cannot assess" vs "no finding"

These must be distinguished in the report. They mean very different things to an auditor.

| Result code | When to use |
|---|---|
| `NOT_APPLICABLE` | The service/resource type being checked doesn't exist in this environment (e.g., no RDS → skip RDS encryption check) |
| `UNABLE_TO_ASSESS` | The check couldn't complete (AccessDenied, timeout, API error). Retry once; if still failing, mark as this and include the error |
| `INHERITED` | The requirement is satisfied by AWS (PA 9 physical protection, parts of PA 8 media sanitization). Reference AWS Artifact documents as evidence |
| `ORGANIZATIONAL` | The requirement is procedural and cannot be assessed technically (PA 2 training, PA 12 background checks, most of PA 1 agreements). Surface as a questionnaire item |
| `COMPLIANT` / `NON_COMPLIANT` | Check ran and produced a definite answer |

## Priority matrix (for the remediation roadmap)

Within a given PA, order remediation by:

```
Priority = Severity weight × (1 / Fix effort)

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

## Audit-heat map (which PAs fail audits most)

When summarizing, weight attention toward the PAs most often cited in real CJIS audits:

| PA | Typical audit failure rate | Notes |
|---|---|---|
| PA 6 — Authentication | **Very high** | Advanced Authentication (MFA) is the #1 finding nationwide |
| PA 4 — Auditing | **High** | Log retention, application-level CJI access logging gaps |
| PA 8 / PA 10 — Encryption | **High** | Non-FIPS endpoints, retrofit encryption gaps on legacy DBs |
| PA 12 — Personnel | **High** | Admins without current background checks |
| PA 1 — Agreements | **Medium** | Missing state-specific CJIS Security Addendum |
| PA 5 — Access Control | **Medium** | Least privilege, session timeouts |
| PA 7 — Config Management | **Medium** | Patch timeliness |
| PA 13 — Mobile | Low | Only relevant if mobile access to CJI exists |
| PA 2 / PA 3 / PA 9 / PA 11 | Low-to-Medium | Mostly organizational or inherited from AWS |

The skill's Quick Scan mode (PA 4, 6, 8, 10) targets the four PAs that account for the bulk of real-world audit findings.
