# Severity Classification (FERPA-specific)

Findings from FERPA checks are classified by how they affect real-world outcomes — a state-AG breach-notification decision, a U.S. Dept. of Education SPPO complaint investigation, a state-contract annual review, or a SOC 2 Type II opinion. The classes below are what an auditor, DPA reviewer, or state-ED privacy officer would flag.

## Per-finding severity

| Level | Meaning | Examples |
|---|---|---|
| **BREACH RISK** | Would likely cause a reportable data breach (triggering state-AG notification), an SPPO complaint finding, or a material DPA violation if exploited. Must be fixed immediately. | Unencrypted S3 bucket containing student records exposed to the internet (FCD 5/7), no MFA on admin accounts that touch SIS data (FCD 6), missing §99.32 disclosure log entirely (FCD 4), unauthorized subprocessor receiving student data (FCD 3/10), RDS instance storing grades set to `PubliclyAccessible=true` (FCD 5) |
| **COMPLIANCE GAP** | Would be cited in a state-contract annual review, SOC 2 Type II engagement, or DPA renewal. Usually fixable in days-to-weeks. | Access keys >90 days old (FCD 6), partial log retention below student-record retention schedule (FCD 4), IAM users with console access missing MFA (FCD 6), VPC Flow Logs disabled (FCD 4), KMS CMKs without automatic rotation (FCD 7), no S3 lifecycle policy on student-data buckets (FCD 8) |
| **HARDENING GAP** | Best-practice gap or PTAC guidance weakly met. Unlikely to fail a contract review alone but accumulates. | Password policy slightly below 14-char floor (FCD 6), EBS encryption not set as account default (FCD 7), VPC endpoints not used (FCD 3), stale IAM roles not cleaned up (FCD 5), TLS 1.0/1.1 listener still enabled alongside 1.2 (FCD 7) |
| **INFO** | Passing check, or optional hardening observation. | GuardDuty enabled, Macie scanning student-data buckets, all resources encrypted, flow logs in place, etc. |

## Aggregate assessment status

At the end of a full assessment, each FCD gets an aggregate status:

| Status | Rule |
|---|---|
| **Non-Compliant** | ≥1 Breach Risk in this FCD |
| **At Risk** | 0 Breach Risks but ≥2 Compliance Gaps, OR ≥1 Compliance Gap + ≥3 Hardening Gaps |
| **Substantially Compliant** | 0 Breach Risks, ≤1 Compliance Gap, any number of Hardening Gaps |
| **Compliant** | 0 Breach Risks, 0 Compliance Gaps |
| **Not Assessed** | Check could not run (see `UNABLE_TO_ASSESS`) or FCD is organizational-only |

Do not use a numeric score or stars — FCDs are categorically different (FCD 10 vendor management is not comparable to FCD 7 encryption), and averaging them misleads the reader.

## "Cannot assess" vs "no finding"

These must be distinguished in the report. They mean very different things to a DPA reviewer.

| Result code | When to use |
|---|---|
| `NOT_APPLICABLE` | The service/resource type being checked doesn't exist in this environment (e.g., no RDS → skip RDS encryption check) |
| `UNABLE_TO_ASSESS` | The check couldn't complete (AccessDenied, timeout, API error). Retry once; if still failing, mark as this and include the error |
| `INHERITED` | The requirement is satisfied by AWS (NIST 800-88 physical media destruction, some physical-protection controls). Reference AWS Artifact documents as evidence |
| `ORGANIZATIONAL` | The requirement is procedural and cannot be assessed technically (FCD 2 parental rights, FCD 10 DPA quality, most of FCD 1 consent management). Surface as a questionnaire item |
| `COMPLIANT` / `NON_COMPLIANT` | Check ran and produced a definite answer |

## Priority matrix (for the remediation roadmap)

Within a given FCD, order remediation by:

```
Priority = Severity weight × (1 / Fix effort)

Severity weight:
  BREACH RISK     = 5
  COMPLIANCE GAP  = 3
  HARDENING GAP   = 1

Fix effort:
  1 = single CLI command or console toggle (minutes)
  2 = configuration change across multiple resources (hours)
  3 = architectural change (days)
  4 = multi-account / multi-region rework (weeks)
  5 = organizational change — DPAs, training, new subprocessor contracts (months)
```

This produces a natural Quick Wins list (Breach Risks with effort 1-2) that should go to the top of the roadmap.

## Breach-risk-heat map (which FCDs cause real EdTech incidents)

When summarizing, weight attention toward the FCDs most often cited in real-world EdTech breach notifications, state-AG settlements, and SPPO complaint findings:

| FCD | Typical incident frequency | Notes |
|---|---|---|
| FCD 4 — Auditing & §99.32 log | **Very high** | Missing or incomplete disclosure logs; cannot answer "who viewed this student's record" |
| FCD 7 — Encryption | **High** | Unencrypted S3 buckets exposed to the internet — breach vector #1 in state-AG notifications |
| FCD 6 — Authentication | **High** | Credential compromise on unMFAed admin accounts; SSO misconfigurations |
| FCD 5 — Access Control | **High** | Over-privileged IAM roles; public RDS snapshots; public S3 ACLs |
| FCD 3 — Disclosure Controls | **Medium-High** | Unauthorized subprocessor disclosure; ML training on student data without district consent |
| FCD 10 — Vendor management | **Medium** | Undisclosed subprocessors surface during breach notification |
| FCD 8 — Retention & destruction | **Medium** | Failure to destroy district data after contract termination |
| FCD 9 — Incident response | **Medium** | Notification timeline missed; state-contract SLA violation |
| FCD 1 — Directory info / consent | Low-Medium | Opt-outs not honored; pre-opt-out disclosure |
| FCD 2 — Parent/student rights | Low | Usually surfaces as a DSAR timeline miss, not a breach |

The skill's Quick Scan mode (FCD 4, 5, 6, 7) targets the four FCDs that account for the bulk of real-world EdTech incidents.

## Federal vs state distinctions in severity

Unlike CJIS (single federal policy), FERPA findings split along federal and state lines. Note the difference in the report:

- **Federal FERPA finding**: Would be cited by SPPO in a complaint investigation (§99.32 log, unauthorized redisclosure, school-official-exception misuse). Classified BREACH RISK or COMPLIANCE GAP.
- **State-contract finding**: Would be cited under a state DPA or state data-protection law (SOPIPA, Ed Law 2-d, TX SB 820, SOPPA, etc.). Classified on state-specific severity — often BREACH RISK given state AG enforcement teeth.
- **Best-practice / PTAC guidance**: Not cited federally; might appear as a SOC 2 control deviation. Usually HARDENING GAP.

When a finding applies under multiple frameworks, use the highest severity. Annotate the finding with all frameworks it violates — this matters for the remediation roadmap (multi-framework fixes have more urgency).
