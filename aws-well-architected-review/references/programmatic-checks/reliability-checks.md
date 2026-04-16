# Reliability Pillar — Programmatic Checks

> Record findings with severity: CRITICAL / HIGH / MEDIUM / LOW / INFO

---

## REL-01: Multi-AZ RDS

```bash
aws rds describe-db-instances --query 'DBInstances[].{DBId:DBInstanceIdentifier,MultiAZ:MultiAZ,Engine:Engine,Status:DBInstanceStatus}' --output json
```

| Result | Severity | Finding |
|--------|----------|---------|
| Production DB not Multi-AZ | HIGH | RDS instance {id} is single-AZ — no automatic failover |
| All Multi-AZ | INFO | All RDS instances are Multi-AZ ✅ |

---

## REL-02: Auto Scaling Groups

```bash
aws autoscaling describe-auto-scaling-groups --query 'AutoScalingGroups[].{Name:AutoScalingGroupName,Min:MinSize,Max:MaxSize,Desired:DesiredCapacity,AZs:AvailabilityZones}' --output json
```

| Result | Severity | Finding |
|--------|----------|---------|
| ASG in single AZ | HIGH | ASG {name} spans only 1 AZ — no cross-AZ resilience |
| Min=Max=1 | MEDIUM | ASG {name} has min=max=1 — no horizontal scaling |
| ASG spans 2+ AZs | INFO | ASG spans multiple AZs ✅ |

---

## REL-03: ELB Health Checks

```bash
aws elbv2 describe-target-groups --query 'TargetGroups[].{Name:TargetGroupName,HealthCheck:HealthCheckPath,Protocol:Protocol,Port:Port}' --output json
aws elbv2 describe-target-health --target-group-arn {arn} --query 'TargetHealthDescriptions[].{Target:Target.Id,Health:TargetHealth.State}' --output json
```

| Result | Severity | Finding |
|--------|----------|---------|
| Unhealthy targets | HIGH | {count} unhealthy targets in target group {name} |
| No health check path | MEDIUM | Target group {name} uses TCP health check (not application-level) |
| All healthy | INFO | All targets healthy ✅ |

---

## REL-04: AWS Backup Plans

```bash
aws backup list-backup-plans --query 'BackupPlansList[].{Name:BackupPlanName,Id:BackupPlanId}' --output json
aws backup list-protected-resources --query 'Results | length(@)' --output text
```

| Result | Severity | Finding |
|--------|----------|---------|
| No backup plans | HIGH | No AWS Backup plans configured — data loss risk |
| Plans exist but few resources | MEDIUM | Only {count} resources protected by AWS Backup |
| Comprehensive coverage | INFO | AWS Backup protecting {count} resources ✅ |

---

## REL-05: Route 53 Health Checks

```bash
aws route53 list-health-checks --query 'HealthChecks[].{Id:Id,Type:HealthCheckConfig.Type,FQDN:HealthCheckConfig.FullyQualifiedDomainName}' --output json
```

| Result | Severity | Finding |
|--------|----------|---------|
| No health checks | MEDIUM | No Route 53 health checks — no DNS-level failover |
| Health checks configured | INFO | Route 53 health checks active ✅ |

---

## REL-06: EKS Node Groups (if EKS present)

```bash
for cluster in $(aws eks list-clusters --query 'clusters[]' --output text); do
  aws eks list-nodegroups --cluster-name "$cluster" --query 'nodegroups[]' --output text | tr '\t' '\n' | while read ng; do
    aws eks describe-nodegroup --cluster-name "$cluster" --nodegroup-name "$ng" \
      --query '{Name:nodegroupName,Min:scalingConfig.minSize,Max:scalingConfig.maxSize,Desired:scalingConfig.desiredSize,Subnets:subnets}' --output json
  done
done
```

| Result | Severity | Finding |
|--------|----------|---------|
| Single-AZ nodegroup | HIGH | EKS nodegroup {name} in single AZ |
| Min=Desired=1 | MEDIUM | EKS nodegroup {name} has no scaling headroom |
| Multi-AZ, scaling configured | INFO | EKS nodegroup properly configured ✅ |

---

## REL-07: S3 Versioning

```bash
aws s3api list-buckets --query 'Buckets[].Name' --output text | tr '\t' '\n' | while read b; do
  ver=$(aws s3api get-bucket-versioning --bucket "$b" --query 'Status' --output text)
  if [ "$ver" != "Enabled" ]; then echo "WARN: $b — versioning $ver"; fi
done
```

| Result | Severity | Finding |
|--------|----------|---------|
| Critical buckets unversioned | MEDIUM | {count} S3 buckets without versioning |
| All versioned | INFO | All S3 buckets have versioning ✅ |

---

## REL-08: DynamoDB Point-in-Time Recovery

```bash
aws dynamodb list-tables --query 'TableNames[]' --output text | tr '\t' '\n' | while read t; do
  pitr=$(aws dynamodb describe-continuous-backups --table-name "$t" --query 'ContinuousBackupsDescription.PointInTimeRecoveryDescription.PointInTimeRecoveryStatus' --output text)
  if [ "$pitr" != "ENABLED" ]; then echo "WARN: $t — PITR $pitr"; fi
done
```

| Result | Severity | Finding |
|--------|----------|---------|
| Tables without PITR | MEDIUM | {count} DynamoDB tables without point-in-time recovery |
| All PITR enabled | INFO | All DynamoDB tables have PITR ✅ |

---

## REL-09: Lambda Reserved/Provisioned Concurrency

```bash
aws lambda list-functions --query 'Functions[].FunctionName' --output text | tr '\t' '\n' | while read fn; do
  conc=$(aws lambda get-function-concurrency --function-name "$fn" --query 'ReservedConcurrentExecutions' --output text 2>/dev/null)
  echo "$fn: reserved=$conc"
done
```

| Result | Severity | Finding |
|--------|----------|---------|
| Critical functions unreserved | LOW | Lambda {fn} has no reserved concurrency — throttling risk under load |
| Reserved concurrency set | INFO | Lambda concurrency configured ✅ |

---

## Summary

| Check | ID | Key Question |
|-------|----|-------------|
| Multi-AZ RDS | REL-01 | Database failover capability? |
| Auto Scaling | REL-02 | Horizontal scaling + multi-AZ? |
| ELB Health | REL-03 | Are backends healthy? |
| AWS Backup | REL-04 | Is data protected? |
| Route 53 | REL-05 | DNS-level failover? |
| EKS Nodes | REL-06 | Container resilience? |
| S3 Versioning | REL-07 | Object recovery? |
| DynamoDB PITR | REL-08 | Table recovery? |
| Lambda Concurrency | REL-09 | Function throttling protection? |

**Total checks: 9** | Expected time: ~3-5 minutes
