# ElastiCache Redis Primary Node Reboot — FIS Template

> Source: [aws-samples/fis-template-library](https://github.com/aws-samples/fis-template-library/tree/main/elasticache-redis-primary-node-reboot) (commit ee74d58) | License: MIT-0

> ⚠️ **Destructive: this experiment clears the data of every targeted replication group.** Rebooting a primary
> does not fail over; the primary comes back empty and the replicas then clear their copy too (AWS docs:
> "Minimizing downtime in ElastiCache by using Multi-AZ"). Run it only on groups whose contents you can lose.

## Hypothesis Template

> If the primary node of a tagged replication group is rebooted, the time your application can't write to the
> primary endpoint should not exceed 30 seconds, and its error rate should be back to baseline within 60 seconds
> of the replication group showing `available` again. Because the reboot clears the cache, the application
> should then read from its source of truth and repopulate the cache without returning errors.
>
> Measure from the application: time between first and last failed write to the primary endpoint, and error
> rate per minute vs. the 5 minutes before. The hypothesis is false if writes fail for > 30 s, the error rate is
> still above baseline 60 s after `available`, or requests fail while the cache is empty. `CacheMisses` and
> `CurrConnections` on the primary show the emptied cache and the reconnections.

## How It Works

FIS runs one `aws:ssm:start-automation-execution` action (`maxDuration` PT30M). The document:

1. `rebootPrimaryNode` (timeout 300 s): lists every replication group in the Region, keeps those tagged `FIS-Ready=True`, and fails if none. It **refuses to run if more than 20 groups** carry the tag. For every tagged group it re-checks: Redis OSS engine (Valkey refused), cluster mode disabled, `MultiAZ=enabled`, `AutomaticFailover=enabled`, one primary + ≥ 1 replica, not in a Global Datastore, group/primary cluster/node `available`. **If any group fails a check, nothing is rebooted.** It then calls `RebootCacheCluster` on the primary of **every** tagged group. Before each call it reads its own execution and stops calling unless the run and step are still `InProgress`; it makes no call after 200 s.
2. `waitForReboot` + `waitForRebootContinued` (≤ 17 min total): wait until each rebooted node has restarted (`rebooting` seen, or event `Cache node <id> restarted`) and the cluster, node, group and all its nodes are `available`; fails if the rebooted node is no longer primary.
3. `reportAfterFailure` / `reportAfterStop`: run only on failure / stop; check for ~30 s whether every tagged group is healthy and print what they found.

ElastiCache does **not** fail over on a primary reboot: the same node stays primary and the primary endpoint keeps pointing to it. Measured upstream (2-node Redis OSS 7.1 `cache.t4g.micro`, `eu-west-2`): the node kept serving 13–33 s after the call, then restarted; 6–7 one-per-second writes failed (5–6 s from first to last failure); reader-endpoint reads did not fail; **data was gone after every restart**; the group was `available` again 95–213 s after the call.

## Prerequisites

- Replication groups tagged `FIS-Ready=True` (ElastiCache copies group tags to its clusters). Anyone who can add this tag opts a group in — check with `aws resourcegroupstaggingapi get-resources --tag-filters Key=FIS-Ready,Values=True` before each run.
- Each target meets the checks in step 1 above; losing its data is acceptable.
- SSM document named `ElastiCache-Redis-Primary-Node-Reboot` (YAML), the name the template and FIS policy use.
- FIS role: start/get/stop automation on that document; `iam:PassRole` on the SSM role with `iam:PassedToService=ssm.amazonaws.com`. Its trust policy has `aws:SourceAccount` / `aws:SourceArn` conditions — replace `<YOUR REGION>` / `<YOUR AWS ACCOUNT>` in both trust policies.
- SSM role: `elasticache:DescribeCacheClusters`, `DescribeReplicationGroups`, `DescribeEvents`, `ListTagsForResource` on `*`; `elasticache:RebootCacheCluster` only on `cluster:*` with `aws:ResourceTag/FIS-Ready=True`; `ssm:GetAutomationExecution` on its own executions. Change the tag condition if you change `tagKey` / `tagValue`.

## Files

| File | Description |
|------|-------------|
| `elasticache-redis-primary-node-reboot-experiment-template.json` | FIS experiment template |
| `elasticache-redis-primary-node-reboot-automation.yaml` | SSM Automation document |
| `elasticache-redis-primary-node-reboot-fis-role-iam-policy.json` | IAM policy for FIS role |
| `elasticache-redis-primary-node-reboot-ssm-automation-role-iam-policy.json` | IAM policy for SSM role |
| `fis-iam-trust-relationship.json` | Trust policy for FIS role (with confused-deputy condition) |
| `ssm-iam-trust-relationship.json` | Trust policy for SSM role |
| `AWSFIS.json` | Template-library metadata |

## Deployment

```bash
# 1. Create IAM roles (replace placeholders in policies and both trust policies first)
aws iam create-role --role-name FIS-RedisPrimaryReboot --assume-role-policy-document file://fis-iam-trust-relationship.json
aws iam put-role-policy --role-name FIS-RedisPrimaryReboot --policy-name fis-policy --policy-document file://elasticache-redis-primary-node-reboot-fis-role-iam-policy.json

aws iam create-role --role-name SSM-RedisPrimaryReboot --assume-role-policy-document file://ssm-iam-trust-relationship.json
aws iam put-role-policy --role-name SSM-RedisPrimaryReboot --policy-name ssm-policy --policy-document file://elasticache-redis-primary-node-reboot-ssm-automation-role-iam-policy.json

# 2. Create SSM Automation document (exact name)
aws ssm create-document --name ElastiCache-Redis-Primary-Node-Reboot --document-type Automation --content file://elasticache-redis-primary-node-reboot-automation.yaml --document-format YAML

# 3. Tag only the replication groups whose data may be lost: FIS-Ready=True

# 4. Replace <YOUR REGION>, <YOUR AWS ACCOUNT>, <YOUR ROLE NAME>, <YOUR SSM AUTOMATION ROLE NAME>, then:
aws fis create-experiment-template --cli-input-json file://elasticache-redis-primary-node-reboot-experiment-template.json
```

## Stop Conditions and What a Stop Does

The template ships with `"stopConditions": [{"source": "none"}]`. The run ends on stop, when every rebooted node is back and `available`, on a step failure, or when the wait runs out (≈ 25 min max, inside `maxDuration` 30 min).

- **Before the `RebootCacheCluster` call**: no more calls once the step reads a status other than `InProgress`. A call already being sent cannot be stopped, and because AWS does not document how fast the step status changes, a slow change can let remaining tagged groups (up to 20) still be rebooted after the stop.
- **After the call**: the stop ends the wait, **not the reboot**. An accepted reboot cannot be cancelled; the node restarts and its data is cleared, possibly after the experiment has ended (stopping 3 s after the call did not prevent the restart or data loss; the restart came 18 s after the experiment ended).
- A stop condition can end the wait but cannot protect the data. An alarm on a metric of the rebooted node may have no data while it restarts — set missing-data treatment to `breaching` if it should fire then.
- Restarting the experiment reboots the primaries and clears their data again.

## Cleanup

Nothing to restore: there is no failover to reverse. The data cannot be brought back — repopulate from your source of truth or restore a backup into a **new** replication group.

## What to Verify

- [ ] Write failures on the primary endpoint last ≤ 30 s
- [ ] Error rate back to baseline within 60 s of the group showing `available`
- [ ] No request errors while the cache is empty; source of truth absorbs the miss load
- [ ] Clients reconnect to the primary endpoint (connect/read timeouts and retries configured)
- [ ] The same node is still primary afterwards
