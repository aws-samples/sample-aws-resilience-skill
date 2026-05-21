# AC — Access Control — Programmatic Checks

> Based on CJIS Security Policy v6.0 (effective December 2024).
> Last verified against official source: 2025-05-21.
> Check https://le.fbi.gov/cjis-division/cjis-security-policy-resource-center for newer versions.

> Execute in order. Each check uses read-only AWS CLI. Record results as
> `COMPLIANT` / `NON_COMPLIANT` / `NOT_APPLICABLE` / `UNABLE_TO_ASSESS` with severity per
> [`../severity-classification.md`](../severity-classification.md).

AC family (Priority P1) — least privilege, account management, session lock, encrypted remote access, information flow enforcement, separation of duties.

---

## AC-02-01: IAM users enumeration and credential health

**CJIS reference**: CJIS v6.0 AC-2 | **Priority**: P1*

```bash
aws iam generate-credential-report >/dev/null 2>&1; sleep 2
aws iam get-credential-report --query Content --output text | base64 -d > /tmp/cred-report.csv
awk -F',' 'NR>1 {print $1, "mfa="$8, "pw_enabled="$4, "pw_last_used="$5}' /tmp/cred-report.csv
```

| Result | Severity | Finding |
|---|---|---|
| Users with `password_enabled=true, mfa_active=false` | AUDIT BLOCKER | {count} IAM users have console access without MFA (AC-2 account management) |
| Users with `password_last_used > 90 days` | FINDING RISK | Inactive accounts not disabled per AC-2 |
| All accounts active and MFA-enforced | INFO | Account management healthy |

**Rationale**: AC-2 requires account management including disabling inactive accounts and enforcing authenticator requirements.

---

## AC-03-01: S3 Block Public Access (account-level)

**CJIS reference**: CJIS v6.0 AC-3 | **Priority**: P1*

```bash
account=$(aws sts get-caller-identity --query Account --output text)
aws s3control get-public-access-block --account-id $account --query 'PublicAccessBlockConfiguration' --output json 2>/dev/null
```

| Result | Severity | Finding |
|---|---|---|
| Account-level block disabled or partial | AUDIT BLOCKER | Account-level S3 public access block not fully enabled |
| All four block settings `true` | INFO | S3 public access blocked account-wide |

---

## AC-03-02: No publicly-accessible RDS instances

**CJIS reference**: CJIS v6.0 AC-3 | **Priority**: P1*

```bash
aws rds describe-db-instances --query 'DBInstances[?PubliclyAccessible==`true`].{Id:DBInstanceIdentifier,Endpoint:Endpoint.Address}' --output json
```

| Result | Severity | Finding |
|---|---|---|
| Any publicly accessible RDS | AUDIT BLOCKER | RDS `{id}` is publicly accessible — may expose CJI |
| None public | INFO | RDS instances not publicly accessible |

---

## AC-03-03: Security groups with 0.0.0.0/0 ingress on critical ports

**CJIS reference**: CJIS v6.0 AC-3 | **Priority**: P1*

```bash
aws ec2 describe-security-groups --filters Name=ip-permission.cidr,Values=0.0.0.0/0 --query 'SecurityGroups[].{Id:GroupId,Name:GroupName,Vpc:VpcId,Rules:IpPermissions[?IpRanges[?CidrIp==`0.0.0.0/0`]].{Proto:IpProtocol,FromPort:FromPort,ToPort:ToPort}}' --output json
```

Critical ports: 22, 3389, 3306, 5432, 1433, 27017, 6379, 9200, all-ports (-1).

| Result | Severity | Finding |
|---|---|---|
| 0.0.0.0/0 to any critical port | AUDIT BLOCKER | Security Group `{id}` allows {port} from internet |
| 0.0.0.0/0 to web ports (80/443) on CJI app | FINDING RISK | Confirm WAF + authentication in front |
| No unrestricted critical-port ingress | INFO | SGs have no unrestricted critical-port ingress |

---

## AC-04-01: VPC Flow Logs for information flow enforcement

**CJIS reference**: CJIS v6.0 AC-4 | **Priority**: P1*

```bash
aws ec2 describe-vpcs --query 'Vpcs[].VpcId' --output text | tr '\t' '\n' | while read vpc; do
  logs=$(aws ec2 describe-flow-logs --filter Name=resource-id,Values=$vpc --query 'FlowLogs[?FlowLogStatus==`ACTIVE`].FlowLogId' --output text)
  [ -z "$logs" ] && echo "$vpc: NO FLOW LOGS"
done
```

| Result | Severity | Finding |
|---|---|---|
| CJI VPCs without flow logs | AUDIT BLOCKER | VPC `{id}` has no flow logs — cannot enforce/monitor information flow |
| All CJI VPCs have flow logs | INFO | Information flow monitoring in place |

---

## AC-04-02: VPC endpoint policies (restrict AWS service access)

**CJIS reference**: CJIS v6.0 AC-4 | **Priority**: P1*

```bash
aws ec2 describe-vpc-endpoints --query 'VpcEndpoints[].{Id:VpcEndpointId,Service:ServiceName,PolicyDoc:PolicyDocument}' --output json
```

| Result | Severity | Finding |
|---|---|---|
| No VPC endpoints in CJI VPC | GAP | AWS API traffic traverses internet — consider VPC endpoints |
| Endpoints with full-access policy (`"Action": "*"`) | GAP | VPC endpoint policies not restricted — consider scoping |
| Scoped endpoint policies | INFO | VPC endpoint policies enforced |

---

## AC-05-01: Separation of duties — admin vs operator roles

**CJIS reference**: CJIS v6.0 AC-5 | **Priority**: P1*

```bash
aws iam list-policies --scope Local --only-attached --query 'Policies[].{Arn:Arn,Name:PolicyName,DefaultVersion:DefaultVersionId}' --output json
# Check for AdministratorAccess attached to multiple principals:
aws iam list-entities-for-policy --policy-arn arn:aws:iam::aws:policy/AdministratorAccess --query '{Groups:PolicyGroups,Users:PolicyUsers,Roles:PolicyRoles}' --output json 2>/dev/null
```

| Result | Severity | Finding |
|---|---|---|
| AdministratorAccess attached to >2 principals or CJI-access roles | FINDING RISK | Insufficient separation of duties — admin privilege too broadly assigned |
| Distinct admin/operator/CJI-reader roles | INFO | Role separation implemented |

---

## AC-06-01: Least privilege — Access Analyzer findings

**CJIS reference**: CJIS v6.0 AC-6 | **Priority**: P1*

```bash
aws accessanalyzer list-analyzers --query 'analyzers[?status==`ACTIVE`].{Name:name,Arn:arn,Type:type}' --output json
# For each active analyzer:
aws accessanalyzer list-findings --analyzer-arn {arn} --filter '{"status":{"eq":["ACTIVE"]}}' --query 'findings[].{Id:id,Resource:resource,ExternalPrincipal:principal}' --output json
```

| Result | Severity | Finding |
|---|---|---|
| No Access Analyzer enabled | FINDING RISK | Access Analyzer not enabled — cannot detect external exposure |
| Active findings for external principals | AUDIT BLOCKER | {count} resources exposed to external principals |
| No active findings | INFO | No external-principal exposure |

---

## AC-07-01: Account lockout settings

**CJIS reference**: CJIS v6.0 AC-7 | **Priority**: P1*

```bash
aws iam get-account-password-policy --query '{MaxPasswordAge:MaxPasswordAge,HardExpiry:HardExpiry}' --output json 2>/dev/null
# Cognito user pools (if applicable):
aws cognito-idp list-user-pools --max-results 10 --query 'UserPools[].{Id:Id,Name:Name}' --output json 2>/dev/null
```

| Result | Severity | Finding |
|---|---|---|
| No password policy set | AUDIT BLOCKER | No IAM password policy — AC-7 lockout cannot be enforced at IAM level |
| IAM password policy exists (lockout is at app/Cognito layer) | INFO | Note: IAM does not natively support lockout — verify at application layer |

Note: AWS IAM does not have a native lockout mechanism. Flag for questionnaire if Cognito or AD-based lockout is not in use.

---

## AC-11-01: Session timeout — IAM role max session duration

**CJIS reference**: CJIS v6.0 AC-11 | **Priority**: P1*

```bash
aws iam list-roles --query 'Roles[?!starts_with(Path, `/aws-service-role/`)].{Name:RoleName,MaxSession:MaxSessionDuration}' --output json
```

| Result | Severity | Finding |
|---|---|---|
| CJI-access roles with `MaxSessionDuration > 3600` (1 hour) | FINDING RISK | Role `{name}` allows sessions > 1 hour — CJIS requires 30-min session lock |
| All CJI roles ≤ 3600 | INFO | Session duration within CJIS bounds |

**Rationale**: AC-11 requires session lock after 30 minutes of inactivity. MaxSessionDuration is the upper bound — actual lock depends on application implementation.

---

## AC-17-01: Remote access — no direct SSH/RDP from internet

**CJIS reference**: CJIS v6.0 AC-17 | **Priority**: P1*

```bash
# SGs allowing 22 or 3389 from 0.0.0.0/0
aws ec2 describe-security-groups --filters Name=ip-permission.from-port,Values=22 Name=ip-permission.cidr,Values=0.0.0.0/0 --query 'SecurityGroups[].GroupId' --output json
aws ec2 describe-security-groups --filters Name=ip-permission.from-port,Values=3389 Name=ip-permission.cidr,Values=0.0.0.0/0 --query 'SecurityGroups[].GroupId' --output json
# SSM Session Manager usage:
aws ssm describe-sessions --state History --max-results 5 --query 'Sessions[].SessionId' --output text 2>/dev/null
```

| Result | Severity | Finding |
|---|---|---|
| SGs allow SSH/RDP from internet AND no SSM usage | AUDIT BLOCKER | Direct SSH/RDP from internet — AC-17 requires encrypted, audited remote access |
| SGs allow SSH/RDP but SSM in use | FINDING RISK | Close internet-facing SSH/RDP ports; use SSM exclusively |
| SSM Session Manager in use, no open ports | INFO | Audited encrypted remote access via SSM |

---

## AC-22-01: Publicly accessible content — S3 BPA check

**CJIS reference**: CJIS v6.0 AC-22 | **Priority**: P1

```bash
aws s3api list-buckets --query 'Buckets[].Name' --output text | tr '\t' '\n' | while read b; do
  pol_status=$(aws s3api get-bucket-policy-status --bucket "$b" --query 'PolicyStatus.IsPublic' --output text 2>/dev/null)
  [ "$pol_status" = "True" ] && echo "$b: PUBLIC POLICY"
done
```

| Result | Severity | Finding |
|---|---|---|
| Any bucket with public policy in CJI account | AUDIT BLOCKER | S3 bucket `{name}` publicly accessible — AC-22 violation |
| No public buckets | INFO | No publicly accessible content |

---

## Summary

| Check | ID | Key question |
|---|---|---|
| Credential health / MFA | AC-02-01 | Are accounts managed with MFA? |
| S3 Block Public Access | AC-03-01 | Is public access blocked account-wide? |
| Public RDS | AC-03-02 | Are databases private? |
| SG critical ports | AC-03-03 | Are sensitive ports closed to internet? |
| VPC Flow Logs | AC-04-01 | Is information flow monitored? |
| VPC endpoint policies | AC-04-02 | Is AWS API traffic private? |
| Separation of duties | AC-05-01 | Are admin/operator roles distinct? |
| Access Analyzer | AC-06-01 | Is external exposure monitored? |
| Account lockout | AC-07-01 | Is lockout configured? |
| Session timeout | AC-11-01 | Are sessions time-limited? |
| Remote access | AC-17-01 | Is SSH/RDP replaced by SSM? |
| Public content | AC-22-01 | Is content exposure controlled? |

**Total: 12 checks.** Expected time: ~3 min.
