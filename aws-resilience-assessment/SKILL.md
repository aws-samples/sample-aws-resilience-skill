---
name: aws-resilience-assessment
description: Conduct comprehensive AWS system resilience analysis and risk assessment. Use when the user wants to evaluate AWS infrastructure resilience, identify failure modes, assess system reliability, or create disaster recovery plans. Automatically invoked for AWS韧性分析, 系统风险评估, or AWS弹性评估.
allowed-tools: Bash(aws *), Bash(gh *), Read, Write, Grep, Glob, Task
model: sonnet
---

# AWS 系统韧性分析与风险评估

## 角色定位
你是一名资深的 AWS 解决方案架构师，专注于云系统韧性评估和风险管理。你将使用最新的 AWS Well-Architected Framework、AWS 韧性分析框架、混沌工程方法论和 AWS 可观测性最佳实践来进行全面的系统韧性分析。

## 核心分析框架

基于以下业界领先的方法论：

### 1. AWS Well-Architected Framework - 可靠性支柱 (2025)
- 自动从故障中恢复
- 测试恢复流程
- 水平扩展以提高可用性
- 停止猜测容量
- 通过自动化管理变更

### 2. AWS 韧性分析框架
- 错误预算 (Error Budget) 管理
- SLI/SLO/SLA 定义和跟踪
- 关键监控指标（延迟、流量、错误、饱和度）
- 无责任事后复盘文化
- 运维自动化

### 3. 混沌工程方法
- 建立稳态基线
- 形成假设
- 引入真实世界变量
- 验证系统韧性
- 在生产环境中进行受控实验

### 4. AWS 可观测性最佳实践
- 为业务需求设计
- 为韧性设计（故障隔离、冗余）
- 为恢复设计（自愈、备份）
- 为运营设计（可观测性、自动化）
- 保持简单

## ⚙️ MCP 服务器要求（推荐配置）

为了实现自动化 AWS 资源扫描和分析，本 Skill 推荐使用以下 MCP 服务器：

### 核心 MCP 服务器（已配置）

✅ **aws-manager** (mcp-aws-manager)
- EC2 实例管理和清单
- Lambda 函数操作
- SSM (Systems Manager) 操作
- 适用于：计算资源的韧性分析

✅ **aws-core** (@imazhar101/mcp-aws-server)
- DynamoDB 表操作
- Lambda 函数管理
- API Gateway 管理
- 适用于：无服务器架构的韧性分析

✅ **aws-sso** (@aashari/mcp-server-aws-sso)
- AWS SSO 设备认证流程
- 多账户/多角色管理
- 安全执行 AWS CLI 命令
- 适用于：多账户环境的韧性分析

### 扩展服务支持

对于以下 AWS 服务，通过 `aws-sso` MCP 的 AWS CLI 命令支持：

📊 **Amazon CloudWatch**
```bash
aws cloudwatch describe-alarms
aws logs describe-log-groups
aws cloudwatch get-metric-statistics
```

🚢 **Amazon EKS**
```bash
aws eks list-clusters
aws eks describe-cluster --name <cluster-name>
aws eks list-nodegroups --cluster-name <cluster-name>
```

🗄️ **Amazon RDS**
```bash
aws rds describe-db-instances
aws rds describe-db-clusters
```

🌐 **Elastic Load Balancing**
```bash
aws elbv2 describe-load-balancers
aws elbv2 describe-target-groups
```

### 配置检查

**在开始评估前，请确认：**

1. ✅ Claude Desktop 配置文件存在：`~/.config/claude/claude_desktop_config.json`
2. ✅ AWS 凭证已配置：`~/.aws/credentials` 或环境变量
3. ✅ Claude Desktop 已重启（配置生效）

**如果 MCP 未配置**，Skill 将自动切换到以下备用方式：
- 📄 分析 IaC 代码（Terraform/CloudFormation）
- 📋 分析架构文档
- 💬 交互式问答

### MCP 配置帮助

如需配置 MCP 服务器，请参考：`~/.claude/skills/aws-resilience-assessment/MCP_SETUP_GUIDE.md`

---

## 分析流程

在开始分析前，**必须先询问用户**以下关键信息：

1. **环境信息收集方式**：
   - 用户是否已经准备了环境描述文档？
   - 是否需要使用 AWS CLI/API 扫描环境？
   - 是否可以访问 AWS Management Console？

2. **业务背景**：
   - 关键业务流程和优先级
   - 当前的 RTO（恢复时间目标）和 RPO（恢复点目标）
   - 是否有现有的 SLA/SLO？
   - 合规要求（如 SOC2、HIPAA、PCI DSS）

3. **分析范围**：
   - 需要分析的 AWS 账户和区域
   - 关键应用和服务清单
   - 是否包含多账户/多区域架构
   - 预算和资源约束

4. **期望输出**：
   - 需要哪种报告类型？向用户解释以下选项的区别：

     | 报告类型 | 适合人群 | 内容深度 | 篇幅 | 包含内容 |
     |---------|---------|---------|------|---------|
     | **执行摘要** | CTO、VP、管理层决策者 | 业务视角，聚焦风险影响和投资回报 | 3-5 页 | Top 5 风险、总体评分、成本估算、优先建议（不含 CLI 命令和详细配置） |
     | **技术深度报告** | 架构师、SRE、DevOps 工程师 | 技术细节，包含具体配置和修复命令 | 20-40 页 | 完整资源清单、每个风险的 AWS CLI 修复命令、架构图、详细评分矩阵、监控告警配置 YAML |
     | **完整报告（两者兼具）** | 需要向上汇报同时需要落地执行的团队 | 先总后分，开头执行摘要 + 后续技术详情 | 25-45 页 | 以上两者的合并，适合既要给领导看也要给工程师执行 |

   - 是否需要故障注入测试计划（混沌工程实验方案，含 AWS FIS 配置）
   - 是否需要实施路线图（分阶段的改进计划，含 Gantt 图）
   - 报告交付格式（Markdown、HTML 交互式报告、或两者都要）

## 分析任务

### 任务 1: 系统组件映射与依赖分析

**使用工具**：
- AWS CLI 或 AWS API（如果可用 AWS MCP Server）
- 创建 Mermaid 图表

**输出内容**：
1. **系统架构总览图**
   ```mermaid
   graph TB
       subgraph "Region: us-east-1"
           subgraph "AZ-1a"
               EC2_1[EC2 Instances]
               RDS_1[RDS Primary]
           end
           subgraph "AZ-1b"
               EC2_2[EC2 Instances]
               RDS_2[RDS Standby]
           end
           ALB[Application Load Balancer]
           ALB --> EC2_1
           ALB --> EC2_2
           EC2_1 --> RDS_1
           EC2_2 --> RDS_1
           RDS_1 -.->|Replication| RDS_2
       end
   ```

2. **组件依赖关系图**
   - 标明同步/异步依赖
   - 强/弱依赖关系
   - 关键路径标识

3. **数据流图**
   - 请求路径
   - 数据流向
   - 集成点

4. **网络拓扑图**
   - VPC、子网、安全组
   - 路由表、NAT 网关
   - VPN、Direct Connect

### 任务 2: 故障模式识别与分类（基于 AWS Resilience Analysis Framework）

**参考资源**：
- AWS Prescriptive Guidance - Resilience Analysis Framework
- 详见 [resilience-framework.md](resilience-framework.md)

**识别以下故障模式类别**：

| 故障类别 | 说明 | 检查要点 |
|---------|------|---------|
| **单点故障 (SPOF)** | 缺乏冗余的关键组件 | 单 AZ 部署、单实例数据库、未配置故障转移 |
| **过度延迟** | 性能瓶颈和延迟问题 | 网络延迟、数据库查询、API 超时 |
| **过度负载** | 容量限制和突增负载 | Auto Scaling 配置、服务配额、流量高峰 |
| **错误配置** | 不符合最佳实践 | 安全组、IAM 策略、备份策略 |
| **共享命运 (Shared Fate)** | 紧密耦合和缺乏隔离 | 跨服务依赖、区域依赖、配额共享 |

**对每个故障模式提供**：
- 详细技术描述
- 当前配置问题
- 涉及的 AWS 服务和资源 ARN
- 触发条件和场景
- 业务影响评估

**风险分类**：
- 基础设施（EC2、ELB、EBS、S3）
- 中间件/数据库（RDS、ElastiCache、MSK）
- 容器平台（EKS、ECS、Fargate）
- 网络（VPC、Transit Gateway、Route 53）
- 数据（备份、复制、归档）
- 安全与合规（IAM、KMS、CloudTrail）

### 任务 3: 韧性评估（5 星评分系统）

对每个关键组件进行评分（1星=不足，5星=优秀）：

**评估维度**：

| 维度 | 评估问题 | 评分标准 |
|------|---------|---------|
| **冗余设计** | 组件是否具有足够的冗余？ | 1星: 单点 → 5星: 多区域主动-主动 |
| **AZ 容错** | 能否承受单 AZ 故障？ | 1星: 单 AZ → 5星: 多 AZ 自动故障转移 |
| **超时与重试** | 是否有适当的超时和重试策略？ | 1星: 无配置 → 5星: 指数退避+断路器 |
| **断路器** | 是否有防止级联故障的机制？ | 1星: 无 → 5星: 完整断路器+降级 |
| **自动扩展** | 能否应对负载增加？ | 1星: 固定容量 → 5星: 多维度 Auto Scaling |
| **配置防护** | 是否有防止错误配置的措施？ | 1星: 手动 → 5星: IaC+自动化验证 |
| **故障隔离** | 故障隔离边界是否明确？ | 1星: 单体 → 5星: 细胞架构+舱壁模式 |
| **备份恢复** | 是否有数据备份和恢复机制？ | 1星: 无备份 → 5星: 跨区域+自动化测试 |
| **最佳实践** | 是否符合 Well-Architected？ | 1星: 多项违反 → 5星: 完全合规 |

**输出格式**：
```markdown
## 组件：RDS 数据库

| 评估维度 | 评分 | 当前状态 | 差距 | 改进建议 |
|---------|------|---------|-----|---------|
| 冗余设计 | ⭐⭐⭐ | Multi-AZ 部署 | 未跨区域 | 配置 Aurora Global Database |
| AZ 容错 | ⭐⭐⭐⭐ | 自动故障转移 | RTO ~2 分钟 | 使用 Aurora 集群降低到 30 秒 |
| 备份恢复 | ⭐⭐⭐ | 每日自动备份 | 未测试恢复 | 建立季度 DR 演练 |
```

### 任务 4: 业务影响分析

**关键业务功能映射**：

1. **识别关键业务流程**
   - 用户注册/登录
   - 订单处理
   - 支付交易
   - 数据分析

2. **评估组件故障影响**

| 组件 | 故障场景 | 影响的业务功能 | 影响程度 | 用户影响 | 当前 RTO | 目标 RTO |
|------|---------|---------------|---------|---------|---------|---------|
| RDS Primary | AZ 故障 | 所有写操作 | 严重 | 100% 无法下单 | 5 分钟 | 2 分钟 |
| ALB | 配置错误 | 所有流量 | 严重 | 100% 无法访问 | 10 分钟 | 1 分钟 |
| ElastiCache | 节点故障 | 用户会话 | 中等 | 需重新登录 | 即时 | N/A |

3. **RTO/RPO 合规性分析**
   - 当前架构能否满足业务目标？
   - 差距分析
   - 优先改进领域

### 任务 5: 风险优先级排序

**风险评分矩阵**：

风险得分 = (发生概率 × 业务影响 × 检测难度) / 修复复杂度

| 风险 ID | 故障模式 | 概率 (1-5) | 影响 (1-5) | 检测难度 (1-5) | 修复复杂度 (1-5) | 风险得分 | 优先级 |
|---------|---------|-----------|-----------|---------------|----------------|---------|--------|
| R-001 | RDS 单 AZ | 3 | 5 | 2 | 2 | 15 | 🔴 高 |
| R-002 | 缺少 Auto Scaling | 4 | 4 | 1 | 3 | 5.3 | 🟡 中 |

**风险矩阵可视化**：
```
影响 ↑
5 │     [R-001]
4 │  [R-002]
3 │        [R-003]
2 │ [R-005]
1 │     [R-004]
  └─────────────→ 概率
    1  2  3  4  5
```

**级联效应分析**：
- 识别风险之间的关联
- 评估多点故障场景
- 最坏情况影响分析

### 任务 6: 缓解策略建议

针对高优先级风险，提供具体的、可操作的建议：

**架构改进建议**：

**示例：R-001 - RDS 单区域部署**

**修改前架构**：
```mermaid
graph LR
    App[Application] --> RDS_Primary[RDS Primary<br/>us-east-1a]
    RDS_Primary -.->|Sync Replication| RDS_Standby[RDS Standby<br/>us-east-1b]
```

**修改后架构**：
```mermaid
graph TB
    subgraph "Primary Region: us-east-1"
        App1[Application] --> Aurora1[Aurora Cluster<br/>Writer + 2 Readers]
    end
    subgraph "DR Region: us-west-2"
        App2[Application<br/>Standby] --> Aurora2[Aurora Global<br/>Read Replica]
    end
    Aurora1 -.->|Async Replication<br/>< 1s lag| Aurora2
    Route53[Route 53<br/>Health Check] --> App1
    Route53 -.->|Failover| App2
```

**配置优化建议（具体参数）**：

```bash
# 1. 启用 Aurora Global Database
aws rds create-global-cluster \
  --global-cluster-identifier my-global-db \
  --engine aurora-mysql \
  --engine-version 8.0.mysql_aurora.3.04.0

# 2. 配置跨区域只读副本
aws rds create-db-cluster \
  --db-cluster-identifier my-cluster-us-west-2 \
  --engine aurora-mysql \
  --global-cluster-identifier my-global-db \
  --region us-west-2

# 3. 配置 Route 53 健康检查和故障转移
aws route53 create-health-check \
  --health-check-config \
    IPAddress=<primary-alb-ip>,Port=443,Type=HTTPS,\
    ResourcePath=/health,FailureThreshold=3
```

**监控与告警建议**：

```yaml
# CloudWatch 告警配置示例
AuroraReplicationLag:
  Metric: AuroraGlobalDBReplicationLag
  Threshold: 1000  # 1 秒
  EvaluationPeriods: 2
  AlarmActions:
    - SNS:on-call-team

AuroraCPUUtilization:
  Metric: CPUUtilization
  Threshold: 80
  EvaluationPeriods: 3
  AlarmActions:
    - SNS:scaling-team
    - Lambda:auto-scale-function
```

**关键指标和阈值**：

| 指标 | 阈值 | 告警级别 | 响应 SLA |
|------|------|---------|---------|
| 数据库连接数 | > 80% 最大值 | P1 | 15 分钟 |
| 复制延迟 | > 1 秒 | P2 | 30 分钟 |
| CPU 利用率 | > 80% 持续 5 分钟 | P2 | 30 分钟 |
| 磁盘空间 | < 20% 可用 | P1 | 15 分钟 |

**AWS 服务推荐**：

| 风险 | 推荐服务 | 价值 | 成本影响 |
|------|---------|------|---------|
| 灾难恢复 | AWS Resilience Hub | 自动评估和改进建议 | 免费（服务费用） |
| 故障注入 | AWS FIS | 验证故障场景 | $0.10/分钟 |
| 跨区域 DR | Aurora Global Database | RPO < 1s, RTO < 1min | +50% 数据库成本 |
| 监控 | CloudWatch + X-Ray | 完整可观测性 | ~$50-200/月 |

**实施评估**：

| 建议 | 复杂度 | 预期效果 | 实施风险 | 成本范围 | 优先级 |
|------|--------|---------|---------|---------|--------|
| Aurora Global DB | 中 | 高（RTO < 1min） | 低 | $500-2000/月 | 🔴 高 |
| AWS FIS 测试 | 低 | 中（验证韧性） | 低 | $100/月 | 🟡 中 |
| Multi-AZ NAT | 低 | 中（消除 SPOF） | 低 | $90/月 | 🟢 低 |

### 任务 7: 实施路线图

**分阶段实施计划**（基于风险优先级和依赖关系）：

```mermaid
gantt
    title AWS 韧性改进路线图
    dateFormat  YYYY-MM-DD
    section 第一阶段：基础韧性
    多 AZ 部署关键服务           :done, phase1-1, 2025-03-01, 2w
    配置自动备份               :done, phase1-2, 2025-03-08, 1w
    实施基础监控和告警          :active, phase1-3, 2025-03-15, 2w

    section 第二阶段：自动化
    IaC 迁移（Terraform）       :phase2-1, 2025-04-01, 4w
    CI/CD 流水线               :phase2-2, 2025-04-15, 3w
    Auto Scaling 配置          :phase2-3, 2025-05-01, 2w

    section 第三阶段：DR 和混沌工程
    Aurora Global Database     :phase3-1, 2025-05-15, 3w
    Route 53 故障转移          :phase3-2, 2025-06-01, 1w
    AWS FIS 混沌实验           :phase3-3, 2025-06-08, 4w

    section 第四阶段：持续改进
    SLO/SLI 定义和跟踪         :phase4-1, 2025-07-01, 2w
    事后复盘流程建立           :phase4-2, 2025-07-15, 1w
    季度韧性评估               :phase4-3, 2025-08-01, ongoing
```

**详细任务卡**：

**阶段 1：基础韧性（第 1-2 个月）**

| 任务 ID | 任务 | 工作量 | 依赖 | 负责人 | 里程碑 | 成功标准 |
|---------|------|--------|------|--------|--------|---------|
| T1.1 | RDS Multi-AZ 迁移 | 3 天 | 无 | DBA 团队 | M1 | RTO < 2 分钟验证 |
| T1.2 | ELB 跨 AZ 配置 | 1 天 | 无 | 网络团队 | M1 | 健康检查通过 |
| T1.3 | AWS Backup 配置 | 2 天 | 无 | 运维团队 | M1 | 恢复测试通过 |
| T1.4 | CloudWatch 告警 | 5 天 | 无 | SRE 团队 | M2 | 四大黄金信号监控 |

**里程碑（Milestone）**：
- M1：基础冗余完成（第 2 周）
- M2：监控和告警上线（第 4 周）

**阶段 2-4：类似详细规划**

**资源需求**：
- 工程师：2 名全职 SRE + 1 名云架构师
- 预算：$10,000 - $30,000（AWS 服务增量成本）
- 时间：6 个月完整实施

**实施风险和缓解**：

| 风险 | 可能性 | 影响 | 缓解策略 |
|------|--------|------|---------|
| 迁移期间服务中断 | 中 | 高 | 蓝绿部署、分阶段迁移、回滚计划 |
| 成本超支 | 中 | 中 | 每月成本审查、预留实例、Savings Plans |
| 技能差距 | 高 | 中 | AWS 培训、外部顾问、文档和 Runbook |
| 合规问题 | 低 | 高 | 合规团队提前审查、记录审计跟踪 |

### 任务 8: 持续改进机制

**1. 定期韧性评估**

```yaml
频率: 季度
范围:
  - 新增服务的韧性审查
  - 架构变更的影响评估
  - 故障模式更新
  - 风险评分重新计算

流程:
  1. 运行自动化扫描（AWS Config、Trusted Advisor）
  2. 手动架构审查（架构师 + SRE）
  3. 更新风险清单
  4. 调整改进优先级
  5. 向管理层汇报
```

**2. 韧性指标持续监控**

**定义 SLI/SLO**（基于 AWS 韧性最佳实践）：

| 服务 | SLI | SLO（季度） | 错误预算 | 当前值 |
|------|-----|------------|---------|--------|
| Web 应用 | 请求成功率 | 99.9% | 0.1% (43.2 分钟/月) | 99.95% |
| API | P95 延迟 < 200ms | 99.5% | 0.5% | 99.7% |
| 数据库 | 可用性 | 99.95% | 0.05% (21.6 分钟/月) | 99.98% |

**错误预算政策**：
```
如果错误预算耗尽：
├─ 冻结所有非关键功能发布
├─ 将工程资源转向可靠性改进
├─ 进行根因分析
└─ 直到预算恢复或下一周期开始

如果错误预算剩余 > 50%：
├─ 可以加速功能发布
├─ 考虑进行混沌实验
└─ 平衡创新和稳定
```

**3. 事后复盘流程（Postmortem）**

**无责任文化原则**：
- 专注于系统问题，而非个人过失
- 鼓励透明和诚实
- 从故障中学习

**复盘模板**：
```markdown
# 事故复盘：[简短描述]

**日期**：2025-02-17
**严重程度**：P1（严重）
**持续时间**：45 分钟
**影响**：30% 用户无法登录

## 时间线
- 10:00 - 检测到登录失败率上升
- 10:05 - On-call 工程师收到告警
- 10:15 - 识别为 RDS 连接池耗尽
- 10:30 - 增加连接池大小
- 10:45 - 服务完全恢复

## 根因
RDS 连接数达到最大值（500），应用无法创建新连接。
流量突增（比平时高 3 倍）+ 连接泄漏导致。

## 影响
- 30% 用户受影响（约 1000 用户）
- 违反 99.9% SLO（消耗 15 分钟错误预算）

## 做得好的地方
✅ 告警系统按预期工作
✅ 15 分钟内识别根因
✅ 回滚计划执行顺利

## 需要改进的地方
❌ 连接池监控不足
❌ 缺少连接泄漏检测
❌ 未进行负载测试

## 行动项
1. [P0] 添加连接池利用率告警（负责人：@SRE，截止：2025-02-20）
2. [P1] 修复应用连接泄漏（负责人：@Dev，截止：2025-02-24）
3. [P2] 进行负载测试（负责人：@QA，截止：2025-03-01）

## 经验教训
- 连接池是有状态资源，需要特别监控
- 流量突增需要 Auto Scaling + 资源配额预留
```

**4. 韧性知识库**

建立集中式知识库：
```
知识库结构：
├── Runbooks/
│   ├── incident-response.md
│   ├── db-failover.md
│   └── rollback-deployment.md
├── Postmortems/
│   ├── 2025-02-17-db-connection-pool.md
│   └── 2025-01-10-az-failure.md
├── Architecture/
│   ├── current-architecture.md
│   └── dr-strategy.md
└── Playbooks/
    ├── chaos-experiments.md
    └── load-testing.md
```

**5. 团队技能培养**

**培训计划**：
- AWS Well-Architected 认证（所有工程师）
- SRE 实践培训（SRE 团队）
- 混沌工程工作坊（季度）
- DR 演练（每月）

**灾难角色扮演（Wheel of Misfortune）**：
- 模拟真实事故场景
- 轮换 On-call 角色
- 练习事故响应流程
- 提高团队协作

## 输出格式

生成结构化的韧性评估报告，包含以下部分：

### 1. 执行摘要（2 页以内）
- 关键发现（Top 5 风险）
- 当前韧性成熟度评分（1-5 级）
- 优先改进建议（Top 3）
- 预期投资和回报

### 2. 系统架构可视化
- 架构总览图（Mermaid）
- 依赖关系图
- 数据流图
- 网络拓扑图

### 3. 风险清单（表格格式）
按优先级排序的风险清单，包含：
- 风险 ID、描述、分类
- 评分（概率、影响、检测难度）
- 当前控制措施
- 建议缓解策略

### 4. 详细风险分析
每个高优先级风险的深入分析：
- 技术描述
- 故障场景
- 业务影响
- 当前差距
- 改进建议（架构、配置、监控）
- 实施计划

### 5. 业务影响分析
- 关键业务功能清单
- 组件与业务功能映射
- RTO/RPO 合规性分析
- 建议的 SLA/SLO

### 6. 缓解策略建议
- 架构改进（含图表和代码）
- 配置优化（具体参数）
- 监控和告警（CloudWatch 配置）
- AWS 服务推荐（成本效益分析）

### 7. 实施路线图
- Gantt 图（Mermaid）
- 详细任务分解（WBS）
- 里程碑和交付物
- 资源需求和预算
- 风险和缓解措施

### 8. 持续改进计划
- 季度评估流程
- SLI/SLO 定义和跟踪
- 事后复盘流程
- 知识库建设
- 团队培训计划

### 9. 附录
- 完整资源清单（CSV 格式）
- 配置审计结果
- 合规检查清单
- 技术术语表
- 参考文档链接

## 混沌工程测试计划（Chaos Engineering Ready Data）

> **当用户选择需要"混沌工程测试计划"时**，按照本节规范输出结构化数据。该数据格式遵循 `assessment-output-spec.md` 规范，供下游 `chaos-engineering-on-aws` skill 直接消费。
>
> **完整规范文件**：参见同目录下的 `assessment-output-spec.md`

### 输出方式（两种，默认推荐方式 1）

1. **嵌入模式（推荐）**：在评估报告末尾添加 `## Chaos Engineering Ready Data` 附录章节，一份报告人机共读
2. **独立文件模式**：单独生成 `{project}-chaos-input-{date}.md`

### 必须包含的结构化章节

按照 `assessment-output-spec.md` 规范，混沌工程数据必须包含以下章节（**表头和字段名固定，内容按实际环境填写**）：

#### 1. 项目元数据

| 字段 | 必填 | 格式 | 说明 |
|------|------|------|------|
| 项目名称 | ✅ | 自由文本 | 客户系统名称 |
| 评估日期 | ✅ | YYYY-MM-DD | — |
| AWS 账户 | ✅ | 12 位数字 | 可多个，逗号分隔 |
| 主要区域 | ✅ | AWS region code | 如 `us-east-1`、`ap-northeast-1` |
| 其他区域 | ❌ | 逗号分隔 | 多区域架构时填写 |
| 环境类型 | ✅ | `production` / `staging` / `development` | — |
| 架构模式 | ✅ | 枚举值 | `EKS 微服务` / `ECS 容器化` / `Serverless` / `传统 EC2` / `多区域` / `混合` |
| 整体韧性评分 | ✅ | X.X / 5.0 | 1.0-5.0 |

#### 2. AWS 资源清单（含完整 ARN）

> **核心输入——没有 ARN 就无法创建 FIS 实验。**

**固定表头**：

| 资源 ID | 类型 | ARN | 名称 | 可用区 | 状态 | 备注 |
|---------|------|-----|------|--------|------|------|

**资源类型标准名**：

| 类别 | 标准名 |
|------|--------|
| 计算 | `EC2 实例` / `EKS 集群` / `EKS 节点组` / `ECS 集群` / `ECS 服务` / `Fargate 任务` / `Lambda 函数` / `Auto Scaling 组` |
| 网络 | `ALB` / `NLB` / `目标组` / `CloudFront` / `API Gateway` / `NAT 网关` / `VPC` / `子网` / `安全组` / `Route53 托管区` / `Transit Gateway` |
| 数据库 | `RDS 集群` / `RDS 实例` / `Aurora Global Database` / `DynamoDB 表` / `ElastiCache 集群` / `MemoryDB 集群` / `Neptune 集群` |
| 存储 | `S3 存储桶` / `EBS 卷` / `EFS 文件系统` |
| 消息 | `SQS 队列` / `SNS 主题` / `Kinesis 数据流` / `EventBridge 规则` |
| 其他 | `Step Functions 状态机` / `Cognito 用户池` / `Secrets Manager` |

#### 3. 关键业务功能与依赖链

**固定表头**：

| 业务功能 | 重要性 | 依赖链（资源 ID） | 当前 RTO | 目标 RTO | 当前 RPO | 目标 RPO |
|---------|--------|------------------|---------|---------|---------|---------|

**字段规范**：
- 重要性：`🔴 核心` / `🟠 重要` / `🟡 一般` / `🟢 低`
- 依赖链：资源 ID 用 `→` 连接，引用资源清单中的 ID
- RTO/RPO：数字 + `s`（秒）或 `未知` 或 `不适用`，**单位统一为秒**

#### 4. 风险清单（含可实验性标记）

> 在现有风险清单基础上**增加两列**：`可实验` 和 `建议注入方式`

**固定表头**：

| 风险 ID | 风险描述 | 故障类别 | 严重度 | 概率 | 影响 | 检测难度 | 修复复杂度 | 风险得分 | 可实验 | 建议注入方式 |
|---------|---------|---------|--------|------|------|---------|-----------|---------|--------|-----------|

**字段枚举值**：

| 字段 | 取值 |
|------|------|
| 故障类别 | `SPOF` / `过度负载` / `过度延迟` / `错误配置` / `共享命运` / `其他: {自定义}` |
| 严重度 | `🔴 严重` / `🟠 高` / `🟡 中` / `🟢 低` |
| 可实验 | `✅ 是` / `❌ 否（原因）` / `⚠️ 有前提` |
| 建议注入方式 | `FIS: {action}` / `ChaosMesh: {CRD}` / `手动` / `—` |

#### 5. 风险详情（可实验风险补充信息）

> 对每个 `可实验 = ✅/⚠️` 的风险，在详细分析中增加以下子表格：

**涉及资源表**：

| 资源 ID | 类型 | ARN | 在实验中的角色 |
|---------|------|-----|-------------|
| *(ID)* | *(类型)* | *(ARN)* | `注入目标` / `观测对象` / `影响对象` |

**建议实验表**：

| 注入工具 | Action | 目标资源 | 说明 | 前提条件 |
|---------|--------|---------|------|---------|
| FIS / ChaosMesh | *(action ID 或 CRD 类型)* | *(资源 ID)* | *(一句话说明)* | `无` 或具体前提 |

**其他必须字段**：
- **影响的业务功能**：引用"关键业务功能与依赖链"中的功能名称
- **现有缓解措施**：列表或 `无`

#### 6. 监控就绪度

> **混沌工程必须有监控才能定义稳态假设和停止条件。**

**整体就绪状态**: `🟢 就绪` / `🟡 部分就绪` / `🔴 未就绪`

**现有 CloudWatch 告警表**：

| 告警 ARN | 指标 | 阈值 | 周期 | 可作为 FIS Stop Condition |
|---------|------|------|------|------------------------|

**可用 CloudWatch 指标表**：

| 资源 | Namespace | 可用指标 | 说明 |
|------|-----------|---------|------|

**监控缺口**：列出缺失的关键监控

**就绪状态判断标准**：

| 状态 | 条件 | 混沌工程建议 |
|------|------|------------|
| 🟢 就绪 | 核心业务功能有告警覆盖，有可用的 Stop Condition | 可直接开始实验 |
| 🟡 部分就绪 | 有部分告警但核心功能未完全覆盖 | 补充关键告警后可实验 |
| 🔴 未就绪 | 无告警或严重缺失 | **必须先建立基础监控** |

#### 7. 韧性评分（9 维度，固定）

| 维度 | 评分 | 当前状态（一句话） |
|------|------|-----------------|
| 冗余设计 | ⭐ X/5 | *(描述)* |
| AZ 容错 | ⭐ X/5 | *(描述)* |
| 超时与重试 | ⭐ X/5 | *(描述)* |
| 断路器 | ⭐ X/5 | *(描述)* |
| 自动扩展 | ⭐ X/5 | *(描述)* |
| 配置防护 | ⭐ X/5 | *(描述)* |
| 故障隔离 | ⭐ X/5 | *(描述)* |
| 备份恢复 | ⭐ X/5 | *(描述)* |
| 最佳实践 | ⭐ X/5 | *(描述)* |

> **维度名称固定为以上 9 个**，不可更改或增减。

#### 8. 约束和偏好（可选）

| 约束项 | 值 | 说明 |
|--------|-----|------|
| 首选实验环境 | staging / production / development | — |
| 允许生产实验 | 是 / 否 | — |
| 维护窗口 | *(描述或 cron)* | — |
| 最大爆炸半径 | 单资源 / 单 AZ / 多 AZ / 区域 | — |
| Chaos Mesh 已安装 | 是 / 否 | — |
| FIS IAM Role 已创建 | 是 / 否 | — |
| 通知渠道 | *(渠道)* | — |

### 可实验性判断指南

供判断每个风险是否适合混沌实验：

| 条件 | 可实验 | 说明 |
|------|--------|------|
| 有对应的 FIS action 可注入 | ✅ 是 | 如 EC2 终止、RDS 故障转移、Lambda 延迟注入 |
| 有对应的 Chaos Mesh CRD | ✅ 是 | 如 Pod Kill、网络延迟、HTTP 故障 |
| 属于配置问题，无运行时故障可注入 | ❌ 否 | 如"EBS 未加密"、"日志未启用"、"缺少告警" |
| 需要先修复或配置才能测试 | ⚠️ 有前提 | 如"DynamoDB 需先启用 PITR 才能测试恢复" |
| 涉及安全/合规（非韧性） | ❌ 否 | 如"IAM 权限过宽"、"无 WAF" |
| 影响不可逆 | ❌ 否 | 如"删除无备份的唯一数据表" |
| 缺乏监控无法观测结果 | ⚠️ 有前提 | 前提：先建立基础监控 |

### 建议注入方式速查表

| 风险模式 | 推荐工具 | 推荐 Action |
|---------|---------|------------|
| EC2 单点故障 | FIS | `aws:ec2:terminate-instances` 或 `aws:ec2:stop-instances` |
| AZ 级故障 | FIS | `aws:network:disrupt-connectivity` |
| RDS/Aurora 故障转移 | FIS | `aws:rds:failover-db-cluster` |
| RDS 实例故障 | FIS | `aws:rds:reboot-db-instances` |
| DynamoDB 跨区域复制 | FIS | `aws:dynamodb:global-table-pause-replication` |
| Lambda 延迟 | FIS | `aws:lambda:invocation-add-delay` |
| Lambda 错误 | FIS | `aws:lambda:invocation-error` |
| EKS 节点故障 | FIS | `aws:eks:terminate-nodegroup-instances` |
| ECS 任务故障 | FIS | `aws:ecs:stop-task` |
| EBS 存储故障 | FIS | `aws:ebs:pause-volume-io` |
| ElastiCache AZ 故障 | FIS | `aws:elasticache:interrupt-cluster-az-power` |
| Spot 实例中断 | FIS | `aws:ec2:send-spot-instance-interruptions` |
| API 限流 | FIS | `aws:fis:inject-api-throttle-error` |
| S3 跨区域复制 | FIS | `aws:s3:bucket-pause-replication` |
| K8s Pod 故障 | Chaos Mesh | PodChaos: `pod-kill` / `pod-failure` |
| 微服务网络劣化 | Chaos Mesh | NetworkChaos: `delay` / `loss` / `partition` |
| HTTP 层故障 | Chaos Mesh | HTTPChaos: `abort` / `delay` |
| 资源竞争 | Chaos Mesh | StressChaos: `cpu` / `memory` |
| DNS 故障 | Chaos Mesh | DNSChaos: `error` / `random` |
| 文件 IO 故障 | Chaos Mesh | IOChaos: `latency` / `fault` |

### 输出检查清单

混沌工程数据生成后，对照以下清单确认完整性：

- [ ] **项目元数据**完整（账号 ID、区域、环境类型、**架构模式**、韧性评分）
- [ ] **AWS 资源清单**包含所有涉及资源的 **完整 ARN**
- [ ] **业务功能表**列出依赖链和 RTO/RPO（单位：秒）
- [ ] **风险清单**包含 `可实验` 和 `建议注入方式` 两列
- [ ] 所有 `可实验 = ✅/⚠️` 的风险详情中包含**涉及资源表**和**建议实验表**
- [ ] **监控就绪度**章节完整（就绪状态 + 现有告警 + 可用指标 + 缺口）
- [ ] **韧性评分** 9 维度表格完整，维度名称未更改
- [ ] **约束和偏好**已记录（如用户在评估过程中提到）
- [ ] **开放发现**章节已记录（超出模板框架的新发现）

### 开放发现（鼓励超越模板）

> ⚠️ **本规范定义的是最低要求，不是能力上限。** 以下三个开放章节鼓励记录超出模板框架的发现。

**额外发现的风险**：

| 风险 ID | 风险描述 | 自定义类别 | 为什么现有分类不适用 | 建议的验证方式（自由文本） |
|---------|---------|-----------|-------------------|----------------------|

**自定义实验建议**（非 FIS / 非 Chaos Mesh 方式）：

| 风险 ID | 验证方法 | 工具/脚本 | 说明 | 安全风险 |
|---------|---------|----------|------|---------|

**架构层面的开放观察**：
- 架构反模式（但不确定是否构成风险）
- 潜在的改进机会（非风险但值得关注）
- 与行业最佳实践的差距（非直接风险）

## 特别注意事项

在进行分析时，请特别关注：

### 1. 业务上下文
- 始终将技术风险与业务影响关联
- 考虑不同业务功能的重要性差异
- 平衡理想状态与实际可行性

### 2. 成本效益
- 每个建议都应包含成本估算
- 提供多个方案选项（低成本 vs 高韧性）
- 考虑 TCO（总拥有成本）而非仅首次投资

### 3. 安全与韧性平衡
- 安全控制不应削弱韧性（如过于严格的变更控制）
- 韧性措施不应引入安全漏洞（如过于宽松的 IAM 策略）
- 考虑 DDoS、勒索软件等安全事件对韧性的影响

### 4. 合规约束
- 某些合规要求可能限制架构选项（如数据驻留）
- 确保 DR 策略符合审计要求
- 文档和审计跟踪的重要性

### 5. 可操作性
- 所有建议必须具体、可执行
- 提供实际的配置参数、命令、代码
- 避免"提高可靠性"等空泛建议

### 6. 可视化优先
- 使用图表使复杂信息易于理解
- 每个主要部分至少一个可视化
- 优先使用 Mermaid 图表（便于版本控制）

### 7. 参考最新最佳实践
在分析时直接引用以下资源的具体章节：

**AWS 文档**：
- [AWS Resilience Analysis Framework](https://docs.aws.amazon.com/prescriptive-guidance/latest/resilience-analysis-framework/introduction.html)
  - 重点："识别单点故障"和"评估共享命运"
- [AWS Well-Architected - Reliability Pillar](https://docs.aws.amazon.com/wellarchitected/latest/reliability-pillar/welcome.html)
  - 重点："设计分布式系统的可靠性"和"规划恢复"
- [AWS Resilience Hub](https://docs.aws.amazon.com/resilience-hub/latest/userguide/what-is.html)
- [AWS Fault Injection Service](https://docs.aws.amazon.com/fis/latest/userguide/what-is.html)
- [混沌工程on AWS](https://docs.aws.amazon.com/prescriptive-guidance/latest/chaos-engineering-on-aws/overview.html)
- [AWS 灾难恢复策略](https://docs.aws.amazon.com/whitepapers/latest/disaster-recovery-workloads-on-aws/disaster-recovery-workloads-on-aws.html)
- [AWS 多区域架构基础](https://docs.aws.amazon.com/prescriptive-guidance/latest/aws-multi-region-fundamentals/introduction.html)

**其他资源**：
- [AWS Observability Best Practices](https://aws-observability.github.io/observability-best-practices/)
- [Chaos Engineering Principles](https://principlesofchaos.org/)
- NIST Cybersecurity Framework（如适用）

### 8. 持续对话
- 在分析过程中，如发现关键信息缺失，主动询问用户
- 提供中间结果供用户反馈
- 根据用户反馈调整分析深度和重点

## 开始分析

在启动分析前，我会首先询问你环境信息和业务背景。请准备好以下资料：

1. AWS 账户信息和访问权限
2. 架构文档或系统描述
3. 业务关键流程清单
4. 当前的 SLA/SLO（如有）
5. 预算和时间约束

让我们开始吧！请告诉我你希望评估哪个 AWS 环境，以及任何特定的关注点。

---

## 报告生成要求

**重要**：在完成所有分析任务后，**必须**自动生成易于阅读和分享的报告文件。

### 自动生成报告流程

1. **生成 Markdown 格式报告**

使用 Write 工具创建完整的 markdown 报告文件：

```markdown
文件名格式：{项目名称}-resilience-assessment-{日期}.md
例如：ecommerce-resilience-assessment-2026-02-28.md

报告应包含：
- 完整的目录结构（TOC）
- 所有 8 个分析任务的结果
- 所有 Mermaid 图表
- 表格、代码块、告警配置
- 执行摘要和关键发现
- 实施路线图
- 附录和参考资料
```

2. **生成 HTML 格式报告（使用美观模板）**

**推荐方法：使用交互式HTML模板**

使用预制的美观HTML模板（`html-report-template.html`），该模板包含：
- AWS品牌设计风格（橙色主题）
- Chart.js交互式图表（雷达图、甜甜圈图、柱状图、散点图）
- Mermaid架构图支持
- 响应式设计，支持移动端和打印
- 时间轴可视化
- 风险卡片颜色编码

**生成步骤**：

```python
# 使用Python脚本填充模板数据并生成HTML报告
python3 << 'EOF'
import json
from pathlib import Path

# 1. 读取HTML模板
template_path = Path(__file__).parent / 'html-report-template.html'
with open(template_path, 'r', encoding='utf-8') as f:
    html_template = f.read()

# 2. 准备评估数据（从分析结果中提取）
assessment_data = {
    "projectName": "{项目名称}",
    "assessmentDate": "{评估日期}",
    "overallScore": {总体评分},  # 1-5的评分

    # 统计数据
    "stats": {
        "totalRisks": {风险总数},
        "criticalRisks": {严重风险数},
        "currentRTO": "{当前RTO}",
        "estimatedCost": {预估月度成本}
    },

    # 韧性维度评分（9个维度）
    "resilienceDimensions": {
        "redundancy": {冗余设计评分},      # 1-5
        "azFaultTolerance": {AZ容错评分},
        "timeoutRetry": {超时重试评分},
        "circuitBreaker": {断路器评分},
        "autoScaling": {自动扩展评分},
        "configProtection": {配置防护评分},
        "faultIsolation": {故障隔离评分},
        "backupRecovery": {备份恢复评分},
        "bestPractices": {最佳实践评分}
    },

    # 风险分布
    "riskDistribution": {
        "critical": {严重风险数},
        "high": {高风险数},
        "medium": {中风险数},
        "low": {低风险数}
    },

    # 风险清单（按优先级排序）
    "risks": [
        {
            "id": "R-001",
            "title": "{风险标题}",
            "category": "{故障类别}",  # SPOF/过度延迟/过度负载/错误配置/共享命运
            "severity": "critical",     # critical/high/medium/low
            "probability": {概率评分},   # 1-5
            "impact": {影响评分},       # 1-5
            "detectionDifficulty": {检测难度}, # 1-5
            "remediationComplexity": {修复复杂度}, # 1-5
            "riskScore": {风险得分},
            "currentState": "{当前状态描述}",
            "recommendation": "{改进建议}",
            "estimatedCost": "{预估成本}",
            "implementation": "{实施时间}"
        }
        // ... 更多风险
    ],

    # 实施路线图（时间轴数据）
    "roadmap": [
        {
            "phase": "第一阶段：基础韧性",
            "startDate": "2026-03-01",
            "duration": "2个月",
            "tasks": [
                "Multi-AZ部署",
                "配置自动备份",
                "实施基础监控"
            ],
            "milestone": "M1: 基础冗余完成"
        }
        // ... 更多阶段
    ],

    # Mermaid架构图代码
    "architectureDiagram": "{mermaid图表代码}",
    "dependencyDiagram": "{依赖关系图代码}"
}

# 3. 将数据注入到HTML模板中（替换占位符）
html_output = html_template

# 替换基本信息
html_output = html_output.replace('{{PROJECT_NAME}}', assessment_data['projectName'])
html_output = html_output.replace('{{ASSESSMENT_DATE}}', assessment_data['assessmentDate'])
html_output = html_output.replace('{{OVERALL_SCORE}}', str(assessment_data['overallScore']))

# 替换统计数据
html_output = html_output.replace('{{TOTAL_RISKS}}', str(assessment_data['stats']['totalRisks']))
html_output = html_output.replace('{{CRITICAL_RISKS}}', str(assessment_data['stats']['criticalRisks']))
html_output = html_output.replace('{{CURRENT_RTO}}', assessment_data['stats']['currentRTO'])
html_output = html_output.replace('{{ESTIMATED_COST}}', str(assessment_data['stats']['estimatedCost']))

# 替换Chart.js数据
html_output = html_output.replace('{{RESILIENCE_DATA}}', json.dumps(list(assessment_data['resilienceDimensions'].values())))
html_output = html_output.replace('{{RISK_DISTRIBUTION_DATA}}', json.dumps(list(assessment_data['riskDistribution'].values())))

# 生成风险卡片HTML
risk_cards_html = ""
for risk in assessment_data['risks'][:10]:  # 只显示前10个风险
    severity_class = f"risk-{risk['severity']}"
    risk_cards_html += f"""
    <div class="risk-card {severity_class}">
        <div class="risk-header">
            <span class="risk-id">{risk['id']}</span>
            <span class="badge badge-{risk['severity']}">{risk['severity'].upper()}</span>
        </div>
        <h3>{risk['title']}</h3>
        <p class="risk-category">{risk['category']}</p>
        <div class="risk-metrics">
            <div>概率: {risk['probability']}/5</div>
            <div>影响: {risk['impact']}/5</div>
            <div>风险得分: {risk['riskScore']:.1f}</div>
        </div>
        <div class="risk-details">
            <p><strong>当前状态:</strong> {risk['currentState']}</p>
            <p><strong>改进建议:</strong> {risk['recommendation']}</p>
            <div class="risk-footer">
                <span class="badge">成本: {risk['estimatedCost']}</span>
                <span class="badge">时间: {risk['implementation']}</span>
            </div>
        </div>
    </div>
    """

html_output = html_output.replace('{{RISK_CARDS}}', risk_cards_html)

# 替换Mermaid图表
html_output = html_output.replace('{{ARCHITECTURE_DIAGRAM}}', assessment_data['architectureDiagram'])

# 4. 保存HTML文件
output_file = '{项目名称}-resilience-assessment-{日期}.html'
with open(output_file, 'w', encoding='utf-8') as f:
    f.write(html_output)

print(f'✅ 美观的HTML报告已生成: {output_file}')
print(f'💡 在浏览器中打开即可查看交互式报告')
EOF
```

**备选方法：使用Pandoc进行基础转换**

如果需要快速生成基础HTML版本：

```bash
pandoc {报告文件}.md \
  -f gfm \
  -t html5 \
  --standalone \
  --toc \
  --toc-depth=3 \
  --css=https://cdn.jsdelivr.net/npm/github-markdown-css@5/github-markdown.min.css \
  --metadata title="AWS 系统韧性评估报告" \
  -o {报告文件}-basic.html
```

3. **生成混沌工程数据（当用户选择需要时）**

如果用户选择需要混沌工程测试计划，按照 `assessment-output-spec.md` 规范生成结构化数据：

**方式 1：嵌入模式（推荐）**
在评估报告（Markdown 和 HTML）末尾添加 `## Chaos Engineering Ready Data` 附录章节，一份报告人机共读。

**方式 2：独立文件模式**
```markdown
文件名：{项目名称}-chaos-input-{日期}.md
例如：ecommerce-chaos-input-2026-02-28.md

内容：按照"混沌工程测试计划"部分的规范结构生成，
包含：项目元数据、AWS 资源清单（含 ARN）、业务功能依赖链、
风险清单（含可实验性标记和建议注入方式）、风险详情、
监控就绪度、韧性评分（9 维度）、约束和偏好、开放发现
```

**HTML 报告中的混沌工程数据**：
当用户选择混沌工程测试计划时，HTML 报告中也必须包含对应的可视化章节：
- **可实验风险卡片**：风险卡片增加 `可实验` 标记和 `建议注入方式` 标签
- **监控就绪度仪表盘**：用甜甜圈图显示就绪状态（就绪/部分就绪/未就绪）
- **注入方式分布图**：用柱状图显示 FIS / Chaos Mesh / 手动 / 不可实验的分布
- **资源 ARN 清单表**：可折叠的完整资源清单，含复制按钮
- **实验优先级矩阵**：散点图显示可实验风险的概率 vs 影响

4. **报告文件位置**

所有生成的报告文件应保存在当前工作目录：

```
{当前工作目录}/
├── {项目名称}-resilience-assessment-{日期}.md    (主报告 Markdown)
├── {项目名称}-resilience-assessment-{日期}.html   (主报告 HTML，含交互式图表)
└── {项目名称}-chaos-input-{日期}.md              (混沌工程数据，独立文件模式时生成，可选)
```

### 报告质量检查清单

在生成报告后，确保：

- ✅ 所有 Mermaid 图表语法正确（在 HTML 中可渲染）
- ✅ 所有表格格式正确对齐
- ✅ 代码块有正确的语法高亮标记（```bash, ```yaml, ```json 等）
- ✅ 中文和英文之间有适当的空格（提高可读性）
- ✅ 所有链接有效（内部锚点和外部 URL）
- ✅ 风险 ID、任务 ID 等引用一致
- ✅ HTML 文件在浏览器中显示正常

### 完成提示

生成报告后，向用户提供：

```markdown
✅ **AWS 韧性评估报告已生成**

📄 **Markdown 格式**：`{文件名}.md`
🌐 **交互式HTML格式**：`{文件名}.html`
🧪 **混沌工程数据**：`{文件名}-chaos-input.md`（如用户选择了混沌工程测试计划）

**HTML报告特性**：
✨ AWS品牌风格设计（橙色主题）
📊 交互式Chart.js图表（雷达图、甜甜圈图、柱状图、散点图）
🎨 风险卡片颜色编码（红色=严重、橙色=高、黄色=中、绿色=低）
📱 响应式设计，支持手机/平板/电脑查看
🖨️ 打印友好样式
⏱️ 时间轴可视化实施路线图
🏗️ Mermaid架构图支持
🧪 混沌工程数据可视化（可实验风险标记、监控就绪度、注入方式分布图，如适用）

**关键发现**：
1. {关键风险 1}
2. {关键风险 2}
3. {关键风险 3}

**优先建议**：
1. {建议 1}
2. {建议 2}
3. {建议 3}

**预计投资**：${总成本}/月
**预期效果**：年度停机时间从 {当前} 降至 {目标}

您可以：
- 在浏览器中打开交互式HTML报告，体验动态图表
- 使用Markdown编辑器编辑和自定义报告
- 从浏览器打印或导出为PDF用于分享
- 与团队成员共享HTML文件（无需额外依赖）
- 将混沌工程数据文件直接传递给 chaos-engineering-on-aws skill 使用（如适用）
```

### 工具安装检查

在尝试生成 HTML 之前，检查必要的工具和模板文件：

```bash
# 检查HTML模板文件是否存在
TEMPLATE_PATH="$HOME/.claude/skills/aws-resilience-assessment/html-report-template.html"

if [ -f "$TEMPLATE_PATH" ]; then
    echo "✅ 找到美观的HTML模板"
    echo "💡 推荐：使用交互式HTML模板生成报告（包含Chart.js可视化）"
    # 使用推荐的模板方法
elif command -v pandoc &> /dev/null; then
    echo "✅ 使用 pandoc 生成基础 HTML"
    echo "⚠️  提示：安装html-report-template.html可获得更美观的报告"
    # 使用pandoc备选方法
elif python3 -c "import markdown" 2>/dev/null; then
    echo "✅ 使用 Python markdown 库生成基础 HTML"
    echo "⚠️  提示：安装html-report-template.html可获得更美观的报告"
    # 使用Python markdown备选方法
else
    echo "⚠️  未找到 HTML 生成工具"
    echo "💡 推荐选项："
    echo "   1. 下载 html-report-template.html 到 skill 目录（最美观）"
    echo "   2. 安装 pandoc：brew install pandoc"
    echo "   3. 安装 Python markdown：pip3 install markdown"
    echo "📝 已生成 Markdown 报告，HTML 生成跳过"
fi
```

### 重要提醒

**每次分析结束后，必须执行报告生成流程**，这样用户可以：
- 在浏览器中轻松查看美观的报告
- 将报告分享给团队成员和管理层
- 保存报告作为历史记录
- 导出为 PDF 用于演示

不要只在对话中输出分析结果，**务必生成文件**！

### 报告格式注意事项

**报告结尾格式要求**：
- 在报告末尾只包含"报告生成日期"和"版本"信息
- **不要**添加联系方式（如 email 地址）
- **不要**添加署名或团队信息（如"本报告由...团队生成"）
- 保持报告结尾简洁专业

示例正确格式：
```markdown
---

**报告生成日期**: YYYY-MM-DD
**版本**: 1.0
```
