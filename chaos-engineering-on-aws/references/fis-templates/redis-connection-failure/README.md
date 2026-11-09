# ElastiCache Redis Connection Failure — FIS Template

> Source: [aws-samples/fis-template-library](https://github.com/aws-samples/fis-template-library/tree/main/elasticache-redis-connection-failure) (commit ee74d58) | License: MIT-0

## Hypothesis Template

> If the port 6379 ingress rules are removed from the target nodes' security groups for 5 minutes (the
> default `duration`):
> - your application's error rate should not exceed `<YOUR THRESHOLD>` from 30 seconds after its first failed
>   Redis call until the rules are back, because its circuit breakers serve degraded responses instead of errors;
> - within 60 seconds of the rules coming back, your application's Redis calls should succeed at their usual rate; and
> - in the minute after the rules come back, `NewConnections` summed across the nodes should not exceed the
>   number of connections your clients normally open (clients × pool size). A higher sum means a reconnect
>   retry storm. Retries during the fault don't show in this metric, because the security group drops them.

## How It Works

FIS runs one `aws:ssm:start-automation-execution` action (`maxDuration` PT30M, `duration` PT5M). The document:

1. `getTargetClusters`: scans every ElastiCache **cache cluster (node)** running the **Redis** engine and keeps those tagged `FIS-Ready=True` (replication-group tags are copied to its nodes). The list passes to the next step as a step output, which SSM cuts to 100 items, so at most 100 tagged nodes are acted on; the rest are skipped without error. Valkey nodes are not targeted.
2. `disableRedisConnections`: for each node's security groups, removes the ingress rules whose `FromPort` and `ToPort` are both 6379 (any protocol) and records them in the step output. A rule for a port range that includes 6379, an all-traffic rule, or another SG that allows 6379 keeps the node reachable.
3. `waitForDuration`: holds the fault.
4. `restoreRedisConnections`: adds the recorded rules back.

If no tagged node is found, no rule matches, or a tag read / SG call fails, the run still ends `Success` with no fault on those nodes. A failed restore is listed in the output but the run **also ends `Success`** — always check the rules afterwards.

**Key technique**: security-group rule removal — targets one service's connections, unlike subnet-level `aws:network:disrupt-connectivity`.

**Connection tracking**: removing a rule does not cut tracked connections that are already open. Long-lived pooled clients may keep working (in one test, a Lambda client's open connection kept working for ~40 s, the whole observation window) while only new connections fail. To test pooled clients, restart them or close their pools at the start of the fault, and confirm from application metrics that Redis calls actually failed.

## Prerequisites

- Target Redis clusters tagged `FIS-Ready=True`, running the Redis engine (not Valkey), in the standard `aws` partition (node ARNs are built with `arn:aws`; GovCloud/China find nothing).
- Target clusters use **security groups of their own**: everything else using those SGs also loses port 6379 for the duration.
- Save each target SG's rules before every run, e.g. `aws ec2 describe-security-groups --group-ids <SG> > <SG>-before.json`.
- FIS role: start/get/stop automation on your document, `iam:PassRole` on the SSM role.
- SSM role: `elasticache:DescribeCacheClusters`, `ListTagsForResource`; `ec2:DescribeSecurityGroups`, `AuthorizeSecurityGroupIngress`, `RevokeSecurityGroupIngress`; `sts:GetCallerIdentity` — all on `*` with **no tag condition**, so the role can change any SG in the account.
- Tested upstream on a two-node Redis OSS 7.1 replication group (`cache.t4g.micro`, cluster mode disabled) with one SG holding one SG-sourced 6379 rule; cluster mode enabled, other ports, CIDR-sourced rules and multi-SG nodes were not tested.

## Files

| File | Description |
|------|-------------|
| `redis-connection-failure-experiment-template.json` | FIS experiment template |
| `redis-connection-failure-automation.yaml` | SSM Automation document |
| `redis-connection-failure-fis-role-iam-policy.json` | IAM policy for FIS role |
| `redis-connection-failure-ssm-role-iam-policy.json` | IAM policy for SSM role |
| `fis-iam-trust-relationship.json` | Trust policy for FIS role |
| `ssm-iam-trust-relationship.json` | Trust policy for SSM role |
| `AWSFIS.json` | Template-library metadata |

## Deployment

```bash
# 1. Create IAM roles
aws iam create-role --role-name FIS-RedisConnFailure --assume-role-policy-document file://fis-iam-trust-relationship.json
aws iam put-role-policy --role-name FIS-RedisConnFailure --policy-name fis-policy --policy-document file://redis-connection-failure-fis-role-iam-policy.json

aws iam create-role --role-name SSM-RedisConnFailure --assume-role-policy-document file://ssm-iam-trust-relationship.json
aws iam put-role-policy --role-name SSM-RedisConnFailure --policy-name ssm-policy --policy-document file://redis-connection-failure-ssm-role-iam-policy.json

# 2. Create SSM Automation document (name must match the FIS policy and template)
aws ssm create-document --name redis-connection-failure --document-type Automation --content file://redis-connection-failure-automation.yaml --document-format YAML

# 3. Update experiment template with your role ARNs and document ARN, then:
aws fis create-experiment-template --cli-input-json file://redis-connection-failure-experiment-template.json
```

## Stop Conditions and What a Stop Does

The template ships with `"stopConditions": [{"source": "none"}]`. A stop (or a stop condition) behaves by step:

| Step running at stop | Effect |
|----------------------|--------|
| `getTargetClusters` | Nothing changed, nothing to undo |
| `disableRedisConnections` | Not tested upstream. The cancel handler restores the rules in this step's output; rules removed before the output was recorded may stay removed |
| `waitForDuration` | Cancel handler adds the rules back (SSM gives a cancel path ≤ 2 minutes). In one test a stop 23 s into the fault restored the rule 3 s after FIS cancelled; FIS showed `stopped` before the rule was back |
| `restoreRedisConnections` | No cancel handler — rules may stay removed. Same risk if the action hits `maxDuration` (30 min): script steps have no own timeout and can each take up to 600 s |

Keep `duration` well below `maxDuration`.

## Cleanup

After every run, compare each SG with the saved copy. To restore by hand: find the execution (`aws ssm describe-automation-executions --filters Key=StartTimeAfter,Values=<time>` — FIS starts it by ARN, so filter by time), read `disableRedisConnections`' `OutputPayload` (limited to 100 KB) for `removed_rules`, and re-add them with `aws ec2 authorize-security-group-ingress --group-id <SG> --ip-permissions '<JSON>'`. CloudTrail `RevokeSecurityGroupIngress` events (90 days) are the third record. If CloudFormation/CDK manages the SGs, restored rules get new rule IDs and show drift; do not update the stack during a run.

## What to Verify

- [ ] Redis connectivity monitoring detects the failure
- [ ] Application error rate stays under threshold (circuit breaker serves degraded responses)
- [ ] `NewConnections` after restore ≤ normal pool size (no retry storm)
- [ ] Redis calls back to normal rate within 60 s of restore
- [ ] All 6379 rules are back on every target SG
