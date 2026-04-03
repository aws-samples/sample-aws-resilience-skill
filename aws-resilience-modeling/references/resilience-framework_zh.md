# AWS 韧性分析框架 - 参考索引

本文档作为韧性分析详细参考资料的索引。每个章节作为独立文件维护，便于高效访问。

## 参考文件

| # | 文件 | 描述 | 关键主题 |
|---|------|------|---------|
| 1 | [waf-reliability-pillar_zh.md](waf-reliability-pillar_zh.md) | AWS Well-Architected Framework - 可靠性支柱 (2025) | 5 大设计原则、4 种 DR 策略、多 AZ/多 Region、变更管理 |
| 2 | [resilience-analysis-core_zh.md](resilience-analysis-core_zh.md) | AWS 韧性分析核心原则 | Error Budget、SLI/SLO/SLA、4 大黄金信号、告警、事后复盘文化、故障排查 |
| 3 | [chaos-engineering-methodology_zh.md](chaos-engineering-methodology_zh.md) | 混沌工程方法论 | 4 步实验流程、AWS FIS 模板、常见场景 |
| 4 | [observability-standards_zh.md](observability-standards_zh.md) | 现代可观测性标准 | OpenTelemetry、日志/指标/链路追踪、健康模型 |
| 5 | [cloud-design-patterns_zh.md](cloud-design-patterns_zh.md) | 云设计模式（韧性相关） | 舱壁、熔断器、重试、基于队列的负载均衡、限流 |

## 使用方式

仅加载与当前分析任务相关的特定参考文件。例如：
- 分析故障模式 → `resilience-analysis-core_zh.md`
- 审查 DR 策略 → `waf-reliability-pillar_zh.md`
- 设计混沌实验 → `chaos-engineering-methodology_zh.md`
- 评估监控差距 → `observability-standards_zh.md`
- 评估设计模式 → `cloud-design-patterns_zh.md`
