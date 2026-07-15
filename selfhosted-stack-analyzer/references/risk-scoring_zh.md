# 风险分级与评分（Risk Scoring）

> 沿用家族统一的风险模型，并针对自建有状态中间件增加 **AZ 故障爆炸半径** 与 **数据丢失风险** 两个专项维度。

---

## 1. 严重级别（每个 finding）

> 颜色契约：报告渲染必须使用这些颜色，保证视觉一致。

| 级别 | 颜色 | Emoji | 含义 | 自建中间件示例 |
|------|------|-------|------|---------------|
| **CRITICAL** | 红 | 🔴 | 立即威胁数据安全/可用性 | Kafka topic rf=1、PD 仲裁偶数、单实例 MySQL、副本全在一个 AZ、未配 TiKV location-labels |
| **HIGH** | 橙 | 🟠 | 显著风险，数日内处理 | 无 PDB、无 Pod 反亲和、异步复制不满足 RPO、无自动故障切换 |
| **MEDIUM** | 黄 | 🟡 | 明显缺口，数周内处理 | 探针缺失、资源无 limits、监控告警不全 |
| **LOW** | 蓝 | 🔵 | 小改进项 | 卷类型偏旧、命名不规范 |
| **INFO** | 灰 | ⚪ | 通过项/提示 | 配置正确、建议性说明 |

## 2. 修复影响 4 维度（每个 finding 必填）

> Severity 回答"问题多严重"，这 4 个字段回答"修复代价多大"，供客户决策。值用 `0`/`1`/`-1`。

| 字段 | 值 | 含义 |
|------|----|------|
| `downtime` | `0`/`1`/`-1` | 修复是否造成服务中断 |
| `slowness` | `0`/`1`/`-1` | 修复期间是否性能下降 |
| `additionalCost` | `0`/`1`/`-1` | 是否产生持续新成本 |
| `needFullTest` | `0`/`1`/`-1` | 是否需要全量回归测试 |

常见自建中间件修复的参考评分：

| 修复动作 | downtime | slowness | additionalCost | needFullTest |
|---------|----------|----------|----------------|--------------|
| Kafka topic 提升 rf（分区重分配） | `0` | `1`（重分配占带宽） | `1`（多存副本） | `0` |
| Kafka 设 min.insync.replicas=2 | `0` | `0` | `0` | `-1` |
| TiKV 配 location-labels + 重打标签 | `-1`（可能触发调度） | `1`（Region 再平衡） | `0` | `0` |
| PD 从 2 扩到 3（补奇数） | `0`（在线扩） | `0` | `1`（+1 实例） | `0` |
| MySQL 异步→半同步 | `0` | `1`（提交延迟↑） | `0` | `1` |
| Redis 单点→哨兵主从 | `1`（需重建拓扑） | `0` | `1`（+副本+哨兵） | `1` |
| 加 PodDisruptionBudget | `0` | `0` | `0` | `0` |
| 副本重分布到多 AZ | `-1`（重建 Pod） | `1`（数据再同步） | `1`（跨 AZ 流量费） | `0` |
| 建立 S3 备份 | `0` | `0` | `1`（存储费） | `0` |

## 3. 风险聚合（HRI / MRI / LRI）

- **HRI（高风险）**：任意 CRITICAL；或 HIGH 且爆炸半径 > 1 个组件；或同组件聚集 3+ MEDIUM；或跨组件级联风险。
- **MRI（中风险）**：孤立 HIGH（单组件影响）；带成本/性能影响的 MEDIUM。
- **LRI（低风险）**：LOW 或提示性建议。

## 4. 优先级评分与 Quick Wins

```
Priority = Impact × (1 / FixEffort)

Impact (1-5):
  5 = 数据永久丢失 / 集群整体不可用
  4 = 服务中断（可恢复）
  3 = 性能降级 / 成本浪费
  2 = 运维摩擦 / 不合规
  1 = 轻微改进

FixEffort (1-5):
  1 = 单条命令 / 配置开关（分钟）
  2 = 配置变更（小时）
  3 = 架构调整（天）
  4 = 多组件重设计（周）
  5 = 大迁移（月）

Quick Wins = 高 Impact(4-5) + 低 Effort(1-2)
```

典型 Quick Win：设置 `min.insync.replicas=2`、加 PDB、补奇数 PD、加告警规则——影响大、代价小。

---

## 5. ★ AZ 故障爆炸半径矩阵（自建中间件专项）

对**每个 AZ** 假设整体失效，逐组件判定结果。这是本 skill 最有价值的输出之一。

| 组件 | 假设 AZ-a 失效 | 假设 AZ-c 失效 | 假设 AZ-d 失效 | 最坏结论 |
|------|---------------|---------------|---------------|---------|
| TiDB(PD) | 仍可用（2/3 PD 存活） | 仍可用 | 仍可用 | ✅ 容忍任一 AZ |
| TiKV(Region) | ⚠️ 若未配 location-labels，部分 Region 3 副本同 AZ → **丢数据** | … | … | 🔴 取决于 TI4 |
| MySQL | 主在 AZ-a → **写中断，需切换** | 从丢失，主存活 | — | 🟠 取决于切换机制 |
| Redis | 哨兵 2/3 在 AZ-a → **无法选主** | … | … | 🔴 取决于哨兵分布 |
| Kafka | ⚠️ 若未配 rack awareness，部分分区 3 副本同 AZ → **丢消息** | … | … | 🔴 取决于 KA4 |

**判定规则**：
- **可用且不丢数据** → ✅
- **可用但降级/需切换**（有短暂中断，RTO 可控） → 🟠
- **不可用 或 丢已确认数据** → 🔴，列为 HRI

对每个 🔴/🟠 结果，给出：受影响组件、根因检查项（如 KA4/TI4/RD3）、预估 RTO/RPO、修复建议。

---

## 6. 数据丢失风险专项（RPO 视角）

有状态组件区别于无状态服务的核心——**副本 ≠ 备份，同步 ≠ 异步**。逐组件明确：

| 组件 | 已确认写入的持久性 | RPO 风险点 |
|------|------------------|-----------|
| MySQL 异步复制 | 主 commit 即返回，未必到从 | 主宕机丢失未同步 binlog → RPO > 0 |
| MySQL 半同步/MGR | 至少一从确认 | RPO ≈ 0（正常） |
| Kafka acks=all + minISR=2 | 至少 2 副本落盘 | RPO ≈ 0；acks=1 或 minISR=1 则有丢失窗口 |
| Redis AOF everysec | 最多丢 1s | 纯内存无持久化 → 重启全丢 |
| TiKV(Raft) | 多数副本确认 | 正常 RPO≈0；副本同 AZ 时 AZ 故障可丢 |

报告必须对每个数据库/队列明确标注 **当前 RPO 估计** 与 **目标 RPO 差距**。

---

## 7. findings.json 汇总结构

```json
{
  "cluster": "prod-eks",
  "analyzedAt": "2026-07-14",
  "summary": {
    "total": 42, "critical": 6, "high": 11, "medium": 18, "low": 7,
    "hri": 9, "mri": 15, "lri": 18,
    "azFaultTolerant": false,
    "componentsAtDataLossRisk": ["kafka-events", "tikv(tidb-main)"]
  },
  "findings": [ /* 每项按 weakness-catalog 的统一结构 */ ],
  "azBlastRadius": [
    {"az": "ap-northeast-1a", "unavailable": ["redis-cache"], "dataLoss": ["kafka-events"], "degraded": ["mysql-orders"]}
  ],
  "quickWins": ["KA3", "P4-kafka", "TI1"]
}
```

供下游 `chaos-engineering-on-aws` 消费：标记了 `chaos_experiment_recommendation` 的 finding 可直接生成故障注入实验（AZ 隔离验证爆炸半径结论）。
