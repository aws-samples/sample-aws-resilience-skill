# SI — System and Information Integrity — Programmatic Checks

> Based on CJIS Security Policy v6.0 (effective December 2024).
> Last verified against official source: 2025-05-21.
> Check https://le.fbi.gov/cjis-division/cjis-security-policy-resource-center for newer versions.

> Execute in order. Each check uses read-only AWS CLI. Record results as
> `COMPLIANT` / `NON_COMPLIANT` / `NOT_APPLICABLE` / `UNABLE_TO_ASSESS` with severity per
> [`../severity-classification.md`](../severity-classification.md).

SI family (Priority P1) — flaw remediation, malicious code protection, system monitoring, software integrity.

---

## SI-02-01: Inspector findings — critical/high vulnerabilities

**CJIS reference**: CJIS v6.0 SI-2 | **Priority**: P1

```bash
aws inspector2 batch-get-account-status --query 'accounts[].{AccountId:accountId,Ec2:resourceState.ec2.status,Ecr:resourceState.ecr.status,Lambda:resourceState.lambda.status}' --output json 2>/dev/null
aws inspector2 list-findings --filter-criteria '{"severity":[{"comparison":"EQUALS","value":"CRITICAL"}]}' --max-results 10 --query 'findings[].{Title:title,Severity:severity,Resource:resources[0].id}' --output json 2>/dev/null
```

| Result | Severity | Finding |
|---|---|---|
| Inspector not enabled | AUDIT BLOCKER | Inspector not scanning — no flaw remediation baseline (SI-2 failure) |
| CRITICAL findings on CJI workloads | AUDIT BLOCKER | {count} CRITICAL vulnerabilities on CJI-adjacent resources |
| HIGH findings present | FINDING RISK | {count} HIGH vulnerabilities require remediation |
| No critical/high findings | INFO | No critical Inspector findings |

**Rationale**: SI-2 requires identification and remediation of flaws. Without vulnerability scanning, the organization cannot demonstrate compliance.

---

## SI-02-02: SSM Patch Manager compliance

**CJIS reference**: CJIS v6.0 SI-2 | **Priority**: P1

```bash
aws ssm list-compliance-summaries --query 'ComplianceSummaryItems[?ComplianceType==`Patch`].{Type:ComplianceType,Compliant:CompliantSummary.CompliantCount,NonCompliant:NonCompliantSummary.NonCompliantCount}' --output json
```

| Result | Severity | Finding |
|---|---|---|
| `NonCompliantCount > 0` | FINDING RISK | {count} instances non-compliant with patch baseline |
| All compliant | INFO | Patch compliance at 100% |
| Patch Manager not configured | FINDING RISK | No patch baseline — flaw remediation not automated |

---

## SI-03-01: GuardDuty Malware Protection enabled

**CJIS reference**: CJIS v6.0 SI-3 | **Priority**: P1

```bash
aws guardduty list-detectors --output text | tr '\t' '\n' | while read det; do
  aws guardduty get-detector --detector-id "$det" --query 'Features[?Name==`EBS_MALWARE_PROTECTION`].{Name:Name,Status:Status}' --output json 2>/dev/null
done
```

| Result | Severity | Finding |
|---|---|---|
| No GuardDuty detector | AUDIT BLOCKER | GuardDuty not enabled — no malware detection |
| GuardDuty enabled but Malware Protection disabled | FINDING RISK | GuardDuty Malware Protection not enabled — SI-3 gap |
| Malware Protection enabled | INFO | Malicious code protection active |

**Rationale**: SI-3 requires malicious code protection mechanisms at system entry/exit points. GuardDuty Malware Protection scans EBS volumes for malware.

---

## SI-04-01: GuardDuty enabled (system monitoring)

**CJIS reference**: CJIS v6.0 SI-4 | **Priority**: P1

```bash
aws guardduty list-detectors --output json
```

| Result | Severity | Finding |
|---|---|---|
| No detectors | AUDIT BLOCKER | GuardDuty not enabled — no system monitoring for threats |
| Detector active | INFO | GuardDuty system monitoring active |

---

## SI-04-02: Security Hub enabled

**CJIS reference**: CJIS v6.0 SI-4 | **Priority**: P1

```bash
aws securityhub describe-hub --output json 2>/dev/null
```

| Result | Severity | Finding |
|---|---|---|
| Security Hub not enabled | FINDING RISK | Security Hub not enabled — no aggregated security monitoring |
| Security Hub enabled | INFO | Security Hub providing aggregated monitoring |

---

## SI-04-03: CloudWatch alarms for security events

**CJIS reference**: CJIS v6.0 SI-4 | **Priority**: P1

```bash
aws cloudwatch describe-alarms --query 'MetricAlarms[?contains(AlarmName, `Security`) || contains(AlarmName, `Unauthorized`) || contains(AlarmName, `Root`) || contains(AlarmName, `IAM`)].{Name:AlarmName,State:StateValue}' --output json
```

| Result | Severity | Finding |
|---|---|---|
| No security-related alarms | FINDING RISK | No CloudWatch alarms for security events — SI-4 monitoring gap |
| Security alarms configured | INFO | Security event alerting in place |

---

## SI-07-01: ECR image scanning enabled

**CJIS reference**: CJIS v6.0 SI-7 | **Priority**: P1

```bash
aws ecr describe-repositories --query 'repositories[].{Name:repositoryName,ScanOnPush:imageScanningConfiguration.scanOnPush}' --output json 2>/dev/null
```

| Result | Severity | Finding |
|---|---|---|
| Repositories with `scanOnPush: false` | FINDING RISK | ECR repository `{name}` not scanning images — software integrity gap |
| All repositories scan on push | INFO | ECR image scanning enabled |
| No ECR repositories | NOT_APPLICABLE | — |

---

## SI-07-02: Lambda code signing (if Lambda processes CJI)

**CJIS reference**: CJIS v6.0 SI-7 | **Priority**: P1

```bash
aws lambda list-code-signing-configs --query 'CodeSigningConfigs[].{Id:CodeSigningConfigId,Description:Description}' --output json 2>/dev/null
aws lambda list-functions --query 'Functions[].{Name:FunctionName,CodeSigningConfig:CodeSigningConfigArn}' --output json
```

| Result | Severity | Finding |
|---|---|---|
| Lambda functions with no code signing config | GAP | Lambda functions without code signing — consider for CJI-processing functions |
| Code signing configs applied to CJI functions | INFO | Lambda code signing in use |
| No Lambda functions | NOT_APPLICABLE | — |

---

## Summary

| Check | ID | Key question |
|---|---|---|
| Inspector findings | SI-02-01 | Are vulnerabilities identified? |
| Patch compliance | SI-02-02 | Are systems patched? |
| Malware Protection | SI-03-01 | Is malware scanning active? |
| GuardDuty monitoring | SI-04-01 | Is threat monitoring active? |
| Security Hub | SI-04-02 | Is security posture aggregated? |
| Security alarms | SI-04-03 | Are security events alerted? |
| ECR scanning | SI-07-01 | Are container images scanned? |
| Lambda code signing | SI-07-02 | Is function code verified? |

**Total: 8 checks.** Expected time: ~2 min.
