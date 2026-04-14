[English](README.md) | **中文**

---

# AWS 系统韧性分析 Skill

这是一个全面的 AWS 系统韧性评估和风险分析 skill，整合了 2025 年最新的业界最佳实践。

## 安装

**方式 A：npx skills（推荐）**
```bash
# Install this skill
npx skills add aws-samples/sample-aws-resilience-skill --skill aws-resilience-modeling

# Install all 4 resilience skills
npx skills add aws-samples/sample-aws-resilience-skill --skill '*'
```

**方式 B：Git clone**
```bash
git clone https://github.com/aws-samples/sample-aws-resilience-skill.git
```

## 特性

- ✅ 基于 **AWS Well-Architected Framework** 可靠性支柱
- ✅ 整合 **AWS 韧性分析框架**（错误预算、SLO/SLI）
- ✅ 包含 **混沌工程** 方法论（AWS FIS）
- ✅ 采用 **AWS 可观测性最佳实践**（CloudWatch、X-Ray、分布式追踪）
- ✅ 应用 **云设计模式**（Circuit Breaker、Bulkhead、Retry）
- ✅ 内置 **AWS 常见服务风险参考库**（50+ 个风险点，覆盖存储/数据库/EKS/EC2/网络）

## 使用方式

### 方式 1：直接调用

```bash
/aws-resilience-modeling
```

Claude 会首先询问你的环境信息和业务背景，然后开始进行全面的韧性分析。

### 方式 2：自动触发

当你在对话中提到以下关键词时，skill 会自动激活：
- "AWS 韧性分析"
- "系统风险评估"
- "AWS 韧性评估"
- "AWS resilience assessment"

示例：
```
用户: 我想对我们的 AWS 生产环境进行韧性分析
Claude: [自动加载 aws-resilience-modeling skill]
```

## 准备工作

在开始分析前，请准备以下信息：

### MCP 服务器配置
自动扫描 AWS 环境所需的 MCP 服务器详细配置指南，参见 [references/MCP_SETUP_GUIDE_zh.md](references/MCP_SETUP_GUIDE_zh.md)。

### 1. 环境信息
- AWS 账户 ID 和区域
- 访问权限（建议只读访问）
- 现有架构文档（如有）

### 2. 业务背景
- 关键业务流程清单
- 当前的 RTO/RPO 目标
- 现有的 SLA/SLO（如有）
- 合规要求（如 SOC2、HIPAA、PCI DSS）

### 3. 分析范围
- 需要分析的应用和服务
- 是否包含多账户/多区域
- 预算和时间约束

## 输出内容

分析完成后，你将获得：

### 主报告
1. **执行摘要**（2 页）
   - 关键发现（Top 5 风险）
   - 韧性成熟度评分
   - 优先改进建议

2. **系统架构可视化**
   - 架构总览图（Mermaid）
   - 依赖关系图
   - 数据流图
   - 网络拓扑图

3. **风险清单**（表格）
   - 按优先级排序
   - 包含风险评分、影响、缓解建议

4. **详细风险分析**
   - 每个高优先级风险的深入分析
   - 故障场景
   - 业务影响
   - 改进建议（架构、配置、监控）

5. **业务影响分析**
   - 关键业务功能映射
   - RTO/RPO 合规性分析

6. **缓解策略建议**
   - 具体的架构改进
   - 配置优化（含参数和命令）
   - 监控和告警配置
   - AWS 服务推荐

7. **实施路线图**
   - Gantt 图
   - 详细任务分解
   - 资源需求和预算

8. **持续改进计划**
   - SLI/SLO 定义
   - 事后复盘流程
   - 混沌工程计划

### 附加文件

**references/common-risks-reference_zh.md** - AWS 常见服务风险参考手册（[English](references/common-risks-reference.md)）
- 覆盖存储（EBS/S3/EFS/FSx）、数据库、容器（EKS）、计算（EC2）、网络五大类
- 50+ 个常见风险点，每个包含风险原因和改进建议
- 评估检查清单，按服务类型逐项确认

**references/assessment-output-spec_zh.md** - 混沌工程输入规范（[English](references/assessment-output-spec.md)）
- 定义 `chaos-engineering-on-aws` skill 所需的结构化输入格式
- 包含 AWS 资源清单、风险可实验性标记、监控就绪度等 8 个章节
- 不同架构模式的填写示例（EKS/Serverless/EC2/多区域）

> 所有参考文件均提供英文版本，英文版文件名不带后缀（如 `resilience-framework.md`），中文版使用 `_zh.md` 后缀。

## 目录结构

```
aws-resilience-modeling/
├── SKILL.md                                    # 语言路由器（加载 EN/ZH）
├── SKILL_EN.md                                 # Skill 指令（英文）
├── SKILL_ZH.md                                 # Skill 指令（中文）
├── README.md                                   # Readme（英文）
├── README_zh.md                                # 本文件（中文）
├── references/
│   ├── resilience-framework.md                 # 韧性分析详细参考框架（英文）
│   ├── resilience-framework_zh.md              # 韧性分析详细参考框架（中文）
│   ├── common-risks-reference.md               # AWS 常见服务风险手册（英文）
│   ├── common-risks-reference_zh.md            # AWS 常见服务风险手册（中文）
│   ├── assessment-output-spec.md               # 混沌工程输入规范（英文）
│   ├── assessment-output-spec_zh.md            # 混沌工程输入规范（中文）
│   ├── report-generation.md                    # 报告生成流程和代码（英文）
│   ├── report-generation_zh.md                 # 报告生成流程和代码（中文）
│   ├── HTML-TEMPLATE-USAGE.md                  # HTML 模板使用指南（英文）
│   ├── HTML-TEMPLATE-USAGE_zh.md               # HTML 模板使用指南（中文）
│   ├── MCP_SETUP_GUIDE.md                      # MCP 服务器配置指南（英文）
│   └── MCP_SETUP_GUIDE_zh.md                   # MCP 服务器配置指南（中文）
├── scripts/
│   └── generate-html-report.py                 # Python 报告生成器
└── assets/
    ├── html-report-template.html               # HTML 交互式报告模板
    ├── example-report-template.md              # Markdown 报告示例（英文）
    └── example-report-template_zh.md           # Markdown 报告示例（中文）
```

## 分析框架

### 故障模式分类

| 类别 | 说明 |
|------|------|
| 单点故障 (SPOF) | 缺乏冗余的关键组件 |
| 过度延迟 | 性能瓶颈和延迟问题 |
| 过度负载 | 容量限制和突增负载 |
| 错误配置 | 不符合最佳实践 |
| 共享命运 | 紧密耦合和缺乏隔离 |

### 韧性评估维度

使用 **5 星评分系统**（1星=不足，5星=优秀）评估：

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

## 示例场景

### 场景 1：电商平台
```
环境:
- Multi-AZ RDS (PostgreSQL)
- ECS Fargate 应用
- CloudFront + S3 静态资源
- ElastiCache Redis

关键发现:
- RDS 单区域（无 Aurora Global Database）
- 缺少 Auto Scaling 策略
- 未配置 Circuit Breaker
- 监控覆盖不足

建议:
- 迁移到 Aurora Global Database
- 实施 Target Tracking Auto Scaling
- 集成 AWS X-Ray 分布式追踪
- 建立季度 DR 演练
```

### 场景 2：金融 API
```
环境:
- API Gateway + Lambda
- DynamoDB Global Tables
- Aurora Serverless
- Route 53 健康检查

关键发现:
- Lambda 无 Reserved Concurrency
- 缺少 API 限流策略
- 未定义 SLO/SLI
- 无混沌工程实践

建议:
- 配置 Lambda Reserved Concurrency
- 实施 API Gateway Usage Plans
- 定义 99.99% 可用性 SLO
- 建立每周混沌实验
```

## 灾难恢复策略选择

| 策略 | RTO | RPO | 成本 | 适用场景 |
|------|-----|-----|------|---------|
| 备份与恢复 | 小时-天 | 小时-天 | $ | 非关键系统 |
| 导航灯 | 10分钟-小时 | 分钟 | $$ | 重要系统 |
| 温备份 | 分钟 | 秒-分钟 | $$$ | 关键业务 |
| 多站点主动-主动 | 秒-分钟 | 秒 | $$$$ | 任务关键 |

## 参考资源

### AWS 官方文档
- [AWS Resilience Analysis Framework](https://docs.aws.amazon.com/prescriptive-guidance/latest/resilience-analysis-framework/)
- [AWS Well-Architected - Reliability Pillar](https://docs.aws.amazon.com/wellarchitected/latest/reliability-pillar/)
- [AWS Fault Injection Simulator](https://docs.aws.amazon.com/fis/latest/userguide/)
- [AWS Resilience Hub](https://docs.aws.amazon.com/resilience-hub/latest/userguide/)

### 外部资源
- [AWS Observability Best Practices](https://aws-observability.github.io/observability-best-practices/)
- [Principles of Chaos Engineering](https://principlesofchaos.org/)
- [Chaos Engineering on AWS](https://docs.aws.amazon.com/prescriptive-guidance/latest/chaos-engineering-on-aws/)

## 高级特性

### 错误预算管理

基于 AWS 韧性最佳实践，计算和跟踪错误预算：

```
错误预算 = (1 - SLO) × 时间周期

示例：
SLO = 99.9%（月度）
错误预算 = 43.2 分钟/月
```

### 混沌工程实验

使用 AWS FIS 进行故障注入：

- EC2 实例终止
- 网络延迟/丢包
- RDS 故障转移
- AZ 不可用模拟
- CPU/内存压力测试

### 可观测性三大支柱

- **日志**：CloudWatch Logs + 结构化日志
- **指标**：CloudWatch Metrics + 关键监控指标
- **追踪**：AWS X-Ray + 分布式追踪

## 常见问题

### Q: 分析需要多长时间？
A: 根据环境复杂度：
- 简单环境（单区域，< 10 服务）：1-2 小时
- 中等环境（多 AZ，10-50 服务）：3-5 小时
- 复杂环境（多区域，> 50 服务）：1-2 天

### Q: 是否需要 AWS 账户访问权限？
A: 推荐但非必需：
- **有权限**：可以自动扫描资源，分析更准确
- **无权限**：基于提供的架构文档进行分析

### Q: 分析会产生 AWS 费用吗？
A: 分析本身不产生费用，但实施建议可能包含：
- AWS Resilience Hub（免费）
- AWS FIS 混沌实验（按分钟计费）
- 额外的 AWS 服务（如 Aurora Global Database）

### Q: 如何实施建议？
A: 分析报告包含：
- 具体的架构改进图
- AWS CLI 命令
- CloudFormation/Terraform 代码片段
- 分阶段实施路线图

### Q: 是否支持多云环境？
A: 当前专注于 AWS 环境，提供基于 AWS Well-Architected Framework 的专业韧性评估。

## 更新日志

### v1.1.0 (2026-03-14)
- ✅ 新增 `common-risks-reference.md` — AWS 常见服务风险参考手册
- ✅ 整合 50+ 个常见风险点（存储/数据库/EKS/EC2/网络）
- ✅ 新增按服务类型的评估检查清单
- ✅ SKILL.md 故障模式识别任务引用风险参考
- ✅ 风险分类细化对齐实际 AWS 服务

### v1.0.0 (2025-02-17)
- ✅ 初始版本
- ✅ 整合 AWS Well-Architected Framework (2025)
- ✅ 整合 AWS 韧性分析框架
- ✅ 整合混沌工程方法论
- ✅ 整合 AWS 可观测性最佳实践
- ✅ 包含详细的 resilience-framework.md 参考

## 反馈和贡献

如有问题或建议，请通过以下方式反馈：
- 在对话中直接提出
- 更新你本地的 skill 文件

## 许可

本 skill 基于 AWS Well-Architected Framework 和混沌工程最佳实践编写，供学习和使用。
