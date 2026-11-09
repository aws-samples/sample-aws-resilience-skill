# 报告模板

> **数据完整性规则**：填写任何模板前，先按 workflow-guide_zh.md § 6.0.5 的判定决策树检查数据是否齐备。
> 标 🔴 的字段为必填；数据缺失时，使用下文给出的「数据缺失」替代文字。

## Verdict 判定逻辑参考

| 可用数据 | Verdict |
|---------------|---------|
| 完整指标 + 基线 | PASSED ✅ 或 FAILED ❌（依据假设判定） |
| 有指标但无基线 | OBSERVED (baseline unknown) ⚠ |
| 无指标数据 | OBSERVED (not validated) ⚠ |
| 无实验结果文件 | BLOCKED (no data) ❌ — 不生成报告 |

## 单次实验报告

```markdown
# 混沌工程实验报告

## 实验概况
- 实验名称: {name}
- 风险 ID: {risk_id}（来自 Assessment 2.4）
- 执行时间: {timestamp}
- 实验环境: {env}
- 结果: {PASSED ✅ / FAILED ❌ / ABORTED ⚠️}

## 输入来源
- Assessment 报告: {filename}
- 风险描述: {description}
- 建议注入方式: {suggestion}
- 实际使用注入方式: {actual}

## 稳态假设 vs 实际表现

| 指标 | 基线值 | 假设阈值 | 实验期间值 | 恢复后值 | 判定 |
|------|--------|---------|-----------|---------|------|
| 成功率 | 99.98% | >= 99.5% | {value} | {value} | ✅/❌ |
| P99 延迟 | 120ms | <= 500ms | {value} | {value} | ✅/❌ |
| 恢复时间 | N/A | <= {RTO}s | {value} | N/A | ✅/❌ |

## §6.0.5 数据完整性检查（verdict 前必须执行）

| 数据源 | 文件 | 状态 | 备注 |
|--------|------|:----:|------|
| CloudWatch 指标 | step5-metrics.jsonl | ✅/❌ | {行数} 个采样 |
| 应用日志 | step5-logs.jsonl | ✅/❌ | {行数} 行 |
| 日志摘要 | step5-log-summary.json | ✅/❌ | |
| 基线数据 | baseline-*.json | ✅/❌ | |
| ALB 流量 | RequestCount | ✅/❌ | >0 才有意义 |

**数据限制声明**: {如有数据缺失，在此说明对 verdict 的影响}

判定映射：
- 数据完整 → PASSED ✅ 或 FAILED ❌（基于假设验证）
- 部分缺失但有关键指标 → OBSERVED ⚠️
- 关键数据全部缺失 → BLOCKED 🚫

## 时间线
- T+0s: 故障注入开始
- T+{X}s: 检测到影响
- T+{Y}s: 恢复开始
- T+{Z}s: 服务完全恢复

## MTTR 分阶段分析

| 阶段 | 耗时 | 说明 | 改进方向 |
|------|------|------|---------|
| 检测（故障 → 告警） | {X}s | {description} | {suggestion} |
| 定位（告警 → 根因） | {X}s | {description} | {suggestion} |
| 修复（根因 → 修复） | {X}s | {description} | {suggestion} |
| 恢复（修复 → 恢复） | {X}s | {description} | {suggestion} |
| **总 MTTR** | {X}s | | |

## 关键发现
1. ...

## 改进建议
1. **[P0]** ...
2. **[P1]** ...

## 韧性评分更新

| 维度 | 实验前（2.7） | 实验后 | 变化 |
|------|-------------|--------|------|
| 冗余设计 | ⭐ X/5 | ⭐ X/5 | — |
| ... | | | |

## 新发现风险

| 风险 ID | 描述 | 严重度 | 建议 |
|---------|------|--------|------|
| R-NEW-001 | ... | 🟠 高 | ... |

## 清理状态

实验后清理检查清单，完成每项后勾选。

### FIS 资源
- [ ] 实验模板已删除：`aws fis delete-experiment-template --id <TEMPLATE_ID>`
- [ ] 确认无 FIS 创建的 NACL 残留：`aws ec2 describe-network-acls --filters "Name=tag-key,Values=aws:fis:experiment-id"`
- [ ] 仅为本次实验创建的临时停止条件告警已删除：`aws cloudwatch delete-alarms --alarm-names <ALARM_NAMES>`

### Chaos Mesh 资源
- [ ] PodChaos / NetworkChaos / HTTPChaos CR 已删除：`kubectl delete -f chaos-experiment.yaml`
- [ ] 确认无混沌 CR 残留：`kubectl get podchaos,networkchaos,httpchaos,stresschaos -A`

### 临时监控资源
- [ ] 仅为本次实验创建的临时 CloudWatch 告警已删除（若不复用）
- [ ] 仅为本次实验创建的自定义指标 Dashboard 已移除（若不复用）

### 备注
{cleanup_notes}
```

## 汇总报告

```markdown
# 混沌工程实验汇总报告

## 总览
- 项目: {name}
- 架构模式: {pattern}
- 实验周期: {range}
- 实验总数: {N} | 通过: {P} | 失败: {F} | 中止: {A}

## 韧性成熟度变化
- 实验前: {score}/5.0（Assessment 评估）
- 实验后: {score}/5.0（实验验证）

## 风险验证状态

| 风险 ID | 描述 | 严重度 | 结果 | 验证状态 | 改进优先级 |
|---------|------|--------|------|---------|-----------|
| R-XXX | ... | 🔴 | FAILED | 风险确认 ⚠️ | P0 |
| R-YYY | ... | 🔴 | PASSED | 影响可控 ✅ | P2（降级） |

## 改进路线图
1. ...
```

## HTML 报告

HTML 版本基于 Markdown 内容生成，额外包含：
- 内联 CSS（无外部依赖，单文件可离线打开）
- 颜色编码：PASSED=绿色、FAILED=红色、ABORTED=橙色
- 指标对比可视化（CSS 柱状图或内嵌 SVG）
- 实验时间线图
- 响应式布局
