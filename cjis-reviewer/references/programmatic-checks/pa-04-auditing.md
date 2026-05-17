# PA 4 — Auditing and Accountability — Programmatic Checks

> Execute in order. Each check uses read-only AWS CLI. Record results as
> `COMPLIANT` / `NON_COMPLIANT` / `NOT_APPLICABLE` / `UNABLE_TO_ASSESS` with severity per
> [`../severity-classification.md`](../severity-classification.md).

CJIS PA 4 (Section 5.4) requires: log all CJI-related events, retain ≥1 year, protect logs from tampering, review regularly.

Key distinction: AWS CloudTrail logs **API calls**, not **application-level CJI access**. Application logging is a separate audit-evidence item — flag it in the report even if CloudTrail is perfect.

---

## PA4-01: CloudTrail enabled in all regions

```bash
aws cloudtrail describe-trails --query 'trailList[].{Name:Name,IsMultiRegion:IsMultiRegionTrail,IsOrgTrail:IsOrganizationTrail,S3Bucket:S3BucketName,KmsKey:KmsKeyId}' --output json
```

| Result | Severity | Finding |
|---|---|---|
| No trails found | AUDIT BLOCKER | CloudTrail not configured — no API audit logging (PA 4 failure) |
| Trails exist but none multi-region | FINDING RISK | CloudTrail not multi-region — blind spots in other regions |
| Multi-region trail exists | — | Proceed to PA4-02 |

---

## PA4-02: CloudTrail is actively logging

For each trail from PA4-01:

```bash
aws cloudtrail get-trail-status --name {trail_arn_or_name} --query '{IsLogging:IsLogging,LatestDeliveryTime:LatestDeliveryTime,LatestDeliveryError:LatestDeliveryError}' --output json
```

| Result | Severity | Finding |
|---|---|---|
| `IsLogging: false` | AUDIT BLOCKER | CloudTrail trail `{name}` exists but logging is stopped |
| Delivery error present | FINDING RISK | CloudTrail delivery errors — logs may be incomplete |
| Logging, no errors | INFO | CloudTrail actively logging ✅ |

---

## PA4-03: CloudTrail log file validation enabled

```bash
aws cloudtrail describe-trails --query 'trailList[].{Name:Name,LogFileValidation:LogFileValidationEnabled}' --output json
```

| Result | Severity | Finding |
|---|---|---|
| `LogFileValidation: false` | FINDING RISK | Log file validation disabled — cannot detect tampering |
| `LogFileValidation: true` | INFO | Log integrity protection enabled ✅ |

---

## PA4-04: CloudTrail logs encrypted with KMS CMK

```bash
aws cloudtrail describe-trails --query 'trailList[].{Name:Name,KmsKeyId:KmsKeyId}' --output json
```

| Result | Severity | Finding |
|---|---|---|
| `KmsKeyId: null` | FINDING RISK | CloudTrail logs not encrypted with CMK (SSE-S3 only) |
| KMS key ID present | INFO | CloudTrail logs KMS-encrypted ✅ |

---

## PA4-05: CloudTrail data events for S3 buckets containing CJI

```bash
aws cloudtrail get-event-selectors --trail-name {trail_arn} --query 'EventSelectors[].{ReadWrite:ReadWriteType,DataResources:DataResources}' --output json
# Or for advanced event selectors:
aws cloudtrail get-event-selectors --trail-name {trail_arn} --query 'AdvancedEventSelectors' --output json
```

| Result | Severity | Finding |
|---|---|---|
| No S3 data events configured | FINDING RISK | S3 object-level access to potential CJI buckets is not logged |
| S3 data events for "all buckets" | INFO | S3 data events captured ✅ |
| Data events limited to named buckets | INFO | Confirm the listed buckets cover all CJI buckets (manual check) |

Note: data events are billed, so "all buckets" may be prohibitive. If scoped, the user must confirm CJI-bucket coverage — surface as a questionnaire item.

---

## PA4-06: VPC Flow Logs enabled on all VPCs

```bash
aws ec2 describe-vpcs --query 'Vpcs[].VpcId' --output text | tr '\t' '\n' | while read vpc; do
  logs=$(aws ec2 describe-flow-logs --filter Name=resource-id,Values=$vpc --query 'FlowLogs[?FlowLogStatus==`ACTIVE`].FlowLogId' --output text)
  [ -z "$logs" ] && echo "$vpc: NO ACTIVE FLOW LOGS"
done
```

| Result | Severity | Finding |
|---|---|---|
| Any CJI VPC without active flow logs | FINDING RISK | VPC `{id}` has no flow logs — limited network forensics |
| All VPCs have flow logs | INFO | VPC flow logging complete ✅ |

---

## PA4-07: Log retention ≥365 days (CloudWatch Logs)

```bash
aws logs describe-log-groups --query 'logGroups[].{Name:logGroupName,Retention:retentionInDays}' --output json
```

| Result | Severity | Finding |
|---|---|---|
| Log groups with `retentionInDays < 365` or `null` (never expires is OK) | FINDING RISK | {count} CloudWatch Log Groups with retention below CJIS minimum |
| All ≥365 or never-expire | INFO | Log retention meets CJIS minimum ✅ |

Note: `null` retention = never expires, which is *compliant* (exceeds requirement). `0` is not a valid CloudWatch value — treat as never-expire.

---

## PA4-08: S3 log bucket has Object Lock or restrictive policy

Identify CloudTrail/flow-log destination buckets from earlier checks. For each:

```bash
aws s3api get-object-lock-configuration --bucket {bucket} 2>/dev/null
aws s3api get-bucket-policy --bucket {bucket} --query Policy --output text 2>/dev/null
```

| Result | Severity | Finding |
|---|---|---|
| No Object Lock and bucket policy allows deletes by current principal | FINDING RISK | Audit log bucket `{name}` can be modified/deleted — logs not tamper-resistant |
| Object Lock in Governance or Compliance mode | INFO | Log tamper-resistance in place ✅ |
| Bucket policy denies delete/put across principals | INFO | Logs protected via bucket policy ✅ |

---

## PA4-09: Centralized logging / SIEM integration (informational)

No single command — probe for indicators:

```bash
# Kinesis Data Firehose delivery streams (common CloudTrail → SIEM pipe)
aws firehose list-delivery-streams --output json
# OpenSearch / ES domains
aws opensearch list-domain-names --output json 2>/dev/null || aws es list-domain-names --output json
# Subscription filters on log groups
aws logs describe-subscription-filters --log-group-name {name} --output json
```

| Result | Severity | Finding |
|---|---|---|
| No SIEM / centralized pipe detected | GAP | No evidence of centralized log aggregation — manual review only |
| SIEM pipe detected | INFO | Centralized logging detected ✅ |

This is informational because CJIS doesn't mandate a SIEM, but regular log review does require some aggregation mechanism. Confirm with the user.

---

## PA4-10: Application-level CJI access logging (questionnaire)

No AWS API can verify this — CloudTrail logs infrastructure events, not who read which CJI record. Surface as an organizational question:

```markdown
- [ ] Does your application log every CJI read/write event (user, record, timestamp)?
- [ ] Are application logs shipped to the same retention-protected store as CloudTrail?
- [ ] Is there a documented log review cadence?
```

Mark as `ORGANIZATIONAL` in the report.

---

## Summary

| Check | ID | Key question |
|---|---|---|
| CloudTrail enabled | PA4-01 | Are API calls being logged? |
| CloudTrail actively logging | PA4-02 | Is logging currently flowing? |
| Log file validation | PA4-03 | Can tampering be detected? |
| Logs KMS-encrypted | PA4-04 | Are logs encrypted with a CMK? |
| S3 data events | PA4-05 | Are object-level CJI access events logged? |
| VPC Flow Logs | PA4-06 | Is network traffic logged? |
| Log retention ≥1yr | PA4-07 | Are logs retained per CJIS minimum? |
| Log bucket tamper-resistance | PA4-08 | Are logs protected from deletion? |
| Centralized aggregation | PA4-09 | Are logs aggregated for review? |
| Application CJI logging | PA4-10 | (Questionnaire) Does the app log CJI access? |

**Total: 10 checks** (9 automated + 1 questionnaire). Expected time: ~2-3 min.
