# CloudFront Distribution Impairment — FIS Template

> Source: [aws-samples/fis-template-library](https://github.com/aws-samples/fis-template-library/tree/main/cloudfront-impairment) (commit ee74d58) | License: MIT-0

## Hypothesis Template

> When S3 origins serving CloudFront distributions are experiencing an impairment, CloudFront should
> automatically failover to secondary origins within 30 seconds. An alarm should be raised and the DevOps
> team notified within 2-3 minutes. Content delivery should continue seamlessly through the failover origin.
> Once the primary origin impairment is resolved, CloudFront should resume using the primary origin within
> 30 seconds.

## How It Works

FIS runs one `aws:ssm:start-automation-execution` action (`maxDuration` PT1H, `duration` PT10M by default). The document:

1. `getTargetBuckets`: lists distributions tagged `FIS-Ready=True`; for each, reads the distribution config and keeps only the **first (primary) member of each origin group** whose domain contains `.s3.` or `.s3-`, and derives the bucket name from it.
2. `applyDenyAllPolicyToBuckets`: adds a statement `Sid: FISTemporaryDeny`, `Effect: Deny`, `Principal: "*"`, `Action: s3:GetObject`, `Resource: arn:aws:s3:::<bucket>/*` to each bucket policy (replacing any earlier statement with that Sid).
3. `invalidateCloudFrontCache`: `CreateInvalidation` on `/*` for each affected distribution so edge caches go back to the origin.
4. `waitForDuration`: holds the impairment for `duration`.
5. `removeDenyAllPolicyFromBuckets`: removes the `FISTemporaryDeny` statement; if no statement remains it deletes the bucket policy.
6. `invalidateCloudFrontCacheRestore`: invalidates `/*` again.

**Key technique**: S3 bucket-policy denial — simulates origin failure without touching CloudFront configuration.

Consequences of this logic:
- A distribution **without an origin group** has no bucket selected and is not impaired, even if tagged (the upstream README's "no secondary origin" test scenario does not happen with this document).
- The deny applies to every principal calling `GetObject` on the bucket, not only CloudFront — any other reader of the bucket is impaired too.
- Both invalidations clear the whole distribution cache, so expect an origin-load spike after each.

## Prerequisites

- Distributions tagged `FIS-Ready=True` with **origin groups** configured (primary + secondary). The upstream README calls secondary origins "optional but recommended" in one place and required in another; the code requires them.
- FIS role: start/get/stop automation on your document, `iam:PassRole` on the SSM role.
- SSM role: `cloudfront:ListDistributions`, `ListTagsForResource`, `GetDistributionConfig`, `CreateInvalidation` on `*`; `s3:GetBucketPolicy`, `PutBucketPolicy`, `DeleteBucketPolicy` on `arn:aws:s3:::*`. The upstream README mentions tagging buckets "for the IAM conditions to work", but the shipped policy has **no** tag condition; scope it to your origin buckets if needed.

## Files

| File | Description |
|------|-------------|
| `cloudfront-impairment-tag-based-experiment-template.json` | FIS experiment template |
| `cloudfront-impairment-tag-based-automation.yaml` | SSM Automation document |
| `cloudfront-impairment-tag-based-fis-role-iam-policy.json` | IAM policy for FIS role |
| `cloudfront-impairment-tag-based-ssm-automation-role-iam-policy.json` | IAM policy for SSM role |
| `fis-iam-trust-relationship.json` | Trust policy for FIS role |
| `ssm-iam-trust-relationship.json` | Trust policy for SSM role |
| `AWSFIS.json` | Template-library metadata |

## Deployment

```bash
# 1. Create IAM roles
aws iam create-role --role-name FIS-CloudFrontImpairment --assume-role-policy-document file://fis-iam-trust-relationship.json
aws iam put-role-policy --role-name FIS-CloudFrontImpairment --policy-name fis-policy --policy-document file://cloudfront-impairment-tag-based-fis-role-iam-policy.json

aws iam create-role --role-name SSM-CloudFrontImpairment --assume-role-policy-document file://ssm-iam-trust-relationship.json
aws iam put-role-policy --role-name SSM-CloudFrontImpairment --policy-name ssm-policy --policy-document file://cloudfront-impairment-tag-based-ssm-automation-role-iam-policy.json

# 2. Create SSM Automation document (name must match <AUTOMATION DOCUMENT NAME> in the FIS policy and template)
aws ssm create-document --name cloudfront-impairment --document-type Automation --content file://cloudfront-impairment-tag-based-automation.yaml --document-format YAML

# 3. Tag CloudFront distributions with FIS-Ready=True
# 4. Ensure origin groups are configured on target distributions

# 5. Update experiment template with your role ARNs and document ARN, then:
aws fis create-experiment-template --cli-input-json file://cloudfront-impairment-tag-based-experiment-template.json
```

## Stop Conditions and What a Stop Does

- The template ships with `"stopConditions": [{"source": "none"}]`. Consider alarms on CloudFront `4xxErrorRate` / `5xxErrorRate` / `OriginLatency` or an application metric.
- `applyDenyAllPolicyToBuckets`, `invalidateCloudFrontCache` and `waitForDuration` route `onFailure` / `onCancel` to `removeDenyAllPolicyFromBuckets`, so a stop during the impairment removes the deny statement. Content cached from the secondary origin is not reverted until it expires or the restore invalidation runs.

## Cleanup

Normally automatic. If a run fails during restore, remove only the `FISTemporaryDeny` statement from each origin bucket policy (do not `delete-bucket-policy` unless that statement is the only one — it would also drop OAC/OAI grants), then invalidate `/*` on the distribution.

## What to Verify

- [ ] CloudFront error rate alarm fires when primary origin fails
- [ ] Origin group failover activates within 30 seconds
- [ ] Content continues to be served from secondary origin
- [ ] Application-level monitoring detects degradation
- [ ] After primary origin restore, CloudFront resumes using it
- [ ] No `FISTemporaryDeny` statement remains on any origin bucket
