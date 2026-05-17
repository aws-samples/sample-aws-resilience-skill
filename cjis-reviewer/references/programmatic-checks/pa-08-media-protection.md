# PA 8 — Media Protection — Programmatic Checks

> Execute in order. Read-only AWS CLI. Severity per [`../severity-classification.md`](../severity-classification.md).

CJIS PA 8 (Section 5.8) — encrypt CJI at rest with FIPS 140-2/3 validated modules, sanitize media, control physical & digital media. In AWS, "FIPS 140-2 validated" = KMS HSMs, which are compliant by default. The real audit risk is **unencrypted CJI stores**, not non-FIPS crypto.

---

## PA8-01: EBS encryption by default (account-level)

```bash
aws ec2 get-ebs-encryption-by-default --query 'EbsEncryptionByDefault' --output text
```

| Result | Severity | Finding |
|---|---|---|
| `false` | FINDING RISK | EBS encryption-by-default disabled — new volumes may be created unencrypted |
| `true` | INFO | EBS default encryption on ✅ |

---

## PA8-02: No unencrypted EBS volumes

```bash
aws ec2 describe-volumes --filters Name=encrypted,Values=false --query 'Volumes[].{Id:VolumeId,Size:Size,Attached:Attachments[0].InstanceId}' --output json
```

| Result | Severity | Finding |
|---|---|---|
| Any unencrypted volumes attached to running instances | AUDIT BLOCKER | {count} unencrypted EBS volumes in use — possible CJI at rest without encryption |
| Unencrypted volumes exist but unattached | FINDING RISK | {count} unencrypted EBS snapshots/volumes present — remediate or delete |
| All encrypted | INFO | All EBS volumes encrypted ✅ |

Remediation: EBS can't be encrypted in place. Snapshot → copy snapshot with encryption → create volume from encrypted snapshot → swap.

---

## PA8-03: No unencrypted EBS snapshots (owned by this account)

```bash
account=$(aws sts get-caller-identity --query Account --output text)
aws ec2 describe-snapshots --owner-ids $account --filters Name=encrypted,Values=false --query 'Snapshots[].{Id:SnapshotId,VolumeId:VolumeId,Age:StartTime}' --output json
```

| Result | Severity | Finding |
|---|---|---|
| Any unencrypted snapshots | FINDING RISK | {count} unencrypted EBS snapshots — may contain CJI; copy encrypted + delete originals |
| All encrypted | INFO | All snapshots encrypted ✅ |

---

## PA8-04: All RDS instances encrypted at rest

```bash
aws rds describe-db-instances --query 'DBInstances[].{Id:DBInstanceIdentifier,Engine:Engine,Encrypted:StorageEncrypted,KmsKey:KmsKeyId}' --output json
aws rds describe-db-clusters --query 'DBClusters[].{Id:DBClusterIdentifier,Engine:Engine,Encrypted:StorageEncrypted,KmsKey:KmsKeyId}' --output json
```

| Result | Severity | Finding |
|---|---|---|
| No RDS instances/clusters | NOT_APPLICABLE | No RDS to assess |
| Any unencrypted instance/cluster | AUDIT BLOCKER | {count} RDS instances without encryption at rest — encryption cannot be added in place, requires snapshot migration |
| All encrypted | INFO | All RDS encrypted ✅ |

---

## PA8-05: RDS automated backups encrypted and retained

```bash
aws rds describe-db-instances --query 'DBInstances[].{Id:DBInstanceIdentifier,Retention:BackupRetentionPeriod,Encrypted:StorageEncrypted}' --output json
```

| Result | Severity | Finding |
|---|---|---|
| `BackupRetentionPeriod = 0` on any instance | FINDING RISK | {id} has automated backups disabled |
| Retention < 7 days | GAP | Low backup retention on {id} — consider longer for CJI recovery |
| All ≥ 7 days and encrypted | INFO | Backups retained and encrypted ✅ |

---

## PA8-06: S3 buckets have default encryption

```bash
aws s3api list-buckets --query 'Buckets[].Name' --output text | tr '\t' '\n' | while read b; do
  enc=$(aws s3api get-bucket-encryption --bucket "$b" --query 'ServerSideEncryptionConfiguration.Rules[0].ApplyServerSideEncryptionByDefault.SSEAlgorithm' --output text 2>/dev/null)
  [ -z "$enc" ] || [ "$enc" = "None" ] && echo "$b: NO DEFAULT ENCRYPTION"
done
```

Note: Since Jan 2023 S3 defaults to SSE-S3 for all new buckets, but verify anyway — older buckets may be unconfigured and the command explicitly reveals that.

| Result | Severity | Finding |
|---|---|---|
| Buckets without default encryption | AUDIT BLOCKER | {count} S3 buckets without default encryption — may contain CJI |
| All buckets with default encryption | INFO | All S3 buckets encrypted by default ✅ |

---

## PA8-07: S3 buckets encrypted with KMS (not SSE-S3)

For each bucket from PA8-06 that *has* encryption:

```bash
aws s3api get-bucket-encryption --bucket {b} --query 'ServerSideEncryptionConfiguration.Rules[0].ApplyServerSideEncryptionByDefault' --output json
```

CJIS accepts SSE-S3 (AES-256) as FIPS-validated because the underlying crypto modules are FIPS 140-2 Level 2. However, SSE-KMS with a CMK is stronger because it also enforces key-access control. Flag SSE-S3 only on buckets the user identifies as holding CJI.

| Result | Severity | Finding |
|---|---|---|
| CJI bucket with `SSEAlgorithm = AES256` (SSE-S3) | GAP | CJI bucket `{name}` uses SSE-S3; consider SSE-KMS for key-level access control |
| CJI bucket with `SSEAlgorithm = aws:kms` | INFO | CJI bucket encrypted with KMS ✅ |
| Non-CJI bucket | NOT_APPLICABLE | — |

Which buckets hold CJI is a questionnaire item — ask the user to confirm. Without that signal, don't raise this as a finding.

---

## PA8-08: S3 buckets block public access

```bash
account=$(aws sts get-caller-identity --query Account --output text)
aws s3control get-public-access-block --account-id $account --query 'PublicAccessBlockConfiguration' --output json 2>/dev/null

# Per-bucket:
aws s3api list-buckets --query 'Buckets[].Name' --output text | tr '\t' '\n' | while read b; do
  res=$(aws s3api get-public-access-block --bucket "$b" --query 'PublicAccessBlockConfiguration' --output json 2>/dev/null)
  [ -z "$res" ] && echo "$b: NO PUBLIC ACCESS BLOCK"
done
```

| Result | Severity | Finding |
|---|---|---|
| Account-level block disabled or partial | AUDIT BLOCKER | Account-level S3 public access block not fully enabled |
| Per-bucket without block | FINDING RISK | {count} S3 buckets without public access block |
| All fully blocked | INFO | S3 public access blocked ✅ |

---

## PA8-09: KMS customer keys have automatic rotation

```bash
aws kms list-keys --query 'Keys[].KeyId' --output text | tr '\t' '\n' | while read key; do
  mgr=$(aws kms describe-key --key-id "$key" --query 'KeyMetadata.KeyManager' --output text 2>/dev/null)
  state=$(aws kms describe-key --key-id "$key" --query 'KeyMetadata.KeyState' --output text 2>/dev/null)
  if [ "$mgr" = "CUSTOMER" ] && [ "$state" = "Enabled" ]; then
    rot=$(aws kms get-key-rotation-status --key-id "$key" --query 'KeyRotationEnabled' --output text 2>/dev/null)
    [ "$rot" = "False" ] && echo "$key: ROTATION DISABLED"
  fi
done
```

| Result | Severity | Finding |
|---|---|---|
| Customer CMKs without rotation | FINDING RISK | {count} KMS customer CMKs without annual rotation |
| All rotated | INFO | All customer CMKs rotated ✅ |

---

## PA8-10: DynamoDB tables encryption with CMK (if CJI in DynamoDB)

```bash
aws dynamodb list-tables --query 'TableNames' --output json
# For each table:
aws dynamodb describe-table --table-name {t} --query 'Table.SSEDescription' --output json
```

DynamoDB is always encrypted (AWS-owned key default). For CJI tables, CJIS-safer is CMK-encrypted.

| Result | Severity | Finding |
|---|---|---|
| No tables | NOT_APPLICABLE | — |
| CJI table with `SSEType` null or `AES256` (AWS-owned) | GAP | CJI DynamoDB table `{name}` uses default AWS-owned key; consider CMK |
| CJI table with `SSEType: KMS` | INFO | CJI DynamoDB table CMK-encrypted ✅ |

Which tables hold CJI is a questionnaire item.

---

## PA8-11: EFS filesystems encrypted

```bash
aws efs describe-file-systems --query 'FileSystems[].{Id:FileSystemId,Encrypted:Encrypted,KmsKey:KmsKeyId}' --output json
```

| Result | Severity | Finding |
|---|---|---|
| No EFS filesystems | NOT_APPLICABLE | — |
| Any `Encrypted: false` | AUDIT BLOCKER | Unencrypted EFS filesystem {id} — may hold CJI |
| All encrypted | INFO | All EFS encrypted ✅ |

---

## Summary

| Check | ID | Key question |
|---|---|---|
| EBS default encryption | PA8-01 | Are new volumes encrypted by default? |
| EBS volumes | PA8-02 | Are existing volumes encrypted? |
| EBS snapshots | PA8-03 | Are snapshots encrypted? |
| RDS encryption | PA8-04 | Are databases encrypted? |
| RDS backups | PA8-05 | Are backups retained and encrypted? |
| S3 default encryption | PA8-06 | Do buckets encrypt by default? |
| S3 KMS on CJI buckets | PA8-07 | Do CJI buckets use CMK? |
| S3 public access | PA8-08 | Is public access blocked? |
| KMS rotation | PA8-09 | Are CMKs rotated? |
| DynamoDB CMK | PA8-10 | Are CJI tables CMK-encrypted? |
| EFS encryption | PA8-11 | Are EFS filesystems encrypted? |

**Total: 11 checks.** Expected time: ~3 min.
