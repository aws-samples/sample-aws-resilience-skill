# 报告结构模板（Report Template）

> 阶段二最终交付的 Markdown 报告结构。生成到 `analysis-output/weakness-report-{date}.md`，再用 `scripts/generate-html-report.py` 转 HTML。

---

## 报告必含章节

### 0. 评估元数据（报告开头，表格形式）

| 字段 | 值 |
|-----|---|
| 评估对象 | {EKS 集群名 / Region / 目标 namespace} |
| 自建组件 | {MySQL / TiDB / Redis / Kafka …} |
| 证据来源 | evidence-bundle-{cluster}-{date}.tar.gz（采集于 {采集时间}） |
| 分析日期 | {YYYY-MM-DD} |
| 方法论版本 | selfhosted-stack-analyzer v1.0 |
| 评估人 | {姓名/角色} |
| 保密等级 | {用户指定} |

### 1. 执行摘要（Executive Summary）
- 一句话结论：整体是否可容忍任一 AZ 故障、是否存在数据丢失风险。
- Top 5 风险（🔴 优先）。
- 3 条立即可执行建议（Quick Wins）。
- 总体韧性评级（如：⚠️ 不满足单 AZ 容错）。

### 2. 系统拓扑（来自 topology.md）
- **图 1 部署拓扑**（AZ / 节点 / 组件角色 / 存储，Mermaid）。
- **图 2 依赖数据流拓扑**（Mermaid）。
- 组件清单表：组件 / 形态 / 角色副本 / AZ 分布 / 存储 / 备份 / 监控。
- **节点 → EC2 Name tag → 组件归属表**（本客户按 Name tag 区分组件，务必列出）。

### 3. AZ 故障爆炸半径分析　★核心
- 爆炸半径矩阵（每 AZ × 每组件 = ✅/🟠/🔴，见 risk-scoring）。
- 每个 🔴/🟠 结果的根因、RTO/RPO 估计、修复建议。

### 4. 详细薄弱点发现（按组件分组）
每个组件一小节（平台层 P / MySQL MY / TiDB TI / Redis RD / Kafka KA / 跨组件 X），用表格列出 findings：

```
| 检查 | 结果 | Severity | 发现 | 证据 | Down | Slow | Cost | Test | 修复 |
|------|------|----------|------|------|------|------|------|------|------|
| KA2  | FAIL | 🔴 CRITICAL | topic orders rf=1 | kafka-topics.json | 0 | 1 | 1 | 0 | rf→3, minISR=2 |
```

未检出问题的子项也写"已检查未发现问题"，PASS 计入但可折叠。

### 5. 数据丢失风险（RPO 视角）
- 每个数据库/队列的当前 RPO 估计 vs 目标差距（见 risk-scoring 第 6 节）。

### 6. 风险组合（HRI / MRI / LRI）
- 三张表格，含跨组件级联标记。

### 7. 改进路线图
按时间盒归位每个 finding：
- **0-30 天**：所有 CRITICAL、数据丢失风险、仲裁修正、副本补齐。
- **1-6 个月**：架构改进（半同步、跨 AZ 重分布、备份体系）。
- **6-24 个月**：战略性（多区域容灾、平台标准化）。

可选 Mermaid 甘特图。阶段一任务 > 10 项时标注"需分批修复"。

### 8. Quick Wins
5-10 个当天就能改的高价值低成本项（配置类：minISR、PDB、告警、奇数仲裁补齐）。

### 9. 混沌验证建议（可选，交接 chaos skill）
- 列出 `findings.json` 中带 `chaos_experiment_recommendation` 的项。
- 典型实验：AZ 网络隔离验证 Kafka/TiKV 爆炸半径、pod-kill 验证 Redis 哨兵切换、node-terminate 验证 TiKV Region 再平衡。

### 10. 附录
- 完整 findings 列表。
- `UNABLE_TO_ASSESS` / `NOT_APPLICABLE` 列表 + 原因（bundle 缺哪些证据）。
- 评估限制说明。

---

## 报告写作原则

1. **证据驱动**：每个 finding 引用 bundle 中的具体文件/字段，不臆测。
2. **区分严重性与代价**：Severity + 修复影响 4 维度并列，让客户自主决策。
3. **可视化优先**：拓扑图、爆炸半径矩阵、路线图甘特图。
4. **可执行**：修复建议给出具体参数/CR 字段/命令，不空泛。
5. **不外泄机密**：Secret/连接串/证书只用标识符引用，绝不内联值。
6. **诚实标注盲区**：bundle 未覆盖的检查项明确标 `UNABLE_TO_ASSESS`，写入附录。

## 输出文件

```
analysis-output/
├── inventory.json                     # 归一化组件清单
├── topology.md                        # 两张 Mermaid 图
├── findings.json                      # 结构化结果（下游 chaos skill 可消费）
├── weakness-report-{date}.md          # 本模板的完整报告
└── weakness-report-{date}.html        # HTML（generate-html-report.py 生成）
```
