# FCD 7 — Encryption at Rest & In Transit — Programmatic Checks

> Execute in order. Read-only AWS CLI. Severity per [`../severity-classification.md`](../severity-classification.md).

FERPA doesn't mandate encryption. PTAC guidance and modern state EdTech DPAs do — unencrypted S3 buckets exposed to the internet are the most common root cause in state-AG breach notifications for EdTech vendors.

Retrofit-encryption limitation: **RDS, Aurora, OpenSearch, and ElastiCache cannot be encrypted after creation.** Unencrypted production data stores require snapshot-restore migration.

---

## FCD7-01: Default EBS encryption enabled at account level

```bash
aws ec2 get-ebs-encryption-by-default --query 'EbsEncryptionByDefault' --output text
aws ec2 get-ebs-default-kms-key-id --query 'KmsKeyId' --output text
```

| Result | Severity | Finding |
|---|---|---|
| `EbsEncryptionByDefault: false` | COMPLIANCE GAP | Default EBS encryption disabled — new volumes may be unencrypted |
| Enabled, default key is AWS-managed (`alias/aws/ebs`) | HARDENING GAP | Default key is AWS-managed — use a CMK for auditability |
| Enabled with CMK | INFO | Default EBS encryption with CMK ✅ |

---

## FCD7-02: All existing EBS volumes are encrypted

```bash
aws ec2 describe-volumes --filters Name=encrypted,Values=false --query 'Volumes[].{Id:VolumeId,Size:Size,State:State}' --output json
```

| Result | Severity | Finding |
|---|---|---|
| Any `Encrypted=false` volumes | BREACH RISK | {count} unencrypted EBS volumes — migrate via snapshot (create snapshot, copy-with-encryption, create new volume) |
| All encrypted | INFO | All EBS volumes encrypted ✅ |

---

## FCD7-03: All RDS instances encrypted at rest

```bash
aws rds describe-db-instances --query 'DBInstances[?StorageEncrypted==`false`].{Id:DBInstanceIdentifier,Engine:Engine,Status:DBInstanceStatus}' --output json
```

| Result | Severity | Finding |
|---|---|---|
| Any unencrypted RDS | BREACH RISK | RDS instance `{id}` unencrypted — cannot retrofit; must migrate via snapshot-restore |
| All encrypted | INFO | All RDS instances encrypted ✅ |

---

## FCD7-04: All RDS snapshots encrypted

```bash
aws rds describe-db-snapshots --snapshot-type manual --query 'DBSnapshots[?Encrypted==`false`].{Id:DBSnapshotIdentifier}' --output json
aws rds describe-db-snapshots --snapshot-type automated --query 'DBSnapshots[?Encrypted==`false`].{Id:DBSnapshotIdentifier}' --output json
```

| Result | Severity | Finding |
|---|---|---|
| Unencrypted snapshots exist | BREACH RISK | Unencrypted RDS snapshots present — copy with encryption and delete originals |
| All encrypted | INFO | All RDS snapshots encrypted ✅ |

---

## FCD7-05: All S3 buckets have default encryption

```bash
aws s3api list-buckets --query 'Buckets[].Name' --output text | tr '\t' '\n' | while read b; do
  enc=$(aws s3api get-bucket-encryption --bucket "$b" --query 'ServerSideEncryptionConfiguration.Rules[0].ApplyServerSideEncryptionByDefault.SSEAlgorithm' --output text 2>/dev/null)
  [ -z "$enc" ] || [ "$enc" = "None" ] && echo "$b: NO DEFAULT ENCRYPTION"
done
```

Note: as of Jan 2023, AWS enables SSE-S3 by default on new buckets. Older buckets or explicitly-configured ones may lack it.

| Result | Severity | Finding |
|---|---|---|
| Any bucket without default encryption | COMPLIANCE GAP | S3 bucket `{name}` lacks default encryption — configure SSE-KMS |
| All buckets encrypted with SSE-S3 only | HARDENING GAP | Buckets use SSE-S3 — upgrade to SSE-KMS with CMK for auditability |
| All buckets SSE-KMS | INFO | All S3 buckets SSE-KMS encrypted ✅ |

---

## FCD7-06: S3 buckets deny unencrypted transport (HTTP)

```bash
aws s3api list-buckets --query 'Buckets[].Name' --output text | tr '\t' '\n' | while read b; do
  pol=$(aws s3api get-bucket-policy --bucket "$b" --query 'Policy' --output text 2>/dev/null)
  if [ -z "$pol" ] || ! echo "$pol" | grep -q "aws:SecureTransport"; then
    echo "$b: NO SECURE-TRANSPORT DENY"
  fi
done
```

| Result | Severity | Finding |
|---|---|---|
| Buckets without `aws:SecureTransport: false` deny | COMPLIANCE GAP | S3 bucket `{name}` accepts plain HTTP — add deny policy |
| All buckets enforce TLS | INFO | All S3 buckets enforce TLS ✅ |

---

## FCD7-07: DynamoDB encryption uses CMK for student-data tables

```bash
aws dynamodb list-tables --query 'TableNames' --output text | tr '\t' '\n' | while read t; do
  enc=$(aws dynamodb describe-table --table-name "$t" --query 'Table.SSEDescription.{Type:SSEType,Key:KMSMasterKeyArn}' --output json 2>/dev/null)
  echo "$t: $enc"
done
```

All DynamoDB tables are encrypted by default (AWS-owned key). The check is for CMK usage on student-data tables.

| Result | Severity | Finding |
|---|---|---|
| Student-data table using AWS-owned key (no `SSEDescription`) | HARDENING GAP | Table `{name}` uses AWS-owned key — switch to CMK for auditability |
| Using CMK (`KMS` type) | INFO | Table uses CMK ✅ |

Student-data tables should be identified from the Phase 1 scope declaration.

---

## FCD7-08: KMS CMKs have automatic rotation enabled

```bash
aws kms list-keys --query 'Keys[].KeyId' --output text | tr '\t' '\n' | while read k; do
  meta=$(aws kms describe-key --key-id "$k" --query 'KeyMetadata.{Origin:Origin,Manager:KeyManager,State:KeyState}' --output json 2>/dev/null)
  if echo "$meta" | grep -q '"KeyManager": "CUSTOMER"'; then
    rot=$(aws kms get-key-rotation-status --key-id "$k" --query 'KeyRotationEnabled' --output text 2>/dev/null)
    [ "$rot" != "True" ] && echo "$k: ROTATION OFF"
  fi
done
```

| Result | Severity | Finding |
|---|---|---|
| Customer CMKs with rotation disabled | COMPLIANCE GAP | {count} CMKs lack automatic rotation — enable via console or `aws kms enable-key-rotation` |
| All CMKs rotating | INFO | KMS key rotation enabled ✅ |

---

## FCD7-09: ALB / NLB listeners use TLS 1.2+

```bash
aws elbv2 describe-load-balancers --query 'LoadBalancers[].LoadBalancerArn' --output text | tr '\t' '\n' | while read lb; do
  aws elbv2 describe-listeners --load-balancer-arn "$lb" --query 'Listeners[?Protocol==`HTTPS` || Protocol==`TLS`].{LB:LoadBalancerArn,Port:Port,SslPolicy:SslPolicy}' --output json
done
```

Flag listeners whose SSL policy is older than `ELBSecurityPolicy-TLS-1-2-2017-01` or includes TLS 1.0/1.1 (any policy containing `TLS-1-0` or `2015` or `2016`).

| Result | Severity | Finding |
|---|---|---|
| Listener with TLS 1.0/1.1-inclusive policy | COMPLIANCE GAP | Listener `{arn}:{port}` permits deprecated TLS — upgrade to `ELBSecurityPolicy-TLS13-1-2-2021-06` |
| Listener with HTTP (non-TLS) accepting student-data traffic | BREACH RISK | Listener `{arn}:{port}` is HTTP — student data in plaintext |
| All TLS 1.2+ | INFO | Load balancer TLS policies current ✅ |

---

## FCD7-10: CloudFront distributions enforce HTTPS

```bash
aws cloudfront list-distributions --query 'DistributionList.Items[].{Id:Id,Aliases:Aliases.Items,Viewer:DefaultCacheBehavior.ViewerProtocolPolicy,MinTLS:ViewerCertificate.MinimumProtocolVersion}' --output json 2>/dev/null
```

| Result | Severity | Finding |
|---|---|---|
| Any `ViewerProtocolPolicy: allow-all` | COMPLIANCE GAP | Distribution `{id}` allows HTTP — change to `redirect-to-https` or `https-only` |
| `MinimumProtocolVersion` below `TLSv1.2_2021` | COMPLIANCE GAP | Distribution `{id}` allows TLS < 1.2 — raise minimum to `TLSv1.2_2021` |
| All distributions TLS 1.2+, HTTPS-only | INFO | CloudFront TLS policies current ✅ |
| No distributions | NOT_APPLICABLE | — |

---

## FCD7-11: RDS force SSL (parameter-group check)

```bash
aws rds describe-db-instances --query 'DBInstances[].{Id:DBInstanceIdentifier,Engine:Engine,PG:DBParameterGroups[0].DBParameterGroupName}' --output json
# For each parameter group:
aws rds describe-db-parameters --db-parameter-group-name {pg} --query 'Parameters[?ParameterName==`require_secure_transport` || ParameterName==`rds.force_ssl`].{Name:ParameterName,Value:ParameterValue}' --output json
```

| Result | Severity | Finding |
|---|---|---|
| MySQL/MariaDB with `require_secure_transport != 1` | COMPLIANCE GAP | RDS `{id}` does not require SSL — update parameter group |
| Postgres with `rds.force_ssl != 1` | COMPLIANCE GAP | RDS `{id}` does not require SSL — update parameter group |
| All instances enforce SSL | INFO | RDS force-SSL enabled ✅ |

---

## FCD7-12: OpenSearch encryption (at-rest and node-to-node)

```bash
aws opensearch list-domain-names --query 'DomainNames[].DomainName' --output text | tr '\t' '\n' | while read d; do
  aws opensearch describe-domain --domain-name "$d" --query 'DomainStatus.{Name:DomainName,Encrypt:EncryptionAtRestOptions.Enabled,N2N:NodeToNodeEncryptionOptions.Enabled,TLS:DomainEndpointOptions.EnforceHTTPS}' --output json
done
```

| Result | Severity | Finding |
|---|---|---|
| `Encrypt: false` on a domain | BREACH RISK | OpenSearch domain `{name}` unencrypted at rest — must re-create with encryption |
| `N2N: false` | COMPLIANCE GAP | OpenSearch domain `{name}` lacks node-to-node encryption |
| `EnforceHTTPS: false` | COMPLIANCE GAP | OpenSearch domain `{name}` accepts plain HTTP |
| All enabled | INFO | OpenSearch encryption complete ✅ |
| No domains | NOT_APPLICABLE | — |

---

## FCD7-13: Aurora cluster encryption

```bash
aws rds describe-db-clusters --query 'DBClusters[?StorageEncrypted==`false`].{Id:DBClusterIdentifier,Engine:Engine}' --output json
```

| Result | Severity | Finding |
|---|---|---|
| Any unencrypted Aurora cluster | BREACH RISK | Aurora cluster `{id}` unencrypted — migrate via snapshot-restore |
| All encrypted | INFO | All Aurora clusters encrypted ✅ |

---

## Summary

| Check | ID | Key question |
|---|---|---|
| Default EBS encryption | FCD7-01 | Are new volumes encrypted by default? |
| EBS volumes | FCD7-02 | Are existing volumes encrypted? |
| RDS instances | FCD7-03 | Are databases encrypted? |
| RDS snapshots | FCD7-04 | Are backups encrypted? |
| S3 default encryption | FCD7-05 | Are buckets encrypted by default? |
| S3 HTTPS-only | FCD7-06 | Do buckets reject plain HTTP? |
| DynamoDB CMK | FCD7-07 | Do student-data tables use CMK? |
| KMS rotation | FCD7-08 | Are keys automatically rotated? |
| ALB/NLB TLS | FCD7-09 | Do load balancers enforce TLS 1.2+? |
| CloudFront TLS | FCD7-10 | Are distributions HTTPS-only? |
| RDS SSL | FCD7-11 | Do databases require SSL? |
| OpenSearch encryption | FCD7-12 | Is OpenSearch encrypted? |
| Aurora encryption | FCD7-13 | Are Aurora clusters encrypted? |

**Total: 13 checks.** Expected time: ~3 min.
