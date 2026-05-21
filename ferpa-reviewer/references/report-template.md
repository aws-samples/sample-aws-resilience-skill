# FERPA Assessment Report Template

> Based on 34 CFR Part 99 (FERPA), PTAC "Data Security Checklist," and NIST SP 800-171.
> Last verified against official sources: 2025-05-15.
> Check https://studentprivacy.ed.gov/ for PTAC updates and https://www.ecfr.gov/current/title-34/subtitle-A/part-99 for regulation changes.

Use this template verbatim when emitting the final Markdown report. A consistent shape is what makes reports reproducible across engagements and auditable as DPA-review, state-contract-attestation, or SPPO-response evidence.

Output path: `ferpa-reports/ferpa-assessment-{YYYY-MM-DD}.md`

---

## Section 1: Assessment Metadata

```markdown
# FERPA Compliance Assessment

**Report date**: {YYYY-MM-DD}
**Assessor**: {name or "Kiro FERPA Skill"}
**Target account**: {account_id}
**Target region(s)**: {regions}
**Region residency**: {US | non-US (flagged)}
**Role**: {EdTech vendor | K-12 district | Higher-ed institution}
**States in scope**: {list of states, or "Not specified"}
**FERPA version referenced**: 20 U.S.C. § 1232g; 34 CFR Part 99
**Reference frameworks**: PTAC Data Security Checklist; NIST SP 800-171 R2
**Assessment mode**: {Quick Scan | Standard | Full | Questionnaire}
**Control domains assessed**: {FCD list}
**Credentials used**: {role ARN} (read-only verified ✅)
**COPPA scope**: {Yes — flagged for separate review | No}
```

---

## Section 2: Executive Summary

Two-paragraph prose summary written for a CIO/CSO/General Counsel audience. NOT a list. Cover:
- Overall posture — one sentence (e.g., "The environment is Substantially Compliant with 2 Breach Risks in FCD 6 and FCD 7 that must be remediated before signing the {state} district DPA.")
- Biggest risk — what would a state AG or SPPO investigator flag first?
- Strongest areas — what's working
- The remediation ask — how much work and what kind (configuration vs organizational vs architectural)
- State-contract implications — any state laws in scope that add requirements beyond baseline

Follow with the summary table:

```markdown
## Summary of Findings

| Control Domain | Status | Breach Risks | Compliance Gaps | Hardening Gaps |
|---|---|---|---|---|
| FCD 3 — Disclosure Controls | Substantially Compliant | 0 | 1 | 2 |
| FCD 4 — Auditing & §99.32 Log | **Non-Compliant** | 1 | 2 | 1 |
| FCD 5 — Access Control | Compliant | 0 | 0 | 1 |
| FCD 6 — Authentication | **Non-Compliant** | 1 | 2 | 0 |
| FCD 7 — Encryption | Substantially Compliant | 0 | 1 | 1 |
| FCD 8 — Retention & Destruction | At Risk | 0 | 2 | 3 |
| **TOTAL** | — | **2** | **8** | **8** |

**Top 3 items to remediate before next DPA signing / contract review:**
1. {First Breach Risk — FCD, check ID, one-line fix}
2. {Second item}
3. {Third item}
```

---

## Section 3: Per-FCD Findings

One subsection per FCD that was assessed. Fixed structure:

```markdown
## FCD {N} — {Name}

**Status**: {Compliant | Substantially Compliant | At Risk | Non-Compliant | Not Assessed}
**Checks executed**: {n} — {passed} passed, {failed} failed, {na} N/A, {unable} unable to assess

### Findings

| ID | Check | Severity | Resource(s) | Finding | Remediation |
|---|---|---|---|---|---|
| FCD6-01 | Root MFA | BREACH RISK | root account | Root MFA not enabled | Enable hardware MFA on root; documented procedure for break-glass |
| FCD6-03 | MFA on IAM users | BREACH RISK | 3 users | Users {a,b,c} have console access without MFA | Attach MFA-required policy; remediate within 24 hrs |
| FCD6-04 | Password policy | COMPLIANCE GAP | account-level | Min length 12, baseline 14 | `aws iam update-account-password-policy --minimum-password-length 14` |
| FCD6-01 (pass) | Root MFA | INFO | root | MFA enabled ✅ | — |

### Organizational items

Any checks for this FCD that are organizational rather than technical — surface them as questions the user must answer offline:

- [ ] Does your application emit a §99.32 disclosure log for every student-record disclosure? (FCD 4)
- [ ] Is your current DPA subprocessor list aligned with the cross-account shares detected in FCD 3? (FCD 3 / FCD 10)
```

Severity column: **bold** `BREACH RISK` entries; plain text for the rest, so the worst items jump out on a scan.

If `Status = Not Assessed`, explain why in a single line below the header (e.g., "Skipped — service not present in this account" or "Skipped — organizational-only FCD, see questionnaire").

---

## Section 4: Remediation Roadmap

```markdown
## Remediation Roadmap

### Immediate (0-2 weeks) — Breach Risks + Quick Wins

| Item | FCD | Severity | Effort | Owner |
|---|---|---|---|---|
| Enable root MFA | FCD 6 | BREACH RISK | 1 (mins) | IAM admin |
| Enable MFA for 3 non-compliant IAM users | FCD 6 | BREACH RISK | 1 (mins) | IAM admin |
| Apply S3 public-access-block account-wide | FCD 5 | BREACH RISK | 1 (mins) | Platform team |

### Short-term (2-8 weeks) — Compliance Gaps

| Item | FCD | Severity | Effort | Owner |
|---|---|---|---|---|
| Tighten password policy to 14-char minimum | FCD 6 | COMPLIANCE GAP | 1 (mins) | IAM admin |
| Enable VPC Flow Logs on 2 VPCs | FCD 4 | COMPLIANCE GAP | 1 (mins) | Network |
| Design and deploy §99.32 application-level disclosure log | FCD 4 | COMPLIANCE GAP | 3 (days) | Application team |

### Medium-term (2-6 months) — Hardening & architectural items

| Item | FCD | Severity | Effort | Owner |
|---|---|---|---|---|
| Adopt VPC endpoints to eliminate internet egress | FCD 3 | HARDENING GAP | 3 (days) | Network |
| Migrate to per-district CMKs for crypto-shred | FCD 8 | HARDENING GAP | 4 (weeks) | Platform team |

### Long-term (6-12 months) — Organizational & strategic

- [ ] Execute DPAs with all current district customers (FCD 10)
- [ ] Annual FERPA training for all personnel with student-data access (FCD 2)
- [ ] Formal IR tabletop exercise with state-contract scenario (FCD 9)
- [ ] Subprocessor register documented and published to customers (FCD 10)
```

Sort each phase by severity (Breach Risk first) then by effort (lowest first) so Quick Wins bubble up.

---

## Section 5: Organizational Questionnaire

The organizational FCDs that cannot be assessed technically. Present as a checklist to walk through with the CISO, Legal, and Privacy Officer. Pull directly from `references/readiness-checklist.md`, filtered to the FCDs not covered by the technical scan.

```markdown
## Organizational Readiness — User Action Required

These items cannot be verified from AWS APIs. Work with Legal, the Privacy Officer, Customer Success, and HR to confirm each.

### FCD 1 — Directory Information & Consent Management
- [ ] Annual directory-information notice delivered to parents/eligible students (K-12/higher-ed)
- [ ] Opt-out signals received from the district flow through to all data stores
- [ ] Data-model documents which fields are designated directory information vs protected PII

### FCD 2 — Student/Parent Rights
- [ ] Inspect-and-review procedure documented; 45-day SLA achievable
- [ ] Amendment procedure documented; hearing process in place if a request is denied
- [ ] ...
```

---

## Section 6: State-Law Addendum Rollup

For each state declared in Phase 1, surface incremental requirements from `references/state-law-addenda.md`:

```markdown
## State-Specific Requirements

### California — SOPIPA (BP Code §22584)
Effective since 2016. Applies to operators of websites, services, or applications used primarily for K-12.
Incremental requirements beyond federal FERPA:
- No targeted advertising based on student data
- No building a profile for non-educational purposes
- No selling of student information
- Maintain "reasonable security procedures" (BP Code §22584(b)(4))

Assessment of these controls: {summary, flagging any that this environment cannot yet evidence}

### New York — Education Law §2-d
Applies to any educational agency's service providers. Incremental:
- Parent's Bill of Rights to be appended to every contract
- 3rd-party contract must include specific security clauses (encryption, training, PII use limits, data return/destruction)
- Data breach notification to NYSED in addition to parents

Assessment: {summary}

### Texas — SB 820 + TX-RAMP
...
```

If no states declared, omit this section.

---

## Section 7: Appendix — Raw Check Results

Include the full list of check IDs, the CLI command executed, the raw result, and the severity determination. This is audit evidence — don't truncate.

```markdown
## Appendix A: Raw Check Results

### FCD6-01 — Root MFA

**Command**:
```
aws iam get-account-summary --query 'SummaryMap.AccountMFAEnabled' --output text
```

**Result**:
```
0
```

**Severity**: BREACH RISK — Root account without MFA exposes the entire student-data environment to single-credential compromise. PTAC and all state DPA baselines require MFA on root.

**Remediation**: Enable a hardware MFA device on the root account via the Security Credentials console page. Store the device in a secured location per the organization's break-glass procedure. Do not re-enable root access keys.

---

### FCD4-10 — §99.32 disclosure log (application-level)

**Command**: (heuristic — detect dedicated log groups)
```
aws logs describe-log-groups --log-group-name-prefix "/ferpa/" ...
```

**Result**:
```
(empty)
```

**Severity**: BREACH RISK — No §99.32 disclosure log detected. 34 CFR §99.32 requires the school (and any party acting for the school) to maintain a record of each request for access and each disclosure of education records. CloudTrail logs API calls; it does not satisfy §99.32 on its own.

**Remediation**: Design and deploy an application-level disclosure log emitting structured events `{timestamp, student_id, requestor, purpose, §99.31_exception, records[]}` to a dedicated CloudWatch log group backed by an S3 bucket with Object Lock. Expose query capability for DSARs.

---
```

---

## Section 8: Methodology & Caveats

One short page explaining:
- What the scan did and didn't do (read-only, specific FCDs, single account/region)
- Which FCDs are organizational and not covered by technical checks
- That FERPA enforcement varies — federal SPPO is complaint-driven; state laws impose their own requirements; DPAs impose contractual requirements. Final compliance determination always rests with Legal.
- Timestamp and assessor info so this report is dated and traceable
- Disclaimer: "This report is a point-in-time snapshot of technical configuration. It does not replace legal review of DPAs, a formal SOC 2 Type II engagement, or formal counsel on FERPA or state-law compliance questions."

---

## Formatting conventions

- Dates: `YYYY-MM-DD` (ISO)
- ARNs and resource IDs: backticks
- Severity labels: uppercase (`BREACH RISK`, `COMPLIANCE GAP`, `HARDENING GAP`, `INFO`)
- Status labels: title case (`Non-Compliant`, `At Risk`, `Substantially Compliant`, `Compliant`)
- Commands: fenced code blocks with `bash`
- Never use emoji severity icons in the machine-readable tables — they break downstream parsing. Emoji OK in the Executive Summary prose only.
- Regulation citations: use `§` and full citation on first use (e.g., "34 CFR §99.32"); subsequent uses may abbreviate to `§99.32`.
