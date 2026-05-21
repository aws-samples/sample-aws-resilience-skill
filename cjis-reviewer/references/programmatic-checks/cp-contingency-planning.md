# CP — Contingency Planning — Programmatic Checks

> Based on CJIS Security Policy v6.0 (effective December 2024).
> Last verified against official source: 2026-05-21.
> Check https://le.fbi.gov/cjis-division/cjis-security-policy-resource-center for newer versions.

> Execute in order. Each check uses read-only AWS CLI. Record results as
> `COMPLIANT` / `NON_COMPLIANT` / `NOT_APPLICABLE` / `UNABLE_TO_ASSESS` with severity per
> [`../severity-classification.md`](../severity-classification.md).

CP family (Priority P2) — system backup, system recovery, backup encryption, cross-region replication for CJI systems.

---

## CP-09-01: AWS Backup plans exist for CJI resources

**CJIS reference**: CJIS v6.0 CP-9 | **Priority**: P2

```bash
aws backup list-backup-plans --query 'BackupPlansList[].{Id:BackupPlanId,Name:BackupPlanName,CreationDate:CreationDate}' --output json
# Check for backup selections (what resources are covered):
aws backup list-backup-plans --query 'BackupPlansList[].BackupPlanId' --output text | tr '\t' '\n' | while read plan; do
  aws backup list-backup-selections --backup-plan-id "$plan" --query 'BackupSelectionsList[].{Name:SelectionName,IAMRoleArn:IamRoleArn}' --output json
done
```

| Result | Severity | Finding |
|---|---|---|
| No backup plans exist | FINDING RISK | No AWS Backup plans — CJI system backup not automated (CP-9 gap) |
| Backup plans exist but no selections | FINDING RISK | Backup plans exist but no resources assigned |
| Backup plans with resource selections | INFO | AWS Backup plans active with resource coverage |

**Rationale**: CP-9 requires system backup. AWS Backup provides centralized, policy-driven backup for CJI resources.

---

## CP-09-02: Backup encryption (KMS)

**CJIS reference**: CJIS v6.0 CP-9 | **Priority**: P2

```bash
aws backup list-backup-vaults --query 'BackupVaultList[].{Name:BackupVaultName,EncryptionKeyArn:EncryptionKeyArn}' --output json
```

| Result | Severity | Finding |
|---|---|---|
| Backup vaults without KMS encryption | FINDING RISK | Backup vault `{name}` not encrypted with CMK — CJI backups must be encrypted |
| All vaults KMS-encrypted | INFO | Backup encryption in place |
| No backup vaults | NOT_APPLICABLE | — (check CP-09-01 first) |

---

## CP-09-03: RDS automated backup retention

**CJIS reference**: CJIS v6.0 CP-9 | **Priority**: P2

```bash
aws rds describe-db-instances --query 'DBInstances[].{Id:DBInstanceIdentifier,Retention:BackupRetentionPeriod,Encrypted:StorageEncrypted}' --output json
```

| Result | Severity | Finding |
|---|---|---|
| `BackupRetentionPeriod = 0` on any instance | FINDING RISK | RDS `{id}` has automated backups disabled — no recovery point |
| Retention < 7 days | GAP | Low backup retention on `{id}` — consider longer for CJI recovery |
| All >= 7 days and encrypted | INFO | RDS backups retained and encrypted |
| No RDS instances | NOT_APPLICABLE | — |

---

## CP-10-01: RDS Multi-AZ for system recovery

**CJIS reference**: CJIS v6.0 CP-10 | **Priority**: P2

```bash
aws rds describe-db-instances --query 'DBInstances[].{Id:DBInstanceIdentifier,MultiAZ:MultiAZ,Engine:Engine}' --output json
```

| Result | Severity | Finding |
|---|---|---|
| CJI RDS instances without Multi-AZ | FINDING RISK | RDS `{id}` not Multi-AZ — single-AZ failure impacts CJI system recovery |
| All CJI RDS instances Multi-AZ | INFO | RDS high availability configured |
| No RDS instances | NOT_APPLICABLE | — |

---

## CP-10-02: Cross-region backup replication

**CJIS reference**: CJIS v6.0 CP-10 | **Priority**: P2

```bash
aws backup list-backup-plans --query 'BackupPlansList[].BackupPlanId' --output text | tr '\t' '\n' | while read plan; do
  aws backup get-backup-plan --backup-plan-id "$plan" --query 'BackupPlan.Rules[].{RuleName:RuleName,CopyActions:CopyActions[].DestinationBackupVaultArn}' --output json
done
```

| Result | Severity | Finding |
|---|---|---|
| No copy actions (no cross-region replication) | GAP | No cross-region backup replication — consider for disaster recovery |
| Copy actions to another region | INFO | Cross-region backup replication configured |
| No backup plans | NOT_APPLICABLE | — |

---

## CP-10-03: S3 cross-region replication for CJI data

**CJIS reference**: CJIS v6.0 CP-10 | **Priority**: P2

```bash
aws s3api list-buckets --query 'Buckets[].Name' --output text | tr '\t' '\n' | while read b; do
  rep=$(aws s3api get-bucket-replication --bucket "$b" --query 'ReplicationConfiguration.Rules[?Status==`Enabled`].Destination.Bucket' --output text 2>/dev/null)
  [ -n "$rep" ] && echo "$b: REPLICATION TO $rep"
done
```

| Result | Severity | Finding |
|---|---|---|
| No S3 replication on CJI buckets | GAP | No cross-region replication for CJI S3 data — evaluate for DR |
| Replication configured on CJI buckets | INFO | S3 cross-region replication active |

---

## Summary

| Check | ID | Key question |
|---|---|---|
| Backup plans | CP-09-01 | Are CJI resources backed up? |
| Backup encryption | CP-09-02 | Are backups encrypted? |
| RDS backup retention | CP-09-03 | Are DB backups retained? |
| RDS Multi-AZ | CP-10-01 | Is DB recovery resilient? |
| Cross-region backup | CP-10-02 | Are backups replicated? |
| S3 replication | CP-10-03 | Is CJI data replicated? |

**Total: 6 checks.** Expected time: ~2 min.
