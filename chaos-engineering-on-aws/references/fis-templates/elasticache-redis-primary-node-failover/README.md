# ElastiCache Redis Primary Node Failover — FIS Template

> Source: [aws-samples/fis-template-library](https://github.com/aws-samples/fis-template-library/tree/main/elasticache-redis-primary-node-failover) (commit ee74d58) | License: MIT-0

> ⚠️ **The upstream files at ee74d58 do not run as shipped.** They are embedded byte-identical; read
> [Known upstream defects](#known-upstream-defects-ee74d58) and fix them in your copy before deploying.

## Hypothesis Template

> When the Redis primary node fails over to a replica, applications should detect the failover and reconnect
> to the new primary within 30 seconds. Connection pooling should handle the DNS endpoint changes gracefully,
> and no data should be lost during the transition. Application performance should return to normal within
> 60 seconds of failover completion.

## How It Works

FIS runs one `aws:ssm:start-automation-execution` action (`maxDuration` PT30M). The document (JSON, single step `triggerFailover`, `aws:executeScript`):

1. Calls `DescribeReplicationGroups` (first page only) and, for each group with `Status=available` and `AutomaticFailover=enabled`, reads its tags.
2. On the **first** group tagged `FIS-Ready=True` it calls `TestFailover` for node group `0001` and returns `Failover initiated`. Only one group is failed over per run.
3. ElastiCache promotes a replica, the former primary becomes a replica, and the primary endpoint's DNS moves to the new primary. The cluster status goes `available` → `modifying` → `available`.

The document does **not** wait for the failover to finish: the FIS action completes as soon as `TestFailover` is accepted, while the role swap is still in progress. Watch completion yourself (`describe-replication-groups ... Status` and `NodeGroupMembers[?CurrentRole=='primary']`).

## Prerequisites

- Replication group tagged `FIS-Ready=True`, Multi-AZ with `AutomaticFailover=enabled`, at least 1 primary + 1 replica (the script itself checks only `AutomaticFailover` and `available`).
- Cluster mode enabled groups: only shard `0001` is failed over.
- FIS role and SSM role created from the sample policies after the fixes below.

## Known upstream defects (ee74d58)

| # | Defect | Effect | Fix in your copy |
|---|--------|--------|------------------|
| 1 | SSM role policy grants `DescribeReplicationGroups`, `ListTagsForResource`, `ModifyReplicationGroup`, `sts:GetCallerIdentity` but **not `elasticache:TestFailover`** | `TestFailover` is denied; the script's `except Exception: continue` swallows the error and the run fails with the misleading `No cluster found with tag FIS-Ready=True` | Add `elasticache:TestFailover` (ideally on `replicationgroup:*` with `aws:ResourceTag/FIS-Ready=True`); `ModifyReplicationGroup` is not used |
| 2 | Template passes `region` and `AutomationAssumeRole` in `documentParameters`, but the document declares only `tagKey` and `tagValue` | SSM Automation rejects parameters a document does not declare, so the start is expected to fail (not tested here) | Remove the two keys from `documentParameters`, or declare them in the document |
| 3 | Document `assumeRole` is hard-coded to `arn:aws:iam::{{ global:ACCOUNT_ID }}:role/ElastiCache-SSM-Automation-Role`; template passes `ElastiCache-Failover-SSM-Role` | Two different SSM role names | Name the SSM role `ElastiCache-SSM-Automation-Role`, or edit `assumeRole` |
| 4 | Template `documentArn` uses `{{ aws:region }}` | Not a documented FIS placeholder | Write your Region literally |
| 5 | FIS role policy: `iam:PassRole` on `arn:aws:iam::*:role/*`, plus ElastiCache and STS permissions FIS does not need for this action | Over-broad | Restrict PassRole to the SSM role with `iam:PassedToService=ssm.amazonaws.com`; drop the ElastiCache/STS statements |
| 6 | No wait/verification step | FIS reports success before the failover completes; a rejected `TestFailover` on later groups is never seen | Add a polling step if you need completion in the FIS timeline |

Upstream SSM document name: `ElastiCache-Redis-Primary-Node-Failover` (FIS role policy and template refer to it).

## Files

| File | Description |
|------|-------------|
| `elasticache-redis-primary-node-failover-experiment-template.json` | FIS experiment template |
| `elasticache-redis-primary-node-failover-automation.json` | SSM Automation document (JSON format) |
| `elasticache-redis-primary-node-failover-fis-role-iam-policy.json` | IAM policy for FIS role |
| `elasticache-redis-primary-node-failover-ssm-role-iam-policy.json` | IAM policy for SSM role |
| `fis-iam-trust-relationship.json` | Trust policy for FIS role |
| `ssm-iam-trust-relationship.json` | Trust policy for SSM role |

## Deployment

```bash
# 0. Apply fixes 1-5 above to your copies first.

# 1. Create IAM roles (SSM role name matches the document's hard-coded assumeRole)
aws iam create-role --role-name ElastiCache-Failover-FIS-Role --assume-role-policy-document file://fis-iam-trust-relationship.json
aws iam put-role-policy --role-name ElastiCache-Failover-FIS-Role --policy-name fis-policy --policy-document file://elasticache-redis-primary-node-failover-fis-role-iam-policy.json

aws iam create-role --role-name ElastiCache-SSM-Automation-Role --assume-role-policy-document file://ssm-iam-trust-relationship.json
aws iam put-role-policy --role-name ElastiCache-SSM-Automation-Role --policy-name ssm-policy --policy-document file://elasticache-redis-primary-node-failover-ssm-role-iam-policy.json

# 2. Create SSM Automation document (JSON format, exact name)
aws ssm create-document --name ElastiCache-Redis-Primary-Node-Failover --document-type Automation --content file://elasticache-redis-primary-node-failover-automation.json --document-format JSON

# 3. Tag the replication group with FIS-Ready=True

# 4. Replace <YOUR-ACCOUNT-ID> and {{ aws:region }} in the template, then:
aws fis create-experiment-template --cli-input-json file://elasticache-redis-primary-node-failover-experiment-template.json
```

## Stop Conditions and What a Stop Does

- The template ships with `"stopConditions": [{"source": "none"}]`.
- The automation finishes seconds after `TestFailover` is accepted, so there is almost no window to stop it, and **a stop cannot undo a failover** ElastiCache has started. The new primary stays primary.

## Cleanup

Nothing is restored automatically. The former primary is now a replica; if you need the original node as primary (e.g. AZ affinity), run another `TestFailover` or a manual failover once the group is `available`.

## What to Verify

- [ ] Application detects the failover and reconnects to the new primary within 30 s
- [ ] Connection pool handles the primary-endpoint DNS change (no stale connections to the old primary)
- [ ] No acknowledged write lost
- [ ] Performance back to normal within 60 s of the group returning to `available`
