# IA — Identification and Authentication — Programmatic Checks

> Based on CJIS Security Policy v6.0 (effective December 2024).
> Last verified against official source: 2025-05-21.
> Check https://le.fbi.gov/cjis-division/cjis-security-policy-resource-center for newer versions.

> Execute in order. Each check uses read-only AWS CLI. Record results as
> `COMPLIANT` / `NON_COMPLIANT` / `NOT_APPLICABLE` / `UNABLE_TO_ASSESS` with severity per
> [`../severity-classification.md`](../severity-classification.md).

IA family (Priority P1) — **this is the #1 audit finding area nationwide**. Core requirements: advanced authentication (MFA) at the point of CJI access, unique IDs, password policy, root account lockdown, FIPS 140-2/3 cryptographic modules.

---

## IA-02-01: Root account MFA enabled

**CJIS reference**: CJIS v6.0 IA-2 | **Priority**: P1*

```bash
aws iam get-account-summary --query 'SummaryMap.AccountMFAEnabled' --output text
```

| Result | Severity | Finding |
|---|---|---|
| `0` | AUDIT BLOCKER | Root account MFA not enabled — immediate audit fail |
| `1` | INFO | Root MFA enabled |

---

## IA-02-02: Root account has no active access keys

**CJIS reference**: CJIS v6.0 IA-2 | **Priority**: P1*

```bash
aws iam get-account-summary --query 'SummaryMap.AccountAccessKeysPresent' --output text
```

| Result | Severity | Finding |
|---|---|---|
| `1` | AUDIT BLOCKER | Root access keys exist — must be deleted |
| `0` | INFO | No root access keys |

---

## IA-02-03: All IAM users with console access have MFA

**CJIS reference**: CJIS v6.0 IA-2 | **Priority**: P1*

```bash
aws iam generate-credential-report >/dev/null 2>&1; sleep 2
aws iam get-credential-report --query Content --output text | base64 -d > /tmp/cred-report.csv
awk -F',' 'NR>1 && $4=="true" && $8=="false" {print $1}' /tmp/cred-report.csv
```

| Result | Severity | Finding |
|---|---|---|
| Any users with `password_enabled=true, mfa_active=false` | AUDIT BLOCKER | {count} IAM users have console access without MFA |
| All console users have MFA | INFO | MFA enforced on all IAM console users |

**Rationale**: IA-2 requires multi-factor authentication for all access to CJI. This is the single most common CJIS audit finding.

---

## IA-02-04: MFA on privileged accounts (admin roles)

**CJIS reference**: CJIS v6.0 IA-2 | **Priority**: P1*

```bash
# Check if AdministratorAccess-attached users have MFA
aws iam list-entities-for-policy --policy-arn arn:aws:iam::aws:policy/AdministratorAccess --query 'PolicyUsers[].UserName' --output text 2>/dev/null | tr '\t' '\n' | while read u; do
  mfa=$(aws iam list-mfa-devices --user-name "$u" --query 'MFADevices[0].SerialNumber' --output text 2>/dev/null)
  [ "$mfa" = "None" ] && echo "$u: ADMIN WITHOUT MFA"
done
```

| Result | Severity | Finding |
|---|---|---|
| Admin users without MFA | AUDIT BLOCKER | Privileged user `{name}` has admin access without MFA |
| All admin users have MFA | INFO | Privileged accounts MFA-protected |

---

## IA-04-01: Unique user identifiers — no shared accounts

**CJIS reference**: CJIS v6.0 IA-4 | **Priority**: P1*

```bash
aws iam list-users --query 'Users[].{UserName:UserName,Path:Path,CreateDate:CreateDate}' --output json
```

Heuristic: flag user names that look generic (case-insensitive): `admin`, `root`, `shared`, `service`, `ops`, `automation`, `jenkins`, `ci`, `cd`, or names with no vowels/digits only.

| Result | Severity | Finding |
|---|---|---|
| Generic names with `password_enabled=true` | FINDING RISK | Possible shared IAM user: `{name}` — CJIS requires unique IDs per person |
| No suspicious names | INFO | No obvious shared users detected |

This is heuristic — always surface the list to the user for confirmation.

---

## IA-05-01: Password policy meets CJIS minimums

**CJIS reference**: CJIS v6.0 IA-5 | **Priority**: P1*

```bash
aws iam get-account-password-policy --output json 2>/dev/null
```

CJIS v6.0 thresholds:
- `MinimumPasswordLength` >= 20 (strict benchmark; some states accept 12)
- `RequireSymbols`, `RequireNumbers`, `RequireUppercaseCharacters`, `RequireLowercaseCharacters` all `true`
- `MaxPasswordAge` <= 90
- `PasswordReusePrevention` >= 10

| Result | Severity | Finding |
|---|---|---|
| No policy set (`NoSuchEntity`) | AUDIT BLOCKER | No IAM password policy configured |
| `MinimumPasswordLength < 12` | AUDIT BLOCKER | Password minimum length below CJIS floor |
| `MinimumPasswordLength < 20` | FINDING RISK | Password length below strict benchmark (20 chars) |
| Missing any complexity flag | FINDING RISK | Password policy missing complexity requirements |
| `MaxPasswordAge > 90` or unset | FINDING RISK | Password age exceeds 90 days |
| `PasswordReusePrevention < 10` | GAP | Password reuse prevention below recommended |
| All thresholds met | INFO | Password policy CJIS-compliant |

---

## IA-05-02: Access key rotation (<=90 days)

**CJIS reference**: CJIS v6.0 IA-5 | **Priority**: P1*

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
| Any key > 180 days | AUDIT BLOCKER | {count} access keys older than 180 days |
| Any key 91-180 days | FINDING RISK | {count} access keys over CJIS 90-day rotation policy |
| All <= 90 days | INFO | Access keys within rotation policy |

---

## IA-07-01: FIPS 140-2/3 — KMS usage for cryptographic operations

**CJIS reference**: CJIS v6.0 IA-7 | **Priority**: P1*

```bash
# Check partition (GovCloud = FIPS by default)
aws sts get-caller-identity --query 'Arn' --output text | grep -q 'aws-us-gov' && echo "GovCloud (FIPS default)" || echo "Commercial (FIPS opt-in)"
# KMS keys in use:
aws kms list-keys --query 'Keys[].KeyId' --output text | wc -w
```

| Result | Severity | Finding |
|---|---|---|
| Commercial partition, no evidence of FIPS endpoint usage | AUDIT BLOCKER | Commercial AWS without FIPS endpoints — CJIS requires FIPS 140-2 validated crypto |
| GovCloud partition | INFO | GovCloud — FIPS endpoints by default |
| Commercial with KMS CMKs and FIPS indicators | INFO | FIPS crypto modules in use |

Questionnaire follow-up: "Is `AWS_USE_FIPS_ENDPOINT=true` set in your application runtime config?"

---

## IA-08-01: Non-organizational users — federated access

**CJIS reference**: CJIS v6.0 IA-8 | **Priority**: P1

```bash
aws sso-admin list-instances --output json 2>/dev/null
aws iam list-saml-providers --query 'SAMLProviderList[].Arn' --output json 2>/dev/null
aws iam list-open-id-connect-providers --query 'OpenIDConnectProviderList[].Arn' --output json 2>/dev/null
```

| Result | Severity | Finding |
|---|---|---|
| No federation, multiple IAM users | FINDING RISK | No federated identity — consider Identity Center for non-org user management |
| Identity Center or SAML in use | INFO | Federated access configured |

---

## IA-11-01: Re-authentication — STS session duration checks

**CJIS reference**: CJIS v6.0 IA-11 | **Priority**: P1

```bash
aws iam list-roles --query 'Roles[?!starts_with(Path, `/aws-service-role/`)].{Name:RoleName,MaxSession:MaxSessionDuration}' --output json
```

| Result | Severity | Finding |
|---|---|---|
| Roles with `MaxSessionDuration > 3600` in CJI environment | FINDING RISK | Role `{name}` allows sessions > 1 hour — verify re-authentication controls |
| All roles <=3600 | INFO | Session durations support re-authentication |

**Rationale**: IA-11 requires re-authentication under defined circumstances. Long STS sessions may bypass re-authentication expectations.

---

## Summary

| Check | ID | Key question |
|---|---|---|
| Root MFA | IA-02-01 | Is root protected with MFA? |
| Root access keys | IA-02-02 | Are root API keys eliminated? |
| User MFA | IA-02-03 | Do all console users have MFA? |
| Admin MFA | IA-02-04 | Do all privileged users have MFA? |
| Unique IDs | IA-04-01 | Are all accounts uniquely attributable? |
| Password policy | IA-05-01 | Does the policy meet CJIS thresholds? |
| Key rotation | IA-05-02 | Are access keys rotated <= 90 days? |
| FIPS crypto | IA-07-01 | Are FIPS-validated modules in use? |
| Federated access | IA-08-01 | Is non-org user access federated? |
| Re-authentication | IA-11-01 | Are session durations appropriate? |

**Total: 10 checks.** Expected time: ~2 min.
