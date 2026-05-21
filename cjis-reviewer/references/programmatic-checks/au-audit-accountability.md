# AU — Audit and Accountability — Programmatic Checks

> Based on CJIS Security Policy v6.0 (effective December 2024).
> Last verified against official source: 2026-05-21.
> Check https://le.fbi.gov/cjis-division/cjis-security-policy-resource-center for newer versions.

> Execute in order. Each check uses read-only AWS CLI. Record results as
> `COMPLIANT` / `NON_COMPLIANT` / `NOT_APPLICABLE` / `UNABLE_TO_ASSESS` with severity per
> [`../severity-classification.md`](../severity-classification.md).

AU family (Priority P2) requires: log all CJI-related events, retain per policy, protect logs from tampering, review regularly.

Key distinction: AWS CloudTrail logs **API calls**, not **application-level CJI access**. Application logging is a separate audit-evidence item — flag it in the report even if CloudTrail is perfect.

---

## AU-02-01: CloudTrail enabled in all regions (multi-region trail)

**CJIS reference**: CJIS v6.0 AU-2 | **Priority**: P2*

```bash
aws cloudtrail describe-trails --query 'trailList[].{Name:Name,IsMultiRegion:IsMultiRegionTrail,IsOrgTrail:IsOrganizationTrail,S3Bucket:S3BucketName,KmsKey:KmsKeyId}' --output json
```

| Result | Severity | Finding |
|---|---|---|
| No trails found | FINDING RISK | CloudTrail not configured — no API audit logging (AU-2 failure) |
| Trails exist but none multi-region | FINDING RISK | CloudTrail not multi-region — blind spots in other regions |
| Multi-region trail exists | — | Proceed to AU-02-02 |

**Rationale**: AU-2 requires audit event generation for all CJI systems. A multi-region trail ensures no region has a blind spot.

---

## AU-02-02: CloudTrail is actively logging

**CJIS reference**: CJIS v6.0 AU-2 | **Priority**: P2*

For each trail from AU-02-01:

```bash
aws cloudtrail get-trail-status --name {trail_arn_or_name} --query '{IsLogging:IsLogging,LatestDeliveryTime:LatestDeliveryTime,LatestDeliveryError:LatestDeliveryError}' --output json
```

| Result | Severity | Finding |
|---|---|---|
| `IsLogging: false` | FINDING RISK | CloudTrail trail `{name}` exists but logging is stopped |
| Delivery error present | FINDING RISK | CloudTrail delivery errors — logs may be incomplete |
| Logging, no errors | INFO | CloudTrail actively logging |

---

## AU-03-01: CloudTrail data events for CJI S3 buckets and Lambda

**CJIS reference**: CJIS v6.0 AU-3 | **Priority**: P2*

```bash
aws cloudtrail get-event-selectors --trail-name {trail_arn} --query 'EventSelectors[].{ReadWrite:ReadWriteType,DataResources:DataResources}' --output json
# Or for advanced event selectors:
aws cloudtrail get-event-selectors --trail-name {trail_arn} --query 'AdvancedEventSelectors' --output json
```

| Result | Severity | Finding |
|---|---|---|
| No S3 or Lambda data events configured | FINDING RISK | Object-level access to potential CJI buckets and Lambda invocations not logged |
| S3 data events for "all buckets" + Lambda | INFO | Data events captured |
| Data events limited to named resources | INFO | Confirm the listed resources cover all CJI assets (manual check) |

**Rationale**: AU-3 requires content of audit records to include details sufficient for after-the-fact investigation. Object-level events provide the who/what/when for CJI data access.

---

## AU-04-01: Log storage capacity — S3 log bucket lifecycle

**CJIS reference**: CJIS v6.0 AU-4 | **Priority**: P2*

```bash
aws s3api list-buckets --query 'Buckets[].Name' --output text | tr '\t' '\n' | grep -i -E '(log|trail|audit)' | while read b; do
  aws s3api get-bucket-lifecycle-configuration --bucket "$b" --output json 2>/dev/null || echo "$b: NO LIFECYCLE"
done
```

| Result | Severity | Finding |
|---|---|---|
| Log buckets with deletion lifecycle < 3 years | FINDING RISK | Log bucket `{name}` lifecycle deletes before CJIS retention minimum |
| No lifecycle (infinite retention) | INFO | Log retention unlimited |
| Lifecycle retains ≥3 years | INFO | Log storage meets retention requirement |

---

## AU-05-01: CloudTrail log delivery failure alarms

**CJIS reference**: CJIS v6.0 AU-5 | **Priority**: P2*

```bash
aws cloudwatch describe-alarms --query 'MetricAlarms[?MetricName==`CloudTrailDeliveryFailed` || contains(AlarmName, `CloudTrail`) || contains(AlarmName, `cloudtrail`)].{Name:AlarmName,State:StateValue}' --output json
```

| Result | Severity | Finding |
|---|---|---|
| No alarms for CloudTrail delivery failures | FINDING RISK | No alerting on audit log delivery failures — AU-5 requires response to failures |
| Alarm configured and OK | INFO | CloudTrail delivery failure alerting in place |

**Rationale**: AU-5 requires alerting personnel in event of audit logging process failure and taking additional actions as needed.

---

## AU-06-01: CloudTrail Lake or Athena query capability

**CJIS reference**: CJIS v6.0 AU-6 | **Priority**: P2*

```bash
aws cloudtrail list-event-data-stores --query 'EventDataStores[].{Name:Name,Status:Status}' --output json 2>/dev/null
aws securityhub describe-hub --output json 2>/dev/null
```

| Result | Severity | Finding |
|---|---|---|
| No CloudTrail Lake or Security Hub | GAP | No evidence of log analysis/review capability — AU-6 requires audit record review |
| CloudTrail Lake or Security Hub active | INFO | Audit review capability in place |

---

## AU-08-01: CloudTrail log validation enabled (timestamp integrity)

**CJIS reference**: CJIS v6.0 AU-8 | **Priority**: P2*

```bash
aws cloudtrail describe-trails --query 'trailList[].{Name:Name,LogFileValidation:LogFileValidationEnabled}' --output json
```

| Result | Severity | Finding |
|---|---|---|
| `LogFileValidation: false` | FINDING RISK | Log file validation disabled — cannot verify log timestamp integrity |
| `LogFileValidation: true` | INFO | Log integrity validation enabled |

**Rationale**: AU-8 requires timestamps in audit records. Log file validation ensures digest integrity including timestamps.

---

## AU-09-01: CloudTrail logs encrypted with KMS CMK

**CJIS reference**: CJIS v6.0 AU-9 | **Priority**: P2*

```bash
aws cloudtrail describe-trails --query 'trailList[].{Name:Name,KmsKeyId:KmsKeyId}' --output json
```

| Result | Severity | Finding |
|---|---|---|
| `KmsKeyId: null` | FINDING RISK | CloudTrail logs not encrypted with CMK (SSE-S3 only) |
| KMS key ID present | INFO | CloudTrail logs KMS-encrypted |

---

## AU-09-02: S3 log bucket Object Lock for tamper resistance

**CJIS reference**: CJIS v6.0 AU-9 | **Priority**: P2*

Identify CloudTrail/flow-log destination buckets. For each:

```bash
aws s3api get-object-lock-configuration --bucket {bucket} 2>/dev/null
aws s3api get-bucket-policy --bucket {bucket} --query Policy --output text 2>/dev/null
```

| Result | Severity | Finding |
|---|---|---|
| No Object Lock and bucket policy allows deletes | FINDING RISK | Log bucket `{name}` can be modified/deleted — not tamper-resistant |
| Object Lock in Governance or Compliance mode | INFO | Log tamper-resistance in place |
| Bucket policy denies delete/put across principals | INFO | Logs protected via bucket policy |

---

## AU-11-01: Log retention aligned with CJIS requirements (3+ years)

**CJIS reference**: CJIS v6.0 AU-11 | **Priority**: P2*

```bash
aws logs describe-log-groups --query 'logGroups[].{Name:logGroupName,Retention:retentionInDays}' --output json
```

| Result | Severity | Finding |
|---|---|---|
| Log groups with `retentionInDays < 1095` (3 years) and not `null` | FINDING RISK | {count} CloudWatch Log Groups with retention below CJIS minimum (3 years) |
| All ≥1095 or never-expire (`null`) | INFO | Log retention meets CJIS minimum |

Note: `null` retention = never expires, which is compliant (exceeds requirement).

---

## AU-12-01: VPC Flow Logs enabled for CJI subnets

**CJIS reference**: CJIS v6.0 AU-12 | **Priority**: P2*

```bash
aws ec2 describe-vpcs --query 'Vpcs[].VpcId' --output text | tr '\t' '\n' | while read vpc; do
  logs=$(aws ec2 describe-flow-logs --filter Name=resource-id,Values=$vpc --query 'FlowLogs[?FlowLogStatus==`ACTIVE`].FlowLogId' --output text)
  [ -z "$logs" ] && echo "$vpc: NO ACTIVE FLOW LOGS"
done
```

| Result | Severity | Finding |
|---|---|---|
| Any CJI VPC without active flow logs | FINDING RISK | VPC `{id}` has no flow logs — limited network audit capability |
| All VPCs have flow logs | INFO | VPC flow logging complete |

**Rationale**: AU-12 requires audit record generation at system components. VPC Flow Logs provide network-level audit records for CJI traffic.

---

## Summary

| Check | ID | Key question |
|---|---|---|
| CloudTrail enabled | AU-02-01 | Are API calls being logged? |
| CloudTrail actively logging | AU-02-02 | Is logging currently flowing? |
| Data events | AU-03-01 | Are object-level CJI access events logged? |
| Log storage capacity | AU-04-01 | Are log buckets sized/retained properly? |
| Delivery failure alerts | AU-05-01 | Are log failures detected? |
| Audit review capability | AU-06-01 | Can logs be queried and reviewed? |
| Log validation (timestamps) | AU-08-01 | Can tampering be detected? |
| Log encryption | AU-09-01 | Are logs encrypted with a CMK? |
| Log tamper-resistance | AU-09-02 | Are logs protected from deletion? |
| Log retention | AU-11-01 | Are logs retained per CJIS minimum (3 years)? |
| VPC Flow Logs | AU-12-01 | Is network traffic logged? |

**Total: 11 checks** (all automated). Expected time: ~2-3 min.
