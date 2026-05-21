# FCD 4 — Auditing & Access Logging — Programmatic Checks

> Based on 34 CFR §99.32, PTAC guidance, NIST SP 800-171 §3.3. Last verified: 2026-05-21.

> Execute in order. Each check uses read-only AWS CLI. Record results as
> `COMPLIANT` / `NON_COMPLIANT` / `NOT_APPLICABLE` / `UNABLE_TO_ASSESS` with severity per
> [`../severity-classification.md`](../severity-classification.md).

FERPA FCD 4 covers both:
- **§99.32 Record of disclosures** — statutory requirement to log every request for access and every disclosure of education records. Application-level. CloudTrail does NOT satisfy this.
- **PTAC / NIST 800-171 audit logging** — security-event logging (auth, privilege changes, resource access). Infrastructure-level. CloudTrail + VPC Flow Logs + CloudWatch Logs satisfy this.

Key distinction from CJIS: the §99.32 log is a *statutory* requirement, not a best practice. Its absence is a BREACH RISK by default.

---

## FCD4-01: CloudTrail enabled in all regions

```bash
aws cloudtrail describe-trails --query 'trailList[].{Name:Name,IsMultiRegion:IsMultiRegionTrail,IsOrgTrail:IsOrganizationTrail,S3Bucket:S3BucketName,KmsKey:KmsKeyId}' --output json
```

| Result | Severity | Finding |
|---|---|---|
| No trails found | BREACH RISK | CloudTrail not configured — no API audit logging; undermines every other FCD 4 check |
| Trails exist but none multi-region | COMPLIANCE GAP | CloudTrail not multi-region — blind spots in other regions |
| Multi-region trail exists | — | Proceed to FCD4-02 |

---

## FCD4-02: CloudTrail is actively logging

For each trail from FCD4-01:

```bash
aws cloudtrail get-trail-status --name {trail_arn_or_name} --query '{IsLogging:IsLogging,LatestDeliveryTime:LatestDeliveryTime,LatestDeliveryError:LatestDeliveryError}' --output json
```

| Result | Severity | Finding |
|---|---|---|
| `IsLogging: false` | BREACH RISK | CloudTrail trail `{name}` exists but logging is stopped |
| Delivery error present | COMPLIANCE GAP | CloudTrail delivery errors — logs may be incomplete |
| Logging, no errors | INFO | CloudTrail actively logging ✅ |

---

## FCD4-03: CloudTrail log file validation enabled

```bash
aws cloudtrail describe-trails --query 'trailList[].{Name:Name,LogFileValidation:LogFileValidationEnabled}' --output json
```

| Result | Severity | Finding |
|---|---|---|
| `LogFileValidation: false` | COMPLIANCE GAP | Log file validation disabled — cannot detect tampering |
| `LogFileValidation: true` | INFO | Log integrity protection enabled ✅ |

---

## FCD4-04: CloudTrail logs encrypted with KMS CMK

```bash
aws cloudtrail describe-trails --query 'trailList[].{Name:Name,KmsKeyId:KmsKeyId}' --output json
```

| Result | Severity | Finding |
|---|---|---|
| `KmsKeyId: null` | COMPLIANCE GAP | CloudTrail logs not encrypted with CMK (SSE-S3 only) |
| KMS key ID present | INFO | CloudTrail logs KMS-encrypted ✅ |

---

## FCD4-05: CloudTrail data events for S3 buckets containing student records

```bash
aws cloudtrail get-event-selectors --trail-name {trail_arn} --query 'EventSelectors[].{ReadWrite:ReadWriteType,DataResources:DataResources}' --output json
# Or for advanced event selectors:
aws cloudtrail get-event-selectors --trail-name {trail_arn} --query 'AdvancedEventSelectors' --output json
```

| Result | Severity | Finding |
|---|---|---|
| No S3 data events configured | COMPLIANCE GAP | S3 object-level access to student-record buckets is not logged |
| S3 data events for "all buckets" | INFO | S3 data events captured ✅ |
| Data events limited to named buckets | INFO | Confirm the listed buckets cover all student-data buckets declared in Phase 1 (manual check) |

Data events are billed, so "all buckets" may be prohibitive. If scoped, the user must confirm student-data bucket coverage — surface as a questionnaire item.

---

## FCD4-06: CloudTrail data events for Lambda functions that read student-data S3

```bash
aws cloudtrail get-event-selectors --trail-name {trail_arn} --output json
# Look for Lambda::Function data resources in the output
```

| Result | Severity | Finding |
|---|---|---|
| No Lambda data events | HARDENING GAP | Lambda functions processing student data are not logged at invocation level |
| Lambda data events present | INFO | Lambda invocation logging enabled ✅ |

---

## FCD4-07: VPC Flow Logs enabled on all VPCs

```bash
aws ec2 describe-vpcs --query 'Vpcs[].VpcId' --output text | tr '\t' '\n' | while read vpc; do
  logs=$(aws ec2 describe-flow-logs --filter Name=resource-id,Values=$vpc --query 'FlowLogs[?FlowLogStatus==`ACTIVE`].FlowLogId' --output text)
  [ -z "$logs" ] && echo "$vpc: NO ACTIVE FLOW LOGS"
done
```

| Result | Severity | Finding |
|---|---|---|
| Any VPC without active flow logs | COMPLIANCE GAP | VPC `{id}` has no flow logs — limited network forensics |
| All VPCs have flow logs | INFO | VPC flow logging complete ✅ |

---

## FCD4-08: CloudTrail log bucket has S3 Object Lock (tamper protection)

```bash
# Identify the bucket from FCD4-01 output
aws s3api get-object-lock-configuration --bucket {log-bucket} --query 'ObjectLockConfiguration' --output json 2>/dev/null
aws s3api get-bucket-versioning --bucket {log-bucket} --query '{Status:Status,MFADelete:MFADelete}' --output json
```

| Result | Severity | Finding |
|---|---|---|
| Object Lock not enabled AND versioning disabled | COMPLIANCE GAP | CloudTrail log bucket lacks tamper protection — logs could be deleted |
| Versioning enabled, Object Lock disabled | HARDENING GAP | Consider enabling Object Lock (Governance or Compliance mode) for stronger tamper protection |
| Object Lock enabled | INFO | Log tamper protection in place ✅ |

---

## FCD4-09: Log retention meets student-record retention schedule

For CloudWatch Logs groups:

```bash
aws logs describe-log-groups --query 'logGroups[].{Name:logGroupName,Retention:retentionInDays}' --output json
```

For CloudTrail S3 bucket, inspect lifecycle:

```bash
aws s3api get-bucket-lifecycle-configuration --bucket {log-bucket} --query 'Rules[].{ID:ID,Status:Status,Expiration:Expiration}' --output json 2>/dev/null
```

Expected floor for student-data-related log groups: ≥2555 days (7 years) or `null` (never expire). State schedules vary — some require 5 years, some ≥10 years for certain record categories.

| Result | Severity | Finding |
|---|---|---|
| Any student-data log group with retention < 2555 days (not `null`) | COMPLIANCE GAP | Log group `{name}` retention is {N} days — below typical 7-year student-record floor |
| CloudTrail S3 lifecycle expires logs before retention schedule | COMPLIANCE GAP | CloudTrail log bucket lifecycle expires logs at {N} days |
| Retention ≥ schedule or never-expire | INFO | Log retention meets student-record schedule ✅ |

Note: this check is heuristic — the user declared retention requirements in Phase 1 may differ. Surface the raw retention values and let the user confirm.

---

## FCD4-10: §99.32 disclosure log — application-level (heuristic)

CloudTrail cannot prove the §99.32 log exists — the application emits it. Heuristic check: look for a dedicated CloudWatch log group with a naming convention suggesting a disclosure log, and confirm it has recent entries.

```bash
# Heuristic: log groups containing "disclosure", "access-log", "ferpa", "99-32", "access-record"
aws logs describe-log-groups --log-group-name-prefix "/ferpa/" --query 'logGroups[].logGroupName' --output json 2>/dev/null
aws logs describe-log-groups --log-group-name-prefix "/disclosure/" --query 'logGroups[].logGroupName' --output json 2>/dev/null
aws logs describe-log-groups --log-group-name-prefix "/student-access/" --query 'logGroups[].logGroupName' --output json 2>/dev/null
# If any match, check for recent activity:
aws logs describe-log-streams --log-group-name {name} --order-by LastEventTime --descending --limit 1 --query 'logStreams[0].lastEventTimestamp' --output text
```

| Result | Severity | Finding |
|---|---|---|
| No candidate log group AND application handles student records | BREACH RISK | No §99.32 disclosure log detected — FERPA statutory requirement not met (application must emit structured disclosure records) |
| Candidate log group exists but no activity in >30 days | COMPLIANCE GAP | §99.32 disclosure log may be stale — confirm the application is still emitting events |
| Candidate log group with recent activity | INFO | §99.32 disclosure log present ✅ (manual confirmation recommended — check log structure includes student_id, requestor, purpose, exception, records) |

This is the single most important FERPA-specific check. Even if automated detection fails, surface it as a **MANDATORY questionnaire item**: "Does your application log every disclosure of student records with {timestamp, student_id, requestor, purpose, §99.31 exception, records[]}?" Capture the user's yes/no answer in the report.

---

## FCD4-11: CloudWatch alarms for critical security events

Expected alarms: root login, MFA disable, IAM policy changes, S3 bucket policy changes, CloudTrail config changes.

```bash
aws cloudwatch describe-alarms --query 'MetricAlarms[].AlarmName' --output json
```

Heuristic: look for alarms matching patterns like `root`, `mfa`, `iam`, `cloudtrail`.

| Result | Severity | Finding |
|---|---|---|
| Fewer than 3 security alarms configured | HARDENING GAP | Limited proactive alerting — consider CIS AWS Foundations Benchmark alarms |
| Reasonable alarm coverage | INFO | Security alarms in place ✅ |

---

## FCD4-12: GuardDuty enabled

```bash
aws guardduty list-detectors --query 'DetectorIds' --output json
# If present, check status:
aws guardduty get-detector --detector-id {id} --query '{Status:Status,DataSources:DataSources}' --output json
```

| Result | Severity | Finding |
|---|---|---|
| No detector | COMPLIANCE GAP | GuardDuty not enabled — no automated threat detection on student-data accounts |
| Detector exists, `Status: DISABLED` | COMPLIANCE GAP | GuardDuty disabled |
| Detector enabled, S3 protection on | INFO | GuardDuty protecting student-data S3 ✅ |
| Detector enabled, S3 protection off | HARDENING GAP | Enable GuardDuty S3 protection for student-data buckets |

---

## Summary

| Check | ID | Key question |
|---|---|---|
| CloudTrail enabled | FCD4-01 | Is there any API audit logging? |
| CloudTrail logging | FCD4-02 | Are the trails actually delivering? |
| Log validation | FCD4-03 | Can we detect log tampering? |
| Log encryption | FCD4-04 | Are logs KMS-encrypted? |
| S3 data events | FCD4-05 | Is student-bucket access logged? |
| Lambda data events | FCD4-06 | Are student-data Lambdas logged? |
| VPC Flow Logs | FCD4-07 | Is network access logged? |
| Log tamper protection | FCD4-08 | Are logs deletion-protected? |
| Log retention | FCD4-09 | Do logs meet the retention schedule? |
| §99.32 disclosure log | FCD4-10 | **Does the app log every student-record disclosure?** |
| Security alarms | FCD4-11 | Is critical-event alerting in place? |
| GuardDuty | FCD4-12 | Is threat detection enabled? |

**Total: 12 checks.** Expected time: ~3 min. FCD4-10 is the most important — if nothing else, make sure the §99.32 question reaches the user.
