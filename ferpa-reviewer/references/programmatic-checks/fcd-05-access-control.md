# FCD 5 — Access Control & Least Privilege — Programmatic Checks

> Based on PTAC guidance, NIST SP 800-171 §3.1. Last verified: 2026-05-21.

> Execute in order. Read-only AWS CLI. Severity per [`../severity-classification.md`](../severity-classification.md).

FCD 5 covers *authorization* and *session* controls — what an authenticated principal is allowed to do. FCD 6 covers *authentication*. Overlap is intentional.

Public-facing student-data resources (public S3, public RDS, public snapshots) are the breach vector #1 in state-AG EdTech breach notifications — treat as BREACH RISK.

---

## FCD5-01: No overly-permissive IAM policies (`*:*` wildcards)

```bash
aws iam list-policies --scope Local --only-attached --query 'Policies[].{Arn:Arn,Name:PolicyName,DefaultVersion:DefaultVersionId}' --output json
# For each attached customer-managed policy:
# aws iam get-policy-version --policy-arn {arn} --version-id {ver}
```

Scan each policy document for:
- `"Action": "*"` with `"Resource": "*"` and `"Effect": "Allow"` → unbounded admin
- `"Action": "<svc>:*"` on sensitive services (`iam`, `kms`, `s3`, `rds`, `dynamodb`) with `"Resource": "*"` → service-wide admin

| Result | Severity | Finding |
|---|---|---|
| Policy with `Action: *`, `Resource: *`, `Effect: Allow`, no conditions | BREACH RISK | Customer policy `{name}` grants unbounded admin |
| Policy with `<svc>:*` on sensitive service, no resource scoping | COMPLIANCE GAP | Policy `{name}` broad on service `{svc}` |
| All policies scoped | INFO | No overly-permissive customer policies ✅ |

Managed policies like `AdministratorAccess` are expected to exist — flag only if *attached* to a principal that touches student data.

---

## FCD5-02: IAM Access Analyzer findings for external access

```bash
aws accessanalyzer list-analyzers --query 'analyzers[?status==`ACTIVE`].{Name:name,Arn:arn,Type:type}' --output json
# For each active analyzer:
aws accessanalyzer list-findings --analyzer-arn {arn} --filter '{"status":{"eq":["ACTIVE"]}}' --query 'findings[].{Id:id,Resource:resource,ExternalPrincipal:principal}' --output json
```

| Result | Severity | Finding |
|---|---|---|
| No Access Analyzer enabled | COMPLIANCE GAP | Access Analyzer not enabled — enable to catch cross-account/public exposure |
| Active findings for external principals | COMPLIANCE GAP | {count} resources exposed to external principals per Access Analyzer — review each for subprocessor/disclosure implications |
| No active findings | INFO | No external-principal exposure ✅ |

---

## FCD5-03: No publicly-accessible RDS instances

```bash
aws rds describe-db-instances --query 'DBInstances[?PubliclyAccessible==`true`].{Id:DBInstanceIdentifier,Endpoint:Endpoint.Address,Engine:Engine}' --output json
```

| Result | Severity | Finding |
|---|---|---|
| Any publicly accessible RDS | BREACH RISK | RDS `{id}` is publicly accessible — may expose student data |
| None public | INFO | RDS instances not publicly accessible ✅ |

---

## FCD5-04: No publicly-shared RDS or EBS snapshots

```bash
aws rds describe-db-snapshots --snapshot-type manual --include-public --query 'DBSnapshots[?contains(keys(@), `SnapshotCreateTime`)] | [?not_null(@)].{Id:DBSnapshotIdentifier}' --output json
aws rds describe-db-snapshot-attributes --db-snapshot-identifier {id} --query 'DBSnapshotAttributesResult.DBSnapshotAttributes[?AttributeName==`restore`].AttributeValues' --output json
# Check for "all" in AttributeValues — means public share

aws ec2 describe-snapshots --owner-ids self --query 'Snapshots[].SnapshotId' --output text | tr '\t' '\n' | while read s; do
  pub=$(aws ec2 describe-snapshot-attribute --snapshot-id "$s" --attribute createVolumePermission --query 'CreateVolumePermissions[?Group==`all`]' --output text 2>/dev/null)
  [ -n "$pub" ] && echo "$s: PUBLIC"
done
```

| Result | Severity | Finding |
|---|---|---|
| Any RDS snapshot with `restore: all` | BREACH RISK | RDS snapshot `{id}` publicly shared — potential student-data disclosure |
| Any EBS snapshot publicly shared | BREACH RISK | EBS snapshot `{id}` publicly shared — revoke immediately |
| None public | INFO | No public snapshots ✅ |

---

## FCD5-05: No public S3 bucket policies / ACLs

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
| Any public buckets | BREACH RISK | S3 bucket `{name}` publicly accessible — **highest-urgency FERPA finding** |
| None public | INFO | No public S3 buckets ✅ |

---

## FCD5-06: S3 Block Public Access enabled account-wide

```bash
aws s3control get-public-access-block --account-id {account} --query 'PublicAccessBlockConfiguration' --output json 2>/dev/null
```

| Result | Severity | Finding |
|---|---|---|
| `NoSuchPublicAccessBlockConfiguration` or any flag `false` | COMPLIANCE GAP | S3 BPA not fully enabled at account level — enable all four flags |
| All four flags `true` | INFO | S3 BPA fully enabled ✅ |

---

## FCD5-07: Remote access via Session Manager / encrypted channels (no direct SSH)

```bash
# Count SGs allowing 22 or 3389 from 0.0.0.0/0
aws ec2 describe-security-groups --filters Name=ip-permission.from-port,Values=22,3389 --query 'SecurityGroups[].{Id:GroupId,Ingress:IpPermissions[?FromPort==`22` || FromPort==`3389`].IpRanges[?CidrIp==`0.0.0.0/0`]}' --output json
# Check for recent SSM Session history
aws ssm describe-sessions --state History --max-results 10 --query 'Sessions[].SessionId' --output text 2>/dev/null
```

| Result | Severity | Finding |
|---|---|---|
| SGs allow 22/3389 from 0.0.0.0/0 | BREACH RISK | Security group `{id}` allows SSH/RDP from internet |
| SGs allow 22/3389 from private ranges AND no SSM session history | COMPLIANCE GAP | Direct SSH/RDP appears to be in use — adopt SSM Session Manager for audit trail |
| SSM Session Manager in use | INFO | Session Manager providing audited access ✅ |

---

## FCD5-08: SCPs in place for student-data accounts (Organizations)

```bash
aws organizations list-policies --filter SERVICE_CONTROL_POLICY --query 'Policies[].{Id:Id,Name:Name,AwsManaged:AwsManaged}' --output json 2>/dev/null
```

| Result | Severity | Finding |
|---|---|---|
| Organizations not in use | HARDENING GAP | Single-account setup — SCPs not applicable; confirm student-data isolation via IAM only |
| Organizations in use, no custom SCPs | HARDENING GAP | Only AWS-managed SCPs — consider student-data-specific SCPs (US region restriction, deny-delete-logs, deny-non-approved-services) |
| Custom SCPs applied to student-data OU | INFO | Custom SCPs enforcing the student-data boundary ✅ |

---

## FCD5-09: No inactive/stale IAM roles

```bash
aws iam list-roles --query 'Roles[?!starts_with(Path, `/aws-service-role/`) && !starts_with(Path, `/aws-reserved/`)].{Name:RoleName,Arn:Arn,LastUsed:RoleLastUsed.LastUsedDate}' --output json
```

| Result | Severity | Finding |
|---|---|---|
| Customer roles with `LastUsed` > 180 days or null | HARDENING GAP | {count} customer IAM roles appear unused — review and delete |
| All roles recently used | INFO | No stale roles ✅ |

---

## FCD5-10: No IAM policies allowing `iam:PassRole` broadly

Dangerous pattern: `iam:PassRole` with `Resource: *` or without role-name condition enables privilege escalation.

```bash
aws iam list-policies --scope Local --only-attached --output json
# For each, fetch the default version and grep for iam:PassRole
```

| Result | Severity | Finding |
|---|---|---|
| Policy with `iam:PassRole` + `Resource: *`, no conditions | BREACH RISK | Policy `{name}` permits unscoped PassRole — privilege escalation risk |
| Policy with `iam:PassRole` scoped to specific role ARNs | INFO | PassRole scoped ✅ |
| No PassRole in customer policies | NOT_APPLICABLE | — |

---

## Summary

| Check | ID | Key question |
|---|---|---|
| Overly-permissive policies | FCD5-01 | Any unbounded admin policies? |
| Access Analyzer | FCD5-02 | Is external exposure monitored? |
| Public RDS | FCD5-03 | Are databases private? |
| Public snapshots | FCD5-04 | Are snapshots private? |
| Public S3 | FCD5-05 | Are buckets private? |
| S3 BPA | FCD5-06 | Is S3 Block Public Access on? |
| Audited shell access | FCD5-07 | Is direct SSH replaced by SSM? |
| SCPs | FCD5-08 | Are Org-level guardrails in place? |
| Stale roles | FCD5-09 | Are unused roles cleaned up? |
| PassRole scope | FCD5-10 | Is PassRole scoped to prevent escalation? |

**Total: 10 checks.** Expected time: ~3 min.
