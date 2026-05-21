# CJIS Reviewer

CJIS Security Policy compliance assessor for AWS environments handling Criminal Justice Information (CJI). Runs a read-only 4-phase assessment (Bootstrap → Discover → Analyze → Report) using `Describe`/`Get`/`List` AWS CLI calls, identifies gaps across NIST SP 800-53 control families as defined in CJIS v6.0, and produces a remediation report.

Built for law enforcement agencies, criminal justice organizations, and technology partners handling CJI on AWS. Aligned with FBI CJIS Security Policy v6.0 (effective December 2024).

> **Advisory tool, not a compliance determination.** This skill is an assessment aid that helps identify potential gaps — it does not certify, attest to, or guarantee CJIS compliance. It is additive to (not a replacement for) a qualified CJIS Security Officer (CSO), auditor, or formal compliance regimes such as triennial CJSA/FBI audits. Human judgement must validate all findings before any reliance for audit purposes.

## When to use

Triggers on: "CJIS", "CJIS compliance", "criminal justice data", "CJIS audit prep", "FBI CJIS", "CHRI on AWS", "CJIS on GovCloud", "advanced authentication for CJI", "FIPS 140-2 for law enforcement", "Management Control Agreement", "CJI security".

Also handles control-family-specific questions (AC, AU, IA, CM, SC, SI, CP, IR, etc.).

## Assessment modes

| Mode | Families covered | Time | Use when |
|---|---|---|---|
| **Quick Scan** | IA + SC + AC (P1 families) | ~10 min | Audit-risk triage |
| **Standard** (default) | IA + SC + AC + AU + CM + SI | ~25 min | Gap assessment, pre-audit dry run |
| **Full** | Standard + CP + questionnaire | ~40 min | Pre-triennial audit, new CJI deployment |
| **Questionnaire-only** | Organizational families | ~15 min | No AWS access, paper-based review |

## How to run

1. **Prerequisites**: AWS CLI installed, credentials with read-only access (e.g., `SecurityAudit` managed policy). The skill enforces a credential boundary check — it will refuse to run if write permissions are detected.
2. **Start**: Tell your AI coding assistant "Assess my environment for CJIS compliance"
3. **Answer the bootstrap questions**: Account/region, state CSA, scan mode, and which data stores hold CJI
4. **Wait**: Phases 2-4 run automatically
5. **Get the report**: Output lands in `cjis-reports/cjis-assessment-{YYYY-MM-DD}.md`

Optional HTML render for a polished deliverable:

```bash
python3 scripts/generate-html-report.py cjis-reports/cjis-assessment-{date}.md
```

## Output

1. Per-family compliance status (Compliant / Substantially Compliant / At Risk / Non-Compliant)
2. Findings classified by severity (Audit Blocker / Finding Risk / Gap / Info)
3. Prioritized remediation roadmap in 4 phases (Immediate → Short-term → Medium-term → Long-term)
4. Organizational questionnaire for non-technical families
5. Full evidence appendix (raw check results)

## Guard rails

- **Read-only only** — all AWS operations are `Describe`/`Get`/`List`/`BatchGet`. No mutations.
- **Credential boundary check** — mandatory, non-skippable. If write permissions are detected, the skill halts before any checks run.
- **GovCloud detection** — automatically identifies whether the environment uses GovCloud (FIPS endpoints by default) or commercial partition, and adjusts SC findings accordingly.

## CJIS v6.0 structure

CJIS v6.0 (December 2024) replaced the old "13 Policy Areas" with NIST SP 800-53 control families. This skill assesses the 7 technically-assessable families:

| Family | Name | Priority |
|---|---|---|
| IA | Identification and Authentication | P1 |
| SC | Systems and Communications Protection | P1 |
| AC | Access Control | P1 |
| AU | Audit and Accountability | P2 |
| CM | Configuration Management | P1 |
| SI | System and Information Integrity | P1 |
| CP | Contingency Planning | P2 |

Organizational families (AT, PE, PS, IR, MA, PL, SA, SR, CA) are covered via questionnaire in Full mode.

## Reference files

Loaded on demand to keep context lean:

- `references/control-families.md` — overview of all 18 control families
- `references/aws-service-mapping.md` — CJIS requirement → AWS service matrix
- `references/readiness-checklist.md` — full readiness list by family
- `references/severity-classification.md` — priority-aligned severity levels and aggregate status rubric
- `references/report-template.md` — fixed 7-section report structure
- `references/credential-boundary.md` — read-only IAM gate logic
- `references/programmatic-checks/{family}-*.md` — per-family automated check definitions

See `SKILL.md` for the full skill definition and workflow details.
