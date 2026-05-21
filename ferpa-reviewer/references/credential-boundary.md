# Credential Permission Boundary

> Last verified: 2025-05-15.

## Principle

The FERPA assessment operates in **strict read-only mode**. Credentials used to run programmatic checks MUST NOT have any write, modify, or delete permissions — a compliance tool that could accidentally mutate a production system containing student education records is itself a breach risk.

This is a non-skippable gate at Phase 1 (Bootstrap). If the check fails, HALT the assessment and ask the user for compliant credentials.

## Why this matters for FERPA specifically

- **Student records are protected the moment the environment touches them.** Unlike infrastructure that can be "restored from backup," an unauthorized modification to a student record is itself a potential §99.32 misdisclosure event — the tool that caused it must then be logged as the party that made the change.
- **State EdTech DPAs commonly prohibit non-break-glass write access to production.** A vendor running this skill with write-capable creds may be violating its own DPA with every district in the contract.
- **Incident response posture.** A production environment containing education records is often under elevated change control after a security event. A read-only audit tool fits cleanly into that posture; a write-capable one does not.
- **State AG breach-notification statutes are triggered by unauthorized acquisition or access.** Even a well-intentioned accidental write by an assessment tool could surface in breach-scope analysis. Don't create that problem.

## Allowed IAM policies

| Policy ARN | Description |
|---|---|
| `arn:aws:iam::aws:policy/ReadOnlyAccess` | Full read-only across all services |
| `arn:aws:iam::aws:policy/ViewOnlyAccess` | View-only (slightly more restrictive) |
| `arn:aws:iam::aws:policy/SecurityAudit` | Security-focused read-only — recommended for this skill |
| Custom read-only policy | Must contain ONLY `Describe` / `Get` / `List` / `BatchGet` actions |

## Blocked IAM policies

| Policy ARN / Pattern | Reason |
|---|---|
| `arn:aws:iam::aws:policy/AdministratorAccess` | Full admin — never acceptable |
| `arn:aws:iam::aws:policy/PowerUserAccess` | Write access to most services |
| Any `*:Create*`, `*:Update*`, `*:Delete*`, `*:Put*`, `*:Modify*` | Write actions |
| Inline policies containing `"Action": "*"` or `"Action": "<svc>:*"` | Unbounded — assume write |

## Validation logic

```python
ALLOWED_PREFIXES = {"Describe", "Get", "List", "BatchGet"}
BLOCKED_PREFIXES = {
    "Create", "Update", "Delete", "Put", "Modify", "Start", "Stop",
    "Terminate", "Reboot", "Run", "Invoke", "Execute", "Send", "Publish",
    "Tag", "Untag", "Attach", "Detach", "Associate", "Disassociate",
}

def is_read_only(actions: list[str]) -> bool:
    for action in actions:
        verb = action.split(":", 1)[1] if ":" in action else action
        if verb == "*":
            return False
        if any(verb.startswith(p) for p in BLOCKED_PREFIXES):
            return False
    return True
```

## How to check in practice

1. `aws sts get-caller-identity` — record the principal ARN.
2. For an IAM user: `aws iam list-attached-user-policies` + `aws iam list-user-policies` (inline).
3. For an IAM role: `aws iam list-attached-role-policies` + `aws iam list-role-policies` (inline).
4. For each policy ARN, `aws iam get-policy-version` → scan the `Action` list against `BLOCKED_PREFIXES`.
5. If any blocked action or `*` is present → HALT.

## Boundary violation message

```
🚨 PERMISSION BOUNDARY VIOLATION

Your credentials ({arn}) have write permissions that exceed the read-only
boundary required for this FERPA assessment.

Detected write-capable policies:
{policy_list}

The assessment CANNOT proceed because:
  • Write permissions could accidentally modify a system containing student
    education records — itself a §99.32 misdisclosure risk
  • Most state EdTech DPAs prohibit non-break-glass write access to production
    environments containing student data
  • This assessment is designed to be 100% non-destructive

ACTION REQUIRED:
  1. Create an IAM role with ReadOnlyAccess or SecurityAudit policy
  2. Assume that role (or configure new credentials for it)
  3. Re-run the assessment

Example:
  aws iam create-role --role-name FERPAAssessmentReadOnly \
    --assume-role-policy-document file://trust-policy.json
  aws iam attach-role-policy --role-name FERPAAssessmentReadOnly \
    --policy-arn arn:aws:iam::aws:policy/SecurityAudit
```

## Exceptions — metadata-only actions that look like writes

These are explicitly allowed because they produce reports/identity info without changing infrastructure:

- `sts:GetCallerIdentity` — identity verification
- `sts:GetSessionToken` / `sts:AssumeRole` — session management
- `iam:GenerateCredentialReport` — generates an IAM report, does not modify IAM
- `iam:GenerateServiceLastAccessedDetails` — analysis job, no mutation

## Region residency signal

FERPA itself does not require US region residency. Many state EdTech DPAs do (CA SOPIPA, NY Ed Law 2-d, TX SB 820, and most state-specific school-vendor contract templates). During Phase 1, after validating read-only permissions:

- If the caller's STS endpoint and enumerated resources are in non-US regions → flag as a potential state-contract gap (not a federal FERPA finding). Do not HALT — surface it in the bootstrap summary and carry it into the Phase 2 findings.
- If the user is explicitly operating under a state framework requiring FIPS endpoints (StateRAMP, TX-RAMP L2) → recommend setting `AWS_USE_FIPS_ENDPOINT=true` and using `<service>-fips.<region>.amazonaws.com` endpoints for the scan itself.

## If the user insists on running with write credentials

Do not proceed. Explain the risk and offer two alternatives:

1. **Questionnaire mode** — no automated checks; walk the user through the readiness checklist manually.
2. **Give the user the commands** — emit the full list of `aws` CLI commands the assessment would have run, so they can execute them in a separate shell with the correct read-only credentials and paste results back.
