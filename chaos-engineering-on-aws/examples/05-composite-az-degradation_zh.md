# 示例 05：组合 AZ 降级 — 多 Action FIS 实验

> 本示例展示如何使用 **FIS 原生多 Action 模板** 模拟复合 AZ 级故障，无需任何外部编排代码。

## 场景

模拟单个可用区的多维度降级：
1. **停止 EC2 实例**（目标 AZ）
2. **暂停 EBS 卷 IO**（目标 AZ）
3. **触发 RDS Aurora 故障转移**

EC2 停止和 EBS 暂停同时启动（并行），RDS failover 延迟 30 秒后启动（通过 `startAfter` 串行依赖）。

## 架构

```
          AZ-a (目标)                 AZ-c (健康)
  ┌──────────────────────┐    ┌──────────────────────┐
  │  EC2: 已停止 ❌       │    │  EC2: 运行中 ✅       │
  │  EBS: IO 已暂停 ❌    │    │  EBS: 正常 ✅         │
  │  RDS Writer → 故障    │───►│  RDS Reader → Writer  │
  └──────────────────────┘    └──────────────────────┘
```

## 假设

**假设陈述**：当 AZ-a 的 EC2 实例被停止、EBS IO 被暂停、RDS 发生故障转移时，应用应当：
- 通过健康的 AZ-c 实例继续提供服务
- RDS failover 在 30 秒内完成
- 请求成功率保持 ≥ 95%
- 故障注入停止后 120 秒内完全恢复

## 前置条件

- [ ] 多 AZ 部署，至少 2 个 AZ 有实例
- [ ] 目标 EC2 实例和 EBS 卷已打标签 `AzImpairmentPower: IceQualified`
- [ ] RDS Aurora 集群在其他 AZ 有 Reader 实例
- [ ] FIS IAM Role 已创建（权限见下方）
- [ ] CloudWatch Alarm 已配置（用于 stop condition）
- [ ] 剩余 AZ 有足够容量承接流量

## FIS 模板（多 Action + `startAfter`）

> 完整 JSON 模板：[references/templates/az-power-interruption.json](../references/templates/az-power-interruption.json)

关键 `actions` 部分（展示编排逻辑）：

```json
{
  "actions": {
    "stop-ec2-az-a": {
      "actionId": "aws:ec2:stop-instances",
      "parameters": { "startInstancesAfterDuration": "PT5M" },
      "targets": { "Instances": "ec2-instances-az-a" }
    },
    "pause-ebs-az-a": {
      "actionId": "aws:ebs:pause-volume-io",
      "parameters": { "duration": "PT5M" },
      "targets": { "Volumes": "ebs-volumes-az-a" }
    },
    "failover-rds": {
      "actionId": "aws:rds:failover-db-cluster",
      "targets": { "Clusters": "rds-cluster" },
      "startAfter": ["stop-ec2-az-a"]
    },
    "wait-before-rds": {
      "actionId": "aws:fis:wait",
      "parameters": { "duration": "PT30S" },
      "startAfter": ["stop-ec2-az-a"]
    }
  }
}
```

### 关键设计要点

| 方面 | 实现方式 |
|------|---------|
| **并行 action** | `stop-ec2-az-a` 和 `pause-ebs-az-a` 无 `startAfter` → FIS 同时执行 |
| **串行依赖** | `failover-rds` 设置 `"startAfter": ["stop-ec2-az-a"]` → 等待 EC2 停止后启动 |
| **定时延迟** | `wait-before-rds` 使用 `aws:fis:wait` 的 `PT30S` 插入 30 秒间隔 |
| **自动恢复** | `startInstancesAfterDuration: PT5M` 在 5 分钟后自动重启 EC2 |
| **Stop condition** | CloudWatch Alarm 触发时原子性中止所有 action |

### FIS `startAfter` 参考

| 模式 | `startAfter` 设置 | 效果 |
|------|-------------------|------|
| 并行（默认） | _（不设置）_ | 所有 action 同时启动 |
| 串行 | `["action-A"]` | 在 action-A **开始**后启动 |
| 多依赖 | `["action-A", "action-B"]` | 在 A 和 B **都开始**后启动 |
| 延迟 | 使用 `aws:fis:wait` action | 在 action 之间插入定时间隔 |

## 执行

```bash
# 1. 创建多 action 模板
TEMPLATE_ID=$(aws fis create-experiment-template \
  --cli-input-json file://output/templates/composite-az-degradation.json \
  --region ap-northeast-1 \
  --query 'experimentTemplate.id' --output text)
echo "模板已创建: $TEMPLATE_ID"

# 2. 通过 experiment-runner.sh 运行（与单 action 实验完全相同）
nohup bash scripts/experiment-runner.sh \
  --mode fis \
  --template-id "$TEMPLATE_ID" \
  --region ap-northeast-1 \
  --timeout 720 \
  --poll-interval 15 \
  --output-dir output/ &
RUNNER_PID=$!

# 3. 启动监控
nohup bash scripts/monitor.sh &

# 4. 启动日志采集
nohup bash scripts/log-collector.sh \
  --namespace petadoptions \
  --services "petsite,petsearch,payforadoption" \
  --duration 720 \
  --output-dir output/ \
  --mode live &

# 5. 等待完成
wait $RUNNER_PID
echo "Runner 退出码: $?"
```

## 自定义实验时长

快速验证时缩短 duration：

```bash
# 将所有 action 时长改为 2 分钟
jq '
  .actions["stop-ec2-az-a"].parameters.startInstancesAfterDuration = "PT2M" |
  .actions["pause-ebs-az-a"].parameters.duration = "PT2M"
' output/templates/composite-az-degradation.json > output/templates/composite-az-degradation-short.json
```

## 成本估算

| Action | 时长 | Action-Minutes | 费用 |
|--------|------|---------------|------|
| EC2 Stop | 5 min | 5 | $0.50 |
| EBS Pause IO | 5 min | 5 | $0.50 |
| RDS Failover | ~30s | 0.5 | $0.05 |
| FIS Wait | 30s | 0.5 | $0.05 |
| **合计** | | **11** | **$1.10** |
