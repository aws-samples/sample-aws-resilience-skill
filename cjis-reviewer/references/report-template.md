# CJIS Assessment Report Template

Use this template verbatim when emitting the final Markdown report. A consistent shape is what makes reports reproducible across engagements and auditable as evidence.

Output path: `cjis-reports/cjis-assessment-{YYYY-MM-DD}.md`

---

## Section 1: Assessment Metadata

```markdown
# CJIS Security Policy Compliance Assessment

**Report date**: {YYYY-MM-DD}
**Assessor**: {name or "Kiro CJIS Skill"}
**Target account**: {account_id}
**Target region(s)**: {regions}
**AWS partition**: {GovCloud (US) | Commercial}
**State CSA**: {state, or "Not specified"}
**CJIS Security Policy version**: v5.9.5
**Assessment mode**: {Quick Scan | Standard | Full | Questionnaire}
**Policy areas assessed**: {PA list}
**Credentials used**: {role ARN} (read-only verified ✅)
```

---

## Section 2: Executive Summary

Two-paragraph prose summary written for a CIO/CSO audience. NOT a list. Cover:
- Overall posture — one sentence (e.g., "The environment is Substantially Compliant with 2 Audit Blockers in PA 6 and PA 8 that must be remediated before the next triennial audit.")
- Biggest risk — what would an auditor flag first?
- Strongest areas — what's working
- The remediation ask — how much work and what kind (configuration vs organizational vs architectural)

Follow with the summary table:

```markdown
## Summary of Findings

| Policy Area | Status | Audit Blockers | Finding Risks | Gaps |
|---|---|---|---|---|
| PA 4 — Auditing | Substantially Compliant | 0 | 1 | 2 |
| PA 5 — Access Control | Compliant | 0 | 0 | 1 |
| PA 6 — Authentication | **Non-Compliant** | 1 | 2 | 0 |
| PA 7 — Config Management | At Risk | 0 | 2 | 3 |
| PA 8 — Media Protection | Substantially Compliant | 0 | 1 | 1 |
| PA 10 — Systems & Comms | Compliant | 0 | 0 | 2 |
| **TOTAL** | — | **1** | **6** | **9** |

**Top 3 items to remediate before audit:**
1. {First Audit Blocker — PA, check ID, one-line fix}
2. {Second item}
3. {Third item}
```

---

## Section 3: Per-Policy-Area Findings

One subsection per PA that was assessed. Fixed structure:

```markdown
## PA {N} — {Name}

**Status**: {Compliant | Substantially Compliant | At Risk | Non-Compliant | Not Assessed}
**Checks executed**: {n} — {passed} passed, {failed} failed, {na} N/A, {unable} unable to assess

### Findings

| ID | Check | Severity | Resource(s) | Finding | Remediation |
|---|---|---|---|---|---|
| PA6-01 | MFA on IAM users | AUDIT BLOCKER | 3 users | Users {a,b,c} have console access without MFA | Attach MFA-required policy; remediate within 24 hrs |
| PA6-02 | Password policy | FINDING RISK | account-level | Min length is 12, CJIS requires ≥20 | `aws iam update-account-password-policy --minimum-password-length 20` |
| PA6-03 | Root MFA | INFO | root | MFA enabled ✅ | — |

### Organizational items

Any checks for this PA that are organizational rather than technical — surface them as questions the user must answer offline:

- [ ] Do all personnel with CJI access have current fingerprint-based background checks? (PA 12)
- [ ] Is the CJIS Security Addendum on file with AWS for {state}? (PA 1)
```

Severity badges in the `Severity` column should be **bolded** for `AUDIT BLOCKER` and plain text for the rest, so the worst items jump out on a scan.

If `Status = Not Assessed`, explain why in a single line below the header (e.g., "Skipped — service not present in this account" or "Skipped — organizational-only PA, see questionnaire").

---

## Section 4: Remediation Roadmap

```markdown
## Remediation Roadmap

### Immediate (0-2 weeks) — Audit Blockers + Quick Wins

| Item | PA | Severity | Effort | Owner |
|---|---|---|---|---|
| Enable MFA for 3 non-compliant IAM users | PA 6 | AUDIT BLOCKER | 1 (mins) | IAM admin |
| Encrypt 2 unencrypted RDS instances (snapshot → restore) | PA 8 | AUDIT BLOCKER | 3 (days) | DBA |

### Short-term (2-8 weeks) — Finding Risks

| Item | PA | Severity | Effort | Owner |
|---|---|---|---|---|
| Tighten password policy to 20-char minimum | PA 6 | FINDING RISK | 1 (mins) | IAM admin |
| Enable VPC Flow Logs on 2 VPCs | PA 4 | FINDING RISK | 1 (mins) | Network |

### Medium-term (2-6 months) — Gaps and architectural items

| Item | PA | Severity | Effort | Owner |
|---|---|---|---|---|
| Adopt VPC endpoints to eliminate internet egress | PA 10 | GAP | 3 (days) | Network |

### Long-term (6-12 months) — Organizational & strategic

- [ ] Establish formal IR tabletop schedule (PA 3)
- [ ] Document Management Control Agreement with {contractor} (PA 1)
- [ ] Refresh personnel security screening process (PA 12)
```

Sort each phase by severity (Audit Blocker first) then by effort (lowest first) so Quick Wins bubble up.

---

## Section 5: Organizational Questionnaire

The organizational PAs that cannot be assessed technically. Present as a checklist that the user needs to walk through with their CSO and HR. Pull directly from `references/readiness-checklist.md`, filtered to the PAs not covered by the technical scan.

```markdown
## Organizational Readiness — User Action Required

These items cannot be verified from AWS APIs. Work with your CSO, TAC, and HR to confirm each.

### PA 1 — Information Exchange Agreements
- [ ] CJIS Security Addendum on file with AWS for {state}
- [ ] MCA in place with any contractors accessing CJI
- [ ] All contractor personnel individually signed the Security Addendum

### PA 2 — Security Awareness Training
- [ ] ...
```

---

## Section 6: Appendix — Raw Check Results

Include the full list of check IDs, the CLI command executed, the raw result, and the severity determination. This is audit evidence — don't truncate.

```markdown
## Appendix A: Raw Check Results

### PA6-01 — MFA on IAM users

**Command**:
```
aws iam list-users --query 'Users[].UserName' --output text | while read u; do
  mfa=$(aws iam list-mfa-devices --user-name "$u" --query 'MFADevices[0].SerialNumber' --output text)
  [ "$mfa" = "None" ] && echo "$u: NO MFA"
done
```

**Result**:
```
alice: NO MFA
bob: NO MFA
charlie: NO MFA
```

**Severity**: AUDIT BLOCKER — PA 6 Advanced Authentication requires MFA on all CJI-adjacent access.

---
```

---

## Section 7: Methodology & Caveats

One short page explaining:
- What the scan did and didn't do (read-only, specific PAs, single account/region)
- Which PAs are organizational and not covered by technical checks
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
- Never use emoji severity icons in the machine-readable tables — they break downstream parsing. Emoji OK in the Executive Summary prose only.
