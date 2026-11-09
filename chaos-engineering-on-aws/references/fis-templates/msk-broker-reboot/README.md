# Amazon MSK Broker Reboot — FIS Template

> Source: [aws-samples/fis-template-library](https://github.com/aws-samples/fis-template-library/tree/main/msk-broker-reboot) (commit ee74d58) | License: MIT-0

## Hypothesis Template

> If a single broker of a provisioned Amazon MSK cluster is rebooted, the cluster should keep serving produce
> and consume requests on the remaining brokers while partition leadership moves to in-sync replicas, and:
> - the longest delivery stall on the partitions the rebooted broker led should not exceed what your
>   application allows (in testing: ≤ 150 ms in 3 of 5 reboots, **36 s and 62 s** in the other 2, with no
>   error reported to the application);
> - with replication factor 3 and `min.insync.replicas=2`, producers using `acks=all` and idempotence lose no
>   acknowledged message;
> - `OfflinePartitionsCount` stays at 0, and `UnderReplicatedPartitions` returns to 0 within a few minutes of
>   the broker rejoining (within a minute in testing);
> - the cluster is `ACTIVE` again within a few minutes (135–196 s in testing);
> - surviving brokers' CPU (`CpuUser` + `CpuSystem`) stays below your planned headroom (3–33 % in testing).

## How It Works

AWS FIS has no native `aws:msk` action, so FIS runs one `aws:ssm:start-automation-execution` action (`maxDuration` PT21M) that calls the MSK `RebootBroker` API:

1. `rebootBroker` (timeout 300 s): lists clusters with `ListClustersV2` and selects the **first `ACTIVE`, provisioned** cluster tagged `FIS-Ready=True`; lists its nodes and picks a broker. `brokerSelection=random` (template default) actually picks the **lowest broker ID**, for a deterministic target; you can pass a specific broker ID instead. Calls `RebootBroker` (one broker per call).
2. `monitorRecovery` (timeout 600 s, the `aws:executeScript` limit): polls `DescribeClusterOperation` until a terminal `*COMPLETE` state (`REBOOT_COMPLETE`) and reports cluster state. A `*FAILED` state or no terminal state within the window fails the run.

During the run the operation (`REBOOT_NODE`) goes `PENDING` → `REBOOT_IN_PROGRESS` → `REBOOT_COMPLETE` and the cluster is `REBOOTING_BROKER` until it is `ACTIVE` again (130–192 s operation, 135–196 s to `ACTIVE`, on 3 × `kafka.m7g.large`, Kafka 3.9 KRaft).

**Why stalls happen**: if the broker stops without closing connections, a client retries requests already sent to it only after they time out — the 62 s case matched librdkafka's default 60 s `socket.timeout.ms`. A lower `socket.timeout.ms` (librdkafka) / `request.timeout.ms` (Java) should shorten this (not tested upstream). Configure multiple `bootstrap.servers`, `acks=all`, `enable.idempotence=true`, a high `delivery.timeout.ms` (e.g. 120000), and tune consumer `session.timeout.ms` / `heartbeat.interval.ms`.

## Prerequisites

- A **provisioned** (not Serverless) MSK cluster in `ACTIVE` state, tagged `FIS-Ready=True`. **Tag only one cluster per Region**: there is no cluster-name parameter, and with several tagged clusters the first `ACTIVE` one returned by `ListClustersV2` is rebooted.
- Replication factor ≥ 3 across ≥ 2 (ideally 3) AZs, `min.insync.replicas` ≥ 2.
- SSM document named `msk-broker-reboot-automation` (hard-coded in the template's `documentArn` and the FIS role policy).
- FIS role: start/get/stop automation on that document; `iam:PassRole` on the SSM role with `iam:PassedToService=ssm.amazonaws.com`.
- SSM role: `kafka:ListClustersV2`, `ListNodes`, `DescribeClusterV2`, `DescribeCluster`, `DescribeClusterOperation` on `*`; `kafka:RebootBroker` only on clusters with `aws:ResourceTag/FIS-Ready=True`. If you change `tagKey` / `tagValue` in the template, change this condition too, otherwise discovery succeeds but the reboot is denied.
- Tested upstream in `us-east-2` on 3 × `kafka.m7g.large`, Kafka 3.9 KRaft, TLS, a 6-partition RF 3 topic and a confluent-kafka 2.16 producer at 100 msg/s. ZooKeeper clusters, Java clients, other broker types/Regions were not tested.

## Files

| File | Description |
|------|-------------|
| `msk-broker-reboot-experiment-template.json` | FIS experiment template |
| `msk-broker-reboot-automation.yaml` | SSM Automation document |
| `msk-broker-reboot-fis-role-iam-policy.json` | IAM policy for FIS role |
| `msk-broker-reboot-ssm-role-iam-policy.json` | IAM policy for SSM role |
| `fis-iam-trust-relationship.json` | Trust policy for FIS role |
| `ssm-iam-trust-relationship.json` | Trust policy for SSM role |
| `AWSFIS.json` | Template-library metadata |

## Deployment

```bash
# 1. Create IAM roles (replace <YOUR REGION>/<YOUR AWS ACCOUNT>/<YOUR SSM ROLE NAME> first)
aws iam create-role --role-name FIS-MskBrokerReboot --assume-role-policy-document file://fis-iam-trust-relationship.json
aws iam put-role-policy --role-name FIS-MskBrokerReboot --policy-name fis-policy --policy-document file://msk-broker-reboot-fis-role-iam-policy.json

aws iam create-role --role-name SSM-MskBrokerReboot --assume-role-policy-document file://ssm-iam-trust-relationship.json
aws iam put-role-policy --role-name SSM-MskBrokerReboot --policy-name ssm-policy --policy-document file://msk-broker-reboot-ssm-role-iam-policy.json

# 2. Create SSM Automation document (exact name)
aws ssm create-document --name msk-broker-reboot-automation --document-type Automation --content file://msk-broker-reboot-automation.yaml --document-format YAML

# 3. Tag exactly one MSK cluster in the Region with FIS-Ready=True

# 4. Replace every <YOUR ...> placeholder in the template, then:
aws fis create-experiment-template --cli-input-json file://msk-broker-reboot-experiment-template.json
```

## Stop Conditions and What a Stop Does

- The template ships with `"stopConditions": [{"source": "none"}]`. Recommended alarms: `OfflinePartitionsCount` > 0, `UnderMinIsrPartitionCount`, sustained `UnderReplicatedPartitions`, `ActiveControllerCount` ≠ 1.
- Once `RebootBroker` has been called, a stop ends the monitoring step, **not the reboot**: in testing FIS reported `stopped` ~1 s after the request and the broker finished rebooting 82 s later. There is nothing to restore.
- A stop in the first seconds, before `RebootBroker`, may or may not prevent the reboot (not tested) — check `list-cluster-operations-v2` afterwards.
- While the cluster is `REBOOTING_BROKER`, MSK refuses update operations (configuration changes, scaling) from anyone. A second run started during that window fails discovery (`No ACTIVE provisioned MSK cluster found ...`) — or reboots another tagged `ACTIVE` cluster if one exists. Run one experiment per cluster at a time.

## Cleanup

None. The broker rejoins on its own; verify the cluster is `ACTIVE` and `UnderReplicatedPartitions` is 0.

## What to Verify

- [ ] Delivery stall on the rebooted broker's partitions within your SLA; no producer error surfaced
- [ ] No acknowledged message lost (`acks=all`, idempotent producer)
- [ ] `OfflinePartitionsCount` stays 0; `UnderReplicatedPartitions` returns to 0
- [ ] Cluster `ACTIVE` again within a few minutes
- [ ] Surviving brokers' CPU stays within planned headroom
- [ ] Consumers resume without being ejected from the group
