# PA 7 — Configuration Management — Programmatic Checks

> Execute in order. Read-only AWS CLI. Severity per [`../severity-classification.md`](../severity-classification.md).

CJIS PA 7 (Section 5.7) — baseline configurations, formal change management, patch management, restrict software installation.

---

## PA7-01: AWS Config enabled

```bash
aws configservice describe-configuration-recorders --query 'ConfigurationRecorders[].{Name:name,Recording:recordingGroup,Role:roleARN}' --output json
aws configservice describe-configuration-recorder-status --query 'ConfigurationRecordersStatus[].{Name:name,Recording:recording,LastStatus:lastStatus}' --output json
```

| Result | Severity | Finding |
|---|---|---|
| No recorders | FINDING RISK | AWS Config not enabled — no config-change audit trail |
| Recorder exists but `recording: false` | FINDING RISK | Config recorder stopped |
| Recorder with `allSupported: false` | GAP | Config not recording all resource types |
| Recording all supported | INFO | AWS Config active ✅ |

---

## PA7-02: Config conformance packs or Security Hub aligned to CJIS

```bash
aws configservice describe-conformance-packs --query 'ConformancePackDetails[].{Name:ConformancePackName,Arn:ConformancePackArn}' --output json 2>/dev/null
aws securityhub describe-hub --output json 2>/dev/null
aws securityhub get-enabled-standards --query 'StandardsSubscriptions[].StandardsArn' --output json 2>/dev/null
```

CJIS-relevant standards to look for:
- `FedRAMP-Moderate` / `FedRAMP-High` (strong overlap with CJIS)
- `CIS AWS Foundations Benchmark`
- `AWS Foundational Security Best Practices`
- `NIST SP 800-53 Rev 5`

| Result | Severity | Finding |
|---|---|---|
| Security Hub not enabled | GAP | Security Hub not enabled — no continuous compliance posture |
| Enabled but no CJIS-relevant standards | GAP | Consider enabling FedRAMP or NIST 800-53 standards (inherited controls) |
| CJIS-relevant standards active | INFO | Continuous compliance standards active ✅ |

---

## PA7-03: Systems Manager managed instances coverage

```bash
aws ec2 describe-instances --filters Name=instance-state-name,Values=running --query 'Reservations[].Instances[].InstanceId' --output text | tr '\t' '\n' | sort > /tmp/ec2-running.txt
aws ssm describe-instance-information --query 'InstanceInformationList[].InstanceId' --output text | tr '\t' '\n' | sort > /tmp/ssm-managed.txt
comm -23 /tmp/ec2-running.txt /tmp/ssm-managed.txt
```

| Result | Severity | Finding |
|---|---|---|
| Running instances not in SSM | FINDING RISK | {count} EC2 instances not managed by SSM — cannot verify patch/config state |
| All running instances in SSM | INFO | SSM manages all running instances ✅ |
| No running instances | NOT_APPLICABLE | — |

---

## PA7-04: SSM Patch Manager compliance

```bash
aws ssm describe-instance-patch-states-for-patch-group --patch-group "{group}" 2>/dev/null
# Or account-wide patch compliance summary:
aws ssm list-compliance-summaries --query 'ComplianceSummaryItems[?ComplianceType==`Patch`].{Type:ComplianceType,Compliant:CompliantSummary.CompliantCount,NonCompliant:NonCompliantSummary.NonCompliantCount}' --output json
```

| Result | Severity | Finding |
|---|---|---|
| `NonCompliantCount > 0` | FINDING RISK | {count} instances non-compliant with patch baseline |
| All compliant | INFO | Patch compliance at 100% ✅ |
| Patch Manager not configured | GAP | No patch baseline — automate via SSM Patch Manager |

---

## PA7-05: AMI ages (stale AMIs indicate stale patching)

```bash
account=$(aws sts get-caller-identity --query Account --output text)
aws ec2 describe-images --owners $account --query 'Images[].{Id:ImageId,Name:Name,Created:CreationDate}' --output json
# Flag AMIs older than 90 days that are in use:
aws ec2 describe-instances --query 'Reservations[].Instances[].ImageId' --output text | tr '\t' '\n' | sort -u
```

| Result | Severity | Finding |
|---|---|---|
| In-use AMIs older than 90 days | GAP | {count} AMIs in use older than 90 days — may carry stale packages |
| All in-use AMIs recent | INFO | Current AMIs in use ✅ |

This is GAP not FINDING RISK because an old AMI can still be patched post-boot via SSM. Flag only as a signal of possibly-stale baselines.

---

## PA7-06: Inspector findings (vuln scan)

```bash
aws inspector2 batch-get-account-status --query 'accounts[].resourceState' --output json 2>/dev/null
aws inspector2 list-findings --filter-criteria '{"severity":[{"comparison":"EQUALS","value":"CRITICAL"}]}' --max-results 10 --query 'findings[].{Title:title,Severity:severity,Resource:resources[0].id}' --output json 2>/dev/null
```

| Result | Severity | Finding |
|---|---|---|
| Inspector not enabled | GAP | Inspector not scanning — no vulnerability baseline |
| `CRITICAL` Inspector findings on CJI workloads | FINDING RISK | {count} CRITICAL vulns on CJI-adjacent resources |
| No critical findings | INFO | No critical Inspector findings ✅ |

---

## PA7-07: CloudFormation / IaC usage (baseline-as-code indicator)

```bash
aws cloudformation list-stacks --stack-status-filter CREATE_COMPLETE UPDATE_COMPLETE --query 'StackSummaries[].{Name:StackName,Created:CreationTime}' --output json | head
# Also check for Terraform backend buckets
aws s3api list-buckets --query 'Buckets[?contains(Name,`terraform`) || contains(Name,`tf-state`)].Name' --output json
```

| Result | Severity | Finding |
|---|---|---|
| No CFN stacks AND no TF state evidence | GAP | No IaC detected — consider IaC for reproducible baselines (PA 7 best practice) |
| CFN or TF in use | INFO | IaC in use ✅ |

Advisory GAP only — CJIS doesn't mandate IaC, but it makes PA 7 evidence easier at audit.

---

## PA7-08: Default security group tight (AWS best practice for CJIS)

```bash
aws ec2 describe-security-groups --filters Name=group-name,Values=default --query 'SecurityGroups[].{Id:GroupId,Vpc:VpcId,Ingress:length(IpPermissions),Egress:length(IpPermissionsEgress)}' --output json
```

| Result | Severity | Finding |
|---|---|---|
| Any default SG with non-empty ingress or egress rules | GAP | Default SG `{id}` has rules — should be empty to prevent accidental use |
| All default SGs empty | INFO | Default SGs locked down ✅ |

---

## Summary

| Check | ID | Key question |
|---|---|---|
| AWS Config | PA7-01 | Is config-change logging on? |
| Compliance standards | PA7-02 | Are CJIS-relevant standards monitored? |
| SSM coverage | PA7-03 | Are all instances managed? |
| Patch compliance | PA7-04 | Are instances patched? |
| AMI age | PA7-05 | Are baselines current? |
| Vuln scan | PA7-06 | Are vulnerabilities tracked? |
| IaC | PA7-07 | Are baselines codified? |
| Default SGs | PA7-08 | Are default SGs locked down? |

**Total: 8 checks.** Expected time: ~3 min.
