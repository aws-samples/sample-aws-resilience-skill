# PA 6 — Identification and Authentication — Programmatic Checks

> Execute in order. Read-only AWS CLI. Severity per [`../severity-classification.md`](../severity-classification.md).

CJIS PA 6 (Section 5.6) — **this is the #1 audit-finding PA nationwide**. Core requirements:
- Advanced Authentication (MFA) at the point of CJI access
- Unique IDs (no shared accounts)
- Password policy: complexity, ≤90-day age, lockout after 5 failed attempts
- Root account locked down

---

## PA6-01: Root account MFA enabled

```bash
aws iam get-account-summary --query 'SummaryMap.AccountMFAEnabled' --output text
```

| Result | Severity | Finding |
|---|---|---|
| `0` | AUDIT BLOCKER | Root account MFA not enabled — immediate audit fail |
| `1` | INFO | Root MFA enabled ✅ |

---

## PA6-02: Root account has no active access keys

```bash
aws iam get-account-summary --query 'SummaryMap.AccountAccessKeysPresent' --output text
```

| Result | Severity | Finding |
|---|---|---|
| `1` | AUDIT BLOCKER | Root access keys exist — must be deleted (PA 6 + AWS best practice) |
| `0` | INFO | No root access keys ✅ |

---

## PA6-03: All IAM users with console access have MFA

```bash
aws iam generate-credential-report >/dev/null 2>&1; sleep 2
aws iam get-credential-report --query Content --output text | base64 -d > /tmp/cred-report.csv
# Columns: user, arn, user_creation_time, password_enabled, password_last_used,
#   password_last_changed, password_next_rotation, mfa_active, ...
awk -F',' 'NR>1 && $4=="true" && $8=="false" {print $1}' /tmp/cred-report.csv
```

| Result | Severity | Finding |
|---|---|---|
| Any users with `password_enabled=true, mfa_active=false` | AUDIT BLOCKER | {count} IAM users have console access without MFA |
| All console users have MFA | INFO | MFA enforced on all IAM console users ✅ |

Note: CJIS requires MFA at the point of CJI access. If a user has console access but only touches non-CJI resources, the finding is still an AUDIT BLOCKER unless the user can demonstrate policy-level separation. Err on the strict side.

---

## PA6-04: IAM password policy meets CJIS minimums

```bash
aws iam get-account-password-policy --output json 2>/dev/null
```

CJIS-aligned thresholds (the stricter of CJIS Section 5.6.2.1.1 and common state CSA addenda):
- `MinimumPasswordLength` ≥ 20 (some states accept 12; 20 is the conservative benchmark)
- `RequireSymbols`, `RequireNumbers`, `RequireUppercaseCharacters`, `RequireLowercaseCharacters` all `true`
- `MaxPasswordAge` ≤ 90
- `PasswordReusePrevention` ≥ 10

| Result | Severity | Finding |
|---|---|---|
| No policy set (`NoSuchEntity`) | AUDIT BLOCKER | No IAM password policy configured |
| `MinimumPasswordLength < 12` | AUDIT BLOCKER | Password minimum length below CJIS floor |
| `MinimumPasswordLength < 20` | FINDING RISK | Password length below strict benchmark (20 chars) |
| Missing any complexity flag | FINDING RISK | Password policy missing complexity requirements |
| `MaxPasswordAge > 90` or unset | FINDING RISK | Password age exceeds 90 days |
| `PasswordReusePrevention < 10` | GAP | Password reuse prevention below recommended (10+) |
| All thresholds met | INFO | Password policy CJIS-compliant ✅ |

---

## PA6-05: Access key age ≤ 90 days

```bash
aws iam generate-credential-report >/dev/null 2>&1; sleep 2
aws iam get-credential-report --query Content --output text | base64 -d > /tmp/cred-report.csv
# Columns 9 and 14 are access_key_1_last_rotated and access_key_2_last_rotated
python3 - <<'PY'
import csv, datetime
now = datetime.datetime.utcnow()
over = []
with open('/tmp/cred-report.csv') as f:
    for row in csv.DictReader(f):
        for k in ('access_key_1_last_rotated', 'access_key_2_last_rotated'):
            v = row.get(k, 'N/A')
            if v in ('N/A', 'no_information', ''): continue
            age = (now - datetime.datetime.strptime(v.split('+')[0].rstrip('Z'), '%Y-%m-%dT%H:%M:%S')).days
            if age > 90:
                over.append((row['user'], k, age))
for u, k, a in over:
    print(f"{u}: {k} age {a}d")
PY
```

| Result | Severity | Finding |
|---|---|---|
| Any key > 180 days | AUDIT BLOCKER | {count} access keys older than 180 days |
| Any key 90-180 days | FINDING RISK | {count} access keys over CJIS 90-day rotation policy |
| All ≤ 90 days | INFO | Access keys within rotation policy ✅ |

---

## PA6-06: No shared / generic IAM users

```bash
aws iam list-users --query 'Users[].{UserName:UserName,Path:Path,CreateDate:CreateDate}' --output json
```

Heuristic: flag user names that look generic (case-insensitive): `admin`, `root`, `shared`, `service`, `ops`, `automation`, `jenkins`, `ci`, `cd`, or names with no vowels/digits only.

| Result | Severity | Finding |
|---|---|---|
| Any user names match the generic list AND have `password_enabled=true` | FINDING RISK | Possible shared IAM user: `{name}` — CJIS requires unique IDs per person |
| No suspicious names | INFO | No obvious shared users detected ✅ |

This is heuristic — always surface the list to the user for confirmation rather than auto-flagging. A named service account (`ci-deploy-prod`) is fine; a human-like but shared account is not.

---

## PA6-07: IAM Identity Center (SSO) configured with MFA

```bash
aws sso-admin list-instances --output json 2>/dev/null
# If an instance exists, check MFA settings for that instance:
aws sso-admin describe-instance-access-control-attribute-configuration --instance-arn {arn} 2>/dev/null
# MFA enforcement lives in IAM Identity Center console; API coverage is limited.
```

| Result | Severity | Finding |
|---|---|---|
| No Identity Center instance, and multiple IAM users detected | GAP | Consider IAM Identity Center for centralized MFA + federation |
| Identity Center instance exists | INFO | Identity Center in use — confirm MFA required (manual check) |
| No Identity Center, single-user account | NOT_APPLICABLE | — |

Identity Center's MFA enforcement setting isn't exposed cleanly via CLI. Mark as a follow-up: "Open the IAM Identity Center console → Settings → Authentication → confirm MFA is 'Required' and 'Every time they sign in'."

---

## PA6-08: No long-unused IAM users

```bash
# Reuse /tmp/cred-report.csv from PA6-03
python3 - <<'PY'
import csv, datetime
now = datetime.datetime.utcnow()
stale = []
with open('/tmp/cred-report.csv') as f:
    for row in csv.DictReader(f):
        last = row.get('password_last_used', 'N/A')
        if last in ('N/A', 'no_information', ''): continue
        age = (now - datetime.datetime.strptime(last.split('+')[0].rstrip('Z'), '%Y-%m-%dT%H:%M:%S')).days
        if age > 90:
            stale.append((row['user'], age))
for u, a in stale:
    print(f"{u}: last login {a}d ago")
PY
```

| Result | Severity | Finding |
|---|---|---|
| Users with login > 90 days | FINDING RISK | {count} IAM users inactive > 90 days — disable or delete (PA 5 + PA 6) |
| All active | INFO | No stale console users ✅ |

---

## Summary

| Check | ID | Key question |
|---|---|---|
| Root MFA | PA6-01 | Is root protected with MFA? |
| Root access keys | PA6-02 | Are root API keys eliminated? |
| User MFA | PA6-03 | Do all console users have MFA? |
| Password policy | PA6-04 | Does the policy meet CJIS thresholds? |
| Key rotation | PA6-05 | Are access keys rotated ≤ 90 days? |
| Shared accounts | PA6-06 | Are all accounts uniquely attributable? |
| Identity Center | PA6-07 | Is federated SSO + MFA in use? |
| Stale users | PA6-08 | Are inactive accounts disabled? |

**Total: 8 checks.** Expected time: ~2 min.
