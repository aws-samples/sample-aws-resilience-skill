中文 | [**English**](README.md)

# AWS 韧性评估技能集 (Claude Code)

一组 [Claude Code](https://docs.anthropic.com/en/docs/claude-code) 自定义技能，用于全面的 AWS 系统韧性分析与风险评估，基于 2025 年最新业界最佳实践构建。

## 技能列表

本项目包含两个互补的技能：

### 1. AWS 韧性评估 (`aws-resilience-assessment`)

全面的 AWS 基础设施韧性分析技能。它能够映射系统组件、识别故障模式、执行风险优先级评估，并生成包含可操作缓解策略的详细报告。

**调用方式：** `/aws-resilience-assessment` 或在对话中提及 "AWS 韧性分析"、"系统风险评估" 等关键词。

### 2. RMA 评估助手 (`aws-rma-assessment`)

交互式的可靠性、可维护性与可用性 (RMA) 评估技能。通过基于 AWS Well-Architected Framework 的引导式问答，评估应用程序的韧性成熟度，并生成评估报告与改进路线图。

**调用方式：** `/rma-assessment-assistant` 或在对话中提及 "RMA 评估" 等关键词。

## 特性

- 基于 **AWS Well-Architected Framework** 可靠性支柱 (2025)
- 整合 **AWS 韧性分析框架**（错误预算、SLO/SLI/SLA）
- 包含**混沌工程**方法论（AWS FIS）
- 采用 **AWS 可观测性最佳实践**（CloudWatch、X-Ray、分布式追踪）
- 应用**云设计模式**（Circuit Breaker、Bulkhead、Retry）
- 生成**交互式 HTML 报告**，包含 Chart.js 可视化图表和 Mermaid 架构图

## 分析框架

### 故障模式分类

| 类别 | 说明 |
|------|------|
| 单点故障 (SPOF) | 缺乏冗余的关键组件 |
| 过度延迟 | 性能瓶颈和延迟问题 |
| 过度负载 | 容量限制和突增负载 |
| 错误配置 | 不符合最佳实践 |
| 共享命运 | 紧密耦合和缺乏隔离 |

### 韧性评估维度（5 星评分）

- 冗余设计
- AZ 容错能力
- 超时与重试策略
- 断路器机制
- 自动扩展能力
- 配置防护措施
- 故障隔离
- 备份恢复机制
- AWS 最佳实践合规性

### 风险优先级评分

```
风险得分 = (发生概率 × 业务影响 × 检测难度) / 修复复杂度
```

## 输出内容

每次评估生成：

1. **执行摘要** — 关键风险、韧性成熟度评分、优先改进建议
2. **架构可视化** — Mermaid 图表（架构总览、依赖关系、数据流、网络拓扑）
3. **风险清单** — 按优先级排序的表格，包含评分、影响和缓解建议
4. **详细风险分析** — 对每个高优先级风险的深入分析，包含故障场景和业务影响
5. **业务影响分析** — 关键功能映射、RTO/RPO 合规性分析
6. **缓解策略** — 架构改进、配置优化（含 CLI 命令）、监控告警配置
7. **实施路线图** — Gantt 图、任务分解 (WBS)、资源需求、预算估算
8. **持续改进计划** — SLI/SLO 定义、事后复盘流程、混沌工程计划
9. **混沌工程测试计划**（可选）— 针对 Top 10 风险的 AWS FIS 实验模板

## 前提条件

### 1. Claude Code

安装 [Claude Code](https://docs.anthropic.com/en/docs/claude-code) CLI。

### 2. 安装

克隆本仓库并将技能添加到你的 Claude Code 项目中：

```bash
git clone https://github.com/aws-samples/sample-gcr-resilience-skill.git
```

将技能目录复制到项目的 `.claude/skills/` 文件夹中，或直接引用。

### 3. AWS 访问权限（推荐）

- 具有只读访问权限的 AWS 账户，用于自动化资源扫描
- 已配置适当凭证的 AWS CLI
- 可选：MCP 服务器以增强自动化能力（参见各技能目录下的 `MCP_SETUP_GUIDE.md`）

## 项目结构

```
.
├── aws-resilience-assessment/        # 全面韧性分析技能
│   ├── SKILL.md                      # 技能定义
│   ├── README.md                     # 详细使用指南
│   ├── resilience-framework.md       # AWS 最佳实践参考 (2025)
│   ├── MCP_SETUP_GUIDE.md            # MCP 服务器配置
│   ├── html-report-template.html     # 交互式 HTML 报告模板
│   ├── HTML-TEMPLATE-USAGE.md        # HTML 报告指南
│   ├── example-report-template.md    # Markdown 报告示例
│   └── generate-html-report.py       # HTML 报告生成脚本
├── aws-rma-assessment/               # RMA 评估技能
│   ├── SKILL.md                      # 技能定义
│   ├── README.md                     # 详细使用指南
│   ├── resilience-framework.md       # AWS 最佳实践参考 (2025)
│   ├── MCP_SETUP_GUIDE.md            # MCP 服务器配置
│   ├── html-report-template.html     # 交互式 HTML 报告模板
│   ├── HTML-TEMPLATE-USAGE.md        # HTML 报告指南
│   ├── example-report-template.md    # Markdown 报告示例
│   └── generate-html-report.py       # HTML 报告生成脚本
└── README.md
```

## 安全

详见 [CONTRIBUTING](CONTRIBUTING.md#security-issue-notifications)。

## 许可证

本项目基于 MIT-0 许可证授权。详见 [LICENSE](LICENSE) 文件。
