# CJIS Assessment Report Template

> Based on CJIS Security Policy v6.0 (effective December 2024).
> Last verified against official source: 2025-05-21.
> Check https://le.fbi.gov/cjis-division/cjis-security-policy-resource-center for newer versions.

Use this template verbatim when emitting the final Markdown report. A consistent shape is what makes reports reproducible across engagements and auditable as evidence.

Output path: `cjis-reports/cjis-assessment-{YYYY-MM-DD}.md`

---

## Section 1: Assessment Metadata

```markdown
# CJIS Security Policy Compliance Assessment

**Report date**: {YYYY-MM-DD}
**Assessor**: {name or "Claude CJIS Skill"}
**Target account**: {account_id}
**Target region(s)**: {regions}
**AWS partition**: {GovCloud (US) | Commercial}
**State CSA**: {state, or "Not specified"}
**CJIS Security Policy version**: v6.0
**Assessment mode**: {Quick Scan | Standard | Full | Questionnaire}
**Control families assessed**: {family list}
**Credentials used**: {role ARN} (read-only verified)
```

---

## Section 2: Executive Summary

Two-paragraph prose summary written for a CIO/CSO audience. NOT a list. Cover:
- Overall posture — one sentence (e.g., "The environment is Substantially Compliant with 2 Audit Blockers in IA and SC that must be remediated before the next triennial audit.")
- Biggest risk — what would an auditor flag first?
- Strongest areas — what's working
- The remediation ask — how much work and what kind (configuration vs organizational vs architectural)

Follow with the summary table:

```markdown
## Summary of Findings

| Control Family | Status | Audit Blockers | Finding Risks | Gaps |
|---|---|---|---|---|
| IA — Identification & Auth | **Non-Compliant** | 1 | 2 | 0 |
| SC — Systems & Comms | Substantially Compliant | 0 | 1 | 2 |
| AC — Access Control | Compliant | 0 | 0 | 1 |
| AU — Audit & Accountability | Substantially Compliant | 0 | 1 | 1 |
| CM — Config Management | At Risk | 0 | 2 | 3 |
| SI — System Integrity | Substantially Compliant | 0 | 1 | 1 |
| CP — Contingency Planning | Compliant | 0 | 0 | 2 |
| **TOTAL** | — | **1** | **7** | **10** |

**Top 3 items to remediate before audit:**
1. {First Audit Blocker — family, check ID, one-line fix}
2. {Second item}
3. {Third item}
```

---

## Section 3: Per-Control-Family Findings

One subsection per control family that was assessed. Fixed structure:

```markdown
## {Family Code} — {Family Name}

**Status**: {Compliant | Substantially Compliant | At Risk | Non-Compliant | Not Assessed}
**Checks executed**: {n} — {passed} passed, {failed} failed, {na} N/A, {unable} unable to assess

### Findings

| ID | Check | Severity | Resource(s) | Finding | Remediation |
|---|---|---|---|---|---|
| IA-02-03 | MFA on IAM users | AUDIT BLOCKER | 3 users | Users {a,b,c} have console access without MFA | Attach MFA-required policy; remediate within 24 hrs |
| IA-05-01 | Password policy | FINDING RISK | account-level | Min length is 12, CJIS requires >=20 | `aws iam update-account-password-policy --minimum-password-length 20` |
| IA-02-01 | Root MFA | INFO | root | MFA enabled | — |

### Organizational items

Any checks for this family that are organizational rather than technical — surface them as questions the user must answer offline:

- [ ] Do all personnel with CJI access have current fingerprint-based background checks? (PS)
- [ ] Is the CJIS Security Addendum on file with AWS for {state}? (Section 5.1)
```

Severity badges in the `Severity` column should be **bolded** for `AUDIT BLOCKER` and plain text for the rest, so the worst items jump out on a scan.

If `Status = Not Assessed`, explain why in a single line below the header (e.g., "Skipped — service not present in this account" or "Skipped — organizational-only family, see questionnaire").

---

## Section 4: Remediation Roadmap

```markdown
## Remediation Roadmap

### Immediate (0-2 weeks) — Audit Blockers + Quick Wins

| Item | Family | Severity | Effort | Owner |
|---|---|---|---|---|
| Enable MFA for 3 non-compliant IAM users | IA | AUDIT BLOCKER | 1 (mins) | IAM admin |
| Encrypt 2 unencrypted RDS instances (snapshot -> restore) | SC | AUDIT BLOCKER | 3 (days) | DBA |

### Short-term (2-8 weeks) — Finding Risks

| Item | Family | Severity | Effort | Owner |
|---|---|---|---|---|
| Tighten password policy to 20-char minimum | IA | FINDING RISK | 1 (mins) | IAM admin |
| Enable VPC Flow Logs on 2 VPCs | AU | FINDING RISK | 1 (mins) | Network |

### Medium-term (2-6 months) — Gaps and architectural items

| Item | Family | Severity | Effort | Owner |
|---|---|---|---|---|
| Adopt VPC endpoints to eliminate internet egress | AC/SC | GAP | 3 (days) | Network |

### Long-term (6-12 months) — Organizational & strategic

- [ ] Establish formal IR tabletop schedule (IR)
- [ ] Document Management Control Agreement with {contractor} (Section 5.1)
- [ ] Refresh personnel security screening process (PS)
```

Sort each phase by severity (Audit Blocker first) then by effort (lowest first) so Quick Wins bubble up.

---

## Section 5: Organizational Questionnaire

The organizational families that cannot be assessed technically. Present as a checklist that the user needs to walk through with their CSO and HR. Pull directly from `references/readiness-checklist.md`, filtered to the families not covered by the technical scan.

```markdown
## Organizational Readiness — User Action Required

These items cannot be verified from AWS APIs. Work with your CSO, TAC, and HR to confirm each.

### Section 5.1 — Information Exchange Agreements
- [ ] CJIS Security Addendum on file with AWS for {state}
- [ ] MCA in place with any contractors accessing CJI
- [ ] All contractor personnel individually signed the Security Addendum

### PS — Personnel Security
- [ ] Fingerprint-based background checks for all CJI-access personnel
- [ ] Background checks completed before access granted
- [ ] Renewal schedule defined and tracked

### AT — Awareness and Training
- [ ] Training program established
- [ ] ...
```

---

## Section 6: Appendix — Raw Check Results

Include the full list of check IDs, the CLI command executed, the raw result, and the severity determination. This is audit evidence — do not truncate.

```markdown
## Appendix A: Raw Check Results

### IA-02-03 — MFA on IAM users

**Command**:
```
aws iam generate-credential-report && sleep 2
aws iam get-credential-report --query Content --output text | base64 -d
```

**Result**:
```
alice: password_enabled=true, mfa_active=false
bob: password_enabled=true, mfa_active=false
charlie: password_enabled=true, mfa_active=false
```

**Severity**: AUDIT BLOCKER — IA-2 requires multi-factor authentication for all CJI access.

---
```

---

## Section 7: Methodology & Caveats

One short page explaining:
- What the scan did and didn't do (read-only, specific families, single account/region)
- Which families are organizational and not covered by technical checks
- That CJIS compliance varies by state CSA — final determination always rests with the CSO
- Timestamp and assessor info so this report is dated and traceable
- Disclaimer: "This report is a point-in-time snapshot of technical configuration. It does not replace a formal CJIS audit by the CSA."

---

## Formatting conventions

- Dates: `YYYY-MM-DD` (ISO)
- ARNs and resource IDs: backticks
- Severity labels: uppercase (`AUDIT BLOCKER`, `FINDING RISK`, `GAP`, `INFO`)
- Status labels: title case (`Non-Compliant`, `At Risk`)
- Commands: fenced code blocks with `bash`
- Control references: `{Family}-{Number}` format (e.g., IA-2, SC-28, AU-12)
- Never use emoji severity icons in the machine-readable tables — they break downstream parsing. Emoji OK in the Executive Summary prose only.
