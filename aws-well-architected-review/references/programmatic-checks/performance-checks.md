# Performance Efficiency Pillar — Programmatic Checks

> Record findings with severity: CRITICAL / HIGH / MEDIUM / LOW / INFO

---

## PERF-01: EC2 Instance Generation

```bash
aws ec2 describe-instances --filters Name=instance-state-name,Values=running \
  --query 'Reservations[].Instances[].{Id:InstanceId,Type:InstanceType,Name:Tags[?Key==`Name`].Value|[0]}' --output json
```

Check instance type generation — older generations (t2, m4, c4, r4) should be upgraded.

| Result | Severity | Finding |
|--------|----------|---------|
| Instances on gen ≤ 4 (t2, m4, c4) | MEDIUM | {count} instances on old generation — missing performance + cost improvements |
| All current generation | INFO | All instances on current generation ✅ |

---

## PERF-02: EBS Volume Types

```bash
aws ec2 describe-volumes --query 'Volumes[].{VolumeId:VolumeId,Type:VolumeType,Size:Size,Iops:Iops,State:State}' --output json
```

| Result | Severity | Finding |
|--------|----------|---------|
| gp2 volumes exist | MEDIUM | {count} gp2 volumes — migrate to gp3 for better price/performance |
| io1 volumes exist | LOW | {count} io1 volumes — consider io2 for better durability |
| All gp3/io2 | INFO | All EBS volumes on latest types ✅ |

---

## PERF-03: Compute Optimizer Recommendations

```bash
aws compute-optimizer get-enrollment-status --query 'Status' --output text
aws compute-optimizer get-ec2-instance-recommendations --query 'instanceRecommendations[?finding!=`OPTIMIZED`].{InstanceId:instanceArn,Finding:finding,CurrentType:currentInstanceType,Recommended:recommendationOptions[0].instanceType}' --output json 2>/dev/null
```

| Result | Severity | Finding |
|--------|----------|---------|
| Not enrolled | MEDIUM | Compute Optimizer not enrolled — missing right-sizing insights |
| Over-provisioned instances | MEDIUM | {count} over-provisioned instances identified |
| Under-provisioned instances | HIGH | {count} under-provisioned instances — performance risk |
| All optimized | INFO | All instances optimized ✅ |

---

## PERF-04: RDS Instance Classes

```bash
aws rds describe-db-instances --query 'DBInstances[].{DBId:DBInstanceIdentifier,Class:DBInstanceClass,Engine:Engine,EngineVersion:EngineVersion}' --output json
```

| Result | Severity | Finding |
|--------|----------|---------|
| Old-gen classes (db.m4, db.r4, db.t2) | MEDIUM | {count} RDS instances on old generation classes |
| All current generation | INFO | All RDS on current generation ✅ |

---

## PERF-05: CloudFront Distributions

```bash
aws cloudfront list-distributions --query 'DistributionList.Items[].{Id:Id,Domain:DomainName,HTTP2:IsIPV6Enabled,PriceClass:PriceClass}' --output json 2>/dev/null
```

| Result | Severity | Finding |
|--------|----------|---------|
| No CloudFront | LOW | No CDN — consider CloudFront for static content delivery |
| PriceClass_All | INFO | CloudFront with global edge locations ✅ |

---

## PERF-06: ElastiCache Engine Versions

```bash
aws elasticache describe-cache-clusters --query 'CacheClusters[].{Id:CacheClusterId,Engine:Engine,Version:EngineVersion,NodeType:CacheNodeType}' --output json 2>/dev/null
```

| Result | Severity | Finding |
|--------|----------|---------|
| Outdated engine version | LOW | ElastiCache {id} on old engine version |
| Current versions | INFO | All ElastiCache on current versions ✅ |

---

## PERF-07: Lambda Memory Configuration

```bash
aws lambda list-functions --query 'Functions[].{Name:FunctionName,Memory:MemorySize,Timeout:Timeout,Runtime:Runtime}' --output json
```

| Result | Severity | Finding |
|--------|----------|---------|
| Functions at 128MB default | LOW | {count} Lambda functions at minimum 128MB — may benefit from more memory |
| Deprecated runtimes | MEDIUM | {count} Lambda functions on deprecated runtimes |
| Optimized configs | INFO | Lambda configurations look reasonable ✅ |

---

## Summary

| Check | ID | Key Question |
|-------|----|-------------|
| EC2 Generation | PERF-01 | Latest instance types? |
| EBS Types | PERF-02 | Optimal storage types? |
| Compute Optimizer | PERF-03 | Right-sized instances? |
| RDS Classes | PERF-04 | Current-gen databases? |
| CloudFront | PERF-05 | CDN for content delivery? |
| ElastiCache | PERF-06 | Current cache engines? |
| Lambda Memory | PERF-07 | Optimal function config? |

**Total checks: 7** | Expected time: ~2-3 minutes
