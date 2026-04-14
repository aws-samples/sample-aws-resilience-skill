# AWS 韧性分析框架 - 参考文件索引

本文档是韧性分析详细参考资料的索引。每个部分作为独立文件维护，按需加载。

## 参考文件

| # | 文件 | 何时读取 | 说明 | 行数 |
|---|------|---------|------|------|
| 1 | [analysis-tasks_zh.md](analysis-tasks_zh.md) | 执行任务 1-8 时 | 8 个分析任务的详细指令，含评分维度、RMA 交叉映射、风险矩阵 | ~200 行 |
| 2 | [waf-reliability-pillar_zh.md](waf-reliability-pillar_zh.md) | 任务 2、任务 3 DR 评估、成本估算 | AWS WAF 可靠性支柱、4 种 DR 策略、多 AZ/多 Region、DR 成本基线 | ~510 行 |
| 3 | [resilience-analysis-core_zh.md](resilience-analysis-core_zh.md) | 任务 2 故障模式、任务 3 评分、任务 8 复盘 | Error Budget、SLI/SLO/SLA、黄金信号、告警、事后复盘 | ~510 行 |
| 4 | [chaos-engineering-methodology_zh.md](chaos-engineering-methodology_zh.md) | 混沌工程测试计划输出 | 4 步实验流程、AWS FIS 模板、常见场景 | ~212 行 |
| 5 | [observability-standards_zh.md](observability-standards_zh.md) | 任务 1 监控缺口、任务 3 可观测性评估 | OpenTelemetry、日志/指标/链路、健康模型 | ~395 行 |
| 6 | [cloud-design-patterns_zh.md](cloud-design-patterns_zh.md) | 任务 2 设计模式评估、任务 6 缓解 | 舱壁、熔断器、重试、队列负载平衡、限流 | ~282 行 |
| 7 | [compliance-mapping_zh.md](compliance-mapping_zh.md) | 合规要求在范围内时 | SOC2、ISO 27001、NIST CSF 到分析任务的映射 | ~25 行 |
| 8 | [common-risks-reference_zh.md](common-risks-reference_zh.md) | 任务 2、任务 5 风险识别 | 常见 AWS 韧性风险和模式 | ~305 行 |
| 9 | [assessment-output-spec_zh.md](assessment-output-spec_zh.md) | 生成混沌工程就绪数据输出 | 8 节结构化输出格式，供 chaos-engineering-on-aws 消费 | ~471 行 |
| 10 | [report-generation_zh.md](report-generation_zh.md) | 最终报告生成步骤 | 报告流程、Python 模板代码、质量检查清单 | ~366 行 |
| 11 | [HTML-TEMPLATE-USAGE_zh.md](HTML-TEMPLATE-USAGE_zh.md) | 生成 HTML 交互式报告 | HTML 模板使用、数据填充、Chart.js 配置 | ~482 行 |
| 12 | [MCP_SETUP_GUIDE_zh.md](MCP_SETUP_GUIDE_zh.md) | MCP 服务器安装和配置 | 详细 MCP 服务器配置指南、Region/Profile 配置 | ~506 行 |

## 使用方法

仅加载与当前分析任务相关的参考文件，不要一次性加载所有文件。

**按任务快速查找**：
- **任务 1**（架构映射）→ `observability-standards_zh.md` 检查监控缺口
- **任务 2**（故障模式）→ `resilience-analysis-core_zh.md`、`common-risks-reference_zh.md`、`cloud-design-patterns_zh.md`
- **任务 3**（韧性评分）→ `analysis-tasks_zh.md` 获取评分维度和 RMA 交叉映射
- **任务 4**（业务影响）→ `waf-reliability-pillar_zh.md` 获取 RTO/RPO 和 DR 策略
- **任务 5**（风险排序）→ `analysis-tasks_zh.md` 获取风险评分矩阵
- **任务 6**（缓解策略）→ `cloud-design-patterns_zh.md`、`waf-reliability-pillar_zh.md`
- **任务 7**（路线图）→ `analysis-tasks_zh.md` 获取分阶段计划结构
- **任务 8**（持续改进）→ `resilience-analysis-core_zh.md` 获取 SLI/SLO 和复盘
- **混沌工程输出** → `assessment-output-spec_zh.md`
- **合规** → `compliance-mapping_zh.md`
- **报告生成** → `report-generation_zh.md`、`HTML-TEMPLATE-USAGE_zh.md`
