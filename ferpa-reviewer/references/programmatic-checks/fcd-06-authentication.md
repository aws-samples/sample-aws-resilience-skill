# FCD 6 — Authentication — Programmatic Checks

> Execute in order. Read-only AWS CLI. Severity per [`../severity-classification.md`](../severity-classification.md).

FERPA itself doesn't specify authentication requirements — "reasonable methods." The PTAC "Data Security Checklist," NIST SP 800-171 (3.5.x), and every modern state EdTech DPA establish the baseline:
- MFA for admin access and for any access that touches bulk student records
- Unique IDs — no shared accounts
- Password policy: length, complexity, ≤90-day age, lockout after 5 failed attempts
- Root account locked down

Credential compromise on unMFAed admin accounts is one of the top EdTech breach vectors — treat missing MFA as BREACH RISK.

---

## FCD6-01: Root account MFA enabled

```bash
aws iam get-account-summary --query 'SummaryMap.AccountMFAEnabled' --output text
```

| Result | Severity | Finding |
|---|---|---|
| `0` | BREACH RISK | Root account MFA not enabled — single compromised credential compromises the entire environment |
| `1` | INFO | Root MFA enabled ✅ |

---

## FCD6-02: Root account has no active access keys

```bash
aws iam get-account-summary --query 'SummaryMap.AccountAccessKeysPresent' --output text
```

| Result | Severity | Finding |
|---|---|---|
| `1` | BREACH RISK | Root access keys exist — must be deleted (AWS best practice + state-DPA baseline) |
| `0` | INFO | No root access keys ✅ |

---

## FCD6-03: All IAM users with console access have MFA

```bash
aws iam generate-credential-report >/dev/null 2>&1; sleep 2
aws iam get-credential-report --query Content --output text | base64 -d > /tmp/cred-report.csv
# Columns: user, arn, user_creation_time, password_enabled, password_last_used,
#   password_last_changed, password_next_rotation, mfa_active, ...
awk -F',' 'NR>1 && $4=="true" && $8=="false" {print $1}' /tmp/cred-report.csv
```

| Result | Severity | Finding |
|---|---|---|
| Any users with `password_enabled=true, mfa_active=false` | BREACH RISK | {count} IAM users have console access without MFA — credential-compromise risk to student data |
| All console users have MFA | INFO | MFA enforced on all IAM console users ✅ |

---

## FCD6-04: IAM password policy meets student-data baseline

```bash
aws iam get-account-password-policy --output json 2>/dev/null
```

Student-data baseline (from PTAC + state-DPA common denominators):
- `MinimumPasswordLength` ≥ 14 (some state DPAs accept 12; 14 is the strict modern benchmark)
- `RequireSymbols`, `RequireNumbers`, `RequireUppercaseCharacters`, `RequireLowercaseCharacters` all `true`
- `MaxPasswordAge` ≤ 90
- `PasswordReusePrevention` ≥ 10

| Result | Severity | Finding |
|---|---|---|
| No policy set (`NoSuchEntity`) | BREACH RISK | No IAM password policy configured |
| `MinimumPasswordLength < 12` | BREACH RISK | Password minimum length below minimum baseline |
| `MinimumPasswordLength < 14` | COMPLIANCE GAP | Password length below strict benchmark (14 chars) |
| Missing any complexity flag | COMPLIANCE GAP | Password policy missing complexity requirements |
| `MaxPasswordAge > 90` or unset | COMPLIANCE GAP | Password age exceeds 90 days |
| `PasswordReusePrevention < 10` | HARDENING GAP | Password reuse prevention below recommended (10+) |
| All thresholds met | INFO | Password policy meets student-data baseline ✅ |

---

## FCD6-05: Access key age ≤ 90 days

```bash
aws iam generate-credential-report >/dev/null 2>&1; sleep 2
aws iam get-credential-report --query Content --output text | base64 -d > /tmp/cred-report.csv
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
| Any key > 180 days | BREACH RISK | {count} access keys older than 180 days — rotate or delete immediately |
| Any key 90-180 days | COMPLIANCE GAP | {count} access keys over 90-day rotation baseline |
| All ≤ 90 days | INFO | Access keys within rotation policy ✅ |

---

## FCD6-06: No shared / generic IAM users

```bash
aws iam list-users --query 'Users[].{UserName:UserName,Path:Path,CreateDate:CreateDate}' --output json
```

Heuristic: flag user names that look generic (case-insensitive): `admin`, `root`, `shared`, `service`, `ops`, `automation`, `jenkins`, `ci`, `cd`, or names with no vowels/digits only.

| Result | Severity | Finding |
|---|---|---|
| Any user names match the generic list AND have `password_enabled=true` | COMPLIANCE GAP | Possible shared IAM user: `{name}` — student-data baseline requires unique attributable accounts |
| No suspicious names | INFO | No obvious shared users detected ✅ |

Heuristic — always surface the list to the user for confirmation. A named service account (`ci-deploy-prod`) without console access is fine; a human-like shared console account is not.

---

## FCD6-07: IAM Identity Center (SSO) configured

```bash
aws sso-admin list-instances --output json 2>/dev/null
# If an instance exists:
aws sso-admin describe-instance-access-control-attribute-configuration --instance-arn {arn} 2>/dev/null
```

| Result | Severity | Finding |
|---|---|---|
| No Identity Center instance, and multiple IAM users detected | COMPLIANCE GAP | Consider IAM Identity Center for centralized MFA + federation; long-lived IAM users are an anti-pattern for student-data environments |
| Identity Center instance exists | INFO | Identity Center in use — confirm MFA required (manual check: Console → Settings → Authentication → "Every time they sign in") |
| No Identity Center, single-user admin account | HARDENING GAP | Single-user setup — still acceptable but lacks federation advantages |

Identity Center's MFA enforcement setting isn't exposed cleanly via CLI. Mark as a follow-up: confirm in the console.

---

## FCD6-08: No long-unused IAM users

```bash
# Reuse /tmp/cred-report.csv from FCD6-03
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
| Users with login > 90 days | COMPLIANCE GAP | {count} IAM users inactive > 90 days — disable or delete (FCD 5 + FCD 6) |
| All active | INFO | No stale console users ✅ |

---

## FCD6-09: Cognito user pools enforce MFA (end-user auth)

If the application uses Cognito for student/parent/teacher authentication:

```bash
aws cognito-idp list-user-pools --max-results 60 --query 'UserPools[].{Id:Id,Name:Name}' --output json
# For each pool:
aws cognito-idp describe-user-pool --user-pool-id {id} --query 'UserPool.{MfaConfiguration:MfaConfiguration,Policies:Policies.PasswordPolicy}' --output json
```

| Result | Severity | Finding |
|---|---|---|
| Pool with `MfaConfiguration: OFF` serving admin-class users | BREACH RISK | Cognito pool `{name}` has MFA disabled — admin auth path unprotected |
| Pool `MfaConfiguration: OPTIONAL` | COMPLIANCE GAP | MFA optional — enforce for admin/staff roles |
| Pool `MfaConfiguration: ON` | INFO | MFA enforced on Cognito pool ✅ |
| No Cognito pools | NOT_APPLICABLE | End-user auth not via Cognito |

Note: for student-facing pools (K-12 under-13), MFA may be impractical — surface as a design question: "Is this pool used by students under 13? If so, ensure SSO federation from the district IdP handles auth upstream."

---

## Summary

| Check | ID | Key question |
|---|---|---|
| Root MFA | FCD6-01 | Is root protected with MFA? |
| Root access keys | FCD6-02 | Are root API keys eliminated? |
| User MFA | FCD6-03 | Do all console users have MFA? |
| Password policy | FCD6-04 | Does the policy meet the baseline? |
| Key rotation | FCD6-05 | Are access keys rotated ≤90 days? |
| Shared accounts | FCD6-06 | Are all accounts uniquely attributable? |
| Identity Center | FCD6-07 | Is federated SSO + MFA in use? |
| Stale users | FCD6-08 | Are inactive accounts disabled? |
| Cognito MFA | FCD6-09 | Is end-user auth MFA-protected? |

**Total: 9 checks.** Expected time: ~2 min.
