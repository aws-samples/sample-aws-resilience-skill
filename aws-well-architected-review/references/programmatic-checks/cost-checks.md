# Cost Optimization Pillar — Programmatic Checks

> Record findings with severity: CRITICAL / HIGH / MEDIUM / LOW / INFO

---

## COST-01: Cost Explorer Anomaly Detection

```bash
aws ce get-anomaly-monitors --query 'AnomalyMonitors[].{Name:MonitorName,Type:MonitorType}' --output json 2>/dev/null
```

| Result | Severity | Finding |
|--------|----------|---------|
| No monitors | MEDIUM | No Cost Anomaly Detection — unexpected spend won't be caught |
| Monitors active | INFO | Cost Anomaly Detection active ✅ |

---

## COST-02: Idle EC2 Instances (Low CPU)

```bash
# Check for instances with <5% avg CPU over 14 days
for inst in $(aws ec2 describe-instances --filters Name=instance-state-name,Values=running --query 'Reservations[].Instances[].InstanceId' --output text); do
  cpu=$(aws cloudwatch get-metric-statistics --namespace AWS/EC2 --metric-name CPUUtilization \
    --dimensions Name=InstanceId,Value=$inst --start-time $(date -d '14 days ago' -u +%Y-%m-%dT%H:%M:%S) \
    --end-time $(date -u +%Y-%m-%dT%H:%M:%S) --period 86400 --statistics Average \
    --query 'Datapoints | sort_by(@, &Timestamp) | [-1].Average' --output text 2>/dev/null)
  if [ "$cpu" != "None" ] && [ "$(echo "$cpu < 5" | bc -l 2>/dev/null)" = "1" ]; then
    echo "IDLE: $inst avg_cpu=${cpu}%"
  fi
done
```

| Result | Severity | Finding |
|--------|----------|---------|
| Instances < 5% CPU avg | HIGH | {count} potentially idle EC2 instances (avg CPU < 5%) |
| All utilized | INFO | No idle instances detected ✅ |

---

## COST-03: Unattached EBS Volumes

```bash
aws ec2 describe-volumes --filters Name=status,Values=available \
  --query 'Volumes[].{VolumeId:VolumeId,Size:Size,Type:VolumeType,CreateTime:CreateTime}' --output json
```

| Result | Severity | Finding |
|--------|----------|---------|
| Unattached volumes | MEDIUM | {count} unattached EBS volumes ({total_gb} GB) — wasting ${est_monthly}/mo |
| No unattached | INFO | No unattached EBS volumes ✅ |

---

## COST-04: Elastic IPs Not Associated

```bash
aws ec2 describe-addresses --query 'Addresses[?AssociationId==null].{PublicIp:PublicIp,AllocationId:AllocationId}' --output json
```

| Result | Severity | Finding |
|--------|----------|---------|
| Unassociated EIPs | LOW | {count} unassociated Elastic IPs ($3.65/mo each) |
| All associated | INFO | All Elastic IPs associated ✅ |

---

## COST-05: Old Generation Instances (Cost Angle)

```bash
# Reuse PERF-01 data — old gen instances cost more per vCPU
aws ec2 describe-instances --filters Name=instance-state-name,Values=running \
  --query 'Reservations[].Instances[?starts_with(InstanceType, `t2`) || starts_with(InstanceType, `m4`) || starts_with(InstanceType, `c4`) || starts_with(InstanceType, `r4`)].{Id:InstanceId,Type:InstanceType}' --output json
```

| Result | Severity | Finding |
|--------|----------|---------|
| Old gen instances | MEDIUM | {count} old-gen instances — newer generations offer 20-40% better price/perf |
| All current gen | INFO | All instances on cost-efficient current gen ✅ |

---

## COST-06: Savings Plans / Reserved Instances Coverage

```bash
aws ce get-savings-plans-coverage --time-period Start=$(date -d '30 days ago' -u +%Y-%m-%d),End=$(date -u +%Y-%m-%d) \
  --query 'SavingsPlansCoverages[-1].CoveragePercentage' --output json 2>/dev/null
aws ce get-reservation-coverage --time-period Start=$(date -d '30 days ago' -u +%Y-%m-%d),End=$(date -u +%Y-%m-%d) \
  --query 'Total.CoverageHours.CoverageHoursPercentage' --output text 2>/dev/null
```

| Result | Severity | Finding |
|--------|----------|---------|
| Coverage < 50% | HIGH | Savings Plans/RI coverage at {pct}% — significant savings opportunity |
| Coverage 50-80% | MEDIUM | Savings Plans/RI coverage at {pct}% — room for improvement |
| Coverage > 80% | INFO | Good Savings Plans/RI coverage at {pct}% ✅ |

---

## COST-07: NAT Gateway Data Transfer

```bash
aws ec2 describe-nat-gateways --filter Name=state,Values=available \
  --query 'NatGateways[].{Id:NatGatewayId,SubnetId:SubnetId,VpcId:VpcId}' --output json
```

| Result | Severity | Finding |
|--------|----------|---------|
| Multiple NAT GWs | LOW | {count} NAT Gateways — review if all needed ($32/mo each + data transfer) |
| Single NAT GW | INFO | NAT Gateway configuration noted |

---

## COST-08: S3 Storage Classes

```bash
aws s3api list-buckets --query 'Buckets[].Name' --output text | tr '\t' '\n' | head -20 | while read b; do
  lc=$(aws s3api get-bucket-lifecycle-configuration --bucket "$b" 2>/dev/null)
  if [ $? -ne 0 ]; then echo "NO_LIFECYCLE: $b"; fi
done
```

| Result | Severity | Finding |
|--------|----------|---------|
| Buckets without lifecycle | MEDIUM | {count} S3 buckets without lifecycle rules — no automatic tiering |
| All with lifecycle | INFO | All S3 buckets have lifecycle policies ✅ |

---

## Summary

| Check | ID | Key Question |
|-------|----|-------------|
| Cost Anomaly | COST-01 | Spend monitoring active? |
| Idle EC2 | COST-02 | Unused compute resources? |
| Unattached EBS | COST-03 | Orphaned storage? |
| Unused EIPs | COST-04 | Idle IP addresses? |
| Old Gen Instances | COST-05 | Outdated instance types? |
| SP/RI Coverage | COST-06 | Commitment discounts? |
| NAT Gateways | COST-07 | Data transfer costs? |
| S3 Lifecycle | COST-08 | Storage tiering? |

**Total checks: 8** | Expected time: ~3-5 minutes
