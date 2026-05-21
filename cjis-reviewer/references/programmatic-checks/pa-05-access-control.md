# PA 5 — Access Control — Programmatic Checks

> Execute in order. Read-only AWS CLI. Severity per [`../severity-classification.md`](../severity-classification.md).

CJIS PA 5 (Section 5.5) — least privilege, account management, session lock (≤30 min), encrypted remote access.

Many PA 5 requirements overlap with PA 6 (identity) — checks here focus on *authorization* and *session* controls rather than *authentication*.

---

## PA5-01: No overly-permissive IAM policies (`*:*`)

```bash
aws iam list-policies --scope Local --only-attached --query 'Policies[].{Arn:Arn,Name:PolicyName,DefaultVersion:DefaultVersionId}' --output json
# For each attached customer-managed policy, fetch the default version:
# aws iam get-policy-version --policy-arn {arn} --version-id {ver}
```

Scan each policy document for:
- `"Action": "*"` with `"Resource": "*"` and `"Effect": "Allow"` → unbounded admin
- `"Action": "<svc>:*"` on sensitive services (`iam`, `kms`, `s3`, `rds`, `dynamodb`) with `"Resource": "*"` → service-wide admin

| Result | Severity | Finding |
|---|---|---|
| Policy with `Action: *`, `Resource: *`, `Effect: Allow` and no conditions | AUDIT BLOCKER | Customer policy `{name}` grants unbounded admin |
| Policy with `<svc>:*` on sensitive service, no resource scoping | FINDING RISK | Policy `{name}` broad on service `{svc}` |
| All policies scoped | INFO | No overly-permissive customer policies ✅ |

Note: Managed policies like `AdministratorAccess` are expected to exist — flag only if *attached* to a principal that touches CJI.

---

## PA5-02: IAM Access Analyzer findings for external access

```bash
aws accessanalyzer list-analyzers --query 'analyzers[?status==`ACTIVE`].{Name:name,Arn:arn,Type:type}' --output json
# For each active analyzer:
aws accessanalyzer list-findings --analyzer-arn {arn} --filter '{"status":{"eq":["ACTIVE"]}}' --query 'findings[].{Id:id,Resource:resource,ExternalPrincipal:principal}' --output json
```

| Result | Severity | Finding |
|---|---|---|
| No Access Analyzer enabled | GAP | Access Analyzer not enabled — enable to catch cross-account/public exposure |
| Active findings for external principals | FINDING RISK | {count} resources exposed to external principals per Access Analyzer |
| No active findings | INFO | No external-principal exposure ✅ |

---

## PA5-03: No publicly-accessible RDS instances

```bash
aws rds describe-db-instances --query 'DBInstances[?PubliclyAccessible==`true`].{Id:DBInstanceIdentifier,Endpoint:Endpoint.Address}' --output json
```

| Result | Severity | Finding |
|---|---|---|
| Any publicly accessible RDS | AUDIT BLOCKER | RDS `{id}` is publicly accessible — may expose CJI |
| None public | INFO | RDS instances not publicly accessible ✅ |

---

## PA5-04: No public S3 bucket policies / ACLs

Already partially covered by PA8-08 (public access block). Here specifically check bucket ACLs and policies that are currently *granting* public access:

```bash
aws s3api list-buckets --query 'Buckets[].Name' --output text | tr '\t' '\n' | while read b; do
  pol_status=$(aws s3api get-bucket-policy-status --bucket "$b" --query 'PolicyStatus.IsPublic' --output text 2>/dev/null)
  [ "$pol_status" = "True" ] && echo "$b: PUBLIC POLICY"
  acl=$(aws s3api get-bucket-acl --bucket "$b" --query 'Grants[?Grantee.URI==`http://acs.amazonaws.com/groups/global/AllUsers` || Grantee.URI==`http://acs.amazonaws.com/groups/global/AuthenticatedUsers`].Permission' --output text 2>/dev/null)
  [ -n "$acl" ] && echo "$b: PUBLIC ACL ($acl)"
done
```

| Result | Severity | Finding |
|---|---|---|
| Any public buckets | AUDIT BLOCKER | S3 bucket `{name}` publicly accessible |
| None public | INFO | No public S3 buckets ✅ |

---

## PA5-05: Remote access via Session Manager / encrypted channels (no direct SSH)

Heuristic — check for IAM roles allowing `ssm:StartSession` and for security groups opening 22/3389:

```bash
# Count SGs allowing 22 or 3389 from anywhere-but-internal
aws ec2 describe-security-groups --filters Name=ip-permission.from-port,Values=22,3389 --query 'SecurityGroups[].GroupId' --output json
# Check for recent SSM Session history
aws ssm describe-sessions --state History --max-results 10 --query 'Sessions[].SessionId' --output text 2>/dev/null
```

| Result | Severity | Finding |
|---|---|---|
| SGs allow 22/3389 AND no SSM session history | FINDING RISK | Direct SSH/RDP appears to be in use — adopt SSM Session Manager for audit trail |
| SSM Session Manager in use | INFO | Session Manager providing audited access ✅ |

---

## PA5-06: SCPs in place for CJI accounts (Organizations)

```bash
aws organizations list-policies --filter SERVICE_CONTROL_POLICY --query 'Policies[].{Id:Id,Name:Name,AwsManaged:AwsManaged}' --output json 2>/dev/null
# If Organizations not in use, command fails with AccessDenied or not-a-member.
```

| Result | Severity | Finding |
|---|---|---|
| Organizations not in use | GAP | Single-account setup — SCPs not applicable; confirm CJI isolation via IAM only |
| Organizations in use, no custom SCPs | GAP | Only AWS-managed SCPs — consider CJI-specific SCPs (region restriction, deny-delete-logs) |
| Custom SCPs applied to CJI OU | INFO | Custom SCPs enforcing CJI boundary ✅ |

---

## PA5-07: No inactive/stale IAM roles

```bash
# Requires iam:GetServiceLastAccessedDetails — start the analysis:
aws iam list-roles --query 'Roles[?!starts_with(Path, `/aws-service-role/`) && !starts_with(Path, `/aws-reserved/`)].{Name:RoleName,Arn:Arn,LastUsed:RoleLastUsed.LastUsedDate}' --output json
```

| Result | Severity | Finding |
|---|---|---|
| Customer roles with `LastUsed` > 180 days or null | GAP | {count} customer IAM roles appear unused — review and delete |
| All roles recently used | INFO | No stale roles ✅ |

---

## Summary

| Check | ID | Key question |
|---|---|---|
| Overly-permissive policies | PA5-01 | Any `*:*` admin policies in use? |
| Access Analyzer | PA5-02 | Is external exposure monitored? |
| Public RDS | PA5-03 | Are DBs private? |
| Public S3 | PA5-04 | Are buckets private? |
| Audited shell access | PA5-05 | Is direct SSH replaced by SSM? |
| SCPs | PA5-06 | Are Org-level guardrails in place? |
| Stale roles | PA5-07 | Are unused roles cleaned up? |

**Total: 7 checks.** Expected time: ~2 min.
