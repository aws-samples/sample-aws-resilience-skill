# SC — Systems and Communications Protection — Programmatic Checks

> Based on CJIS Security Policy v6.0 (effective December 2024).
> Last verified against official source: 2026-05-21.
> Check https://le.fbi.gov/cjis-division/cjis-security-policy-resource-center for newer versions.

> Execute in order. Each check uses read-only AWS CLI. Record results as
> `COMPLIANT` / `NON_COMPLIANT` / `NOT_APPLICABLE` / `UNABLE_TO_ASSESS` with severity per
> [`../severity-classification.md`](../severity-classification.md).

SC family (Priority P1) — boundary protection, transmission confidentiality (FIPS TLS 1.2+), cryptographic key management, protection of information at rest.

---

## SC-07-01: Boundary protection — VPC isolation, no IGW on CJI VPC

**CJIS reference**: CJIS v6.0 SC-7 | **Priority**: P1*

```bash
aws ec2 describe-vpcs --query 'Vpcs[].{VpcId:VpcId,IsDefault:IsDefault,CidrBlock:CidrBlock}' --output json
# For each non-default VPC (CJI candidates):
aws ec2 describe-internet-gateways --filters Name=attachment.vpc-id,Values={vpc_id} --query 'InternetGateways[].InternetGatewayId' --output text
```

| Result | Severity | Finding |
|---|---|---|
| IGW attached to CJI VPC | AUDIT BLOCKER | CJI VPC `{id}` has internet gateway — direct internet exposure |
| No IGW on CJI VPC | INFO | CJI VPC has no direct internet path |

---

## SC-07-02: Boundary protection — Security Groups and NACLs

**CJIS reference**: CJIS v6.0 SC-7 | **Priority**: P1*

```bash
aws ec2 describe-security-groups --filters Name=ip-permission.cidr,Values=0.0.0.0/0 --query 'SecurityGroups[].{Id:GroupId,Name:GroupName,Vpc:VpcId,Rules:IpPermissions[?IpRanges[?CidrIp==`0.0.0.0/0`]].{Proto:IpProtocol,FromPort:FromPort,ToPort:ToPort}}' --output json
```

| Result | Severity | Finding |
|---|---|---|
| 0.0.0.0/0 to critical ports (22, 3389, DB ports, all-traffic) | AUDIT BLOCKER | SG `{id}` allows {port} from internet — boundary protection failure |
| 0.0.0.0/0 to web ports only | FINDING RISK | Verify WAF + authentication in front of web-facing SGs |
| No unrestricted public ingress | INFO | Boundary controls enforced |

---

## SC-07-03: GuardDuty enabled for threat detection at boundary

**CJIS reference**: CJIS v6.0 SC-7 | **Priority**: P1*

```bash
aws guardduty list-detectors --output json
# For each detector:
aws guardduty get-detector --detector-id {id} --query '{Status:Status,Features:Features}' --output json 2>/dev/null
```

| Result | Severity | Finding |
|---|---|---|
| No GuardDuty detectors | AUDIT BLOCKER | GuardDuty not enabled — no boundary threat detection |
| Detector exists but status is not ENABLED | FINDING RISK | GuardDuty detector disabled |
| GuardDuty enabled | INFO | Boundary threat detection active |

---

## SC-07-04: WAF on internet-facing ALBs

**CJIS reference**: CJIS v6.0 SC-7 | **Priority**: P1*

```bash
aws elbv2 describe-load-balancers --query 'LoadBalancers[?Scheme==`internet-facing`].LoadBalancerArn' --output text | tr '\t' '\n' | while read lb; do
  waf=$(aws wafv2 get-web-acl-for-resource --resource-arn "$lb" --query 'WebACL.Name' --output text 2>/dev/null)
  [ -z "$waf" ] || [ "$waf" = "None" ] && echo "$lb: NO WAF"
done
```

| Result | Severity | Finding |
|---|---|---|
| Internet-facing ALB without WAF | FINDING RISK | Internet-facing load balancer without WAF protection |
| All internet-facing ALBs have WAF | INFO | WAF protecting internet-facing endpoints |
| No internet-facing ALBs | NOT_APPLICABLE | — |

---

## SC-08-01: TLS policy on load balancers (>=TLS 1.2)

**CJIS reference**: CJIS v6.0 SC-8 | **Priority**: P1*

```bash
aws elbv2 describe-load-balancers --query 'LoadBalancers[].LoadBalancerArn' --output text | tr '\t' '\n' | while read lb; do
  aws elbv2 describe-listeners --load-balancer-arn "$lb" --query 'Listeners[?Protocol==`HTTPS` || Protocol==`TLS`].{Port:Port,SslPolicy:SslPolicy}' --output json
done
```

| Result | Severity | Finding |
|---|---|---|
| Listener with SSL policy containing `TLS-1-0` or `TLS-1-1` | AUDIT BLOCKER | Load balancer allows TLS below 1.2 — SC-8 requires TLS 1.2+ |
| Listener using `ELBSecurityPolicy-FS-*` or `ELBSecurityPolicy-TLS13-*` | INFO | Modern TLS policy |
| HTTP-only listener on CJI app | AUDIT BLOCKER | Plaintext HTTP on CJI application |
| No HTTPS listeners | NOT_APPLICABLE | — |

---

## SC-08-02: RDS force-SSL

**CJIS reference**: CJIS v6.0 SC-8 | **Priority**: P1*

```bash
aws rds describe-db-instances --query 'DBInstances[].{Id:DBInstanceIdentifier,Engine:Engine}' --output json
# For each PostgreSQL/MySQL instance, check parameter group for force_ssl/require_secure_transport:
aws rds describe-db-parameters --db-parameter-group-name {pg_name} --query 'Parameters[?ParameterName==`rds.force_ssl` || ParameterName==`require_secure_transport`].{Name:ParameterName,Value:ParameterValue}' --output json
```

| Result | Severity | Finding |
|---|---|---|
| RDS without force_ssl/require_secure_transport | FINDING RISK | RDS `{id}` does not enforce TLS — plaintext connections possible |
| All RDS instances force SSL | INFO | RDS connections encrypted in transit |
| No RDS instances | NOT_APPLICABLE | — |

---

## SC-08-03: S3 bucket policy denies plaintext (deny non-SSL)

**CJIS reference**: CJIS v6.0 SC-8 | **Priority**: P1*

```bash
aws s3api list-buckets --query 'Buckets[].Name' --output text | tr '\t' '\n' | while read b; do
  pol=$(aws s3api get-bucket-policy --bucket "$b" --query Policy --output text 2>/dev/null)
  echo "$pol" | grep -q 'aws:SecureTransport.*false' || echo "$b: NO SSL-ONLY POLICY"
done
```

| Result | Severity | Finding |
|---|---|---|
| CJI buckets without SSL-only policy | FINDING RISK | Bucket `{name}` allows non-TLS access — add `aws:SecureTransport` deny |
| All buckets have SSL-only policy | INFO | S3 transit encryption enforced via policy |

---

## SC-12-01: KMS key rotation enabled

**CJIS reference**: CJIS v6.0 SC-12 | **Priority**: P1*

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
| Customer CMKs without rotation | FINDING RISK | {count} KMS CMKs without annual rotation — SC-12 key management gap |
| All CMKs rotated | INFO | All customer CMKs rotated |

---

## SC-13-01: FIPS endpoints — partition and endpoint check

**CJIS reference**: CJIS v6.0 SC-13 | **Priority**: P1*

```bash
# Partition check
aws sts get-caller-identity --query 'Arn' --output text | grep -q 'aws-us-gov' && echo "GovCloud (FIPS default)" || echo "Commercial (FIPS opt-in)"
# VPC endpoints with FIPS service names
aws ec2 describe-vpc-endpoints --query 'VpcEndpoints[].ServiceName' --output text | tr '\t' '\n' | grep -i fips || echo "No FIPS VPC endpoints"
```

| Result | Severity | Finding |
|---|---|---|
| Commercial partition, no FIPS evidence, CJI workload | AUDIT BLOCKER | Commercial AWS without FIPS endpoints — CJIS requires FIPS 140-2 validated crypto |
| GovCloud | INFO | GovCloud partition — FIPS endpoints by default |
| Commercial with FIPS explicitly configured | INFO | FIPS endpoints in use |

---

## SC-28-01: EBS encryption by default

**CJIS reference**: CJIS v6.0 SC-28 | **Priority**: P1*

```bash
aws ec2 get-ebs-encryption-by-default --query 'EbsEncryptionByDefault' --output text
```

| Result | Severity | Finding |
|---|---|---|
| `false` | FINDING RISK | EBS encryption-by-default disabled — new volumes may be unencrypted |
| `true` | INFO | EBS default encryption on |

---

## SC-28-02: No unencrypted EBS volumes in use

**CJIS reference**: CJIS v6.0 SC-28 | **Priority**: P1*

```bash
aws ec2 describe-volumes --filters Name=encrypted,Values=false --query 'Volumes[?Attachments[0].State==`attached`].{Id:VolumeId,Instance:Attachments[0].InstanceId}' --output json
```

| Result | Severity | Finding |
|---|---|---|
| Unencrypted volumes attached to running instances | AUDIT BLOCKER | {count} unencrypted EBS volumes in use — CJI at rest without encryption |
| All attached volumes encrypted | INFO | All EBS volumes encrypted |

---

## SC-28-03: RDS encryption at rest

**CJIS reference**: CJIS v6.0 SC-28 | **Priority**: P1*

```bash
aws rds describe-db-instances --query 'DBInstances[?StorageEncrypted==`false`].{Id:DBInstanceIdentifier,Engine:Engine}' --output json
```

| Result | Severity | Finding |
|---|---|---|
| Unencrypted RDS instances | AUDIT BLOCKER | {count} RDS instances without encryption at rest — requires snapshot migration |
| All encrypted | INFO | All RDS encrypted |
| No RDS instances | NOT_APPLICABLE | — |

---

## SC-28-04: S3 default encryption

**CJIS reference**: CJIS v6.0 SC-28 | **Priority**: P1*

```bash
aws s3api list-buckets --query 'Buckets[].Name' --output text | tr '\t' '\n' | while read b; do
  enc=$(aws s3api get-bucket-encryption --bucket "$b" --query 'ServerSideEncryptionConfiguration.Rules[0].ApplyServerSideEncryptionByDefault.SSEAlgorithm' --output text 2>/dev/null)
  [ -z "$enc" ] || [ "$enc" = "None" ] && echo "$b: NO DEFAULT ENCRYPTION"
done
```

| Result | Severity | Finding |
|---|---|---|
| Buckets without default encryption | AUDIT BLOCKER | {count} S3 buckets without encryption — may contain CJI |
| All buckets encrypted | INFO | All S3 buckets encrypted by default |

---

## SC-28-05: DynamoDB and EFS encryption

**CJIS reference**: CJIS v6.0 SC-28 | **Priority**: P1*

```bash
aws efs describe-file-systems --query 'FileSystems[?Encrypted==`false`].{Id:FileSystemId}' --output json
aws dynamodb list-tables --query 'TableNames' --output text | tr '\t' '\n' | while read t; do
  sse=$(aws dynamodb describe-table --table-name "$t" --query 'Table.SSEDescription.SSEType' --output text 2>/dev/null)
  [ "$sse" = "None" ] || [ -z "$sse" ] && echo "$t: AWS-OWNED KEY (default)"
done
```

| Result | Severity | Finding |
|---|---|---|
| Unencrypted EFS | AUDIT BLOCKER | EFS filesystem `{id}` not encrypted |
| CJI DynamoDB tables with AWS-owned key only | GAP | Consider CMK for CJI DynamoDB tables |
| All encrypted with CMK | INFO | All storage encrypted with customer keys |
| No EFS or DynamoDB | NOT_APPLICABLE | — |

---

## Summary

| Check | ID | Key question |
|---|---|---|
| VPC boundary (no IGW) | SC-07-01 | Is CJI VPC internet-isolated? |
| Security Groups | SC-07-02 | Are sensitive ports closed? |
| GuardDuty | SC-07-03 | Is threat detection active? |
| WAF on ALBs | SC-07-04 | Are web endpoints protected? |
| LB TLS policy | SC-08-01 | Do LBs enforce TLS 1.2+? |
| RDS force-SSL | SC-08-02 | Are DB connections encrypted? |
| S3 SSL-only | SC-08-03 | Is plaintext S3 access denied? |
| KMS rotation | SC-12-01 | Are CMKs rotated? |
| FIPS endpoints | SC-13-01 | Is TLS FIPS-validated? |
| EBS encryption | SC-28-01 | Are new volumes encrypted? |
| EBS volumes | SC-28-02 | Are existing volumes encrypted? |
| RDS encryption | SC-28-03 | Are databases encrypted at rest? |
| S3 encryption | SC-28-04 | Are buckets encrypted? |
| DynamoDB/EFS | SC-28-05 | Are other stores encrypted? |

**Total: 14 checks.** Expected time: ~4 min.
