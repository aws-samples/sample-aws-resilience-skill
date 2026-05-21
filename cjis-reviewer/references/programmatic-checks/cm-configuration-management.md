# CM — Configuration Management — Programmatic Checks

> Based on CJIS Security Policy v6.0 (effective December 2024).
> Last verified against official source: 2026-05-21.
> Check https://le.fbi.gov/cjis-division/cjis-security-policy-resource-center for newer versions.

> Execute in order. Each check uses read-only AWS CLI. Record results as
> `COMPLIANT` / `NON_COMPLIANT` / `NOT_APPLICABLE` / `UNABLE_TO_ASSESS` with severity per
> [`../severity-classification.md`](../severity-classification.md).

CM family (Priority P1) — baseline configurations, formal change management, patch management, least functionality, system component inventory.

---

## CM-02-01: AWS Config recording enabled

**CJIS reference**: CJIS v6.0 CM-2 | **Priority**: P1*

```bash
aws configservice describe-configuration-recorders --query 'ConfigurationRecorders[].{Name:name,Recording:recordingGroup,Role:roleARN}' --output json
aws configservice describe-configuration-recorder-status --query 'ConfigurationRecordersStatus[].{Name:name,Recording:recording,LastStatus:lastStatus}' --output json
```

| Result | Severity | Finding |
|---|---|---|
| No recorders | AUDIT BLOCKER | AWS Config not enabled — no baseline configuration tracking |
| Recorder exists but `recording: false` | AUDIT BLOCKER | Config recorder stopped — configuration changes untracked |
| Recorder with `allSupported: false` | FINDING RISK | Config not recording all resource types |
| Recording all supported | INFO | AWS Config active |

**Rationale**: CM-2 requires documented baseline configurations for systems. AWS Config provides the foundational config recording for all AWS resources.

---

## CM-02-02: Config rules deployed for compliance baselines

**CJIS reference**: CJIS v6.0 CM-2 | **Priority**: P1*

```bash
aws configservice describe-config-rules --query 'ConfigRules[].{Name:ConfigRuleName,State:ConfigRuleState,Source:Source.Owner}' --output json | head -50
aws configservice describe-conformance-packs --query 'ConformancePackDetails[].{Name:ConformancePackName}' --output json 2>/dev/null
```

| Result | Severity | Finding |
|---|---|---|
| No Config rules deployed | FINDING RISK | No compliance rules — baselines not enforced |
| Rules exist but no CJIS-relevant conformance pack | GAP | Consider deploying NIST 800-53 or FedRAMP conformance pack |
| CJIS-relevant rules or conformance pack active | INFO | Baseline compliance rules deployed |

---

## CM-03-01: Change control — Config change tracking

**CJIS reference**: CJIS v6.0 CM-3 | **Priority**: P1*

```bash
aws configservice describe-delivery-channels --query 'DeliveryChannels[].{Name:name,S3Bucket:s3BucketName,SnsArn:snsTopicARN}' --output json
```

| Result | Severity | Finding |
|---|---|---|
| No delivery channel (no change notifications) | FINDING RISK | Config changes not being delivered/stored — change control gap |
| Delivery channel with S3 + SNS | INFO | Configuration changes tracked and delivered |
| Delivery channel with S3 only (no SNS) | GAP | No real-time change notification — consider adding SNS |

---

## CM-06-01: Security Hub CIS/NIST benchmark score

**CJIS reference**: CJIS v6.0 CM-6 | **Priority**: P1*

```bash
aws securityhub describe-hub --output json 2>/dev/null
aws securityhub get-enabled-standards --query 'StandardsSubscriptions[].{Arn:StandardsArn,Status:StandardsStatus}' --output json 2>/dev/null
```

CJIS-relevant standards: `NIST SP 800-53 Rev 5`, `CIS AWS Foundations Benchmark`, `AWS Foundational Security Best Practices`, `FedRAMP`.

| Result | Severity | Finding |
|---|---|---|
| Security Hub not enabled | FINDING RISK | Security Hub not enabled — no continuous posture assessment |
| Enabled but no CJIS-relevant standards | GAP | Enable NIST 800-53 or FedRAMP standard for CJIS alignment |
| CJIS-relevant standards active | INFO | Continuous compliance posture monitoring active |

---

## CM-07-01: Least functionality — unnecessary ports blocked

**CJIS reference**: CJIS v6.0 CM-7 | **Priority**: P1*

```bash
aws ec2 describe-security-groups --query 'SecurityGroups[?IpPermissions[?IpProtocol==`-1` && IpRanges[?CidrIp==`0.0.0.0/0`]]].{Id:GroupId,Name:GroupName}' --output json
# Lambda public access:
aws lambda list-functions --query 'Functions[].FunctionName' --output text | tr '\t' '\n' | while read fn; do
  pol=$(aws lambda get-policy --function-name "$fn" 2>/dev/null)
  echo "$pol" | grep -q '"Principal":"*"' && echo "$fn: PUBLIC LAMBDA"
done 2>/dev/null
```

| Result | Severity | Finding |
|---|---|---|
| SGs allowing all-traffic from 0.0.0.0/0 | AUDIT BLOCKER | Security group `{id}` allows ALL traffic from internet |
| Publicly invocable Lambda functions | FINDING RISK | Lambda `{fn}` publicly accessible — review necessity |
| All ports restricted, no public Lambda | INFO | Least functionality enforced |

---

## CM-08-01: System component inventory — Config resource inventory

**CJIS reference**: CJIS v6.0 CM-8 | **Priority**: P1*

```bash
aws configservice get-discovered-resource-counts --query 'resourceCounts[].{Type:resourceType,Count:count}' --output json
# SSM managed instances:
aws ssm describe-instance-information --query 'InstanceInformationList[].{Id:InstanceId,Platform:PlatformType,PingStatus:PingStatus}' --output json
```

| Result | Severity | Finding |
|---|---|---|
| Config not recording (no inventory) | AUDIT BLOCKER | No resource inventory available — CM-8 requires component tracking |
| Config recording but SSM incomplete | FINDING RISK | {count} running instances not SSM-managed — incomplete inventory |
| Config + SSM covering all instances | INFO | System component inventory complete |

---

## CM-08-02: SSM managed instances coverage

**CJIS reference**: CJIS v6.0 CM-8 | **Priority**: P1*

```bash
aws ec2 describe-instances --filters Name=instance-state-name,Values=running --query 'Reservations[].Instances[].InstanceId' --output text | tr '\t' '\n' | sort > /tmp/ec2-running.txt
aws ssm describe-instance-information --query 'InstanceInformationList[].InstanceId' --output text | tr '\t' '\n' | sort > /tmp/ssm-managed.txt
comm -23 /tmp/ec2-running.txt /tmp/ssm-managed.txt
```

| Result | Severity | Finding |
|---|---|---|
| Running instances not in SSM | FINDING RISK | {count} EC2 instances not managed by SSM — cannot verify patch/config state |
| All running instances in SSM | INFO | SSM manages all running instances |
| No running instances | NOT_APPLICABLE | — |

---

## CM-12-01: Information location — CJI resource mapping

**CJIS reference**: CJIS v6.0 CM-12 | **Priority**: P1

```bash
aws configservice select-resource-config --expression "SELECT resourceType, resourceId, awsRegion WHERE resourceType IN ('AWS::S3::Bucket', 'AWS::RDS::DBInstance', 'AWS::DynamoDB::Table', 'AWS::EFS::FileSystem')" --output json 2>/dev/null
```

| Result | Severity | Finding |
|---|---|---|
| Config Advanced Queries not available | GAP | Cannot programmatically map CJI data locations — confirm manually |
| Query returns resources across multiple regions | GAP | Data resources in multiple regions — verify CJI is only in approved regions |
| Resources in single approved region | INFO | CJI resource locations identifiable |

---

## Summary

| Check | ID | Key question |
|---|---|---|
| AWS Config enabled | CM-02-01 | Is baseline config tracking on? |
| Config rules | CM-02-02 | Are compliance baselines enforced? |
| Change tracking | CM-03-01 | Are changes recorded and notified? |
| Security Hub standards | CM-06-01 | Is posture continuously assessed? |
| Least functionality | CM-07-01 | Are unnecessary functions restricted? |
| Resource inventory | CM-08-01 | Is a system component inventory maintained? |
| SSM coverage | CM-08-02 | Are all instances managed? |
| Information location | CM-12-01 | Can CJI resource locations be identified? |

**Total: 8 checks.** Expected time: ~3 min.
