# Chaos Engineering Input Specification Template

> **Purpose**: This document defines the structured input format required by the `chaos-engineering-on-aws` skill.
> The `aws-resilience-modeling` skill should organize report content according to this specification when generating resilience assessment reports, ensuring the chaos engineering phase can directly consume the data.
>
> **Two Output Methods (choose one)**:
> 1. **Standalone File Mode (Recommended)**: Generate a separate `{project}-chaos-input-{date}.md`. The main report should only include a brief reference, without duplicating the full data.
> 2. **Embedded Mode**: Add a `## Chaos Engineering Ready Data` appendix section at the end of the existing assessment report (only when user explicitly requests embedding)
>
> **Method 1 is recommended** (standalone file, easier for downstream `chaos-engineering-on-aws` skill to consume directly, and keeps the main report concise)
>
> **This specification defines structure (table headers + fields + enum values) and is not tied to any specific system.** Appendix A provides fill-in examples for different architecture patterns.

---

## 1. Why Is This Specification Needed?

Assessment free-format Markdown reports are designed for human reading, but the Chaos Engineering Skill needs **consistent structure** to automate the following steps:
- Filter experimentable risks from the risk inventory
- Map logical resource names to actual AWS resources (ARN)
- Generate FIS / Chaos Mesh experiment configurations
- Set steady-state hypothesis thresholds and stop conditions

**Issues with Current Assessment Output**:

| Current State | Improvement Required |
|--------------|---------------------|
| Risk descriptions are free text | Unified enum classification (`SPOF` / `Excessive Load` / `Misconfiguration` / `Shared Fate` / `Excessive Latency`) |
| AWS resources scattered throughout | Unified resource inventory table with complete ARNs |
| RTO says "Unknown" / "Unrecoverable" | Use `Unknown` or `N/A`, with units uniformly in seconds |
| No "can we experiment" marker | Each risk marked for experiment readiness + reason |
| No suggested injection method | High/critical risks include suggested FIS action or Chaos Mesh CRD |
| No structured monitoring capability description | Unified monitoring readiness section |

---

## 2. Specification Definition

The following are structured sections that should be included in Assessment reports. **Table headers and field names are fixed**; content is filled based on the customer's actual environment.

---

### 2.1 Project Metadata

> Place at the beginning of the report.

| Field | Required | Format | Description |
|-------|----------|--------|-------------|
| Project Name | Yes | Free text | Customer system name |
| Assessment Date | Yes | YYYY-MM-DD | -- |
| AWS Account | Yes | 12-digit number | Multiple accounts comma-separated |
| Primary Region | Yes | AWS region code | e.g., `us-east-1`, `ap-northeast-1` |
| Other Regions | No | Comma-separated | Fill for multi-region architectures |
| Environment Type | Yes | `production` / `staging` / `development` | -- |
| Architecture Pattern | Yes | See enum below | Helps the Chaos Engineering Skill select experiment strategies |
| Overall Resilience Score | Yes | X.X / 5.0 | 1.0-5.0 |

**Architecture Pattern Enum**:

| Architecture Pattern | Typical Components | Chaos Engineering Focus |
|--------------------|-------------------|----------------------|
| `EKS Microservices` | EKS + ALB + RDS/DynamoDB | Pod failures, inter-service network, database failover |
| `ECS Containerized` | ECS/Fargate + ALB + RDS | Task failures, service discovery, database HA |
| `Serverless` | API Gateway + Lambda + DynamoDB + SQS/SNS | Lambda latency/errors, queue backlog, DDB throttling |
| `Traditional EC2` | EC2 + ALB/NLB + RDS + ElastiCache | Instance termination, AZ failure, database failover |
| `Multi-Region` | Any of the above + Route53 + cross-region replication | Region failover, replication lag, DNS switching |
| `Hybrid` | Multiple combinations above | Design experiments per layer |

---

### 2.2 AWS Resource Inventory

> **Core input** -- FIS experiments cannot be created without ARNs. List all AWS resources involved in the assessment.

**Fixed Table Headers**:

| Resource ID | Type | ARN | Name | Availability Zone | Status | Notes |
|-------------|------|-----|------|-------------------|--------|-------|
| *(instance/cluster/table ID)* | *(standard type name)* | *(complete ARN)* | *(resource name or tag)* | *(AZ or AZ list)* | *(running/active etc.)* | *(key assessment findings)* |

**Standard Resource Type Names** (prefer the following names; if the customer uses an AWS service not on this list, **add the type name as needed**, format: `{Service} {Resource}`):

| Category | Standard Names |
|----------|---------------|
| Compute | `EC2 Instance` / `EKS Cluster` / `EKS Node Group` / `ECS Cluster` / `ECS Service` / `Fargate Task` / `Lambda Function` / `Auto Scaling Group` |
| Network | `ALB` / `NLB` / `Target Group` / `CloudFront` / `API Gateway` / `NAT Gateway` / `VPC` / `Subnet` / `Security Group` / `Route53 Hosted Zone` / `Transit Gateway` |
| Database | `RDS Cluster` / `RDS Instance` / `Aurora Global Database` / `DynamoDB Table` / `ElastiCache Cluster` / `MemoryDB Cluster` / `Neptune Cluster` |
| Storage | `S3 Bucket` / `EBS Volume` / `EFS File System` |
| Messaging | `SQS Queue` / `SNS Topic` / `Kinesis Data Stream` / `EventBridge Rule` |
| Other | `Step Functions State Machine` / `Cognito User Pool` / `Secrets Manager` |

---

### 2.3 Critical Business Functions and Dependency Chains

> List the system's critical business functions, dependency component chains, and RTO/RPO.

**Fixed Table Headers**:

| Business Function | Importance | Dependency Chain (Resource IDs) | Current RTO | Target RTO | Current RPO | Target RPO |
|------------------|------------|-------------------------------|-------------|------------|-------------|------------|
| *(function name)* | *(importance marker)* | *(ID -> ID -> ID)* | *(seconds/Unknown/N/A)* | *(seconds)* | *(seconds/Unknown/N/A)* | *(seconds/N/A)* |

**Field Specifications**:

| Field | Values | Description |
|-------|--------|-------------|
| Importance | `Critical` / `High` / `Medium` / `Low` | Corresponding to critical/high/medium/low |
| Dependency Chain | Resource IDs connected with `->` | References resource IDs from Section 2.2 |
| RTO/RPO | Number + `s` (seconds) or `Unknown` or `N/A` | **Units uniformly in seconds**. `Unknown` = never tested; `N/A` = dimension not applicable |

---

### 2.4 Risk Inventory (With Experiment-Readiness Flags)

> **Add two columns** to the existing risk inventory: `Testable` and `Suggested Injection Method`.

**Fixed Table Headers**:

| Risk ID | Risk Description | Failure Category | Severity | Probability | Impact | Detection Difficulty | Remediation Complexity | Risk Score | Testable | Suggested Injection Method |
|---------|-----------------|-----------------|----------|-------------|--------|---------------------|----------------------|-----------|---------|--------------------------|
| R-XXX | *(description)* | *(category)* | *(severity)* | 1-5 | 1-5 | 1-5 | 1-5 | *(score)* | *(flag)* | *(tool: action)* |

**Field Enum Values**:

| Field | Values | Description |
|-------|--------|-------------|
| Failure Category | `SPOF` / `Excessive Load` / `Excessive Latency` / `Misconfiguration` / `Shared Fate` / `Other: {custom}` | From AWS Resilience Analysis Framework. **Use `Other: {description}` to extend beyond 5 categories** |
| Severity | `Critical` / `High` / `Medium` / `Low` | -- |
| Testable | `Yes` / `No ({reason})` / `Conditional` | **Key field**, assessment guide in Section 3 |
| Suggested Injection Method | `FIS: {action}` / `ChaosMesh: {CRD}` / `Manual` / `--` | Quick reference in Section 4; fill `--` if not testable |

---

### 2.5 Risk Details (Supplementary Info for Testable Risks)

> For each risk with `Testable = Yes/Conditional`, add the following structured content in the detailed analysis:

**Required Sub-tables**:

#### Involved Resources Table

| Resource ID | Type | ARN | Role in Experiment |
|-------------|------|-----|-------------------|
| *(ID)* | *(type)* | *(ARN)* | `Injection Target` / `Observation Target` / `Impact Target` |

#### Suggested Experiments Table

| Injection Tool | Action | Target Resource | Description | Prerequisites |
|---------------|--------|----------------|-------------|---------------|
| FIS / ChaosMesh | *(action ID or CRD type)* | *(resource ID)* | *(one-line description)* | `None` or specific prerequisites |

#### Other Required Fields

- **Affected Business Functions**: Reference function names from Section 2.3
- **Existing Mitigations**: List or `None`

---

### 2.6 Monitoring Readiness

> **New section**. Chaos engineering requires monitoring to define steady-state hypotheses and stop conditions.

**Fixed Structure**:

```markdown
## Monitoring Readiness

**Overall Readiness Status**: Ready / Partially Ready / Not Ready
```

#### Existing CloudWatch Alarms Table

| Alarm ARN | Metric | Threshold | Period | Usable as FIS Stop Condition |
|-----------|--------|-----------|--------|------------------------------|
| *(ARN or "None")* | -- | -- | -- | Yes / No |

#### Available CloudWatch Metrics Table

| Resource | Namespace | Available Metrics | Notes |
|----------|-----------|-------------------|-------|
| *(Resource ID)* | *(AWS/XXX)* | *(metric list)* | -- |

#### Monitoring Gaps (List)

**Readiness Status Criteria**:

| Status | Condition | Chaos Engineering Recommendation |
|--------|-----------|--------------------------------|
| Ready | Core business functions have alarm coverage with available Stop Conditions | Can begin experiments directly |
| Partially Ready | Some alarms exist but core functions not fully covered | Supplement critical alarms before experimenting |
| Not Ready | No alarms or severe gaps | **Must establish baseline monitoring first** |

---

### 2.7 Resilience Scores (9 Dimensions)

> Use **fixed dimension names and 1-5 scoring**.

**Fixed Table Headers**:

| Dimension | Score | Current Status (one sentence) |
|-----------|-------|------------------------------|
| Redundancy Design | X/5 | *(description)* |
| AZ Fault Tolerance | X/5 | *(description)* |
| Timeout & Retry | X/5 | *(description)* |
| Circuit Breaker | X/5 | *(description)* |
| Auto Scaling | X/5 | *(description)* |
| Configuration Safeguards | X/5 | *(description)* |
| Fault Isolation | X/5 | *(description)* |
| Backup & Recovery | X/5 | *(description)* |
| Best Practices | X/5 | *(description)* |

**Dimension names are fixed to the above 9** and cannot be modified or added/removed. If resilience issues outside these 9 dimensions are found, record them in free text after the scoring table.

---

### 2.8 Constraints and Preferences (Optional)

> If the user mentions experiment preferences during the Assessment, record them here.

**Fixed Table Headers**:

| Constraint | Value | Notes |
|-----------|-------|-------|
| Preferred Experiment Environment | staging / production / development | -- |
| Production Experiments Allowed | Yes / No | -- |
| Maintenance Window | *(description or cron)* | -- |
| Maximum Blast Radius | Single Resource / Single AZ / Multi-AZ / Region | -- |
| Chaos Mesh Installed | Yes / No | -- |
| FIS IAM Role Created | Yes / No | -- |
| Notification Channel | *(channel)* | -- |

---

## 3. `testable` (Experiment-Readiness) Assessment Guide

For the Assessment Skill to determine whether each risk is suitable for chaos experiments:

| Condition | Testable | Description |
|-----------|----------|-------------|
| Corresponding FIS action available for injection | Yes | e.g., EC2 termination, RDS failover, Lambda delay injection |
| Corresponding Chaos Mesh CRD available | Yes | e.g., Pod Kill, network delay, HTTP fault |
| Configuration issue with no runtime fault to inject | No | e.g., "EBS not encrypted", "logging not enabled", "missing alarm" |
| Requires fix or configuration before testing | Conditional | e.g., "DynamoDB needs PITR enabled before testing recovery" |
| Security/compliance related (not resilience) | No | e.g., "IAM permissions too broad", "no WAF" |
| Impact is irreversible | No | e.g., "delete the only data table without backup" |
| Lacks monitoring to observe results | Conditional | Prerequisite: establish baseline monitoring first |

---

## 4. Suggested Injection Method Quick Reference

For the Assessment Skill to recommend tools and actions for testable risks:

| Risk Pattern | Recommended Tool | Recommended Action |
|-------------|-----------------|-------------------|
| EC2 single point of failure | FIS | `aws:ec2:terminate-instances` or `aws:ec2:stop-instances` |
| AZ-level failure | FIS | `aws:network:disrupt-connectivity` |
| RDS/Aurora failover | FIS | `aws:rds:failover-db-cluster` |
| RDS instance failure | FIS | `aws:rds:reboot-db-instances` |
| DynamoDB cross-region replication | FIS | `aws:dynamodb:global-table-pause-replication` |
| Lambda delay | FIS | `aws:lambda:invocation-add-delay` |
| Lambda error | FIS | `aws:lambda:invocation-error` |
| EKS node failure | FIS | `aws:eks:terminate-nodegroup-instances` |
| ECS task failure | FIS | `aws:ecs:stop-task` |
| EBS storage failure | FIS | `aws:ebs:pause-volume-io` |
| ElastiCache AZ failure | FIS | `aws:elasticache:interrupt-cluster-az-power` |
| Spot instance interruption | FIS | `aws:ec2:send-spot-instance-interruptions` |
| API throttling | FIS | `aws:fis:inject-api-throttle-error` |
| S3 cross-region replication | FIS | `aws:s3:bucket-pause-replication` |
| K8s Pod failure | Chaos Mesh | PodChaos: `pod-kill` / `pod-failure` |
| Microservice network degradation | Chaos Mesh | NetworkChaos: `delay` / `loss` / `partition` |
| HTTP layer failure | Chaos Mesh | HTTPChaos: `abort` / `delay` |
| Resource contention | Chaos Mesh | StressChaos: `cpu` / `memory` |
| DNS failure | Chaos Mesh | DNSChaos: `error` / `random` |
| File IO failure | Chaos Mesh | IOChaos: `latency` / `fault` |

---

## 5. Assessment Output Checklist

After Assessment completion, verify output completeness against this checklist:

- [ ] **Project metadata** is complete (account ID, region, environment type, **architecture pattern**, resilience score)
- [ ] **AWS resource inventory** contains **complete ARNs** for all involved resources
- [ ] **Business function table** lists dependency chains and RTO/RPO (unit: seconds)
- [ ] **Risk inventory** includes `Testable` and `Suggested Injection Method` columns
- [ ] All `Testable = Yes/Conditional` risk details contain **involved resources table** and **suggested experiments table**
- [ ] **Monitoring readiness** section is complete (readiness status + existing alarms + available metrics + gaps)
- [ ] **Resilience scores** 9-dimension table is complete, dimension names unchanged
- [ ] **Constraints and preferences** recorded (if user mentioned during assessment)
- [ ] **Open findings** section recorded (new findings beyond template framework)

---

## 6. Open Findings (Encouraging LLMs to Go Beyond the Template)

> **This specification defines minimum requirements, not capability limits.** The following three open sections encourage Assessment and Chaos Skill LLMs to record findings beyond the template framework.

### 6.1 Assessment Phase: Additional Discovered Risks

> If the Assessment LLM discovers risks that don't belong to the 5 standard failure categories, or risks without corresponding injection methods in the quick reference, **do not discard them** -- record them here.

```markdown
## Additional Findings

### Risks Beyond Standard Classification

| Risk ID | Risk Description | Custom Category | Why Existing Classification Doesn't Apply | Suggested Verification Method (free text) |
|---------|-----------------|----------------|------------------------------------------|------------------------------------------|
| R-EXT-001 | Third-party API provider SLA is opaque | Supply Chain Risk | Not an AWS resource, doesn't fit 5 categories | Simulate third-party API timeout/errors, observe degradation behavior |
| R-EXT-002 | DNS TTL too long causing failover delay | Recovery Delay | Between "configuration" and "latency" | Modify TTL then use FIS to simulate AZ failure, measure actual switchover time |

### Risks Newly Discovered During Experiments

> New risks discovered by the Chaos Engineering Skill during experiment execution that were not identified during the Assessment phase. **Fill in this table after experiments.**

| Discovery Source (Experiment ID) | New Risk Description | Severity | Recommendation |
|--------------------------------|---------------------|----------|----------------|
| *(fill after experiment execution)* | | | |
```

### 6.2 Custom Experiment Methods

> If the LLM believes a risk can be verified through methods **other than FIS / Chaos Mesh** (e.g., AWS CLI scripts, SSM Run Command, custom Lambda, etc.), record here.

```markdown
### Custom Experiment Suggestions

| Risk ID | Verification Method | Tool/Script | Description | Safety Risk |
|---------|-------------------|-------------|-------------|-------------|
| R-XXX | AWS CLI Script | `aws ec2 modify-instance-attribute --no-source-dest-check` | Modify network attribute and observe impact | Needs rollback |
| R-XXX | SSM Run Command | stress-ng memory stress | Inject stress directly on instance | Controllable impact scope |
```

### 6.3 Architecture-Level Open Observations

> Architecture-level observations discovered during the Assessment that don't directly correspond to a specific risk ID. For example:
> - Architecture anti-patterns (uncertain if they constitute risks)
> - Potential improvement opportunities (not risks but worth noting)
> - Gaps from industry best practices (not direct risks)

```markdown
### Open Observations

1. **Observation**: EKS cluster uses managed node group but has not configured Cluster Autoscaler; may run out of resources during peaks
   **Suggestion**: Consider adding load stress testing in chaos experiments to verify elasticity boundaries

2. **Observation**: All microservices share a single DynamoDB table, lacking data isolation
   **Suggestion**: Can be further assessed as a "Shared Fate" risk
```

---

## Appendix A: Fill-in Examples for Different Architecture Patterns

> The following examples show how different types of customer systems fill in this specification. Only key differences are shown.

### A.1 EKS Microservices Architecture (e.g., VotingApp)

**Metadata**:
```
Architecture Pattern: EKS Microservices
```

**Typical Resource Inventory Rows**:

| Resource ID | Type | ARN | Notes |
|-------------|------|-----|-------|
| my-cluster | EKS Cluster | arn:aws:eks:us-east-2:123456789012:cluster/my-cluster | v1.32, 6 nodes |
| my-table | DynamoDB Table | arn:aws:dynamodb:us-east-2:123456789012:table/my-table | No PITR |
| nat-0abc123 | NAT Gateway | arn:aws:ec2:us-east-2:123456789012:natgateway/nat-0abc123 | Single AZ |

**Typical Testable Risks**:

| Risk ID | Testable | Suggested Injection Method |
|---------|----------|--------------------------|
| R-001 | Yes | FIS: `aws:eks:terminate-nodegroup-instances` |
| R-002 | Yes | ChaosMesh: PodChaos `pod-kill` |
| R-003 | Yes | ChaosMesh: NetworkChaos `delay` |

---

### A.2 Serverless Architecture (e.g., E-Commerce Backend)

**Metadata**:
```
Architecture Pattern: Serverless
```

**Typical Resource Inventory Rows**:

| Resource ID | Type | ARN | Notes |
|-------------|------|-----|-------|
| order-api | API Gateway | arn:aws:apigateway:us-east-1::/restapis/abc123 | REST API |
| process-order | Lambda Function | arn:aws:lambda:us-east-1:123456789012:function:process-order | 128MB, 30s timeout |
| orders-table | DynamoDB Table | arn:aws:dynamodb:us-east-1:123456789012:table/orders | PAY_PER_REQUEST |
| order-events | SQS Queue | arn:aws:sqs:us-east-1:123456789012:order-events | Standard queue |

**Typical Testable Risks**:

| Risk ID | Testable | Suggested Injection Method |
|---------|----------|--------------------------|
| R-001 | Yes | FIS: `aws:lambda:invocation-add-delay` (Lambda cold start + delay) |
| R-002 | Yes | FIS: `aws:fis:inject-api-throttle-error` (API throttling) |
| R-003 | Yes | FIS: `aws:dynamodb:global-table-pause-replication` (DDB replication interruption) |

**Typical Monitoring Readiness Differences**:
- Serverless typically has built-in CloudWatch metrics (Lambda Duration/Errors/Throttles)
- Monitoring readiness is more likely to be Partially Ready

---

### A.3 Traditional EC2 Three-Tier Architecture (e.g., Enterprise Internal System)

**Metadata**:
```
Architecture Pattern: Traditional EC2
```

**Typical Resource Inventory Rows**:

| Resource ID | Type | ARN | Notes |
|-------------|------|-----|-------|
| i-0abc123 | EC2 Instance | arn:aws:ec2:ap-northeast-1:123456789012:instance/i-0abc123 | Web Server |
| my-alb | ALB | arn:aws:elasticloadbalancing:ap-northeast-1:123456789012:loadbalancer/app/my-alb/abc | Cross 2 AZs |
| my-db-cluster | RDS Cluster | arn:aws:rds:ap-northeast-1:123456789012:cluster:my-db-cluster | Aurora Multi-AZ |
| my-cache | ElastiCache Cluster | arn:aws:elasticache:ap-northeast-1:123456789012:replicationgroup:my-cache | Redis 3 nodes |

**Typical Testable Risks**:

| Risk ID | Testable | Suggested Injection Method |
|---------|----------|--------------------------|
| R-001 | Yes | FIS: `aws:ec2:terminate-instances` (EC2 failure) |
| R-002 | Yes | FIS: `aws:rds:failover-db-cluster` (Aurora failover) |
| R-003 | Yes | FIS: `aws:elasticache:interrupt-cluster-az-power` (Cache AZ failure) |
| R-004 | Yes | FIS: `aws:network:disrupt-connectivity` (AZ network disruption) |

---

### A.4 Multi-Region Architecture (e.g., Global SaaS Platform)

**Metadata**:
```
Architecture Pattern: Multi-Region
Primary Region: us-east-1
Other Regions: eu-west-1, ap-southeast-1
```

**Resource inventory needs to include multi-region resources**:

| Resource ID | Type | ARN | Notes |
|-------------|------|-----|-------|
| global-table | DynamoDB Table | arn:aws:dynamodb:us-east-1:123456789012:table/global-table | Global table, 3 regions |
| primary-db | Aurora Global Database | arn:aws:rds:us-east-1:123456789012:global-cluster:my-global-db | Primary cluster us-east-1 |
| dns-zone | Route53 Hosted Zone | arn:aws:route53:::hostedzone/Z1234567 | Failover routing policy |

**Typical Testable Risks**:

| Risk ID | Testable | Suggested Injection Method |
|---------|----------|--------------------------|
| R-001 | Yes | FIS: `aws:dynamodb:global-table-pause-replication` (Cross-region replication interruption) |
| R-002 | Yes | FIS: `aws:s3:bucket-pause-replication` (S3 replication interruption) |
| R-003 | Yes | FIS: `aws:network:route-table-disrupt-cross-region-connectivity` (Cross-region network) |
| R-004 | Yes | FIS: `aws:arc:start-zonal-autoshift` (AZ automatic traffic shift) |

---

*This specification is defined by the `chaos-engineering-on-aws` skill, provided as feedback to the `aws-resilience-modeling` skill designers*
*Version: 1.2 | Date: 2026-03-23*
