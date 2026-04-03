> Part of the [AWS Resilience Analysis Framework Reference](resilience-framework.md).

## 3. Chaos Engineering Methodology

### 3.1 Core Definition

> "Chaos Engineering is the discipline of experimenting on a system to build confidence in the system's capability to withstand turbulent conditions in production."
>
> -- Principles of Chaos Engineering

**Goals**:
- Discover system weaknesses before they cause real impact
- Build confidence in system resilience
- Verify monitoring and alerting effectiveness
- Improve incident response processes

### 3.2 Four-Step Experiment Process

```yaml
Step 1: Establish Steady-State Baseline
  Definition:
    - "Steady state" is a measurable system output
    - Represents normal behavior

  Examples:
    - Request success rate: > 99.9%
    - P95 latency: < 200ms
    - Throughput: 1000 req/s
    - Error rate: < 0.1%

Step 2: Form Hypothesis
  Prediction:
    - Steady state will continue in both control and experimental groups
    - Based on system understanding

  Example:
    "Hypothesis: After terminating 2 EC2 instances,
     Auto Scaling will restore capacity within 5 minutes,
     user experience impact < 1%"

Step 3: Introduce Variables
  Simulate Real-World Disruptions:
    - Server crashes
    - Network failures
    - Disk full
    - Clock skew

  Assess Impact:
    - Observe steady-state metrics
    - Record system behavior

Step 4: Validate or Refute
  Compare:
    - Control group vs. experimental group
    - Identify steady-state deviations

  Results:
    - Hypothesis correct: System resilience verified
    - Hypothesis incorrect: Weakness discovered, improve system
```

### 3.3 Advanced Implementation Principles

| Principle | Description | Practice |
|-----------|-------------|----------|
| **Steady-State Focus** | Measure system output, not internal mechanics | Monitor user-visible metrics (latency, errors) |
| **Real-World Events** | Variables should mirror actual operational disruptions | Reference historical failures (EC2 failures, AZ outages) |
| **Production Testing** | "Sampling real traffic is the only reliable approach" | Test in production (controlled) |
| **Continuous Automation** | Manual experiments are not sustainable | Automate for continuous verification (weekly/monthly) |
| **Control Blast Radius** | Minimize customer impact | Limit impact scope (single AZ, 10% traffic) |

### 3.4 Common Chaos Experiment Scenarios

#### Common AWS Scenarios:

| Experiment Category | Scenario | AWS FIS Action | Expected System Behavior |
|--------------------|----------|----------------|-------------------------|
| **Instance Failure** | Terminate EC2 instances | `aws:ec2:terminate-instances` | Auto Scaling automatically replaces |
| | Stop EC2 instances | `aws:ec2:stop-instances` | Health check fails, traffic shifts |
| **Network Failure** | Network latency | `aws:ec2:api-network-latency` | Request timeout, retry mechanism triggers |
| | Packet loss | `aws:ec2:api-packet-loss` | Circuit breaker opens, service degrades |
| **AZ Failure** | Simulate AZ unavailability | Combined experiment (terminate all AZ instances) | Traffic shifts to other AZs |
| **Database** | RDS failover | `aws:rds:failover-db-cluster` | Application auto-reconnects, brief interruption |
| **Containers** | ECS task termination | `aws:ecs:stop-task` | ECS restarts task |
| | EKS Pod deletion | `aws:eks:pod-delete` | Deployment rebuilds Pod |
| **Resource Exhaustion** | CPU stress | `aws:ec2:cpu-stress` | Auto Scaling scales out |
| | Memory stress | `aws:ec2:memory-stress` | OOM kill, container restarts |
| | Disk full | `aws:ec2:disk-fill` | Alert triggers, cleanup process starts |

### 3.5 AWS FIS Experiment Template Examples

**Experiment 1: EC2 Instance Termination**

```json
{
  "description": "Terminate 30% of EC2 instances to test Auto Scaling",
  "targets": {
    "ec2-instances": {
      "resourceType": "aws:ec2:instance",
      "resourceTags": {
        "Environment": "production",
        "AutoScaling": "enabled"
      },
      "filters": [
        {
          "path": "State.Name",
          "values": ["running"]
        }
      ],
      "selectionMode": "PERCENT(30)"
    }
  },
  "actions": {
    "terminate-instances": {
      "actionId": "aws:ec2:terminate-instances",
      "parameters": {},
      "targets": {
        "Instances": "ec2-instances"
      }
    }
  },
  "stopConditions": [
    {
      "source": "aws:cloudwatch:alarm",
      "value": "arn:aws:cloudwatch:us-east-1:123456789012:alarm:high-error-rate"
    }
  ],
  "roleArn": "arn:aws:iam::123456789012:role/FISExperimentRole",
  "tags": {
    "Name": "EC2-Instance-Termination-Test"
  }
}
```

**Experiment 2: Network Latency Injection**

```json
{
  "description": "Inject 200ms latency to 50% of API calls",
  "targets": {
    "api-gw-targets": {
      "resourceType": "aws:ec2:instance",
      "resourceTags": {
        "Service": "api-gateway"
      },
      "selectionMode": "PERCENT(50)"
    }
  },
  "actions": {
    "inject-latency": {
      "actionId": "aws:ec2:api-network-latency",
      "parameters": {
        "duration": "PT10M",
        "latencyMs": "200",
        "jitterMs": "50",
        "apiList": "ec2,rds,dynamodb"
      },
      "targets": {
        "Instances": "api-gw-targets"
      }
    }
  },
  "stopConditions": [
    {
      "source": "aws:cloudwatch:alarm",
      "value": "arn:aws:cloudwatch:us-east-1:123456789012:alarm:high-p95-latency"
    }
  ],
  "roleArn": "arn:aws:iam::123456789012:role/FISExperimentRole"
}
```

**Experiment 3: RDS Failover**

```json
{
  "description": "Test RDS Multi-AZ failover",
  "targets": {
    "rds-cluster": {
      "resourceType": "aws:rds:cluster",
      "resourceArns": [
        "arn:aws:rds:us-east-1:123456789012:cluster:production-db"
      ],
      "selectionMode": "ALL"
    }
  },
  "actions": {
    "failover-cluster": {
      "actionId": "aws:rds:failover-db-cluster",
      "parameters": {
        "targetInstance": "production-db-instance-2"
      },
      "targets": {
        "Clusters": "rds-cluster"
      }
    }
  },
  "stopConditions": [
    {
      "source": "none"
    }
  ],
  "roleArn": "arn:aws:iam::123456789012:role/FISExperimentRole",
  "tags": {
    "Name": "RDS-Failover-Test",
    "Frequency": "monthly"
  }
}
```

---

