# Chaos Engineering 输入规范模板

> **用途**：本文件定义 `chaos-engineering-on-aws` skill 所需的结构化输入格式。  
> 请 `aws-resilience-modeling` skill 在生成韧性评估报告时，按照本规范的结构组织报告内容，确保混沌工程阶段可直接消费。  
>
> **两种输出方式（任选）**：
> 1. **嵌入模式**：在现有评估报告末尾添加 `## Chaos Engineering Ready Data` 附录章节
> 2. **独立文件模式**：单独生成 `{project}-chaos-input-{date}.md`
>
> **推荐方式 1**（一份报告，人机共读）
>
> ⚠️ **本规范定义的是结构（表头 + 字段 + 枚举值），不绑定任何特定系统。** 附录 A 提供了不同架构模式的填写示例。

---

## 1. 为什么需要这个规范？

Assessment 的自由格式 Markdown 报告面向人类阅读，但混沌工程 Skill 需要**一致的结构**来自动化以下步骤：
- 从风险清单中筛选可实验的风险
- 将逻辑资源名映射为真实 AWS 资源（ARN）
- 生成 FIS / Chaos Mesh 实验配置
- 设定稳态假设阈值和停止条件

**现有 Assessment 输出的问题**：

| 现状 | 改进要求 |
|------|---------|
| 风险描述是自由文本 | 统一枚举分类（`SPOF` / `过度负载` / `错误配置` / `共享命运` / `过度延迟`） |
| 涉及的 AWS 资源散落各处 | 统一资源清单表格，含完整 ARN |
| RTO 写"未知"/"不可恢复" | 使用 `未知` 或 `不适用`，单位统一为秒 |
| 无"能不能做实验"标记 | 每个风险标注是否可实验 + 原因 |
| 无建议注入方式 | 高/严重风险附带建议的 FIS action 或 Chaos Mesh CRD |
| 监控能力无结构化描述 | 统一的监控就绪度章节 |

---

## 2. 规范定义

以下为 Assessment 报告应包含的结构化章节。**表头和字段名是固定的**，内容按客户实际环境填写。

---

### 2.1 项目元数据

> 放在报告开头。

| 字段 | 必填 | 格式 | 说明 |
|------|------|------|------|
| 项目名称 | ✅ | 自由文本 | 客户系统名称 |
| 评估日期 | ✅ | YYYY-MM-DD | — |
| AWS 账户 | ✅ | 12 位数字 | 可多个，逗号分隔 |
| 主要区域 | ✅ | AWS region code | 如 `us-east-1`、`ap-northeast-1` |
| 其他区域 | ❌ | 逗号分隔 | 多区域架构时填写 |
| 环境类型 | ✅ | `production` / `staging` / `development` | — |
| 架构模式 | ✅ | 见下方枚举 | 帮助混沌工程 Skill 选择实验策略 |
| 整体韧性评分 | ✅ | X.X / 5.0 | 1.0-5.0 |

**架构模式枚举**：

| 架构模式 | 典型组件 | 混沌工程重点 |
|---------|---------|------------|
| `EKS 微服务` | EKS + ALB + RDS/DynamoDB | Pod 故障、服务间网络、数据库故障转移 |
| `ECS 容器化` | ECS/Fargate + ALB + RDS | 任务故障、服务发现、数据库 HA |
| `Serverless` | API Gateway + Lambda + DynamoDB + SQS/SNS | Lambda 延迟/错误、队列积压、DDB 限流 |
| `传统 EC2` | EC2 + ALB/NLB + RDS + ElastiCache | 实例终止、AZ 故障、数据库故障转移 |
| `多区域` | 以上任一 + Route53 + 跨区域复制 | 区域故障转移、复制延迟、DNS 切换 |
| `混合` | 以上多种组合 | 按各层分别设计实验 |

---

### 2.2 AWS 资源清单

> **核心输入**——没有 ARN 就无法创建 FIS 实验。列出评估中涉及的所有 AWS 资源。

**固定表头**：

| 资源 ID | 类型 | ARN | 名称 | 可用区 | 状态 | 备注 |
|---------|------|-----|------|--------|------|------|
| *(实例/集群/表等 ID)* | *(标准类型名)* | *(完整 ARN)* | *(资源名或标签)* | *(AZ 或 AZ 列表)* | *(running/active 等)* | *(Assessment 关键发现)* |

**资源类型标准名**（优先使用以下名称；如果客户使用了不在列表中的 AWS 服务，**自行添加类型名即可**，格式为 `{服务} {资源}`）：

| 类别 | 标准名 |
|------|--------|
| 计算 | `EC2 实例` / `EKS 集群` / `EKS 节点组` / `ECS 集群` / `ECS 服务` / `Fargate 任务` / `Lambda 函数` / `Auto Scaling 组` |
| 网络 | `ALB` / `NLB` / `目标组` / `CloudFront` / `API Gateway` / `NAT 网关` / `VPC` / `子网` / `安全组` / `Route53 托管区` / `Transit Gateway` |
| 数据库 | `RDS 集群` / `RDS 实例` / `Aurora Global Database` / `DynamoDB 表` / `ElastiCache 集群` / `MemoryDB 集群` / `Neptune 集群` |
| 存储 | `S3 存储桶` / `EBS 卷` / `EFS 文件系统` |
| 消息 | `SQS 队列` / `SNS 主题` / `Kinesis 数据流` / `EventBridge 规则` |
| 其他 | `Step Functions 状态机` / `Cognito 用户池` / `Secrets Manager` |

---

### 2.3 关键业务功能与依赖链

> 列出系统的关键业务功能、依赖的组件链、以及 RTO/RPO。

**固定表头**：

| 业务功能 | 重要性 | 依赖链（资源 ID） | 当前 RTO | 目标 RTO | 当前 RPO | 目标 RPO |
|---------|--------|------------------|---------|---------|---------|---------|
| *(功能名称)* | *(重要性标记)* | *(ID → ID → ID)* | *(秒/未知/不适用)* | *(秒)* | *(秒/未知/不适用)* | *(秒/不适用)* |

**字段规范**：

| 字段 | 取值 | 说明 |
|------|------|------|
| 重要性 | `🔴 核心` / `🟠 重要` / `🟡 一般` / `🟢 低` | 对应 critical/high/medium/low |
| 依赖链 | 资源 ID 用 `→` 连接 | 引用 2.2 资源清单中的资源 ID |
| RTO/RPO | 数字 + `s`（秒）或 `未知` 或 `不适用` | **单位统一为秒**。`未知` = 没测过；`不适用` = 该维度无意义 |

---

### 2.4 风险清单（含可实验性标记）

> 在现有风险清单基础上**增加两列**：`可实验` 和 `建议注入方式`。

**固定表头**：

| 风险 ID | 风险描述 | 故障类别 | 严重度 | 概率 | 影响 | 检测难度 | 修复复杂度 | 风险得分 | 可实验 | 建议注入方式 |
|---------|---------|---------|--------|------|------|---------|-----------|---------|--------|-----------|
| R-XXX | *(描述)* | *(类别)* | *(严重度)* | 1-5 | 1-5 | 1-5 | 1-5 | *(得分)* | *(标记)* | *(工具: action)* |

**字段枚举值**：

| 字段 | 取值 | 说明 |
|------|------|------|
| 故障类别 | `SPOF` / `过度负载` / `过度延迟` / `错误配置` / `共享命运` / `其他: {自定义}` | 来自 AWS Resilience Analysis Framework。**5 类不够时可用 `其他: {描述}` 扩展** |
| 严重度 | `🔴 严重` / `🟠 高` / `🟡 中` / `🟢 低` | — |
| 可实验 | `✅ 是` / `❌ 否（原因）` / `⚠️ 有前提` | **关键字段**，判断指南见第 3 节 |
| 建议注入方式 | `FIS: {action}` / `ChaosMesh: {CRD}` / `手动` / `—` | 速查表见第 4 节，不可实验则填 `—` |

---

### 2.5 风险详情（可实验风险补充信息）

> 对每个 `可实验 = ✅/⚠️` 的风险，在详细分析中增加以下结构化内容：

**必须包含的子表格**：

#### 涉及资源表

| 资源 ID | 类型 | ARN | 在实验中的角色 |
|---------|------|-----|-------------|
| *(ID)* | *(类型)* | *(ARN)* | `注入目标` / `观测对象` / `影响对象` |

#### 建议实验表

| 注入工具 | Action | 目标资源 | 说明 | 前提条件 |
|---------|--------|---------|------|---------|
| FIS / ChaosMesh | *(action ID 或 CRD 类型)* | *(资源 ID)* | *(一句话说明)* | `无` 或具体前提 |

#### 其他必须字段

- **影响的业务功能**：引用 2.3 中的功能名称
- **现有缓解措施**：列表或 `无`

---

### 2.6 监控就绪度

> **新增章节**。混沌工程必须有监控才能定义稳态假设和停止条件。

**固定结构**：

```markdown
## 监控就绪度

**整体就绪状态**: 🟢 就绪 / 🟡 部分就绪 / 🔴 未就绪
```

#### 现有 CloudWatch 告警表

| 告警 ARN | 指标 | 阈值 | 周期 | 可作为 FIS Stop Condition |
|---------|------|------|------|------------------------|
| *(ARN 或"无")* | — | — | — | 是 / 否 |

#### 可用 CloudWatch 指标表

| 资源 | Namespace | 可用指标 | 说明 |
|------|-----------|---------|------|
| *(资源 ID)* | *(AWS/XXX)* | *(指标列表)* | — |

#### 监控缺口（列表）

**就绪状态判断标准**：

| 状态 | 条件 | 混沌工程建议 |
|------|------|------------|
| 🟢 就绪 | 核心业务功能有告警覆盖，有可用的 Stop Condition | 可直接开始实验 |
| 🟡 部分就绪 | 有部分告警但核心功能未完全覆盖 | 补充关键告警后可实验 |
| 🔴 未就绪 | 无告警或严重缺失 | **必须先建立基础监控** |

---

### 2.7 韧性评分（9 维度）

> 使用**固定的维度名称和 1-5 评分**。

**固定表头**：

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

**维度名称固定为以上 9 个**，不可更改或增减。如果发现了不属于以上 9 维度的韧性问题，在评分表之后用自由文本记录。

---

### 2.8 约束和偏好（可选）

> 如果 Assessment 过程中用户提到了实验偏好，记录在此。

**固定表头**：

| 约束项 | 值 | 说明 |
|--------|-----|------|
| 首选实验环境 | staging / production / development | — |
| 允许生产实验 | 是 / 否 | — |
| 维护窗口 | *(描述或 cron)* | — |
| 最大爆炸半径 | 单资源 / 单 AZ / 多 AZ / 区域 | — |
| Chaos Mesh 已安装 | 是 / 否 | — |
| FIS IAM Role 已创建 | 是 / 否 | — |
| 通知渠道 | *(渠道)* | — |

---

## 3. `testable`（可实验性）判断指南

供 Assessment Skill 判断每个风险是否适合混沌实验：

| 条件 | 可实验 | 说明 |
|------|--------|------|
| 有对应的 FIS action 可注入 | ✅ 是 | 如 EC2 终止、RDS 故障转移、Lambda 延迟注入 |
| 有对应的 Chaos Mesh CRD | ✅ 是 | 如 Pod Kill、网络延迟、HTTP 故障 |
| 属于配置问题，无运行时故障可注入 | ❌ 否 | 如"EBS 未加密"、"日志未启用"、"缺少告警" |
| 需要先修复或配置才能测试 | ⚠️ 有前提 | 如"DynamoDB 需先启用 PITR 才能测试恢复" |
| 涉及安全/合规（非韧性） | ❌ 否 | 如"IAM 权限过宽"、"无 WAF" |
| 影响不可逆 | ❌ 否 | 如"删除无备份的唯一数据表" |
| 缺乏监控无法观测结果 | ⚠️ 有前提 | 前提：先建立基础监控 |

---

## 4. 建议注入方式速查表

供 Assessment Skill 为可实验风险推荐工具和 action：

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

---

## 5. Assessment 输出检查清单

Assessment 完成后，对照以下清单确认输出完整性：

- [ ] **项目元数据**完整（账号 ID、区域、环境类型、**架构模式**、韧性评分）
- [ ] **AWS 资源清单**包含所有涉及资源的 **完整 ARN**
- [ ] **业务功能表**列出依赖链和 RTO/RPO（单位：秒）
- [ ] **风险清单**包含 `可实验` 和 `建议注入方式` 两列
- [ ] 所有 `可实验 = ✅/⚠️` 的风险详情中包含**涉及资源表**和**建议实验表**
- [ ] **监控就绪度**章节完整（就绪状态 + 现有告警 + 可用指标 + 缺口）
- [ ] **韧性评分** 9 维度表格完整，维度名称未更改
- [ ] **约束和偏好**已记录（如用户在评估过程中提到）
- [ ] **开放发现**章节已记录（超出模板框架的新发现）

---

## 6. 开放发现（鼓励 LLM 超越模板）

> ⚠️ **本规范定义的是最低要求，不是能力上限。** 以下三个开放章节鼓励 Assessment 和 Chaos Skill 的 LLM 记录超出模板框架的发现。

### 6.1 Assessment 阶段：额外发现的风险

> 如果 Assessment LLM 在分析过程中发现了不属于 5 种标准故障类别的风险，或速查表中没有对应注入方式的风险，**不要丢弃**，记录在此。

```markdown
## 额外发现

### 超出标准分类的风险

| 风险 ID | 风险描述 | 自定义类别 | 为什么现有分类不适用 | 建议的验证方式（自由文本） |
|---------|---------|-----------|-------------------|----------------------|
| R-EXT-001 | 第三方 API 供应商 SLA 不透明 | 供应链风险 | 非 AWS 资源，不属于 5 类 | 模拟第三方 API 超时/错误，观测降级行为 |
| R-EXT-002 | DNS TTL 过长导致故障转移延迟 | 恢复延迟 | 介于"配置"和"延迟"之间 | 修改 TTL 后用 FIS 模拟 AZ 故障，测量实际切换时间 |

### 实验过程中新发现的风险

> 混沌工程 Skill 在执行实验时发现的、Assessment 阶段未识别的新风险。**实验后回填此表。**

| 发现来源（实验 ID） | 新风险描述 | 严重度 | 建议 |
|-------------------|-----------|--------|------|
| *(实验执行后填写)* | | | |
```

### 6.2 自定义实验方法

> 如果 LLM 认为某个风险可以通过**非 FIS / 非 Chaos Mesh** 的方式验证（如 AWS CLI 脚本、SSM Run Command、自定义 Lambda 等），在此记录。

```markdown
### 自定义实验建议

| 风险 ID | 验证方法 | 工具/脚本 | 说明 | 安全风险 |
|---------|---------|----------|------|---------|
| R-XXX | AWS CLI 脚本 | `aws ec2 modify-instance-attribute --no-source-dest-check` | 修改网络属性观测影响 | 需回滚 |
| R-XXX | SSM Run Command | stress-ng 内存压力 | 在实例上直接注入压力 | 影响范围可控 |
```

### 6.3 架构层面的开放观察

> Assessment 过程中发现的、不直接对应某个风险 ID 的架构层面观察。例如：
> - 架构反模式（但不确定是否构成风险）
> - 潜在的改进机会（非风险但值得关注）
> - 与行业最佳实践的差距（非直接风险）

```markdown
### 开放观察

1. **观察**: EKS 集群使用 managed node group 但未配置 Cluster Autoscaler，高峰期可能资源不足
   **建议**: 考虑在混沌实验中加入负载压力测试，验证弹性边界

2. **观察**: 所有微服务共享同一个 DynamoDB 表，缺乏数据隔离
   **建议**: 可作为"共享命运"风险进一步评估
```

---

## 附录 A：不同架构模式的填写示例

> 以下示例展示不同类型客户系统如何填写本规范。仅展示关键差异部分。

### A.1 EKS 微服务架构（如 VotingApp）

**元数据**：
```
架构模式: EKS 微服务
```

**资源清单典型行**：

| 资源 ID | 类型 | ARN | 备注 |
|---------|------|-----|------|
| my-cluster | EKS 集群 | arn:aws:eks:us-east-2:123456789012:cluster/my-cluster | v1.32，6 节点 |
| my-table | DynamoDB 表 | arn:aws:dynamodb:us-east-2:123456789012:table/my-table | 无 PITR |
| nat-0abc123 | NAT 网关 | arn:aws:ec2:us-east-2:123456789012:natgateway/nat-0abc123 | 单 AZ |

**典型可实验风险**：

| 风险 ID | 可实验 | 建议注入方式 |
|---------|--------|-----------|
| R-001 | ✅ | FIS: `aws:eks:terminate-nodegroup-instances` |
| R-002 | ✅ | ChaosMesh: PodChaos `pod-kill` |
| R-003 | ✅ | ChaosMesh: NetworkChaos `delay` |

---

### A.2 Serverless 架构（如电商后端）

**元数据**：
```
架构模式: Serverless
```

**资源清单典型行**：

| 资源 ID | 类型 | ARN | 备注 |
|---------|------|-----|------|
| order-api | API Gateway | arn:aws:apigateway:us-east-1::/restapis/abc123 | REST API |
| process-order | Lambda 函数 | arn:aws:lambda:us-east-1:123456789012:function:process-order | 128MB，30s 超时 |
| orders-table | DynamoDB 表 | arn:aws:dynamodb:us-east-1:123456789012:table/orders | PAY_PER_REQUEST |
| order-events | SQS 队列 | arn:aws:sqs:us-east-1:123456789012:order-events | 标准队列 |

**典型可实验风险**：

| 风险 ID | 可实验 | 建议注入方式 |
|---------|--------|-----------|
| R-001 | ✅ | FIS: `aws:lambda:invocation-add-delay`（Lambda 冷启动 + 延迟） |
| R-002 | ✅ | FIS: `aws:fis:inject-api-throttle-error`（API 限流） |
| R-003 | ✅ | FIS: `aws:dynamodb:global-table-pause-replication`（DDB 复制中断） |

**监控就绪度典型差异**：
- Serverless 通常自带 CloudWatch 指标（Lambda Duration/Errors/Throttles）
- 监控就绪度更可能是 🟡 部分就绪

---

### A.3 传统 EC2 三层架构（如企业内部系统）

**元数据**：
```
架构模式: 传统 EC2
```

**资源清单典型行**：

| 资源 ID | 类型 | ARN | 备注 |
|---------|------|-----|------|
| i-0abc123 | EC2 实例 | arn:aws:ec2:ap-northeast-1:123456789012:instance/i-0abc123 | Web Server |
| my-alb | ALB | arn:aws:elasticloadbalancing:ap-northeast-1:123456789012:loadbalancer/app/my-alb/abc | 跨 2 AZ |
| my-db-cluster | RDS 集群 | arn:aws:rds:ap-northeast-1:123456789012:cluster:my-db-cluster | Aurora Multi-AZ |
| my-cache | ElastiCache 集群 | arn:aws:elasticache:ap-northeast-1:123456789012:replicationgroup:my-cache | Redis 3 节点 |

**典型可实验风险**：

| 风险 ID | 可实验 | 建议注入方式 |
|---------|--------|-----------|
| R-001 | ✅ | FIS: `aws:ec2:terminate-instances`（EC2 故障） |
| R-002 | ✅ | FIS: `aws:rds:failover-db-cluster`（Aurora 故障转移） |
| R-003 | ✅ | FIS: `aws:elasticache:interrupt-cluster-az-power`（缓存 AZ 故障） |
| R-004 | ✅ | FIS: `aws:network:disrupt-connectivity`（AZ 网络中断） |

---

### A.4 多区域架构（如全球 SaaS 平台）

**元数据**：
```
架构模式: 多区域
主要区域: us-east-1
其他区域: eu-west-1, ap-southeast-1
```

**资源清单需包含多区域资源**：

| 资源 ID | 类型 | ARN | 备注 |
|---------|------|-----|------|
| global-table | DynamoDB 表 | arn:aws:dynamodb:us-east-1:123456789012:table/global-table | 全局表，3 区域 |
| primary-db | Aurora Global Database | arn:aws:rds:us-east-1:123456789012:global-cluster:my-global-db | 主集群 us-east-1 |
| dns-zone | Route53 托管区 | arn:aws:route53:::hostedzone/Z1234567 | 故障转移路由策略 |

**典型可实验风险**：

| 风险 ID | 可实验 | 建议注入方式 |
|---------|--------|-----------|
| R-001 | ✅ | FIS: `aws:dynamodb:global-table-pause-replication`（跨区域复制中断） |
| R-002 | ✅ | FIS: `aws:s3:bucket-pause-replication`（S3 复制中断） |
| R-003 | ✅ | FIS: `aws:network:route-table-disrupt-cross-region-connectivity`（跨区域网络） |
| R-004 | ✅ | FIS: `aws:arc:start-zonal-autoshift`（AZ 自动流量迁移） |

---

*本规范由 `chaos-engineering-on-aws` skill 定义，反馈给 `aws-resilience-modeling` skill 设计者*  
*版本：1.2 | 日期：2026-03-23*
