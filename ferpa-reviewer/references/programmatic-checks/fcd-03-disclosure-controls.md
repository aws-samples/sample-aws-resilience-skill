# FCD 3 — Disclosure Controls & Data Sharing — Programmatic Checks

> Execute in order. Read-only AWS CLI. Severity per [`../severity-classification.md`](../severity-classification.md).

FCD 3 covers the §99.31(a)(1)(i)(B) "school official" exception operationally: who can access student records, which external principals are receiving them, and whether those flows are authorized.

Most FCD 3 findings overlap with FCD 5 (access control) — the distinction is that FCD 3 is specifically about *cross-boundary* sharing (cross-account, cross-region, external subprocessors) rather than internal least-privilege.

---

## FCD3-01: Active IAM Access Analyzer with external-access findings

```bash
aws accessanalyzer list-analyzers --query 'analyzers[?type==`ACCOUNT` && status==`ACTIVE`].arn' --output text
# For each analyzer, list active findings:
aws accessanalyzer list-findings --analyzer-arn {arn} --filter '{"status":{"eq":["ACTIVE"]},"isPublic":{"eq":["false"]}}' --output json
```

Walk each finding — for each external-principal share, classify:
- Is the external principal a known subprocessor? (user must confirm from their DPA subprocessor register)
- Is it a district/school AWS account? Expected for FCD 3.
- Is it an unknown AWS account? Investigation required.

| Result | Severity | Finding |
|---|---|---|
| No Access Analyzer | BREACH RISK | Access Analyzer not enabled — cannot detect unauthorized cross-account disclosures |
| Findings for unknown external principals | BREACH RISK | {N} external-principal findings — review for unauthorized disclosures (potential §99.33 redisclosure violation) |
| Findings only for declared subprocessors/districts | INFO | External sharing limited to declared parties ✅ |

---

## FCD3-02: RAM (Resource Access Manager) shares enumeration

```bash
aws ram get-resource-shares --resource-owner SELF --query 'resourceShares[].{Name:name,Status:status,Arn:resourceShareArn}' --output json
aws ram list-principals --resource-owner SELF --query 'principals[].{Share:resourceShareArn,Id:id,ResourceShareArn:resourceShareArn}' --output json
```

| Result | Severity | Finding |
|---|---|---|
| Active shares to accounts not declared as subprocessors/districts | BREACH RISK | RAM share `{name}` to unknown principal — potential unauthorized disclosure |
| Shares align with declared subprocessor list | INFO | RAM shares within declared disclosure envelope ✅ |
| No RAM shares | NOT_APPLICABLE | — |

---

## FCD3-03: Lake Formation cross-account grants

```bash
aws lakeformation list-permissions --query 'PrincipalResourcePermissions[?contains(keys(@), `Principal`)]' --output json 2>/dev/null
```

Flag any grant where the principal is a cross-account ARN not matching the caller's account.

| Result | Severity | Finding |
|---|---|---|
| Cross-account Lake Formation grants to unknown principals | BREACH RISK | Lake Formation grant to `{principal}` — review for authorized disclosure |
| Grants only to same-account or declared subprocessors | INFO | Lake Formation scoped ✅ |
| Lake Formation not in use | NOT_APPLICABLE | — |

---

## FCD3-04: KMS key policies allowing cross-account use

```bash
aws kms list-keys --query 'Keys[].KeyId' --output text | tr '\t' '\n' | while read k; do
  meta=$(aws kms describe-key --key-id "$k" --query 'KeyMetadata.{Manager:KeyManager,State:KeyState}' --output json 2>/dev/null)
  if echo "$meta" | grep -q '"KeyManager": "CUSTOMER"'; then
    pol=$(aws kms get-key-policy --key-id "$k" --policy-name default --query 'Policy' --output text 2>/dev/null)
    # Look for external AWS account principals:
    echo "$pol" | python3 -c "
import json, sys
p = json.loads(sys.stdin.read())
for stmt in p.get('Statement', []):
    pr = stmt.get('Principal', {})
    if isinstance(pr, dict):
        aws = pr.get('AWS', [])
        if isinstance(aws, str): aws = [aws]
        for a in aws:
            if 'arn:aws:iam::' in a and not a.startswith('arn:aws:iam::{account}:'):
                print(f'Cross-account principal: {a}')
"
  fi
done
```

| Result | Severity | Finding |
|---|---|---|
| KMS keys with cross-account grants to unknown accounts | BREACH RISK | CMK `{id}` grants use to `{principal}` — potential unauthorized decryption of student records |
| Cross-account grants only to declared accounts | INFO | KMS grants within declared disclosure envelope ✅ |
| No cross-account grants | INFO | All KMS keys account-local ✅ |

---

## FCD3-05: S3 bucket policies with non-local principals

```bash
aws s3api list-buckets --query 'Buckets[].Name' --output text | tr '\t' '\n' | while read b; do
  pol=$(aws s3api get-bucket-policy --bucket "$b" --query 'Policy' --output text 2>/dev/null)
  [ -z "$pol" ] && continue
  echo "$pol" | python3 -c "
import json, sys
try:
    p = json.loads(sys.stdin.read())
    for stmt in p.get('Statement', []):
        if stmt.get('Effect') != 'Allow': continue
        pr = stmt.get('Principal', {})
        if pr == '*' or (isinstance(pr, dict) and pr.get('AWS') == '*'):
            print('WILDCARD')
        elif isinstance(pr, dict):
            aws = pr.get('AWS', [])
            if isinstance(aws, str): aws = [aws]
            for a in aws:
                if 'arn:aws:iam::' in a:
                    print(f'Cross-account: {a}')
except: pass
"
done
```

| Result | Severity | Finding |
|---|---|---|
| Bucket policy with `Principal: *` | BREACH RISK | S3 bucket `{name}` has wildcard principal — public share |
| Bucket policy with cross-account principal not in declared subprocessor list | BREACH RISK | S3 bucket `{name}` shared with `{principal}` — unauthorized disclosure risk |
| All bucket policies local or to declared parties | INFO | S3 sharing scoped ✅ |

---

## FCD3-06: VPC peering / Transit Gateway connections to unknown accounts

```bash
aws ec2 describe-vpc-peering-connections --query 'VpcPeeringConnections[?Status.Code==`active`].{Id:VpcPeeringConnectionId,Accepter:AccepterVpcInfo.OwnerId,Requester:RequesterVpcInfo.OwnerId}' --output json
aws ec2 describe-transit-gateway-attachments --query 'TransitGatewayAttachments[?State==`available`].{Id:TransitGatewayAttachmentId,ResourceOwner:ResourceOwnerId,ResourceType:ResourceType}' --output json
```

| Result | Severity | Finding |
|---|---|---|
| Peering / TGW attachment to unknown account | COMPLIANCE GAP | VPC peering to account `{id}` — verify this is a declared subprocessor/district |
| All peerings to declared accounts | INFO | VPC peering scoped ✅ |
| None | NOT_APPLICABLE | — |

---

## FCD3-07: VPC endpoints minimize public-network exposure

```bash
aws ec2 describe-vpc-endpoints --query 'VpcEndpoints[].{Id:VpcEndpointId,Service:ServiceName,Type:VpcEndpointType,Vpc:VpcId}' --output json
```

Expected endpoints for a student-data VPC (minimum): `s3`, `kms`, `logs`, `ssm`, `secretsmanager`.

| Result | Severity | Finding |
|---|---|---|
| Student-data VPC without core endpoints (S3, KMS at minimum) | COMPLIANCE GAP | VPC `{id}` lacks core endpoints — AWS API traffic may traverse the public internet |
| Core endpoints present | INFO | VPC endpoints minimize public-network egress ✅ |

---

## FCD3-08: Macie classification coverage on student-data buckets

```bash
aws macie2 get-macie-session --query 'status' --output text 2>/dev/null
aws macie2 list-classification-jobs --query 'items[].{Name:name,Status:jobStatus,Created:createdAt}' --output json 2>/dev/null
```

| Result | Severity | Finding |
|---|---|---|
| Macie disabled | COMPLIANCE GAP | Macie not enabled — cannot detect accidental student-PII disclosure (e.g., PII leaked into a non-student-data bucket) |
| Macie enabled but no recent classification jobs | HARDENING GAP | Macie enabled but no recent jobs — schedule periodic scans on student-data buckets |
| Macie scanning student-data buckets | INFO | Macie providing PII detection ✅ |

---

## FCD3-09: Secrets Manager resource policies with cross-account principals

```bash
aws secretsmanager list-secrets --query 'SecretList[].ARN' --output text | tr '\t' '\n' | while read s; do
  pol=$(aws secretsmanager get-resource-policy --secret-id "$s" --query 'ResourcePolicy' --output text 2>/dev/null)
  [ -z "$pol" ] && continue
  # Check for cross-account or * principals
  echo "$pol" | python3 -c "
import json, sys
p = json.loads(sys.stdin.read())
for stmt in p.get('Statement', []):
    if stmt.get('Effect') != 'Allow': continue
    pr = stmt.get('Principal', {})
    if pr == '*' or (isinstance(pr, dict) and pr.get('AWS') == '*'):
        print('WILDCARD')
"
done
```

| Result | Severity | Finding |
|---|---|---|
| Secrets Manager secret with wildcard principal | BREACH RISK | Secret `{name}` has wildcard resource policy — potential credential leak |
| All secrets scoped | INFO | Secrets scoped ✅ |
| No custom resource policies | NOT_APPLICABLE | — |

---

## FCD3-10: SageMaker / Bedrock jobs reading student-data S3 (subprocessor check)

If ML/AI is used on student data, each job represents a potential subprocessor data flow.

```bash
# SageMaker training jobs referencing student-data buckets
aws sagemaker list-training-jobs --max-results 50 --query 'TrainingJobSummaries[].{Name:TrainingJobName,Status:TrainingJobStatus,Created:CreationTime}' --output json 2>/dev/null
# For each, describe and inspect InputDataConfig S3Uri:
aws sagemaker describe-training-job --training-job-name {name} --query 'InputDataConfig[].DataSource.S3DataSource.S3Uri' --output text 2>/dev/null

# Bedrock model-customization jobs (if applicable)
aws bedrock list-model-customization-jobs --max-results 50 --query 'modelCustomizationJobSummaries[].{Name:jobName,Status:status,Model:baseModelArn}' --output json 2>/dev/null
```

| Result | Severity | Finding |
|---|---|---|
| Training jobs reading student-data buckets without documented DPA authorization | BREACH RISK | Training job `{name}` reads from student-data — requires explicit district authorization under §99.33; model may be a redisclosure vehicle |
| All training jobs on non-student data | INFO | No ML training on student data detected ✅ |
| Training jobs with documented authorization | INFO | ML training on student data documented in DPA ✅ (manual check required) |

This check flags the pattern; the user must confirm DPA authorization. Model-training on student data without explicit district sign-off is a hot compliance topic and a frequent cause of state-AG investigations.

---

## Summary

| Check | ID | Key question |
|---|---|---|
| Access Analyzer external findings | FCD3-01 | Are unauthorized external shares detected? |
| RAM shares | FCD3-02 | Are RAM shares to declared parties only? |
| Lake Formation grants | FCD3-03 | Are data-catalog shares scoped? |
| KMS cross-account | FCD3-04 | Can external accounts decrypt student data? |
| S3 cross-account | FCD3-05 | Are buckets shared only with declared parties? |
| VPC peering | FCD3-06 | Are network connections scoped? |
| VPC endpoints | FCD3-07 | Does AWS traffic stay private? |
| Macie coverage | FCD3-08 | Is PII leakage detection in place? |
| Secrets policies | FCD3-09 | Are secrets scoped? |
| ML/AI on student data | FCD3-10 | **Is ML training authorized under DPA?** |

**Total: 10 checks.** Expected time: ~3 min. FCD3-10 is the question most likely to surprise the user — always verify model-training authorization.
