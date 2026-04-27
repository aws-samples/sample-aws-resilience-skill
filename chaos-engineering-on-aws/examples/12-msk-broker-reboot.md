# Example 12: MSK Broker Reboot — Kafka Client Resilience

**Architecture pattern**: Kafka Producers/Consumers → Amazon MSK (managed Kafka cluster)
**Injection method**: SSM Automation (kafka:RebootBroker → wait for ACTIVE)
**Validates**: Kafka producer/consumer resilience, partition leader election, broker recovery

> Note: MSK has no native FIS action. Fault injection uses SSM Automation with the MSK API.

---

## Hypothesis

When an MSK broker is rebooted:
- Kafka producers switch to other brokers and continue producing with minimal message loss
- Kafka consumers rebalance partitions and resume consuming within 60 seconds
- The cluster transitions to `REBOOTING_BROKER` then returns to `ACTIVE`
- Partition leaders on the rebooted broker are re-elected to other brokers
- No manual intervention required — the broker comes back online automatically

### What does this enable you to verify?

- Kafka producer `acks` configuration and retry behavior during broker failure
- Consumer group rebalancing speed and partition reassignment
- MSK cluster recovery time after single broker reboot
- Application resilience to partition leader changes
- Two-role IAM pattern for SSM Automation via FIS

## Prerequisites

- [ ] Amazon MSK cluster in `ACTIVE` state
- [ ] Target broker ID identified (use `aws kafka list-nodes`)
- [ ] FIS IAM Role with `AWSFaultInjectionSimulatorSSMAccess` + `iam:PassRole`
- [ ] SSM Automation IAM Role with `kafka:RebootBroker` + `kafka:DescribeCluster`
- [ ] Kafka producers configured with `acks=all` and retry logic
- [ ] Kafka consumers with appropriate `session.timeout.ms` and `heartbeat.interval.ms`

## SSM Automation Runbook

```yaml
description: 'FIS: Reboot MSK broker to test Kafka client resilience'
schemaVersion: '0.3'
assumeRole: '{{ AutomationAssumeRoleArn }}'
parameters:
  AutomationAssumeRoleArn:
    type: String
    description: IAM Role ARN for SSM Automation to assume
  ClusterArn:
    type: String
    description: MSK cluster ARN
  BrokerId:
    type: String
    description: 'Broker ID to reboot (e.g., 1, 2, 3)'
mainSteps:
  - name: RebootMskBroker
    action: aws:executeAwsApi
    inputs:
      Service: kafka
      Api: RebootBroker
      ClusterArn: '{{ ClusterArn }}'
      BrokerIds:
        - '{{ BrokerId }}'
    outputs:
      - Name: ClusterArn
        Selector: $.ClusterArn
        Type: String
      - Name: ClusterOperationArn
        Selector: $.ClusterOperationArn
        Type: String

  - name: WaitForClusterActive
    action: aws:waitForAwsResourceProperty
    timeoutSeconds: 600
    inputs:
      Service: kafka
      Api: DescribeCluster
      ClusterArn: '{{ ClusterArn }}'
      PropertySelector: $.ClusterInfo.State
      DesiredValues:
        - ACTIVE
```

## Setup

### 1. Deploy SSM Automation Document

```bash
aws ssm create-document \
  --name msk-broker-reboot \
  --document-type Automation \
  --content file://ssm-msk-broker-reboot.yaml \
  --document-format YAML
```

### 2. Deploy IAM Roles

```bash
# FIS Role (trusts fis.amazonaws.com)
aws iam create-role \
  --role-name FIS-MSK-Reboot \
  --assume-role-policy-document '{
    "Version": "2012-10-17",
    "Statement": [{"Effect": "Allow", "Principal": {"Service": "fis.amazonaws.com"}, "Action": "sts:AssumeRole"}]
  }'

aws iam attach-role-policy \
  --role-name FIS-MSK-Reboot \
  --policy-arn arn:aws:iam::aws:policy/service-role/AWSFaultInjectionSimulatorSSMAccess

aws iam put-role-policy \
  --role-name FIS-MSK-Reboot \
  --policy-name PassSSMRole \
  --policy-document '{
    "Version": "2012-10-17",
    "Statement": [{"Effect": "Allow", "Action": "iam:PassRole", "Resource": "arn:aws:iam::{account}:role/SSM-MSK-Reboot", "Condition": {"StringEquals": {"iam:PassedToService": "ssm.amazonaws.com"}}}]
  }'

# SSM Automation Role (trusts ssm.amazonaws.com)
aws iam create-role \
  --role-name SSM-MSK-Reboot \
  --assume-role-policy-document '{
    "Version": "2012-10-17",
    "Statement": [{"Effect": "Allow", "Principal": {"Service": "ssm.amazonaws.com"}, "Action": "sts:AssumeRole"}]
  }'

aws iam put-role-policy \
  --role-name SSM-MSK-Reboot \
  --policy-name MskAccess \
  --policy-document '{
    "Version": "2012-10-17",
    "Statement": [{"Effect": "Allow", "Action": ["kafka:RebootBroker", "kafka:DescribeCluster"], "Resource": "*"}]
  }'
```

### 3. Create FIS Experiment

```bash
aws fis create-experiment-template --cli-input-json '{
  "description": "Reboot MSK broker to test Kafka producer and consumer resilience",
  "targets": {},
  "actions": {
    "reboot-broker": {
      "actionId": "aws:ssm:start-automation-execution",
      "parameters": {
        "documentArn": "arn:aws:ssm:{region}:{account}:document/msk-broker-reboot",
        "documentParameters": "{\"AutomationAssumeRoleArn\":\"arn:aws:iam::{account}:role/SSM-MSK-Reboot\",\"ClusterArn\":\"{cluster-arn}\",\"BrokerId\":\"{broker-id}\"}",
        "maxDuration": "PT15M"
      }
    }
  },
  "stopConditions": [{"source": "none"}],
  "roleArn": "arn:aws:iam::{account}:role/FIS-MSK-Reboot",
  "tags": {"Purpose": "chaos-engineering", "RiskId": "R-012"}
}'
```

## Execution

```bash
# List available broker IDs
aws kafka list-nodes --cluster-arn {CLUSTER_ARN} \
  --query 'NodeInfoList[].BrokerNodeInfo.BrokerId' --output json

# Verify cluster is ACTIVE
aws kafka describe-cluster --cluster-arn {CLUSTER_ARN} \
  --query 'ClusterInfo.State'

# Start the experiment
aws fis start-experiment --experiment-template-id {TEMPLATE_ID}

# Monitor cluster state
watch -n 10 'aws kafka describe-cluster \
  --cluster-arn {CLUSTER_ARN} \
  --query "ClusterInfo.State"'
```

## Observation Metrics

| Metric | Source | Expected Behavior |
|--------|--------|-------------------|
| Cluster state | MSK API | ACTIVE → REBOOTING_BROKER → ACTIVE |
| ActiveControllerCount | CloudWatch (AWS/Kafka) | Brief drop if rebooted broker was controller |
| UnderReplicatedPartitions | CloudWatch (AWS/Kafka) | Temporary increase during broker reboot |
| MessagesInPerSec | CloudWatch (AWS/Kafka) | Brief dip on rebooted broker, others compensate |
| Consumer group lag | Kafka metrics | Temporary increase during rebalancing |

## Cleanup

`kafka:RebootBroker` is self-recovering — the broker comes back online automatically. No manual cleanup required.

```bash
# Verify cluster is back to ACTIVE
aws kafka describe-cluster --cluster-arn {CLUSTER_ARN} \
  --query 'ClusterInfo.State'

# Delete experiment template when done
aws fis delete-experiment-template --id {TEMPLATE_ID}
```
