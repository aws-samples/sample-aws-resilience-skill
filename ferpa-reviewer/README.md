# FERPA Reviewer

FERPA compliance assessor for AWS environments handling student education records. Runs a read-only 4-phase assessment (Bootstrap → Discover → Analyze → Report) using `Describe`/`Get`/`List` AWS CLI calls, identifies gaps against the 10 FERPA Control Domains, and produces a remediation report.

Built for EdTech vendors operating as "school officials," K-12 districts, and higher-ed institutions. Covers 34 CFR Part 99, PTAC guidance, and the NIST SP 800-171 baseline most state contracts adopt.

> **Advisory tool, not a compliance determination.** This skill is an assessment aid that helps identify potential gaps — it does not certify, attest to, or guarantee FERPA compliance. It is additive to (not a replacement for) qualified legal counsel, institutional compliance officers, and formal compliance regimes such as SOC 2 Type II engagements or state-contract annual reviews. Human judgement must validate all findings before any reliance for audit or contractual purposes.

## When to use

Triggers on: "FERPA", "FERPA compliance", "student data privacy", "education records", "student PII", "FERPA assessment", "DPA review", "SPPO complaint", "PTAC checklist", "K-12 data privacy", "higher-ed data privacy", "SIS on AWS", "LMS compliance".

Also handles state-specific questions for SOPIPA (CA), Ed Law 2-d (NY), SB 820 (TX), and SOPPA (IL).

## Assessment modes

| Mode | FCDs covered | Time | Use when |
|---|---|---|---|
| **Quick Scan** | 4, 5, 6, 7 | ~10 min | Breach-risk triage |
| **Standard** (default) | 3, 4, 5, 6, 7, 8 | ~25 min | Gap assessment, pre-contract review |
| **Full** | All 10 (scan + questionnaire) | ~40 min | DPA signing, annual attestation, SPPO response |
| **Questionnaire-only** | Organizational FCDs | ~15 min | No AWS access, paper-based review |

## How to run

1. **Prerequisites**: AWS CLI installed, credentials with read-only access (e.g., `SecurityAudit` managed policy). The skill enforces a credential boundary check — it will refuse to run if write permissions are detected.
2. **Start**: Tell your AI coding assistant "Assess my environment for FERPA compliance"
3. **Answer the bootstrap questions**: Your role (vendor/K-12/higher-ed), account/region, US states in scope, scan mode, and which data stores hold student records
4. **Wait**: Phases 2-4 run automatically
5. **Get the report**: Output lands in `ferpa-reports/ferpa-assessment-{YYYY-MM-DD}.md`

Optional HTML render for a polished deliverable:

```bash
python3 scripts/generate-html-report.py ferpa-reports/ferpa-assessment-{date}.md
```

## Output

1. Per-FCD compliance status (Compliant / Substantially Compliant / At Risk / Non-Compliant)
2. Findings classified by severity (Breach Risk / Compliance Gap / Hardening Gap / Info)
3. Prioritized remediation roadmap in 4 phases (Immediate → Short-term → Medium-term → Long-term)
4. State-law addendum rollup for in-scope states
5. Organizational questionnaire for non-technical FCDs
6. Full evidence appendix (raw check results)

## Guard rails

- **Read-only only** — all AWS operations are `Describe`/`Get`/`List`/`BatchGet`. No mutations.
- **Credential boundary check** — mandatory, non-skippable. If write permissions are detected, the skill halts before any checks run.
- **COPPA scope-out** — flags under-13 data for downstream review but does not assess COPPA compliance (FERPA-only in v1).

## Reference files

Loaded on demand to keep context lean:

- `references/control-domains.md` — deep-dive on all 10 FCDs
- `references/aws-service-mapping.md` — FERPA requirement → AWS service matrix
- `references/readiness-checklist.md` — full readiness list by FCD
- `references/state-law-addenda.md` — SOPIPA, Ed Law 2-d, SB 820, SOPPA overlays
- `references/severity-classification.md` — severity levels and aggregate status rubric
- `references/report-template.md` — fixed 8-section report structure
- `references/credential-boundary.md` — read-only IAM gate logic
- `references/programmatic-checks/fcd-{03-08}-*.md` — per-FCD automated check definitions

See `SKILL.md` for the full skill definition and workflow details.
