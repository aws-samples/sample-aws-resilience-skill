# Security Pillar — Programmatic Checks

> Execute these checks in order. Each check uses AWS CLI (read-only).
> Record findings with severity: CRITICAL / HIGH / MEDIUM / LOW / INFO

---

## SEC-01: GuardDuty Status

```bash
aws guardduty list-detectors --query 'DetectorIds' --output json
# If empty → CRITICAL: GuardDuty not enabled
# If found → check each detector:
aws guardduty get-detector --detector-id {id} --query '{Status:Status,FindingPublishingFrequency:FindingPublishingFrequency}' --output json
```

| Result | Severity | Finding |
|--------|----------|---------|
| No detectors | CRITICAL | GuardDuty not enabled — no threat detection |
| Status=DISABLED | CRITICAL | GuardDuty detector disabled |
| Status=ENABLED | INFO | GuardDuty active ✅ |

---

## SEC-02: Security Hub Status

```bash
aws securityhub describe-hub --output json 2>/dev/null
# If error → Security Hub not enabled
aws securityhub get-findings --filters '{"SeverityLabel":[{"Value":"CRITICAL","Comparison":"EQUALS"}]}' --max-items 5 --query 'Findings[].{Title:Title,Severity:Severity.Label,Resource:Resources[0].Id}' --output json
```

| Result | Severity | Finding |
|--------|----------|---------|
| Not enabled | HIGH | Security Hub not enabled — no centralized security view |
| Enabled, CRITICAL findings | HIGH | {count} unresolved CRITICAL Security Hub findings |
| Enabled, no CRITICAL | INFO | Security Hub active, no critical findings ✅ |

---

## SEC-03: CloudTrail Status

```bash
aws cloudtrail describe-trails --query 'trailList[].{Name:Name,IsMultiRegion:IsMultiRegionTrail,IsLogging:HasCustomEventSelectors,S3Bucket:S3BucketName}' --output json
aws cloudtrail get-trail-status --name {trail-name} --query '{IsLogging:IsLogging,LatestDeliveryTime:LatestDeliveryTime}' --output json
```

| Result | Severity | Finding |
|--------|----------|---------|
| No trails | CRITICAL | CloudTrail not configured — no API audit logging |
| Trail exists but not logging | HIGH | CloudTrail trail exists but logging stopped |
| Multi-region trail active | INFO | CloudTrail active with multi-region ✅ |

---

## SEC-04: IAM Password Policy

```bash
aws iam get-account-password-policy --output json 2>/dev/null
```

| Result | Severity | Finding |
|--------|----------|---------|
| No policy set | MEDIUM | No IAM password policy — weak password risk |
| MinPasswordLength < 14 | MEDIUM | Password minimum length below 14 characters |
| RequireSymbols=false | LOW | Password policy does not require symbols |
| All strong | INFO | Password policy meets best practices ✅ |

---

## SEC-05: IAM Access Keys Age

```bash
aws iam generate-credential-report >/dev/null 2>&1; sleep 2
aws iam get-credential-report --query 'Content' --output text | base64 -d | awk -F',' 'NR>1 && $9!="N/A" {split($9,a,"T"); if (systime()-mktime(gensub(/-/," ","g",a[1])" 0 0 0") > 7776000) print $1": key age > 90 days"}'
```

| Result | Severity | Finding |
|--------|----------|---------|
| Keys > 90 days | HIGH | {count} IAM users with access keys older than 90 days |
| Keys > 180 days | CRITICAL | {count} IAM users with access keys older than 180 days |
| All < 90 days | INFO | All access keys within rotation policy ✅ |

---

## SEC-06: Root Account MFA

```bash
aws iam get-account-summary --query 'SummaryMap.AccountMFAEnabled' --output text
```

| Result | Severity | Finding |
|--------|----------|---------|
| 0 | CRITICAL | Root account MFA not enabled |
| 1 | INFO | Root account MFA enabled ✅ |

---

## SEC-07: S3 Public Access

```bash
aws s3control get-public-access-block --account-id $(aws sts get-caller-identity --query Account --output text) --output json 2>/dev/null
# Per-bucket check:
aws s3api list-buckets --query 'Buckets[].Name' --output text | tr '\t' '\n' | while read b; do
  result=$(aws s3api get-public-access-block --bucket "$b" 2>/dev/null)
  if [ $? -ne 0 ]; then echo "WARN: $b — no public access block"; fi
done
```

| Result | Severity | Finding |
|--------|----------|---------|
| Account-level block disabled | HIGH | Account-level S3 public access block not enabled |
| Buckets without block | MEDIUM | {count} S3 buckets without public access block |
| All blocked | INFO | S3 public access blocked at account level ✅ |

---

## SEC-08: EBS Encryption Default

```bash
aws ec2 get-ebs-encryption-by-default --query 'EbsEncryptionByDefault' --output text
```

| Result | Severity | Finding |
|--------|----------|---------|
| false | MEDIUM | EBS encryption by default not enabled |
| true | INFO | EBS encryption by default enabled ✅ |

---

## SEC-09: Security Groups — Public Ingress

```bash
aws ec2 describe-security-groups --filters Name=ip-permission.cidr,Values=0.0.0.0/0 --query 'SecurityGroups[].{GroupId:GroupId,GroupName:GroupName,Rules:IpPermissions[?IpRanges[?CidrIp==`0.0.0.0/0`]].{Proto:IpProtocol,FromPort:FromPort,ToPort:ToPort}}' --output json
```

| Result | Severity | Finding |
|--------|----------|---------|
| SG allows 0.0.0.0/0 to SSH (22) | CRITICAL | Security Group {id} allows SSH from internet |
| SG allows 0.0.0.0/0 to RDP (3389) | CRITICAL | Security Group {id} allows RDP from internet |
| SG allows 0.0.0.0/0 to all ports | CRITICAL | Security Group {id} allows all traffic from internet |
| SG allows 0.0.0.0/0 to 443/80 only | LOW | Security Group {id} allows HTTP/HTTPS from internet (may be intentional) |
| No public ingress | INFO | No security groups with unrestricted public ingress ✅ |

---

## SEC-10: RDS Encryption

```bash
aws rds describe-db-instances --query 'DBInstances[].{DBId:DBInstanceIdentifier,Encrypted:StorageEncrypted,Engine:Engine}' --output json
aws rds describe-db-clusters --query 'DBClusters[].{ClusterId:DBClusterIdentifier,Encrypted:StorageEncrypted,Engine:Engine}' --output json
```

| Result | Severity | Finding |
|--------|----------|---------|
| Unencrypted instances | HIGH | {count} RDS instances without encryption at rest |
| All encrypted | INFO | All RDS instances encrypted ✅ |

---

## SEC-11: VPC Flow Logs

```bash
aws ec2 describe-vpcs --query 'Vpcs[].VpcId' --output text | tr '\t' '\n' | while read vpc; do
  logs=$(aws ec2 describe-flow-logs --filter Name=resource-id,Values=$vpc --query 'FlowLogs[0].FlowLogId' --output text)
  if [ "$logs" = "None" ]; then echo "WARN: $vpc — no flow logs"; fi
done
```

| Result | Severity | Finding |
|--------|----------|---------|
| VPC without flow logs | MEDIUM | VPC {id} has no flow logs — limited network visibility |
| All VPCs have flow logs | INFO | All VPCs have flow logs enabled ✅ |

---

## SEC-12: KMS Key Rotation

```bash
aws kms list-keys --query 'Keys[].KeyId' --output text | tr '\t' '\n' | while read key; do
  mgr=$(aws kms describe-key --key-id "$key" --query 'KeyMetadata.KeyManager' --output text)
  if [ "$mgr" = "CUSTOMER" ]; then
    rot=$(aws kms get-key-rotation-status --key-id "$key" --query 'KeyRotationEnabled' --output text)
    if [ "$rot" = "False" ]; then echo "WARN: $key — rotation disabled"; fi
  fi
done
```

| Result | Severity | Finding |
|--------|----------|---------|
| Customer keys without rotation | MEDIUM | {count} KMS customer keys without automatic rotation |
| All rotated | INFO | All customer KMS keys have rotation enabled ✅ |

---

## Summary

| Check | ID | Key Question |
|-------|----|-------------|
| GuardDuty | SEC-01 | Is threat detection active? |
| Security Hub | SEC-02 | Is there a centralized security view? |
| CloudTrail | SEC-03 | Are API calls audited? |
| Password Policy | SEC-04 | Are passwords strong? |
| Access Key Age | SEC-05 | Are keys rotated regularly? |
| Root MFA | SEC-06 | Is root protected? |
| S3 Public Access | SEC-07 | Is data exposure prevented? |
| EBS Encryption | SEC-08 | Is storage encrypted by default? |
| Public SGs | SEC-09 | Is network access restricted? |
| RDS Encryption | SEC-10 | Is database data encrypted? |
| VPC Flow Logs | SEC-11 | Is network traffic logged? |
| KMS Rotation | SEC-12 | Are encryption keys rotated? |

**Total checks: 12** | Expected time: ~3-5 minutes
