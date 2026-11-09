# FIS Scenario Library Reference

> ⚠️ **Important**: The FIS Scenario Library is a console feature. A scenario is a pre-built set of actions and targets, not a ready-to-run experiment template: role, stop conditions, resource tags and some identifiers still have to be supplied.
> Each official scenario page publishes its **Scenario Content** JSON, and AWS states this JSON can be saved and used with `aws fis create-experiment-template`. Three ways to create a template:
> (1) Create it from the Console Scenario Library, then export it with `aws fis get-experiment-template`;
> (2) Copy the scenario content from the Console **Content** tab (the latest version), fill in the missing values, and create it with `aws fis create-experiment-template`;
> (3) Use the official Scenario Content JSON reproduced below, fill in the missing values, and create it with `aws fis create-experiment-template --cli-input-json` — fully automated, no Console interaction.
> The JSON blocks below are copied verbatim from the AWS documentation pages (placeholders such as `us-east-1a` and empty `roleArn` are AWS's own). The console Content tab may be newer than these copies.

> 🛑 **Stop conditions**: AWS documents a limitation for all four scenarios — they **ship without stop conditions**, and the correct stop conditions for your application must be added to the experiment template.
> This skill **requires** a CloudWatch alarm stop condition on every experiment: replace the `stopConditions` block of the official JSON with `[{"source": "aws:cloudwatch:alarm", "value": "<alarm ARN>"}]` before creating the template.

## Overview

FIS Scenario Library provides **pre-built, multi-action experiment templates** that simulate real-world failure scenarios.
Unlike single-action experiments (e.g., terminate one EC2 instance), these scenarios orchestrate **multiple coordinated actions**
across services to simulate AZ-level or region-level failures.

### Key Differences from Single-Action Experiments

| Aspect | Single Action | Scenario Library |
|--------|--------------|-----------------|
| Scope | One service, one action | Multiple services, coordinated actions |
| Template creation | API / CLI / Console | Console Scenario Library UI, or the official Scenario Content JSON via `create-experiment-template` |
| Resource targeting | ARN / tag filters | **Default scenario tags** (or your own tags), EKS pod labels, IAM role ARNs |
| Empty targets | Experiment fails | `emptyTargetResolutionMode: skip` — actions with no matching targets are skipped |
| Complexity | Simple | Orchestrated multi-phase |
| Use case | Component-level validation | AZ/region-level resilience validation |

> ⚠️ Because the scenarios use `emptyTargetResolutionMode: skip`, a missing or misspelled tag does not fail the experiment — the action is silently skipped. Verify target resolution (the experiment's target list) before reading any result as "resilient".

---

## Scenario 1: AZ Power Interruption

**Scenario ID**: `az-availability-scenario` (console name: **AZ Availability: Power Interruption**)

Induces the expected symptoms of a complete power interruption in one Availability Zone: loss of zonal compute (EC2, and EKS/ECS on EC2), no re-scaling of compute in the AZ, subnet connectivity loss, RDS failover, ElastiCache failover and unresponsive EBS volumes.
By default it injects power-interruption symptoms for 30 minutes and then, for another 30 minutes, symptoms that may occur during recovery (`Pause-EBS-IO` starts after both stop actions finish).

### Sub-Actions

| Action name (JSON) | Action ID | Effect |
|--------------------|-----------|--------|
| `Stop-Instances` | `aws:ec2:stop-instances` | Stop tagged running instances in the AZ for 30 min, then restart them |
| `Stop-ASG-Instances` | `aws:ec2:stop-instances` | Stop ASG-managed instances in the AZ for 30 min, then restart them |
| `Pause-Instance-Launches` | `aws:ec2:api-insufficient-instance-capacity-error` | Return InsufficientInstanceCapacity to `RunInstances`/`StartInstances`/`CreateFleet` calls by the target IAM roles in the AZ |
| `Pause-ASG-Scaling` | `aws:ec2:asg-insufficient-instance-capacity-error` | Return InsufficientInstanceCapacity to the ASG control plane in the AZ (also blocks EKS/ECS scaling there) |
| `Pause-network-connectivity` | `aws:network:disrupt-connectivity` | Block all traffic (`scope: all`) for tagged subnets in the AZ for 2 min, approximating the DNS-update window |
| `Failover-RDS` | `aws:rds:failover-db-cluster` | Fail over tagged clusters whose writer is in the AZ |
| `Pause-ElastiCache` | `aws:elasticache:replicationgroup-interrupt-az-power` | Interrupt power to nodes in the AZ for Multi-AZ replication groups for 30 min; replacements are blocked |
| `Pause-EBS-IO` | `aws:ebs:pause-volume-io` | After the stop actions, pause I/O on 1 tagged volume (`COUNT(1)`) for 30 min |

The documentation prose also describes `aws:arc:start-zonal-autoshift` (start 5 min in, shift traffic for 25 min, tag value `RecoverAutoshiftResources`) and an `aws:network:disrupt-connectivity` action against S3 Express One Zone directory buckets. Neither appears in the Scenario Content JSON on the doc page; check the console Content tab if you need them.

### Required Resource Tags

All tags use key `AzImpairmentPower`. Values below are those in the official Scenario Content JSON; you may replace them with your own tags in the template.

| Tag Key | Tag Value | Applied To |
|---------|-----------|------------|
| `AzImpairmentPower` | `StopInstances` | EC2 instances (not in an ASG) |
| `AzImpairmentPower` | `IceAsg` | Auto Scaling groups **and** their EC2 instances |
| `AzImpairmentPower` | `DisruptSubnet` | Subnets in the AZ |
| `AzImpairmentPower` | `DisruptRds` | RDS / Aurora clusters |
| `AzImpairmentPower` | `DisruptElasticache` | ElastiCache replication groups |
| `AzImpairmentPower` | `ApiPauseVolume` | EBS volumes (only volumes with `DeleteOnTermination=false` are targeted) |
| (none) | IAM role ARNs in the `IAM-role` target | Roles that provision instances (this action does not support tags) |

> ⚠️ The doc prose names `ElasticacheImpact` and `APIPauseVolume` for two of these, but the Scenario Content JSON uses `DisruptElasticache` and `ApiPauseVolume`. Tag your resources with whatever value the template you actually create contains.

### Parameters

| Parameter | Where it appears in the JSON | Default |
|-----------|------------------------------|---------|
| Availability Zone | `Placement.AvailabilityZone` / `AvailabilityZone` filters, `availabilityZoneIdentifier`, `writerAvailabilityZoneIdentifiers`, `availabilityZoneIdentifiers` | `us-east-1a` (replace **every** occurrence) |
| Interruption duration | `duration` / `startInstancesAfterDuration` | `PT30M` |
| Network disruption duration | `Pause-network-connectivity.duration` | `PT2M` |
| ICE percentage | `percentage` on both ICE actions | `100` |
| Instance-provisioning roles | `targets.IAM-role.resourceArns` | `[]` (fill in or the action is skipped) |
| Experiment role | `roleArn` | `""` (must be filled) |

### Official Scenario Content JSON

source: official doc https://docs.aws.amazon.com/fis/latest/userguide/az-availability-scenario.html, retrieved 2026-11-09; the console Content tab is the latest version

```json
{
  "targets": {
    "IAM-role": {
      "resourceType": "aws:iam:role",
      "resourceArns": [],
      "selectionMode": "ALL"
    },
    "EBS-Volumes": {
      "resourceType": "aws:ec2:ebs-volume",
      "resourceTags": {
        "AzImpairmentPower": "ApiPauseVolume"
      },
      "selectionMode": "COUNT(1)",
      "parameters": {
        "availabilityZoneIdentifier": "us-east-1a"
      },
      "filters": [
        {
          "path": "Attachments.DeleteOnTermination",
          "values": [
            "false"
          ]
        }
      ]
    },
    "EC2-Instances": {
      "resourceType": "aws:ec2:instance",
      "resourceTags": {
        "AzImpairmentPower": "StopInstances"
      },
      "filters": [
        {
          "path": "State.Name",
          "values": [
            "running"
          ]
        },
        {
          "path": "Placement.AvailabilityZone",
          "values": [
            "us-east-1a"
          ]
        }
      ],
      "selectionMode": "ALL"
    },
    "ASG": {
      "resourceType": "aws:ec2:autoscaling-group",
      "resourceTags": {
        "AzImpairmentPower": "IceAsg"
      },
      "selectionMode": "ALL"
    },
    "ASG-EC2-Instances": {
      "resourceType": "aws:ec2:instance",
      "resourceTags": {
        "AzImpairmentPower": "IceAsg"
      },
      "filters": [
        {
          "path": "State.Name",
          "values": [
            "running"
          ]
        },
        {
          "path": "Placement.AvailabilityZone",
          "values": [
            "us-east-1a"
          ]
        }
      ],
      "selectionMode": "ALL"
    },
    "Subnet": {
      "resourceType": "aws:ec2:subnet",
      "resourceTags": {
        "AzImpairmentPower": "DisruptSubnet"
      },
      "filters": [
        {
          "path": "AvailabilityZone",
          "values": [
            "us-east-1a"
          ]
        }
      ],
      "selectionMode": "ALL",
      "parameters": {}
    },
    "RDS-Cluster": {
      "resourceType": "aws:rds:cluster",
      "resourceTags": {
        "AzImpairmentPower": "DisruptRds"
      },
      "selectionMode": "ALL",
      "parameters": {
        "writerAvailabilityZoneIdentifiers": "us-east-1a"
      }
    },
    "ElastiCache-Cluster": {
      "resourceType": "aws:elasticache:replicationgroup",
      "resourceTags": {
        "AzImpairmentPower": "DisruptElasticache"
      },
      "selectionMode": "ALL",
      "parameters": {
        "availabilityZoneIdentifier": "us-east-1a"
      }
    }
  },
  "actions": {
    "Pause-Instance-Launches": {
      "actionId": "aws:ec2:api-insufficient-instance-capacity-error",
      "parameters": {
        "availabilityZoneIdentifiers": "us-east-1a",
        "duration": "PT30M",
        "percentage": "100"
      },
      "targets": {
        "Roles": "IAM-role"
      }
    },
    "Pause-EBS-IO": {
      "actionId": "aws:ebs:pause-volume-io",
      "parameters": {
        "duration": "PT30M"
      },
      "targets": {
        "Volumes": "EBS-Volumes"
      },
      "startAfter": [
        "Stop-Instances",
        "Stop-ASG-Instances"
      ]
    },
    "Stop-Instances": {
      "actionId": "aws:ec2:stop-instances",
      "parameters": {
        "completeIfInstancesTerminated": "true",
        "startInstancesAfterDuration": "PT30M"
      },
      "targets": {
        "Instances": "EC2-Instances"
      }
    },
    "Pause-ASG-Scaling": {
      "actionId": "aws:ec2:asg-insufficient-instance-capacity-error",
      "parameters": {
        "availabilityZoneIdentifiers": "us-east-1a",
        "duration": "PT30M",
        "percentage": "100"
      },
      "targets": {
        "AutoScalingGroups": "ASG"
      }
    },
    "Stop-ASG-Instances": {
      "actionId": "aws:ec2:stop-instances",
      "parameters": {
        "completeIfInstancesTerminated": "true",
        "startInstancesAfterDuration": "PT30M"
      },
      "targets": {
        "Instances": "ASG-EC2-Instances"
      }
    },
    "Pause-network-connectivity": {
      "actionId": "aws:network:disrupt-connectivity",
      "parameters": {
        "duration": "PT2M",
        "scope": "all"
      },
      "targets": {
        "Subnets": "Subnet"
      }
    },
    "Failover-RDS": {
      "actionId": "aws:rds:failover-db-cluster",
      "parameters": {},
      "targets": {
        "Clusters": "RDS-Cluster"
      }
    },
    "Pause-ElastiCache": {
      "actionId": "aws:elasticache:replicationgroup-interrupt-az-power",
      "parameters": {
        "duration": "PT30M"
      },
      "targets": {
        "ReplicationGroups": "ElastiCache-Cluster"
      }
    }
  },
  "stopConditions": [
    {
      "source": "aws:cloudwatch:alarm",
      "value": ""
    }
  ],
  "roleArn": "",
  "tags": {
    "Name": "AZ Impairment: Power Interruption"
  },
  "logConfiguration": {
    "logSchemaVersion": 2
  },
  "experimentOptions": {
    "accountTargeting": "single-account",
    "emptyTargetResolutionMode": "skip"
  },
  "description": "Affect multiple resource types in a single AZ, targeting by tags and explicit ARNs, to approximate power interruption in one AZ."
}
```

Before creating the template: set `roleArn` (the API requires 20+ characters, so `""` is rejected), replace the empty alarm `value` in `stopConditions` with your alarm ARN, replace `us-east-1a` everywhere, and add role ARNs to `IAM-role` or remove `Pause-Instance-Launches` (see pruning below). The JSON's `logConfiguration` has `logSchemaVersion` but no destination; add a CloudWatch Logs or S3 destination or remove the block (a reference CloudFormation guide reports the destination-less block fails with "Must specify at least one log destination"; not verified here against the CLI).

### CLI Command (API Automation)

Save the edited JSON as `az-power-interruption.json`, then:

```bash
aws fis create-experiment-template --cli-input-json file://az-power-interruption.json
```

After creation, start the experiment:

```bash
aws fis start-experiment --experiment-template-id <TEMPLATE_ID>
```

A parameterized version with a mandatory alarm stop condition is in `references/templates/az-power-interruption.json`. It keeps the official sub-actions, targets and tags, with two deliberate differences: `Pause-EBS-IO` starts after an `aws:fis:wait` action (`Wait-Before-EBS-Pause`, same duration as the interruption) instead of `startAfter` on the two stop actions, so any stop action can be pruned without leaving a dangling reference; and `logConfiguration` is omitted.

### Prerequisites

- Resources tagged as in the table above (or the template edited to your tags)
- FIS experiment role with the policy from the doc page. It grants: `ec2:StopInstances`, `ec2:StartInstances`, `ec2:DescribeInstances`, `ec2:InjectApiError` (condition `ec2:FisActionId` = the two ICE actions), `autoscaling:DescribeAutoScalingGroups`, `ec2:PauseVolumeIO`, `ec2:DescribeVolumes`, `kms:CreateGrant` (for encrypted volumes, via `ec2.*.amazonaws.com`), the network ACL set (`ec2:CreateNetworkAcl`, `ec2:CreateNetworkAclEntry`, `ec2:DeleteNetworkAcl`, `ec2:ReplaceNetworkAclAssociation`, `ec2:CreateTags` with `managedByFIS=true`, `ec2:DescribeVpcs`, `ec2:DescribeSubnets`, `ec2:DescribeNetworkAcls`, `ec2:DescribeManagedPrefixLists`), `rds:FailoverDBCluster`, `rds:RebootDBInstance`, `elasticache:InterruptClusterAzPower`, `elasticache:DescribeReplicationGroups`, `tag:GetResources`, and CloudWatch Logs delivery permissions
- If you add ARC zonal autoshift: the service-linked role `AWSServiceRoleForZonalAutoshiftPracticeRun` (created automatically by ARC)
- Multi-AZ deployment (otherwise this test has no resilience value); ElastiCache replication groups must have Multi-AZ enabled
- CloudWatch alarm for the stop condition (the skill mandates it)
- Sufficient capacity in remaining AZs to handle full traffic
- Documented limitations: EKS pods and ECS tasks on Fargate are not affected; RDS Multi-AZ with two readable standbys is not supported (capacity is re-provisioned in the affected AZ immediately)

### Service-Scoped Sub-Action Pruning

When the user names specific services ("AZ power loss for RDS", "test EC2 and ElastiCache"), keep **only** those services' sub-actions plus the sub-actions that model the AZ itself. Do not ship all eight sub-actions by default: other applications in the same AZ would be hit. Run the full set only when the user asks for a full AZ power interruption or names no service, and always read the final sub-action list back to the user before creating the template.

**Sub-actions that model the AZ itself**, judged against the official doc:

| Sub-action | Decision | Justification |
|------------|----------|---------------|
| `Pause-network-connectivity` (`aws:network:disrupt-connectivity`, target `Subnet`) | **Keep by default** in every pruned set | The doc states networking in the AZ is unavailable during the event and DNS may return unreachable private IPs for a few minutes; this 2-minute block is what makes in-scope clients see that. Drop it only if the user explicitly declines network disruption, and confirm. |
| `Pause-ASG-Scaling` (`aws:ec2:asg-insufficient-instance-capacity-error`, target `ASG`) | Keep whenever **any compute** is in scope (EC2 in an ASG, EKS or ECS on EC2) | The doc ties it to "no re-scaling of compute in the AZ" and says it also stops EKS and ECS scaling there. It acts only on tagged ASGs, so it adds nothing to an RDS-, ElastiCache- or EBS-only test. |
| `Pause-Instance-Launches` (`aws:ec2:api-insufficient-instance-capacity-error`, target `IAM-role`) | Keep **only** when the user supplies the ARNs of roles that launch instances outside Auto Scaling (scripts, CI/CD, Lambda) | The doc says this action targets IAM roles by ARN only and is skipped when none are found. The reference guide additionally reports that service-linked roles are not accepted and that an empty `resourceArns` fails CloudFormation validation; neither is stated in the official doc, so treat them as unverified. |
| ARC zonal autoshift (`aws:arc:start-zonal-autoshift`) | Add only if the environment has autoshift-enabled resources | Described in the doc prose but absent from the doc's Scenario Content JSON and from `references/templates/az-power-interruption.json`. |

**User mentions X → keep:**

| User mentions | Keep sub-actions | Keep targets | Tags to apply (`AzImpairmentPower=`) | IAM statements to keep |
|---------------|------------------|--------------|--------------------------------------|------------------------|
| (always, unless declined) | `Pause-network-connectivity` | `Subnet` | `DisruptSubnet` on the subnets in the AZ | Network ACL set (`ec2:CreateNetworkAcl`, `ec2:CreateNetworkAclEntry`, `ec2:DeleteNetworkAcl`, `ec2:ReplaceNetworkAclAssociation`, `ec2:CreateTags` with `managedByFIS`, `ec2:DescribeVpcs`, `ec2:DescribeSubnets`, `ec2:DescribeNetworkAcls`, `ec2:DescribeManagedPrefixLists`) |
| (always) | — | — | — | `tag:GetResources`; the CloudWatch Logs delivery statement if you keep `logConfiguration` |
| EC2 (standalone instances) | `Stop-Instances` | `EC2-Instances` | `StopInstances` | `ec2:StopInstances`, `ec2:StartInstances`, `ec2:DescribeInstances`, `kms:CreateGrant` (encrypted volumes) |
| EC2 in an ASG, Auto Scaling, EKS or ECS on EC2 | `Stop-ASG-Instances`, `Pause-ASG-Scaling` | `ASG-EC2-Instances`, `ASG` | `IceAsg` on the ASG **and** its current instances | As above, plus `ec2:InjectApiError` (condition `ec2:FisActionId` = `aws:ec2:asg-insufficient-instance-capacity-error`) and `autoscaling:DescribeAutoScalingGroups` |
| Custom roles that call `RunInstances` | `Pause-Instance-Launches` | `IAM-role` (role ARNs) | — (ARN only) | `ec2:InjectApiError` (condition `ec2:FisActionId` = `aws:ec2:api-insufficient-instance-capacity-error`) |
| RDS / Aurora | `Failover-RDS` | `RDS-Cluster` | `DisruptRds` | `rds:FailoverDBCluster` (the doc policy also lists `rds:RebootDBInstance`) |
| ElastiCache (Redis / Valkey) | `Pause-ElastiCache` | `ElastiCache-Cluster` | `DisruptElasticache` | `elasticache:InterruptClusterAzPower`, `elasticache:DescribeReplicationGroups` |
| EBS | `Pause-EBS-IO` (+ `Wait-Before-EBS-Pause` in the skill template) | `EBS-Volumes` | `ApiPauseVolume` (volumes with `DeleteOnTermination=false`) | `ec2:PauseVolumeIO`, `ec2:DescribeVolumes`, `kms:CreateGrant` (encrypted volumes) |

**Pruning rules:**

1. Delete each removed sub-action **together with its target**. In `references/templates/az-power-interruption.json` every action has its own target (the action `description` names the unit), so deleting an action+target pair keeps the template valid under `validate-skill.sh`. In the official doc JSON, `Pause-EBS-IO` has `startAfter: ["Stop-Instances", "Stop-ASG-Instances"]`; if you prune a stop action there, remove its name from that list too.
2. Remove targets that no action references any more. The official FIS documentation does not say whether `create-experiment-template` rejects unreferenced targets (unverified), so remove them regardless; an unused tag-based target only adds confusion.
3. Remove the IAM statements and tags of pruned services as well, so the role keeps least privilege.
4. **Pruning never removes `stopConditions`.** The CloudWatch alarm stop condition stays in every pruned template. Do not adopt `"source": "none"`, even though the official cross-AZ and cross-Region content and some reference guides use it.
5. Pruning reduces the blast radius, but it does not isolate the remaining services: while `Pause-network-connectivity` is kept, **every resource in the tagged subnets loses connectivity for its duration**, whatever service it belongs to. To narrow that, tag only the subnets that host the in-scope services, and tell the user which other workloads share those subnets.

---

## Scenario 2: AZ Application Slowdown

**Scenario ID**: `az-application-slowdown-scenario` (console name: **AZ: Application Slowdown**)

Adds latency to network flows between resources within a single AZ — a gray failure. By default it adds 200 ms to 100% of flows for 30 minutes. The three actions run in parallel; the scenario needs at least one EC2 instance, ECS task or EKS pod in the AZ, and all targets must be in the same VPC.

### Sub-Actions

| Action name (JSON) | Action ID | Effect |
|--------------------|-----------|--------|
| `LatencyForEC2` | `aws:ssm:send-command` (document `AWSFIS-Run-Network-Latency-Sources`) | Add latency on EC2 instances to traffic toward the AZ |
| `LatencyForECS` | `aws:ecs:task-network-latency` | Add latency on ECS tasks (EC2 or Fargate) |
| `LatencyForEKS` | `aws:eks:pod-network-latency` | Add latency on EKS pods (on EC2) |

### Required Resource Tags

| Tag Key / Label | Value | Applied To |
|-----------------|-------|------------|
| `AZApplicationSlowdown` (tag) | `LatencyForEC2` | EC2 instances |
| `AZApplicationSlowdown` (tag) | `LatencyForECS` | ECS tasks |
| `AZApplicationSlowdown` (pod label) | `LatencyForEKS` | EKS pods in the `default` namespace of the cluster set in `clusterIdentifier` |

### Parameters

| Parameter | Where it appears in the JSON | Default |
|-----------|------------------------------|---------|
| Availability Zone | `sources`, `Sources` in `documentParameters`, AZ filters, `availabilityZoneIdentifier` | `us-east-1a` |
| Latency | `delayMilliseconds` / `DelayMilliseconds` | `200` |
| Flows percentage | `flowsPercent` / `FlowsPercent` | `100` |
| Duration | `duration` (and `DurationSeconds` for EC2) | `PT30M` (`1800`) |
| EKS cluster | `TargetsForEKS.parameters.clusterIdentifier` | `""` — fill in, or **remove the EKS action and target** |
| EKS service account | `kubernetesServiceAccount` | `fis-service-account` |

### Official Scenario Content JSON

source: official doc https://docs.aws.amazon.com/fis/latest/userguide/az-application-slowdown-scenario.html, retrieved 2026-11-09; the console Content tab is the latest version

```json
{
  "tags": {
    "Name": "AZ: Application Slowdown"
  },
  "description": "Add latency between resources within a single AZ.",
  "actions": {
    "LatencyForEKS": {
      "actionId": "aws:eks:pod-network-latency",
      "parameters": {
        "delayMilliseconds": "200",
        "duration": "PT30M",
        "flowsPercent": "100",
        "interface": "DEFAULT",
        "kubernetesServiceAccount": "fis-service-account",
        "sources": "us-east-1a"
      },
      "targets": {
        "Pods": "TargetsForEKS"
      }
    },
    "LatencyForEC2": {
      "actionId": "aws:ssm:send-command",
      "parameters": {
        "duration": "PT30M",
        "documentArn": "arn:aws:ssm:us-east-1::document/AWSFIS-Run-Network-Latency-Sources",
        "documentParameters": "{\"DelayMilliseconds\":\"200\",\"Sources\":\"us-east-1a\",\"Interface\":\"DEFAULT\",\"TrafficType\":\"egress\",\"DurationSeconds\":\"1800\",\"FlowsPercent\":\"100\",\"InstallDependencies\":\"True\"}"
      },
      "targets": {
        "Instances": "TargetsForEC2"
      }
    },
    "LatencyForECS": {
      "actionId": "aws:ecs:task-network-latency",
      "parameters": {
        "delayMilliseconds": "200",
        "duration": "PT30M",
        "flowsPercent": "100",
        "installDependencies": "true",
        "sources": "us-east-1a",
        "useEcsFaultInjectionEndpoints": "true"
      },
      "targets": {
        "Tasks": "TargetsForECS"
      },
      "startAfter": []
    }
  },
  "targets": {
    "TargetsForEKS": {
      "parameters": {
        "availabilityZoneIdentifier": "us-east-1a",
        "clusterIdentifier": "",
        "namespace": "default",
        "selectorType": "labelSelector",
        "selectorValue": "AZApplicationSlowdown=LatencyForEKS"
      },
      "resourceType": "aws:eks:pod",
      "selectionMode": "ALL"
    },
    "TargetsForEC2": {
      "filters": [
        {
          "path": "Placement.AvailabilityZone",
          "values": [
            "us-east-1a"
          ]
        }
      ],
      "resourceTags": {
        "AZApplicationSlowdown": "LatencyForEC2"
      },
      "resourceType": "aws:ec2:instance",
      "selectionMode": "ALL"
    },
    "TargetsForECS": {
      "filters": [
        {
          "path": "AvailabilityZone",
          "values": [
            "us-east-1a"
          ]
        }
      ],
      "resourceTags": {
        "AZApplicationSlowdown": "LatencyForECS"
      },
      "resourceType": "aws:ecs:task",
      "selectionMode": "ALL"
    }
  },
  "experimentOptions": {
    "accountTargeting": "single-account",
    "emptyTargetResolutionMode": "skip"
  },
  "stopConditions": [
    {
      "source": "none"
    }
  ]
}
```

Before creating the template: add `roleArn`, replace `"stopConditions": [{"source": "none"}]` with an alarm stop condition, set the AZ and region in the `documentArn`, and fill in or remove the EKS target.

### CLI Command (API Automation)

Save the edited JSON as `az-application-slowdown.json`, then:

```bash
aws fis create-experiment-template --cli-input-json file://az-application-slowdown.json
```

After creation, start the experiment:

```bash
aws fis start-experiment --experiment-template-id <TEMPLATE_ID>
```

### Prerequisites

- An IAM role FIS can assume. When the template is created from the console scenario, FIS creates the role with the managed policies `AWSFaultInjectionSimulatorEC2Access`, `AWSFaultInjectionSimulatorECSAccess` and `AWSFaultInjectionSimulatorEKSAccess`. For an existing role, the doc's policy grants `ssm:SendCommand`, `ssm:ListCommands`, `ssm:CancelCommand`, `ec2:DescribeInstances`, `ec2:DescribeSubnets`, `ecs:DescribeTasks`, `ecs:DescribeContainerInstances`, `eks:DescribeCluster` and `tag:GetResources`
- EC2: SSM Agent installed and instances managed by Systems Manager
- ECS: setup for ECS task actions (SSM-managed tasks, `pidMode: task`, not `bridge` network mode; `flowsPercent` needs ECS agent 1.100.0+)
- EKS: setup for EKS pod actions (service account `fis-service-account` with its RBAC, and the FIS role mapped into the cluster; see "Use the AWS FIS aws:eks:pod actions" in the FIS user guide)
- Latency-aware CloudWatch alarm for the stop condition (the skill mandates it)

---

## Scenario 3: Cross-AZ Traffic Slowdown

**Scenario ID**: `cross-az-traffic-slowdown-scenario` (console name: **Cross-AZ: Traffic Slowdown**)

Injects packet loss on outbound traffic from resources in the selected AZ to the other AZs in the Region — a gray failure in cross-AZ communication. By default 15% packet loss on 100% of outbound flows for 30 minutes. The three actions run in parallel; at least one EC2 instance, ECS task or EKS pod is needed in the AZ, and all targets must be in the same VPC.

### Sub-Actions

| Action name (JSON) | Action ID | Effect |
|--------------------|-----------|--------|
| `PacketLossForEC2` | `aws:ssm:send-command` (document `AWSFIS-Run-Network-Packet-Loss-Sources`) | Packet loss on EC2 egress toward the other AZs |
| `PacketLossForECS` | `aws:ecs:task-network-packet-loss` | Packet loss on ECS task egress toward the other AZs |
| `PacketLossForEKS` | `aws:eks:pod-network-packet-loss` | Packet loss on EKS pod egress toward the other AZs |

### Required Resource Tags

| Tag Key / Label | Value | Applied To |
|-----------------|-------|------------|
| `CrossAZTrafficSlowdown` (tag) | `PacketLossForEC2` | EC2 instances in the selected AZ |
| `CrossAZTrafficSlowdown` (tag) | `PacketLossForECS` | ECS tasks in the selected AZ |
| `CrossAZTrafficSlowdown` (pod label) | `PacketLossForEKS` | EKS pods in the `default` namespace of the cluster set in `clusterIdentifier` |

> ⚠️ The doc prose gives the EKS label as `CrossAZTraffic=PacketLossForEKS`, while the Scenario Content JSON uses `CrossAZTrafficSlowdown=PacketLossForEKS`. Label pods with the `selectorValue` of the template you actually create.

### Parameters

| Parameter | Where it appears in the JSON | Default |
|-----------|------------------------------|---------|
| Impaired AZ | AZ filters and `availabilityZoneIdentifier` | `us-east-1a` |
| Destination AZs | `sources` / `Sources` | `us-east-1b,…,us-east-1f` — set to the **other** AZs of your Region |
| Packet loss | `lossPercent` / `LossPercent` | `15` |
| Flows percentage | `flowsPercent` / `FlowsPercent` | `100` |
| Duration | `duration` (and `DurationSeconds` for EC2) | `PT30M` (`1800`) |
| EKS cluster | `TargetsForEKS.parameters.clusterIdentifier` | `""` — fill in, or **remove the EKS action and target** |

### Official Scenario Content JSON

source: official doc https://docs.aws.amazon.com/fis/latest/userguide/cross-az-traffic-slowdown-scenario.html, retrieved 2026-11-09; the console Content tab is the latest version

```json
{
  "tags": {
    "Name": "Cross-AZ: Traffic Slowdown"
  },
  "description": "Inject packet loss to disrupt and slow down traffic between AZs.",
  "actions": {
    "PacketLossForEC2": {
      "actionId": "aws:ssm:send-command",
      "parameters": {
        "duration": "PT30M",
        "documentArn": "arn:aws:ssm:us-east-1::document/AWSFIS-Run-Network-Packet-Loss-Sources",
        "documentParameters": "{\"Sources\":\"us-east-1b,us-east-1c,us-east-1d,us-east-1e,us-east-1f\",\"LossPercent\":\"15\",\"Interface\":\"DEFAULT\",\"TrafficType\":\"egress\",\"DurationSeconds\":\"1800\",\"FlowsPercent\":\"100\",\"InstallDependencies\":\"True\"}"
      },
      "targets": {
        "Instances": "TargetsForEC2"
      }
    },
    "PacketLossForECS": {
      "actionId": "aws:ecs:task-network-packet-loss",
      "parameters": {
        "sources": "us-east-1b,us-east-1c,us-east-1d,us-east-1e,us-east-1f",
        "lossPercent": "15",
        "duration": "PT30M",
        "flowsPercent": "100",
        "installDependencies": "true",
        "useEcsFaultInjectionEndpoints": "true"
      },
      "targets": {
        "Tasks": "TargetsForECS"
      }
    },
    "PacketLossForEKS": {
      "actionId": "aws:eks:pod-network-packet-loss",
      "parameters": {
        "sources": "us-east-1b,us-east-1c,us-east-1d,us-east-1e,us-east-1f",
        "lossPercent": "15",
        "duration": "PT30M",
        "flowsPercent": "100",
        "interface": "DEFAULT",
        "kubernetesServiceAccount": "fis-service-account"
      },
      "targets": {
        "Pods": "TargetsForEKS"
      }
    }
  },
  "targets": {
    "TargetsForEC2": {
      "filters": [
        {
          "path": "Placement.AvailabilityZone",
          "values": [
            "us-east-1a"
          ]
        }
      ],
      "resourceTags": {
        "CrossAZTrafficSlowdown": "PacketLossForEC2"
      },
      "resourceType": "aws:ec2:instance",
      "selectionMode": "ALL"
    },
    "TargetsForECS": {
      "filters": [
        {
          "path": "AvailabilityZone",
          "values": [
            "us-east-1a"
          ]
        }
      ],
      "resourceTags": {
        "CrossAZTrafficSlowdown": "PacketLossForECS"
      },
      "resourceType": "aws:ecs:task",
      "selectionMode": "ALL"
    },
    "TargetsForEKS": {
      "parameters": {
        "availabilityZoneIdentifier": "us-east-1a",
        "clusterIdentifier": "",
        "namespace": "default",
        "selectorType": "labelSelector",
        "selectorValue": "CrossAZTrafficSlowdown=PacketLossForEKS"
      },
      "resourceType": "aws:eks:pod",
      "selectionMode": "ALL"
    }
  },
  "experimentOptions": {
    "accountTargeting": "single-account",
    "emptyTargetResolutionMode": "skip"
  },
  "stopConditions": [
    {
      "source": "none"
    }
  ]
}
```

Before creating the template: add `roleArn`, replace `"stopConditions": [{"source": "none"}]` with an alarm stop condition, set the AZs and the region in the `documentArn`, and fill in or remove the EKS target.

### CLI Command (API Automation)

Save the edited JSON as `cross-az-traffic-slowdown.json`, then:

```bash
aws fis create-experiment-template --cli-input-json file://cross-az-traffic-slowdown.json
```

After creation, start the experiment:

```bash
aws fis start-experiment --experiment-template-id <TEMPLATE_ID>
```

### Prerequisites

- Same role and permissions as Scenario 2: managed policies `AWSFaultInjectionSimulatorEC2Access`, `AWSFaultInjectionSimulatorECSAccess`, `AWSFaultInjectionSimulatorEKSAccess`, or the doc's policy (`ssm:SendCommand`, `ssm:ListCommands`, `ssm:CancelCommand`, `ec2:DescribeInstances`, `ec2:DescribeSubnets`, `ecs:DescribeTasks`, `ecs:DescribeContainerInstances`, `eks:DescribeCluster`, `tag:GetResources`)
- Same EC2 / ECS / EKS setup as Scenario 2
- Application designed for multi-AZ (otherwise no resilience to validate)
- Cross-AZ latency / error monitoring and a CloudWatch alarm for the stop condition (the skill mandates it)

---

## Scenario 4: Cross-Region Connectivity

**Scenario ID**: `cross-region-scenario` (console name: **Cross-Region: Connectivity**)

Blocks outbound application traffic from the experiment Region to a destination Region and pauses cross-Region replication. Stateless inbound traffic from the destination Region and traffic from AWS managed services may not be blocked. The actions run in parallel for 3 hours by default (maximum 12 hours).

### Sub-Actions

| Action name (JSON) | Action ID | Effect |
|--------------------|-----------|--------|
| `Disrupt-Transit-Gateway-Connectivity` | `aws:network:transit-gateway-disrupt-cross-region-connectivity` | Block traffic over TGW peering to the destination Region |
| `Disrupt-Subnet-Connectivity` | `aws:network:route-table-disrupt-cross-region-connectivity` | Block traffic from target subnets to the destination Region's public AWS IP ranges and over cross-Region VPC peering |
| `Disrupt-Vpc-Endpoint` | `aws:network:disrupt-vpc-endpoint` | Block traffic of target interface VPC endpoints (PrivateLink) |
| `Pause-S3-Replication` | `aws:s3:bucket-pause-replication` | Pause CRR from the experiment Region to the destination Region |
| `Pause-DynamoDB-Replication` | `aws:dynamodb:global-table-pause-replication` | Pause global table replication into and out of the experiment Region |
| `Pause-MemoryDB-Multi-Region-Cluster-Replication` | `aws:memorydb:multi-region-cluster-pause-replication` | Pause replication from the experiment-Region member of a MemoryDB multi-Region cluster |

### Required Resource Tags

Values below are those in the official Scenario Content JSON. The transit gateway and subnet targets use literal placeholder tags that you must replace.

| Tag Key | Tag Value | Applied To |
|---------|-----------|------------|
| `TgwTag` (placeholder) | `TgwValue` (placeholder) | Transit gateways — doc prose default: `DisruptTransitGateway=Allowed` |
| `SubnetKey` (placeholder) | `SubnetValue` (placeholder) | Subnets in the experiment Region — doc prose default: `DisruptSubnet=Allowed` |
| `DisruptPrivateLink` | `Allowed` | Interface VPC endpoints (prose: `DisruptVpcEndpoint`) |
| `S3Impact` | `Allowed` | S3 buckets with CRR to the destination Region (prose: `DisruptS3`) |
| `DisruptDynamoDb` | `Allowed` | DynamoDB global tables (MREC and MRSC) |
| `DisruptMemoryDb` | `Allowed` | MemoryDB multi-Region clusters (prose: `DisruptMemoryDB`) |

> ⚠️ The doc prose and the Scenario Content JSON disagree on four tag keys (shown in parentheses). Tag your resources with what the template you actually create contains.

### Parameters

| Parameter | Where it appears in the JSON | Default |
|-----------|------------------------------|---------|
| Destination Region | `region` on the TGW, subnet, S3 and MemoryDB actions | `eu-west-1` |
| Duration | `duration` on every action | `PT3H` (max 12 h) |

### Official Scenario Content JSON

source: official doc https://docs.aws.amazon.com/fis/latest/userguide/cross-region-scenario.html, retrieved 2026-11-09; the console Content tab is the latest version

```json
{
  "targets": {
    "Transit-Gateway": {
      "resourceType": "aws:ec2:transit-gateway",
      "resourceTags": {
        "TgwTag": "TgwValue"
      },
      "selectionMode": "ALL"
    },
    "Subnet": {
      "resourceType": "aws:ec2:subnet",
      "resourceTags": {
        "SubnetKey": "SubnetValue"
      },
      "selectionMode": "ALL",
      "parameters": {}
    },
    "VPC-Endpoint": {
      "resourceType": "aws:ec2:vpc-endpoint",
      "resourceTags": {
        "DisruptPrivateLink": "Allowed"
      },
      "selectionMode": "ALL"
    },
    "S3-Bucket": {
      "resourceType": "aws:s3:bucket",
      "resourceTags": {
        "S3Impact": "Allowed"
      },
      "selectionMode": "ALL"
    },
    "DynamoDB-Global-Table": {
      "resourceType": "aws:dynamodb:global-table",
      "resourceTags": {
        "DisruptDynamoDb": "Allowed"
      },
      "selectionMode": "ALL"
    },
    "MemoryDB-Multi-Region-Cluster": {
      "resourceType": "aws:memorydb:multi-region-cluster",
      "resourceTags": {
        "DisruptMemoryDb": "Allowed"
      },
      "selectionMode": "ALL"
    }
  },
  "actions": {
    "Disrupt-Transit-Gateway-Connectivity": {
      "actionId": "aws:network:transit-gateway-disrupt-cross-region-connectivity",
      "parameters": {
        "duration": "PT3H",
        "region": "eu-west-1"
      },
      "targets": {
        "TransitGateways": "Transit-Gateway"
      }
    },
    "Disrupt-Subnet-Connectivity": {
      "actionId": "aws:network:route-table-disrupt-cross-region-connectivity",
      "parameters": {
        "duration": "PT3H",
        "region": "eu-west-1"
      },
      "targets": {
        "Subnets": "Subnet"
      }
    },
    "Disrupt-Vpc-Endpoint": {
      "actionId": "aws:network:disrupt-vpc-endpoint",
      "parameters": {
        "duration": "PT3H"
      },
      "targets": {
        "VPCEndpoints": "VPC-Endpoint"
      }
    },
    "Pause-S3-Replication": {
      "actionId": "aws:s3:bucket-pause-replication",
      "parameters": {
        "duration": "PT3H",
        "region": "eu-west-1"
      },
      "targets": {
        "Buckets": "S3-Bucket"
      }
    },
    "Pause-DynamoDB-Replication": {
      "actionId": "aws:dynamodb:global-table-pause-replication",
      "parameters": {
        "duration": "PT3H"
      },
      "targets": {
        "Tables": "DynamoDB-Global-Table"
      }
    },
    "Pause-MemoryDB-Multi-Region-Cluster-Replication": {
      "actionId": "aws:memorydb:multi-region-cluster-pause-replication",
      "parameters": {
        "duration": "PT3H",
        "region": "eu-west-1"
      },
      "targets": {
        "MultiRegionClusters": "MemoryDB-Multi-Region-Cluster"
      }
    }
  },
  "stopConditions": [
    {
      "source": "none"
    }
  ],
  "roleArn": "",
  "logConfiguration": {
    "logSchemaVersion": 2
  },
  "tags": {
    "Name": "Cross-Region: Connectivity"
  },
  "experimentOptions": {
    "accountTargeting": "single-account",
    "emptyTargetResolutionMode": "skip"
  },
  "description": "Block application network traffic from experiment Region to target Region and pause cross-Region replication"
}
```

Before creating the template: set `roleArn`, replace `"stopConditions": [{"source": "none"}]` with an alarm stop condition, replace the placeholder tags, and set `region`.

### CLI Command (API Automation)

Save the edited JSON as `cross-region-connectivity.json`, then:

```bash
aws fis create-experiment-template --cli-input-json file://cross-region-connectivity.json
```

After creation, start the experiment:

```bash
aws fis start-experiment --experiment-template-id <TEMPLATE_ID>
```

### Prerequisites

- Multi-region architecture deployed (TGW peering, cross-Region VPC peering, S3 CRR, DynamoDB global tables or MemoryDB multi-Region)
- FIS experiment role with the policy from the doc page. It grants, among others: route table and prefix-list management (`ec2:CreateRouteTable`, `ec2:CreateRoute`, `ec2:AssociateRouteTable`, `ec2:DisassociateRouteTable`, `ec2:ReplaceRouteTableAssociation`, `ec2:DeleteRouteTable`, `ec2:CreateManagedPrefixList`, `ec2:ModifyManagedPrefixList`, `ec2:DeleteManagedPrefixList`, `ec2:GetManagedPrefixListEntries`), TGW route table association (`ec2:AssociateTransitGatewayRouteTable`, `ec2:DisassociateTransitGatewayRouteTable`), VPC endpoint isolation (`ec2:CreateSecurityGroup`, `ec2:RevokeSecurityGroupEgress`, `ec2:DeleteSecurityGroup`, `ec2:ModifyVpcEndpoint`, `ec2:CreateNetworkInterface`, `ec2:DeleteNetworkInterface`, `vpce:AllowMultiRegion`), `s3:PauseReplication`, `s3:GetReplicationConfiguration`, `s3:PutReplicationConfiguration`, `s3:ListAllMyBuckets`, `dynamodb:InjectError`, `dynamodb:DescribeTable`, `dynamodb:GetResourcePolicy`, `dynamodb:PutResourcePolicy`, `dynamodb:DeleteResourcePolicy`, `memorydb:PauseMultiRegionClusterReplication`, `memorydb:DescribeMultiRegionClusters`, the matching `ec2:Describe*` calls and `tag:GetResources`
- Cross-region health checks and failover mechanisms configured
- DNS failover (Route 53) or Global Accelerator in place
- CloudWatch alarm for the stop condition (the skill mandates it)
- **Caution**: This is the highest-impact scenario — validate in non-production first

---

## Usage in Chaos Engineering Workflow

### When to Use Scenario Library (vs. Single Actions)

| Situation | Recommendation |
|-----------|---------------|
| Validate single component resilience | Single FIS action or Chaos Mesh |
| Validate AZ-level resilience | **Scenario Library** (AZ Power / AZ Slowdown) |
| Validate cross-AZ architecture | **Scenario Library** (Cross-AZ Traffic) |
| Validate multi-region failover | **Scenario Library** (Cross-Region) |
| Game Day exercises | **Scenario Library** (realistic compound failures) |

### Creation Workflow

1. Open **AWS Console → FIS → Scenario Library**
2. Select the desired scenario
3. Configure the shared parameters (AZ, duration, latency / packet loss, target tags or labels)
4. Review the generated multi-action template (Content tab)
5. Ensure all target resources carry the tags / labels the template uses
6. **Add a CloudWatch alarm stop condition** — the scenario has none
7. Create the experiment template
8. Run with monitoring in place, and check the resolved targets before trusting the result

### API/CLI Workflow (Full Automation)

1. Copy the official Scenario Content JSON from the scenario section above (or from the console Content tab)
2. Fill in `roleArn`, replace the `stopConditions` block with your alarm, and replace AZ / Region / tag placeholders
3. Save as a JSON file (e.g., `az-power-interruption.json`)
4. Ensure all target resources carry the tags / labels the template uses
5. Create the experiment template:
   ```bash
   aws fis create-experiment-template --cli-input-json file://az-power-interruption.json
   ```
6. Start the experiment:
   ```bash
   aws fis start-experiment --experiment-template-id <TEMPLATE_ID>
   ```
7. Monitor and stop if needed:
   ```bash
   aws fis stop-experiment --id <EXPERIMENT_ID>
   ```

> **Reference**: [AWS FIS Scenario Library documentation](https://docs.aws.amazon.com/fis/latest/userguide/scenario-library.html)

---

## External Template Library

> The scenarios above are from the **FIS Console Scenario Library** (console-based, multi-action orchestrated scenarios).
> The following section covers [aws-samples/fis-template-library](https://github.com/aws-samples/fis-template-library) —
> a collection of ready-to-deploy FIS experiment templates with IAM policies and SSM Automation documents.
> Unlike Console Scenario Library scenarios, these templates can be directly deployed via CLI/API without any Console interaction.

For the full 27-scenario index with detailed metadata, see [`fis-template-library-index.md`](fis-template-library-index.md).

Eight templates are embedded under `fis-templates/<name>/` for direct use:

### Database Connection Limit Exhaustion ⭐
- **Injection**: SSM Automation — dynamically creates EC2 load generator, exhausts DB connections, auto-cleans up
- **Engines**: Aurora PostgreSQL, Aurora MySQL, RDS PostgreSQL, RDS MySQL, RDS SQL Server
- **Verifies**: Connection pool monitoring, circuit breaker activation, graceful degradation
- **Template**: `fis-templates/database-connection-exhaustion/`
- **Pattern**: Dynamic Resource Injection

### ElastiCache Redis Connection Failure ⭐
- **Injection**: SSM Automation — removes Security Group rules to block app→Redis traffic
- **Verifies**: Circuit breaker (30s), retry storm prevention, degraded mode, recovery (60s)
- **Template**: `fis-templates/redis-connection-failure/`
- **Pattern**: Security Group Manipulation

### SQS Queue Impairment ⭐
- **Injection**: SSM Automation — applies deny-all SQS queue policy in 4 escalating rounds (2→5→7→15 min)
- **Verifies**: Alarm within 5min, component isolation, DLQ capture, producer backpressure
- **Template**: `fis-templates/sqs-queue-impairment/`
- **Pattern**: Resource Policy Denial (Progressive)

### CloudFront Distribution Impairment ⭐
- **Injection**: SSM Automation — applies deny policy to S3 origin buckets
- **Prerequisite**: CloudFront origin groups must be configured
- **Verifies**: Origin group failover (30s), alarm (2-3min), primary resume after restore
- **Template**: `fis-templates/cloudfront-impairment/`
- **Pattern**: Resource Policy Denial

### Aurora Global Database Regional Failover ⭐
- **Injection**: SSM Automation — Aurora Global DB switchover or emergency failover API
- **Modes**: Switchover (no data loss) or Failover (allows data loss)
- **Verifies**: Cross-region promotion, RTO/RPO targets, endpoint updates
- **Template**: `fis-templates/aurora-global-failover/`

### MSK Broker Reboot ⭐
- **Injection**: SSM Automation — reboots a broker of an Amazon MSK cluster
- **Verifies**: Client reconnection, partition leadership failover, producer/consumer error handling
- **Template**: `fis-templates/msk-broker-reboot/`

### ElastiCache Redis Primary Node Reboot ⭐
- **Injection**: SSM Automation — reboots the primary node of each replication group tagged `FIS-Ready=True`; the reboot clears that node's data
- **Verifies**: Client reconnection and behaviour while the primary is unavailable
- **Template**: `fis-templates/elasticache-redis-primary-node-reboot/`

### ElastiCache Redis Primary Node Failover ⭐
- **Injection**: SSM Automation — fails over the primary node so a replica is promoted
- **Verifies**: Replica promotion, endpoint update, client failover handling
- **Template**: `fis-templates/elasticache-redis-primary-node-failover/`

See each template directory's own README for exact parameters and IAM permissions.

### Additional Scenarios (via index)

The remaining 19 scenarios in the index cover, among others:
- EC2 instance termination, Spot interruption, Windows IIS stop
- Aurora cluster failover, Aurora/MySQL load test + failover
- DynamoDB region impairment (resource policy + network blackhole)
- Direct Connect virtual interface disconnect
- SAP workload HA validation (ASCS, database, EBS)

See [`fis-template-library-index.md`](fis-template-library-index.md) for complete details.
