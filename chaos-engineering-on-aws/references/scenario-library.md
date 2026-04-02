# FIS Scenario Library Reference

> ⚠️ **Important**: FIS Scenario Library scenarios are a **console-only experience** — they are not complete experiment templates and cannot be directly imported via API.
> Three automation paths: (1) Create template via Console Scenario Library, then export with `aws fis get-experiment-template`; (2) Copy scenario content from Console Content tab, manually add missing parameters, and create via `aws fis create-experiment-template` API;
> (3) Use the JSON template skeletons below, replace placeholders with actual values, and create directly via `aws fis create-experiment-template --cli-input-json` API — this achieves full automation without any Console interaction.
> The JSON skeletons below are extracted from AWS documentation for reference — use them to understand the structure,
> or use them directly with the CLI for full automation.

## Overview

FIS Scenario Library provides **pre-built, multi-action experiment templates** that simulate real-world failure scenarios.
Unlike single-action experiments (e.g., terminate one EC2 instance), these scenarios orchestrate **multiple coordinated actions**
across services to simulate AZ-level or region-level failures.

### Key Differences from Single-Action Experiments

| Aspect | Single Action | Scenario Library |
|--------|--------------|-----------------|
| Scope | One service, one action | Multiple services, coordinated actions |
| Template creation | API / CLI / Console | Console Scenario Library UI, or manually assemble equivalent multi-action template via API/CLI |
| Resource targeting | ARN / tag filters | **Mandatory resource tags** (scenario-specific) |
| Complexity | Simple | Orchestrated multi-phase |
| Use case | Component-level validation | AZ/region-level resilience validation |

---

## Scenario 1: AZ Power Interruption

**Scenario ID**: `az-availability-scenario`

Simulates a complete power failure in a single Availability Zone, affecting multiple services simultaneously.

### Sub-Actions

| Action | Service | Effect |
|--------|---------|--------|
| `aws:ec2:stop-instances` | EC2 | Stop instances in target AZ |
| `aws:rds:failover-db-cluster` | RDS/Aurora | Trigger database failover |
| `aws:ebs:pause-volume-io` | EBS | Pause volume IO in target AZ |
| `aws:elasticache:interrupt-cluster-az-power` | ElastiCache | Interrupt cache node power in AZ |

### Required Resource Tags

Resources **must** be tagged for the scenario to target them:

| Tag Key | Tag Value | Applied To |
|---------|-----------|------------|
| `AzImpairmentPower` | `IceQualified` | EC2 instances, EBS volumes |
| (RDS clusters) | Selected via cluster identifier in Console | RDS/Aurora |
| (ElastiCache) | Selected via cluster identifier in Console | ElastiCache |

### Parameters

| Parameter | Description | Example |
|-----------|-------------|---------|
| `availabilityZone` | Target AZ to disrupt | `ap-northeast-1a` |
| `duration` | How long the disruption lasts | `PT10M` (ISO 8601) |

### JSON Template Skeleton

```json
{
  "description": "AZ Power Interruption - simulates power loss in a single AZ",
  "targets": {
    "ec2-instances": {
      "resourceType": "aws:ec2:instance",
      "resourceTags": {
        "AzImpairmentPower": "IceQualified"
      },
      "filters": [
        {
          "path": "Placement.AvailabilityZone",
          "values": ["{{availabilityZone}}"]
        }
      ],
      "selectionMode": "ALL"
    },
    "ebs-volumes": {
      "resourceType": "aws:ebs:volume",
      "resourceTags": {
        "AzImpairmentPower": "IceQualified"
      },
      "filters": [
        {
          "path": "AvailabilityZone",
          "values": ["{{availabilityZone}}"]
        }
      ],
      "selectionMode": "ALL"
    },
    "rds-clusters": {
      "resourceType": "aws:rds:cluster",
      "resourceArns": ["{{rdsClusterArn}}"],
      "selectionMode": "ALL"
    },
    "elasticache-clusters": {
      "resourceType": "aws:elasticache:replicationgroup",
      "resourceArns": ["{{elasticacheArn}}"],
      "selectionMode": "ALL"
    }
  },
  "actions": {
    "stop-ec2": {
      "actionId": "aws:ec2:stop-instances",
      "parameters": {
        "startInstancesAfterDuration": "{{duration}}"
      },
      "targets": {
        "Instances": "ec2-instances"
      }
    },
    "pause-ebs-io": {
      "actionId": "aws:ebs:pause-volume-io",
      "parameters": {
        "duration": "{{duration}}"
      },
      "targets": {
        "Volumes": "ebs-volumes"
      }
    },
    "failover-rds": {
      "actionId": "aws:rds:failover-db-cluster",
      "parameters": {},
      "targets": {
        "Clusters": "rds-clusters"
      }
    },
    "interrupt-elasticache": {
      "actionId": "aws:elasticache:interrupt-cluster-az-power",
      "parameters": {
        "duration": "{{duration}}"
      },
      "targets": {
        "ReplicationGroups": "elasticache-clusters"
      }
    }
  },
  "stopConditions": [
    {
      "source": "aws:cloudwatch:alarm",
      "value": "{{stopConditionAlarmArn}}"
    }
  ],
  "roleArn": "{{fisRoleArn}}",
  "tags": {
    "Purpose": "chaos-engineering",
    "Scenario": "az-power-interruption"
  }
}
```

### CLI Command (API Automation)

Save the JSON template above as `az-power-interruption.json` (replacing all `{{placeholder}}` values), then:

```bash
aws fis create-experiment-template --cli-input-json file://az-power-interruption.json
```

After creation, start the experiment:

```bash
aws fis start-experiment --experiment-template-id <TEMPLATE_ID>
```

### Prerequisites

- All target EC2 instances and EBS volumes tagged with `AzImpairmentPower: IceQualified`
- FIS IAM Role with permissions for: `ec2:StopInstances`, `ec2:StartInstances`, `ebs:PauseVolumeIO`, `rds:FailoverDBCluster`, `elasticache:InterruptClusterAzPower`
- Multi-AZ deployment (otherwise this test has no resilience value)
- CloudWatch Alarms configured for stop conditions
- Sufficient capacity in remaining AZs to handle full traffic

---

## Scenario 2: AZ Application Slowdown

**Scenario ID**: `az-application-slowdown-scenario`

Simulates application-level degradation in a single AZ — network latency and packet loss affecting application traffic without full infrastructure failure.

### Sub-Actions

| Action | Service | Effect |
|--------|---------|--------|
| `aws:ec2:disrupt-network-connectivity` | EC2 | Inject network disruption (latency/packet loss) via NACL |
| `aws:lambda:invocation-add-delay` | Lambda | Add latency to Lambda invocations |

### Required Resource Tags

| Tag Key | Tag Value | Applied To |
|---------|-----------|------------|
| `AzImpairmentPower` | `IceQualified` | EC2 instances in target AZ |
| (Lambda functions) | Selected via function name in Console | Lambda functions |

### Parameters

| Parameter | Description | Example |
|-----------|-------------|---------|
| `availabilityZone` | Target AZ | `ap-northeast-1a` |
| `duration` | Duration of slowdown | `PT10M` |
| `scope` | Disruption scope (`availability-zone` or `vpc`) | `availability-zone` |

### JSON Template Skeleton

```json
{
  "description": "AZ Application Slowdown - network degradation in a single AZ",
  "targets": {
    "ec2-subnets": {
      "resourceType": "aws:ec2:subnet",
      "resourceTags": {
        "AzImpairmentPower": "IceQualified"
      },
      "filters": [
        {
          "path": "AvailabilityZone",
          "values": ["{{availabilityZone}}"]
        }
      ],
      "selectionMode": "ALL"
    },
    "lambda-functions": {
      "resourceType": "aws:lambda:function",
      "resourceArns": ["{{lambdaFunctionArn}}"],
      "selectionMode": "ALL"
    }
  },
  "actions": {
    "disrupt-network": {
      "actionId": "aws:network:disrupt-connectivity",
      "parameters": {
        "duration": "{{duration}}",
        "scope": "{{scope}}"
      },
      "targets": {
        "Subnets": "ec2-subnets"
      }
    },
    "slow-lambda": {
      "actionId": "aws:lambda:invocation-add-delay",
      "parameters": {
        "duration": "{{duration}}",
        "invocationPercentage": "100",
        "delayMilliseconds": "2000"
      },
      "targets": {
        "Functions": "lambda-functions"
      }
    }
  },
  "stopConditions": [
    {
      "source": "aws:cloudwatch:alarm",
      "value": "{{stopConditionAlarmArn}}"
    }
  ],
  "roleArn": "{{fisRoleArn}}",
  "tags": {
    "Purpose": "chaos-engineering",
    "Scenario": "az-application-slowdown"
  }
}
```

### CLI Command (API Automation)

Save the JSON template above as `az-application-slowdown.json` (replacing all `{{placeholder}}` values), then:

```bash
aws fis create-experiment-template --cli-input-json file://az-application-slowdown.json
```

After creation, start the experiment:

```bash
aws fis start-experiment --experiment-template-id <TEMPLATE_ID>
```

### Prerequisites

- Target subnets tagged appropriately
- FIS IAM Role with permissions for: `ec2:CreateNetworkAcl*`, `ec2:DeleteNetworkAcl*`, `lambda:InvokeFunction` (FIS extension)
- Application-level health checks configured (not just TCP health checks)
- Latency-aware alarms for stop conditions

---

## Scenario 3: Cross-AZ Traffic Slowdown

**Scenario ID**: `cross-az-traffic-slowdown-scenario`

Simulates degraded network performance between Availability Zones — increased latency and packet loss for cross-AZ traffic while intra-AZ traffic remains normal.

### Sub-Actions

| Action | Service | Effect |
|--------|---------|--------|
| `aws:network:disrupt-connectivity` | VPC | Disrupt cross-AZ network paths |

### Required Resource Tags

| Tag Key | Tag Value | Applied To |
|---------|-----------|------------|
| `AzImpairmentPower` | `IceQualified` | Subnets involved in cross-AZ traffic |

### Parameters

| Parameter | Description | Example |
|-----------|-------------|---------|
| `availabilityZone` | Source AZ experiencing degraded cross-AZ traffic | `ap-northeast-1a` |
| `duration` | Duration of traffic degradation | `PT10M` |
| `scope` | Must be `availability-zone` | `availability-zone` |

### JSON Template Skeleton

```json
{
  "description": "Cross-AZ Traffic Slowdown - degraded inter-AZ network performance",
  "targets": {
    "target-subnets": {
      "resourceType": "aws:ec2:subnet",
      "resourceTags": {
        "AzImpairmentPower": "IceQualified"
      },
      "filters": [
        {
          "path": "AvailabilityZone",
          "values": ["{{availabilityZone}}"]
        }
      ],
      "selectionMode": "ALL"
    }
  },
  "actions": {
    "disrupt-cross-az-traffic": {
      "actionId": "aws:network:disrupt-connectivity",
      "parameters": {
        "duration": "{{duration}}",
        "scope": "availability-zone"
      },
      "targets": {
        "Subnets": "target-subnets"
      }
    }
  },
  "stopConditions": [
    {
      "source": "aws:cloudwatch:alarm",
      "value": "{{stopConditionAlarmArn}}"
    }
  ],
  "roleArn": "{{fisRoleArn}}",
  "tags": {
    "Purpose": "chaos-engineering",
    "Scenario": "cross-az-traffic-slowdown"
  }
}
```

### CLI Command (API Automation)

Save the JSON template above as `cross-az-traffic-slowdown.json` (replacing all `{{placeholder}}` values), then:

```bash
aws fis create-experiment-template --cli-input-json file://cross-az-traffic-slowdown.json
```

After creation, start the experiment:

```bash
aws fis start-experiment --experiment-template-id <TEMPLATE_ID>
```

### Prerequisites

- Subnets in target AZ tagged with `AzImpairmentPower: IceQualified`
- FIS IAM Role with permissions for: `ec2:CreateNetworkAcl*`, `ec2:DeleteNetworkAcl*`, `ec2:DescribeSubnets`, `ec2:DescribeVpcs`
- Application designed for multi-AZ (otherwise no resilience to validate)
- Cross-AZ latency monitoring in place (CloudWatch or application metrics)

---

## Scenario 4: Cross-Region Connectivity

**Scenario ID**: `cross-region-scenario`

Simulates loss of connectivity between AWS Regions — disrupts cross-region traffic via route table or Transit Gateway modifications.

### Sub-Actions

| Action | Service | Effect |
|--------|---------|--------|
| `aws:network:route-table-disrupt-cross-region-connectivity` | VPC | Disrupt cross-region routes |
| `aws:network:transit-gateway-disrupt-cross-region-connectivity` | TGW | Disrupt TGW cross-region peering |

### Required Resource Tags

| Tag Key | Tag Value | Applied To |
|---------|-----------|------------|
| (Route tables) | Selected via route table ID in Console | VPC route tables |
| (Transit Gateways) | Selected via TGW ID in Console | Transit Gateways |

### Parameters

| Parameter | Description | Example |
|-----------|-------------|---------|
| `duration` | Duration of cross-region disruption | `PT10M` |
| `region` | Remote region to disconnect from | `us-west-2` |

### JSON Template Skeleton

```json
{
  "description": "Cross-Region Connectivity - disrupt connectivity between regions",
  "targets": {
    "route-tables": {
      "resourceType": "aws:ec2:routeTable",
      "resourceArns": ["{{routeTableArn}}"],
      "selectionMode": "ALL"
    },
    "transit-gateways": {
      "resourceType": "aws:ec2:transit-gateway",
      "resourceArns": ["{{transitGatewayArn}}"],
      "selectionMode": "ALL"
    }
  },
  "actions": {
    "disrupt-route-tables": {
      "actionId": "aws:network:route-table-disrupt-cross-region-connectivity",
      "parameters": {
        "duration": "{{duration}}"
      },
      "targets": {
        "RouteTables": "route-tables"
      }
    },
    "disrupt-tgw": {
      "actionId": "aws:network:transit-gateway-disrupt-cross-region-connectivity",
      "parameters": {
        "duration": "{{duration}}"
      },
      "targets": {
        "TransitGateways": "transit-gateways"
      }
    }
  },
  "stopConditions": [
    {
      "source": "aws:cloudwatch:alarm",
      "value": "{{stopConditionAlarmArn}}"
    }
  ],
  "roleArn": "{{fisRoleArn}}",
  "tags": {
    "Purpose": "chaos-engineering",
    "Scenario": "cross-region-connectivity"
  }
}
```

### CLI Command (API Automation)

Save the JSON template above as `cross-region-connectivity.json` (replacing all `{{placeholder}}` values), then:

```bash
aws fis create-experiment-template --cli-input-json file://cross-region-connectivity.json
```

After creation, start the experiment:

```bash
aws fis start-experiment --experiment-template-id <TEMPLATE_ID>
```

### Prerequisites

- Multi-region architecture deployed (VPC Peering, TGW, or Direct Connect cross-region)
- FIS IAM Role with permissions for: `ec2:CreateRoute`, `ec2:DeleteRoute`, `ec2:ReplaceRoute`, `ec2:DescribeRouteTables`, `ec2:DescribeTransitGateways`
- Cross-region health checks and failover mechanisms configured
- DNS failover (Route 53) or Global Accelerator in place
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
3. Configure parameters (AZ, duration, target resources)
4. Review the auto-generated multi-action template
5. Ensure all target resources have the **required tags**
6. Create the experiment template
7. Run with stop conditions and monitoring in place

### API/CLI Workflow (Full Automation)

1. Copy the JSON template skeleton from the scenario section above
2. Replace all `{{placeholder}}` values with actual resource ARNs, AZ names, durations
3. Save as a JSON file (e.g., `az-power-interruption.json`)
4. Ensure all target resources have the **required tags**
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
