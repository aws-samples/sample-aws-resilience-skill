# TODO — Service Screener v2 借鉴改造计划

> 来源：扫描 https://github.com/aws-samples/service-screener-v2 全仓后提炼的可借鉴点。
> 创建日期：2026-05-25
> 负责：架构审阅猫

---

## P0 — 立即做（核心工程细节，不抄就会踩坑）

### P0-1 ✅ 给 risk-classification.md 加"修复影响"4 维度
**来源**：`services/*/reporter.json` 的 9 字段 metadata schema
**动作**：在 severity 表后新增 4 字段定义和评分指引
- `downtime`: 0 / 1 / -1 (depends) — 修复是否需要停机
- `slowness`: 0 / 1 / -1 — 修复期间是否性能下降
- `additionalCost`: 0 / 1 / -1 — 修复是否产生新成本
- `needFullTest`: 0 / 1 / -1 — 是否需要全量回归测试

**价值**：客户 PA 决策时最关心"修这个会停机吗 / 加钱吗 / 要全量回归吗"

---

### P0-2 ✅ 把 WATools.py 的 5 个工程细节抄进 wa-tool-sync.md
**来源**：`frameworks/helper/WATools.py`
**动作**：在 wa-tool-sync.md 加一节"AWS WA Tool API 工程细节（必读避坑）"

5 个具体细节：
1. `checkIfReportExists` 用 list-by-prefix 而非 get-by-id（幂等创建模式）
2. Milestone 命名 `SS-{YYYYMMDDHHmmss}-{attempt}`，遇 ConflictException 重试 3 次
3. `update_answer` 的 Notes 必须截断到 2000 字符（API 上限 2048，留 buffer）
4. `selectedChoices` 必须 dedupe + 过滤 None（否则 ValidationException）
5. `list_answers` 在 workload 创建后有 ~3s 最终一致性窗口，加 ResourceNotFoundException 3 次 × 3s 重试

**价值**：AWS 文档里读不到，只能从踩过坑的代码里抄

---

### P0-3 ✅ programmatic-checks/*.md 每个 check 加 Remediation CLI 列
**来源**：wa-summarizer prompt 的"每条建议必带可粘贴 CLI"
**动作**：6 个 pillar checks 文件的 finding 表格加一列 `Remediation`，给出可粘贴的修复命令（或链接到 runbook）

**范围**：security / reliability / cost / ops-excellence / performance / sustainability checks
**注**：找最高频的几个 check 先加，不必一次性全补

---

## P1 — 一周内做（提升输出质量）

### P1-1 ⏳ pillar-assessment-guide.md 加 "Top-N 优先 + 6 支柱 × 4 子主题 grid"
**来源**：wa-summarizer prompt 的 7 步分析指令

具体补充：
- **Top-N 规则**：审阅时聚焦发现数 Top-5 的服务，*IAM 强制纳入*（无论排名）
- **强制覆盖 grid**：每个支柱固定 4 个子主题，避免 LLM 平均用力
  - Security: Identity / Data / Network / Incident
  - Reliability: Foundations / Workload Architecture / Change Mgmt / Failure Mgmt
  - Operational Excellence: Organization / Prepare / Operate / Evolve
  - Performance: Selection / Review / Monitoring / Trade-offs
  - Cost: Practice Cloud Financial Mgmt / Cost-effective Resources / Manage Demand / Optimize Over Time
  - Sustainability: Region Selection / User Behavior / SW & Arch / Data / HW & Services / Process & Culture

---

### P1-2 ⏳ report-template.md 加 "0-30 / 1-6m / 6-24m" 三段路线图
**来源**：wa-summarizer prompt 的路线图框架
**动作**：在 report-template.md 行动建议章节用三个时间盒替代"短中长期"
- 0-30 天：紧急修复（HIGH severity / 公网暴露 / root MFA 等）
- 1-6 个月：架构改进（Multi-AZ / Backup Plan / 监控告警体系）
- 6-24 个月：现代化路线（Serverless 化 / 容器化 / FinOps 体系）

每条 finding 必须放进对应时间盒。

---

### P1-3 ⏳ environment-bootstrap.md 加 DON'T-FETCH 列表
**来源**：wa-summarizer prompt 的明确 negative scope
**动作**：在 environment-bootstrap.md 加一节"上下文预算 — Agent 不应读取的输出"

列表（举例）：
- `aws cloudtrail lookup-events`（一次百万行，吃光窗口）
- `aws ec2 describe-snapshots --owner-ids self`（账户老的话上千条）
- `aws s3api list-objects-v2`（除非明确单 bucket 小规模）
- `aws config get-resource-config-history`（按需，限定 resource-id）
- 大 Excel/JSON dump（>500KB 必须 subagent 处理）

**价值**：避免 Agent 平均用力把窗口吃光

---

### P1-4 ⏳ Severity 颜色编码硬契约
**来源**：wa-summarizer prompt 的 red=H / yellow=M / blue=L
**动作**：在 risk-classification.md 的 severity 表加颜色列，让报告渲染一致

| Severity | Emoji/Color | 触发条件 |
|----------|-------------|----------|
| CRITICAL | 🔴 red | 公网暴露 / root MFA off / 数据未加密 / 无备份 |
| HIGH | 🟠 orange | Single-AZ prod / IAM wildcard / SG 0.0.0.0/0 非必要 |
| MEDIUM | 🟡 yellow | 缺监控 / 缺 tag / 默认 SG 在用 |
| LOW | 🔵 blue | 命名不规范 / 文档缺失 |
| INFO | ⚪ gray | 已合规的资料性事实 |

---

## P2 — 值得做，可延后

### P2-1 ⏳ security-checks.md 加 WA 官方 BP 编号对齐
**来源**：上轮已分析的 `frameworks/WAFS/map.json`
**动作**：每个检查项加 `WA Mapping: SECxx.BPxx (BP 名称)` 行
**示例**：
```
## SEC-01: IAM Root MFA
**WA Mapping**: SEC01.BP02 (Secure account root user and properties)
```
**价值**：可无缝写进 AWS WA Tool

---

### P2-2 ⏳ 新增 mapping-table.md (pillar→question→BP→check 三层映射)
**来源**：service-screener WAFS/map.json 的结构
**动作**：references/ 下新增一个 mapping-table.md，按 pillar 列出
- 完整的 Question (SEC01..SEC11 / REL01..REL11 等) 列表
- 每个 Question 下的 BP 编号 + 标题
- 每个 BP 对应的本地 check ID（SEC-01 等）
- 标记哪些 BP 是程序化覆盖、哪些靠访谈/文档评估

**价值**：审阅 coverage gap 显式化

---

### P2-3 ⏳ 新增 remediation-runbook.md（按 finding 分类的修复脚本集合）
**来源**：SOC2 三件套的 Remediation Guide
**动作**：把 P0-3 加到 checks 里的 remediation 命令汇总到独立文件，按 pillar 组织，方便客户运维粘贴执行

---

## P3 — 不做

- ❌ 不抄 Python 检查器（services/*/drivers/*.py 的 reflection 模式） — 我们是 Agent 驱动不需要
- ❌ 不抄叙事性 best-practices.md — 比当前 markdown 检查清单倒退
- ❌ 不抄 2k 行 wa-summarizer prompt 的内嵌 ETL+HTML — 维护成本极高
- ❌ 不引入 service-screener 作为底层引擎 — 那是另一个项目，超出 skill 范围

---

## 进度跟踪

- [x] P0-1 risk-classification.md 加 4 字段  — 完成 2026-05-25
- [x] P0-2 wa-tool-sync.md 加 7 个工程细节 + Checklist  — 完成 2026-05-25
- [x] P0-3 programmatic-checks 6 个文件 × 49 张表 × 125 行 finding 全部加 Remediation 列  — 完成 2026-05-25
- [x] P1-1 pillar-assessment-guide.md 加 Top-N + IAM 强制 + 6 支柱 × 4 子主题 grid  — 完成 2026-05-25
- [x] P1-2 report-template.md 改为 0-30 / 1-6m / 6-24m 三段路线图  — 完成 2026-05-25
- [x] P1-3 environment-bootstrap.md 加 DON'T-FETCH 列表 + subagent 隔离原则  — 完成 2026-05-25
- [x] P1-4 risk-classification.md 加 severity 颜色契约（🔴🟠🟡🔵⚪）  — 完成 2026-05-25
- [x] P2-1 security-checks.md 为 12 个 SEC-NN 加 WA Mapping: SECxx.BPxx  — 完成 2026-05-25
- [x] P2-2 新增 mapping-table.md（pillar→question→BP→local check 三层映射 + coverage 统计）  — 完成 2026-05-25
- [~] P2-3 remediation-runbook.md  — **已被 P0-3 覆盖**：remediation 现在 inline 在 checks 表格里，独立 runbook 不再必要。如后期需要集中运维手册可从 checks 抽取生成。

## 本轮改造产出文件清单

修改：
- references/risk-classification.md
- references/wa-tool-sync.md
- references/pillar-assessment-guide.md
- references/report-template.md
- references/environment-bootstrap.md
- references/programmatic-checks/security-checks.md
- references/programmatic-checks/reliability-checks.md
- references/programmatic-checks/cost-checks.md
- references/programmatic-checks/ops-excellence-checks.md
- references/programmatic-checks/performance-checks.md
- references/programmatic-checks/sustainability-checks.md

新增：
- references/mapping-table.md
- TODO.md（本文件）

辅助脚本（一次性，/tmp 下）：
- /tmp/add-remediation.py
- /tmp/add-wa-mapping.py
