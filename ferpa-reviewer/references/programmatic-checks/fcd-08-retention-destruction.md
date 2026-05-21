# FCD 8 — Data Minimization, Retention & Secure Destruction — Programmatic Checks

> Based on PTAC guidance, NIST SP 800-171 §3.8. Last verified: 2025-05-15.

> Execute in order. Read-only AWS CLI. Severity per [`../severity-classification.md`](../severity-classification.md).

FCD 8 covers:
- Lifecycle policies on student-data stores (retain-then-delete per schedule)
- Crypto-shred capability for DPA termination (dedicated CMK per district or data category)
- Backup / snapshot retention alignment
- DynamoDB TTL where appropriate
- Secure-destruction evidence

Most FCD 8 findings are COMPLIANCE GAP rather than BREACH RISK — they represent contract-termination and retention-schedule risks rather than active breach vectors.

---

## FCD8-01: S3 bucket lifecycle policies

```bash
aws s3api list-buckets --query 'Buckets[].Name' --output text | tr '\t' '\n' | while read b; do
  lc=$(aws s3api get-bucket-lifecycle-configuration --bucket "$b" --query 'Rules[?Status==`Enabled`]' --output json 2>/dev/null)
  [ -z "$lc" ] || [ "$lc" = "null" ] && echo "$b: NO LIFECYCLE"
done
```

| Result | Severity | Finding |
|---|---|---|
| Student-data bucket without lifecycle policy | COMPLIANCE GAP | Bucket `{name}` has no lifecycle policy — retention is implicit/unbounded |
| Lifecycle present | INFO | Lifecycle configured on `{name}` ✅ (confirm expiry days match retention schedule) |

Note: "no lifecycle" is not always wrong — some retention schedules require *indefinite* retention (e.g., transcripts). Surface the buckets without lifecycle and let the user confirm each matches a documented policy.

---

## FCD8-02: S3 Object Lock status on long-retention buckets

```bash
aws s3api list-buckets --query 'Buckets[].Name' --output text | tr '\t' '\n' | while read b; do
  ol=$(aws s3api get-object-lock-configuration --bucket "$b" --query 'ObjectLockConfiguration.ObjectLockEnabled' --output text 2>/dev/null)
  echo "$b: Object Lock = $ol"
done
```

| Result | Severity | Finding |
|---|---|---|
| CloudTrail / log-retention bucket without Object Lock | COMPLIANCE GAP | Bucket `{name}` lacks WORM protection — logs/records could be deleted |
| Student-record buckets requiring WORM without Object Lock | HARDENING GAP | Consider Object Lock (Governance mode) for records under mandatory retention |
| Object Lock enabled where needed | INFO | WORM protection in place ✅ |

Object Lock can only be enabled at bucket creation — flag missing-but-needed as a design finding.

---

## FCD8-03: RDS backup retention

```bash
aws rds describe-db-instances --query 'DBInstances[].{Id:DBInstanceIdentifier,Retention:BackupRetentionPeriod}' --output json
```

Minimum for student-data: ≥7 days (AWS default); many state contracts require ≥35 days.

| Result | Severity | Finding |
|---|---|---|
| Any instance with `BackupRetentionPeriod: 0` | COMPLIANCE GAP | RDS `{id}` has backups disabled — enable per recovery-objective + retention policy |
| Any instance with retention < 7 | COMPLIANCE GAP | RDS `{id}` backup retention is {N} days — below 7-day baseline |
| Retention ≥ baseline | INFO | RDS backup retention adequate ✅ |

---

## FCD8-04: AWS Backup plan coverage

```bash
aws backup list-backup-plans --query 'BackupPlansList[].{Name:BackupPlanName,Id:BackupPlanId}' --output json
# For each plan:
aws backup get-backup-plan --backup-plan-id {id} --query 'BackupPlan.Rules[].{Name:RuleName,Lifecycle:Lifecycle,Schedule:ScheduleExpression}' --output json
```

| Result | Severity | Finding |
|---|---|---|
| No AWS Backup plans | HARDENING GAP | No centralized backup plan — if RDS PITR is the only backup mechanism, cross-service coverage is limited |
| Backup plan without lifecycle | COMPLIANCE GAP | Backup plan `{name}` lacks lifecycle — backups never expire or may be deleted prematurely |
| Backup plan with lifecycle aligned | INFO | Backup plan configured with retention ✅ |

---

## FCD8-05: DynamoDB TTL for transient student data

```bash
aws dynamodb list-tables --query 'TableNames' --output text | tr '\t' '\n' | while read t; do
  ttl=$(aws dynamodb describe-time-to-live --table-name "$t" --query 'TimeToLiveDescription.TimeToLiveStatus' --output text 2>/dev/null)
  echo "$t: TTL=$ttl"
done
```

| Result | Severity | Finding |
|---|---|---|
| Student-data tables with transient records but no TTL | HARDENING GAP | Table `{name}` has no TTL — consider for session data, ephemeral records |
| TTL enabled where appropriate | INFO | TTL configured ✅ |

TTL is not universally required — most canonical student records should NOT have TTL. Flag only for transient-record tables identified from Phase 1 scope.

---

## FCD8-06: Dedicated CMKs for crypto-shred capability

Crypto-shred pattern: one CMK per district or per data-category, so DPA termination can render the data inert by scheduling key deletion.

```bash
aws kms list-keys --query 'Keys[].KeyId' --output text | tr '\t' '\n' | while read k; do
  meta=$(aws kms describe-key --key-id "$k" --query 'KeyMetadata.{Manager:KeyManager,Desc:Description,Tags:`tags_placeholder`}' --output json 2>/dev/null)
  if echo "$meta" | grep -q '"Manager": "CUSTOMER"'; then
    tags=$(aws kms list-resource-tags --key-id "$k" --query 'Tags[?TagKey==`district` || TagKey==`data-category`]' --output json 2>/dev/null)
    echo "$k: $meta tags=$tags"
  fi
done
```

| Result | Severity | Finding |
|---|---|---|
| Single shared CMK encrypting multiple districts' data | HARDENING GAP | Shared CMK prevents per-district crypto-shred — consider per-district keys for contract-termination data destruction |
| Per-district or per-category CMKs | INFO | Crypto-shred capability per district/category ✅ |
| Single-tenant deployment | NOT_APPLICABLE | — |

This is a design recommendation more than a compliance requirement — surface to the user regardless of severity.

---

## FCD8-07: Macie identifies over-collection in S3

Macie findings can reveal fields being collected/stored that aren't needed for the documented purpose — a data-minimization gap.

```bash
aws macie2 get-macie-session --query 'status' --output text 2>/dev/null
aws macie2 list-findings --finding-criteria '{"criterion":{"category":{"eq":["SENSITIVE_DATA"]},"archived":{"eq":["false"]}}}' --max-results 50 --query 'findingIds' --output json 2>/dev/null
```

| Result | Severity | Finding |
|---|---|---|
| Macie finds unexpected categories of student PII in buckets | COMPLIANCE GAP | Macie detected {category} in bucket `{name}` — review for over-collection |
| Macie enabled, no surprising findings | INFO | Data-collection scope matches expectations ✅ |
| Macie not enabled | HARDENING GAP | Enable Macie for data-minimization visibility (see also FCD3-08) |

---

## FCD8-08: Retention / destruction tags on student-data resources

Heuristic — look for tag keys like `retention`, `retention-expiry`, `destroy-after`, `district`, `student-data`.

```bash
aws resourcegroupstaggingapi get-resources --resource-type-filters s3 rds dynamodb ec2 --tags-per-page 100 --query 'ResourceTagMappingList[].{Arn:ResourceARN,Tags:Tags[?Key==`retention` || Key==`retention-expiry` || Key==`destroy-after` || Key==`district` || Key==`student-data`]}' --output json
```

| Result | Severity | Finding |
|---|---|---|
| Student-data resources without retention/district tags | COMPLIANCE GAP | {count} student-data resources lack retention or district tags — inventory and lifecycle are ad-hoc |
| All student-data resources tagged | INFO | Tag-based inventory in place ✅ |

---

## FCD8-09: Destruction audit trail (CloudTrail key-deletion events)

For the trailing period (check last 90 days), look for KMS key-deletion scheduled events:

```bash
aws cloudtrail lookup-events --lookup-attributes AttributeKey=EventName,AttributeValue=ScheduleKeyDeletion --max-results 20 --query 'Events[].{Name:EventName,User:Username,Time:EventTime}' --output json 2>/dev/null
```

| Result | Severity | Finding |
|---|---|---|
| Recent ScheduleKeyDeletion events | INFO | Crypto-shred audit trail present — confirm these align with documented DPA-termination events |
| No recent events | INFO | No recent key deletions — no current crypto-shred activity |

Not a compliance finding either way — the check exists to surface the audit trail for reference during a DPA-offboarding review.

---

## Summary

| Check | ID | Key question |
|---|---|---|
| S3 lifecycle | FCD8-01 | Are retention policies defined on buckets? |
| S3 Object Lock | FCD8-02 | Are long-retention buckets WORM-protected? |
| RDS backup retention | FCD8-03 | Are backups retained per policy? |
| AWS Backup | FCD8-04 | Is cross-service backup in place? |
| DynamoDB TTL | FCD8-05 | Is transient data auto-expired where appropriate? |
| Per-district CMKs | FCD8-06 | Is crypto-shred possible per district? |
| Macie over-collection | FCD8-07 | Is data collection minimized? |
| Retention tags | FCD8-08 | Are resources tagged for inventory? |
| Destruction audit | FCD8-09 | Is crypto-shred audit trail available? |

**Total: 9 checks.** Expected time: ~2 min.
