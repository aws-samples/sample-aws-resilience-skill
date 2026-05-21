# Credential Permission Boundary

> Based on CJIS Security Policy v6.0 (effective December 2024).
> Last verified against official source: 2026-05-21.
> Check https://le.fbi.gov/cjis-division/cjis-security-policy-resource-center for newer versions.

## Principle

The CJIS assessment operates in **strict read-only mode**. Credentials used to run programmatic checks MUST NOT have any write, modify, or delete permissions — a compliance tool that could accidentally mutate a CJI-handling environment defeats its own purpose.

This is a non-skippable gate at Phase 1 (Bootstrap). If the check fails, HALT the assessment and ask the user for compliant credentials.

## Why this matters for CJIS specifically

- CJI environments are frequently under change-freeze ahead of triennial audits. Unintentional modifications can invalidate the audit.
- Writing to a CJI resource without a documented change ticket is itself a Policy Area 7 (Configuration Management) finding.
- AWS GovCloud customer accounts often have SCPs that require a specific role for any write action — using a write-capable role for a read-only audit crosses that boundary.

## Allowed IAM policies

| Policy ARN | Description |
|---|---|
| `arn:aws:iam::aws:policy/ReadOnlyAccess` | Full read-only across all services |
| `arn:aws:iam::aws:policy/ViewOnlyAccess` | View-only (slightly more restrictive) |
| `arn:aws:iam::aws:policy/SecurityAudit` | Security-focused read-only |
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
boundary required for this CJIS assessment.

Detected write-capable policies:
{policy_list}

The assessment CANNOT proceed because:
  • Write permissions could accidentally modify your CJI environment
  • CJIS environments under audit must not be mutated without change control
  • This assessment is designed to be 100% non-destructive

ACTION REQUIRED:
  1. Create an IAM role with ReadOnlyAccess or SecurityAudit policy
  2. Assume that role (or configure new credentials for it)
  3. Re-run the assessment

Example:
  aws iam create-role --role-name CJISAssessmentReadOnly \
    --assume-role-policy-document file://trust-policy.json
  aws iam attach-role-policy --role-name CJISAssessmentReadOnly \
    --policy-arn arn:aws:iam::aws:policy/SecurityAudit
```

## Exceptions — metadata-only actions that look like writes

These are explicitly allowed because they produce reports/identity info without changing infrastructure:

- `sts:GetCallerIdentity` — identity verification
- `sts:GetSessionToken` / `sts:AssumeRole` — session management
- `iam:GenerateCredentialReport` — generates an IAM report, does not modify IAM
- `iam:GenerateServiceLastAccessedDetails` — analysis job, no mutation

## If the user insists on running with write credentials

Do not proceed. Explain the risk and offer two alternatives:

1. **Questionnaire mode** — no automated checks; walk the user through the readiness checklist manually.
2. **Give the user the commands** — emit the full list of `aws` CLI commands the assessment would have run, so they can execute them in a separate shell with the correct read-only credentials and paste results back.
