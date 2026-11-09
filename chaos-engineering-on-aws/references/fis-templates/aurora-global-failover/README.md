# Aurora Global Database Regional Failover — FIS Template

> Source: [aws-samples/fis-template-library](https://github.com/aws-samples/fis-template-library/tree/main/aurora-global-region-failover) (commit ee74d58) | License: MIT-0

## Hypothesis Template

> When the experiment switches the Aurora Global Database over to the secondary Region (`failoverType` is
> `switchover` by default), the secondary cluster becomes the primary and the application resumes reads and
> writes against it within 5 minutes of the switchover starting (RTO 5 minutes). Writes that fail while the
> old primary is read-only or the database is briefly unavailable are retried against the new primary, so the
> application records no write that failed after its retries. A CloudWatch alarm on application error rate or
> database connection failures returns to OK within 5 minutes of the switchover completing.
>
> With `failoverType` set to `failover` (what a real Regional outage calls for), Aurora promotes the secondary
> without waiting for it to catch up, so writes committed in the last seconds can be lost. Expect the lost
> writes to span no more time than `AuroraGlobalDBRPOLag` (`AuroraGlobalDBReplicationLag` on older Aurora
> MySQL versions) showed just before the failover.

## Failover Types

| Type | Use Case | API call | Data Loss |
|------|----------|----------|-----------|
| **Switchover** (default) | Planned maintenance, testing | `FailoverGlobalCluster` with `Switchover=True` | None |
| **Failover** | Emergency DR | `FailoverGlobalCluster` with `AllowDataLoss=True` | Possible (bounded by RPO lag) |

## How It Works

FIS runs one `aws:ssm:start-automation-execution` action (`maxDuration` PT10M). The document:

1. `waitForFISAction`: sleeps 10 seconds.
2. `findSecondaryCluster`: `DescribeGlobalClusters` on `globalClusterIdentifier`; takes the writer as current primary and the **first** non-writer member as target.
3. `performGlobalFailover`: calls `FailoverGlobalCluster` (switchover or failover), then polls every 30 s for up to 600 s until the global cluster is `available` and the target is the writer.
4. `validateFailover`: fails the run if the target is not the writer.

The experiment does not switch back. To return to the original primary Region, run it again (with exactly two member clusters it picks the original primary, now secondary; with more it picks the first non-writer member) or switch over manually.

## Prerequisites

- Aurora Global Database with a primary and at least one secondary cluster.
- FIS role: `ssm:StartAutomationExecution` / Get / Describe / Stop on `document/*` and `automation-execution/*`; `iam:PassRole` on `arn:aws:iam::*:role/*SSM*` — the SSM role's name must contain `SSM`.
- SSM role: `rds:DescribeGlobalClusters`, `rds:FailoverGlobalCluster` on `*`.
- Document name must be `aurora-global-region-failover-automation` (it is hard-coded in the template's `documentArn`), or change both.
- Upstream README asks for the global cluster to be tagged `FIS-Ready=True`, but nothing enforces it: the cluster is selected only by `globalClusterIdentifier`, and the SSM role's permissions have no tag condition.

## Files

| File | Description |
|------|-------------|
| `aurora-global-region-failover-experiment-template.json` | FIS experiment template |
| `aurora-global-region-failover-automation.yaml` | SSM Automation document |
| `aurora-global-region-failover-fis-role-iam-policy.json` | IAM policy for FIS role |
| `aurora-global-region-failover-ssm-automation-role-iam-policy.json` | IAM policy for SSM role |
| `fis-iam-trust-relationship.json` | Trust policy for FIS role |
| `ssm-iam-trust-relationship.json` | Trust policy for SSM role |
| `AWSFIS.json` | Template-library metadata |

## Deployment

```bash
# 1. Create IAM roles (SSM role name must contain "SSM" because of the FIS role's PassRole pattern)
aws iam create-role --role-name FIS-AuroraGlobalFailover --assume-role-policy-document file://fis-iam-trust-relationship.json
aws iam put-role-policy --role-name FIS-AuroraGlobalFailover --policy-name fis-policy --policy-document file://aurora-global-region-failover-fis-role-iam-policy.json

aws iam create-role --role-name SSM-AuroraGlobalFailover --assume-role-policy-document file://ssm-iam-trust-relationship.json
aws iam put-role-policy --role-name SSM-AuroraGlobalFailover --policy-name ssm-policy --policy-document file://aurora-global-region-failover-ssm-automation-role-iam-policy.json

# 2. Create SSM Automation document (name referenced by the template's documentArn)
aws ssm create-document --name aurora-global-region-failover-automation --document-type Automation --content file://aurora-global-region-failover-automation.yaml --document-format YAML

# 3. Update experiment template: <REGION>, <ACCOUNT>, <GLOBAL-CLUSTER-ID>, failoverType,
#    AutomationAssumeRole ARN, FIS roleArn
aws fis create-experiment-template --cli-input-json file://aurora-global-region-failover-experiment-template.json
```

## Key Parameters

- `globalClusterIdentifier`: Aurora Global Database identifier (required)
- `failoverType`: `switchover` (planned, no data loss) or `failover` (emergency, allows data loss); default `switchover`
- `AutomationAssumeRole`: IAM role ARN for SSM Automation execution

## Stop Conditions and What a Stop Does

- The template ships with `"stopConditions": [{"source": "none"}]`; the run ends when the automation completes or is stopped.
- A stop cancels the automation's polling. It **cannot undo** a switchover/failover that Aurora has accepted — the document has no rollback step. Switch back manually if needed.
- The FIS `maxDuration` (PT10M) is shorter than the document's worst case (10 s + up to 600 s polling + validation). A slow switchover can make FIS end the action before validation; raise `maxDuration` if your switchovers take close to 10 minutes.

## What to Verify

- [ ] Secondary cluster successfully promoted to primary
- [ ] Application resumes reads and writes against the new primary within the RTO
- [ ] No write recorded as failed after retries (switchover); lost-write window ≤ RPO lag (failover)
- [ ] Error-rate / connection-failure alarm returns to OK within 5 minutes
- [ ] DNS/Route53 health checks trigger traffic rerouting (if applicable)
