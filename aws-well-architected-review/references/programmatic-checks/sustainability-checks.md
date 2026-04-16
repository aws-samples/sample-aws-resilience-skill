# Sustainability Pillar — Programmatic Checks

> Record findings with severity: CRITICAL / HIGH / MEDIUM / LOW / INFO

---

## SUS-01: Graviton (ARM64) Adoption

```bash
aws ec2 describe-instances --filters Name=instance-state-name,Values=running \
  --query 'Reservations[].Instances[].{Id:InstanceId,Type:InstanceType,Arch:Architecture}' --output json
```

Count instances by architecture. Graviton (arm64) instances use ~60% less energy per compute unit.

| Result | Severity | Finding |
|--------|----------|---------|
| 0% Graviton adoption | MEDIUM | No Graviton instances — significant energy efficiency opportunity |
| < 30% Graviton | LOW | {pct}% Graviton adoption — room for improvement |
| > 30% Graviton | INFO | Good Graviton adoption at {pct}% ✅ |

---

## SUS-02: EC2 Instance Utilization

```bash
# Average CPU across all instances over 7 days
for inst in $(aws ec2 describe-instances --filters Name=instance-state-name,Values=running --query 'Reservations[].Instances[].InstanceId' --output text | tr '\t' '\n' | head -10); do
  cpu=$(aws cloudwatch get-metric-statistics --namespace AWS/EC2 --metric-name CPUUtilization \
    --dimensions Name=InstanceId,Value=$inst --start-time $(date -d '7 days ago' -u +%Y-%m-%dT%H:%M:%S) \
    --end-time $(date -u +%Y-%m-%dT%H:%M:%S) --period 604800 --statistics Average \
    --query 'Datapoints[0].Average' --output text 2>/dev/null)
  echo "$inst: avg_cpu=${cpu}%"
done
```

| Result | Severity | Finding |
|--------|----------|---------|
| Average CPU < 10% fleet-wide | MEDIUM | Fleet under-utilized — right-sizing reduces energy waste |
| Average CPU 10-40% | LOW | Moderate utilization — some right-sizing opportunity |
| Average CPU > 40% | INFO | Fleet well-utilized ✅ |

---

## SUS-03: Lambda Runtime Efficiency

```bash
aws lambda list-functions --query 'Functions[].{Name:FunctionName,Runtime:Runtime,Arch:Architectures[0],Memory:MemorySize}' --output json
```

| Result | Severity | Finding |
|--------|----------|---------|
| Functions on x86_64 | LOW | {count} Lambda functions on x86_64 — arm64 is 20% more energy efficient |
| Functions on deprecated runtimes | LOW | {count} functions on older runtimes (less efficient) |
| arm64 + current runtimes | INFO | Lambda using efficient configurations ✅ |

---

## SUS-04: S3 Intelligent Tiering

```bash
aws s3api list-buckets --query 'Buckets[].Name' --output text | tr '\t' '\n' | head -20 | while read b; do
  it=$(aws s3api get-bucket-intelligent-tiering-configuration --bucket "$b" --id default 2>/dev/null)
  if [ $? -ne 0 ]; then echo "NO_IT: $b"; fi
done
```

| Result | Severity | Finding |
|--------|----------|---------|
| Large buckets without intelligent tiering | LOW | {count} buckets without Intelligent Tiering — cold data uses unnecessary storage |
| Tiering configured | INFO | S3 Intelligent Tiering in use ✅ |

---

## SUS-05: Auto Scaling Efficiency

```bash
aws autoscaling describe-auto-scaling-groups --query 'AutoScalingGroups[].{Name:AutoScalingGroupName,Min:MinSize,Max:MaxSize,Desired:DesiredCapacity}' --output json
```

| Result | Severity | Finding |
|--------|----------|---------|
| Min == Max (no scaling) | LOW | ASG {name} cannot scale — over-provisioning wastes energy |
| Dynamic scaling active | INFO | Auto Scaling configured for demand-driven capacity ✅ |

---

## Summary

| Check | ID | Key Question |
|-------|----|-------------|
| Graviton Adoption | SUS-01 | Using energy-efficient processors? |
| Instance Utilization | SUS-02 | Right-sized compute? |
| Lambda Efficiency | SUS-03 | Efficient serverless config? |
| S3 Tiering | SUS-04 | Optimized storage? |
| Auto Scaling | SUS-05 | Demand-driven capacity? |

**Total checks: 5** | Expected time: ~2-3 minutes
