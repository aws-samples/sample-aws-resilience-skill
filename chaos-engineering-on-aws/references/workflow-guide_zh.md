# 混沌工程工作流指南 — 详细指令

> 本文件包含运行混沌实验的详细分步指令。
> 主 SKILL 文件（SKILL_ZH.md）提供概览和指针。
> 需要某个步骤的完整流程时，阅读本文件。

## 前置输入

### 输入方式（M1 支持三种）

1. **方式 1**：指定 Assessment 报告文件路径 → 解析 Markdown 结构化章节
2. **方式 2**：指定独立的 chaos-input 文件 → 解析 `{project}-chaos-input-{date}.md`
3. **方式 3**：指定 `eks-resilience-checker` 的 assessment.json → 解析 K8s 韧性检查结果

用户没有报告 → 引导其先运行 `aws-resilience-modeling` Skill。
用户需要 EKS 专项韧性检查 → 引导其先运行 `eks-resilience-checker` Skill。

#### 方式 3：eks-resilience-checker 集成

用户提供 `eks-resilience-checker` 生成的 `assessment.json` 时：

1. 读取 `experiment_recommendations` 数组
2. 按 `priority` 排序（P0 → P1 → P2）
3. 每条建议包含：
   - `suggested_fault_type` — 映射到 `fault-catalog.yaml` 中的类型（如 `pod_kill`、`network_delay`）
   - `target_resources` — 未通过检查的具体 K8s 资源
   - `hypothesis` — 需要验证的内容
4. 如果同时提供了方式 1 或方式 2 的输入，合并并去重实验目标
5. 把合并后的列表呈现给用户确认

### 输入完整性检查

启动时按以下清单检查 Assessment 报告：

```
✅/❌ 项目元数据（账号、Region、环境类型、架构模式、韧性评分）
✅/❌ AWS 资源清单（含完整 ARN）
✅/❌ 业务功能表（含依赖链和 RTO/RPO，单位秒）
✅/❌ 风险清单（含"可实验"和"建议注入方式"列）
✅/❌ 可实验风险详情（含受影响资源和建议实验）
✅/❌ 监控就绪度（状态 + 告警 + 指标 + 缺口）
✅/❌ 韧性评分（9 个维度全部完整）
✅/❌ 约束和偏好已记录（如有）
```

缺失数据处理：ARN 缺失 → 用 AWS CLI 补充扫描；"可实验"标记缺失 → 自行评估；监控就绪度缺失 → 假定为 🔴 未就绪。

## 状态持久化

文件即状态——每一步的输出都作为检查点：

```
output/
├── checkpoints/
│   ├── step1-scope.json          # 目标系统、资源清单
│   ├── step2-assessment.json     # 弱点、实验建议、compatibility[]
│   ├── step2-dependencies.json   # Impact Target 发现证据（§ 2.2）
│   ├── step3-experiment.json     # FIS 实验模板定义
│   ├── step4-validation.json     # Pre-flight 检查、用户确认
│   └── step5-experiment.json     # FIS 实验状态、ID、时间线
├── monitoring/
│   ├── step5-metrics.jsonl       # 监控脚本流式输出的指标
│   ├── step5-logs.jsonl          # 原始应用日志 JSONL
│   ├── step5-log-summary.json    # 分类后的日志摘要
│   ├── metric-queries.json       # CloudWatch 指标查询定义
│   ├── app-map.json              # 需要采集日志的工作负载（§ 2.2 → log-collector --app-map）
│   └── experiment_id.txt         # FIS 实验 ID
├── templates/                    # 生成的 FIS / Chaos Mesh 模板
├── kubeconfigs/                  # 每个被扫描的 EKS 集群各一个隔离的 kubeconfig
├── step6-report.md           # 最终报告（Markdown）
├── step6-report.html         # 最终报告（HTML，内联 CSS）
├── baseline-{timestamp}.json # 稳态基线快照
└── state.json                # 进度元数据
```

启动时检查 `output/state.json`——如果存在且未完成 → 提示用户继续还是重新开始。

### state.json Schema（v2）

```json
{
  "version": 2,
  "created_at": "2026-04-15T17:20:00Z",
  "updated_at": "2026-04-15T17:30:00Z",
  "workflow": {
    "current_step": 5,
    "current_phase": "executing",
    "status": "in_progress"
  },
  "steps": {
    "1": {"status": "completed", "started_at": "...", "completed_at": "..."},
    "2": {"status": "completed", "started_at": "...", "completed_at": "..."},
    "3": {"status": "completed", "started_at": "...", "completed_at": "..."},
    "4": {"status": "completed", "started_at": "...", "completed_at": "..."},
    "5": {"status": "in_progress", "started_at": "...", "phase": "executing"},
    "6": {"status": "pending"}
  },
  "experiments": [
    {
      "id": "EXP-001",
      "name": "EC2 Instance Termination",
      "status": "completed",
      "result": "PASSED",
      "fis_id": "EXP-abcdef",
      "started_at": "...",
      "completed_at": "...",
      "elapsed_seconds": 323
    },
    {
      "id": "EXP-002",
      "name": "EKS Node Termination",
      "status": "running",
      "fis_id": "EXP-123456",
      "started_at": "...",
      "background_pids": {
        "runner": 12345,
        "monitor": 12346,
        "log_collector": 12347
      }
    }
  ],
  "recovery_info": {
    "can_resume": true,
    "resume_from": "EXP-002",
    "last_agent_action": "launched background scripts for EXP-002",
    "background_processes_running": true
  }
}
```

### 会话中断恢复

用户恢复会话时（新对话、上下文重置、IDE 重启）：

1. **第一个动作**：读取 `output/state.json`
   ```bash
   cat output/state.json 2>/dev/null || echo '{"status":"not_started"}'
   ```
   - 不存在 → 全新开始
   - `status: completed` → 告知用户，提供查看报告的选项
   - `status: in_progress` → 进入恢复流程

2. **恢复流程**：
   a. 检查后台 PID：`kill -0 <pid> 2>/dev/null`
      - 存活 → 读取最新的输出文件，继续等待
      - 已退出 → 检查实验结果文件
   b. 对仍在运行的实验，查询实际状态：
      - FIS：`aws fis get-experiment --id <id>`
      - Chaos Mesh：`kubectl get <kind> <name> -n <ns>`
   c. 把实际状态映射到恢复动作：

      | 实际状态 | 动作 |
      |--------------|--------|
      | running | 重启 monitor.sh，继续观测 |
      | completed | 记录结果，进入下一个实验 |
      | failed | 记录失败，进入下一个实验 |
      | not found | 标记为 ABORTED，进入下一个 |

   d. 用恢复结果更新 state.json
   e. 向用户报告：
      ```
      📋 会话恢复：
      ✅ EXP-001 EC2 Terminate — PASSED（5m 23s）
      ⚠️ EXP-002 Node Kill — 原先在运行，FIS 显示 completed → 正在记录结果
      ⬜ EXP-003 Pod Kill — 排队中
      从 EXP-002 的结果分析处继续……
      ```

3. 从恢复到的位置继续工作流

## 步骤 1：定义实验目标

**消费**：风险清单 (2.4) + 项目元数据 (2.1)

1. 读取风险清单，筛选 `Experimentable = ✅` 和 `⚠️ Has prerequisites` 的风险
2. 按风险评分排序，推荐 Top N
3. `⚠️ Has prerequisites` → 列出前置条件，询问用户
4. 按架构模式调整策略重点：
   - EKS 微服务 → Pod/网络/服务间故障
   - Serverless → Lambda 延迟/限流
   - 传统 EC2 → 实例/AZ/数据库故障
   - 多 Region → 跨区域复制/故障转移
5. 与用户确认范围和优先级
6. 检测 Chaos Mesh（EKS 目标必须执行）：
   ```bash
   # 主检查
   CM_INSTALLED=$(kubectl get crd podchaos.chaos-mesh.org >/dev/null 2>&1 && echo "true" || echo "false")
   # 主检查失败时，尝试检查 namespace
   if [[ "$CM_INSTALLED" != "true" ]]; then
       CM_INSTALLED=$(kubectl get ns chaos-mesh >/dev/null 2>&1 && echo "true" || echo "false")
   fi
   # 仍未找到时，尝试 helm
   if [[ "$CM_INSTALLED" != "true" ]]; then
       CM_INSTALLED=$(helm list -A 2>/dev/null | grep -q chaos-mesh && echo "true" || echo "false")
   fi
   ```
   **把结果持久化到 step1-scope.json**：`"chaos_mesh_installed": true/false, "chaos_mesh_namespace": "...", "chaos_mesh_version": "..."`
   后续所有步骤**必须**从 step1-scope.json 读取 `chaos_mesh_installed`。
   如果已检测到 Chaos Mesh，步骤 6 的建议中**不得**出现"安装 Chaos Mesh"。

**输出**：`output/checkpoints/step1-scope.json`

**用户交互**：确认实验目标、环境和时间窗口

## 步骤 2：选择目标资源

**消费**：资源清单 (2.2) + 风险详情资源表 (2.5)

1. 从 2.5 节提取目标风险的资源 ARN
2. 验证 ARN 可用性：
   ```bash
   aws ec2 describe-instances --instance-ids <id>
   aws eks describe-cluster --name <name>
   aws rds describe-db-clusters --db-cluster-identifier <id>
   ```
3. 补充缺失的关联资源（SG、TG 等）
4. 计算爆炸半径（基于 2.3 中的依赖链）
5. 标记资源角色：`Injection Target`（注入目标）/ `Observation Target`（观测目标）/ `Impact Target`（影响目标）
6. 找出依赖每个 Injection Target 的工作负载（§ 2.2）——它们就是
   Impact Target，也是步骤 5 的日志来源

### 2.1 资源与 action 兼容性检查（强制，不通过则不进入步骤 3）

ARN 存在，不代表所选 action 能以它为目标。对每个候选 FIS action（包括 Scenario
Library 场景中裁剪后保留下来的每个子 action），在生成任何模板**之前**，检查该
action 的目标资源类型与真实资源是否匹配：

```bash
# 1. 这个 action 实际以什么为目标？
aws fis get-action --id "<ACTION_ID>" --region "$REGION" \
  --query 'action.targets' --output json
# 2. 这个资源实际是什么？（按资源类型选下表对应行）
```

| 资源 | 命令 | 决定兼容性的字段 |
|---|---|---|
| RDS 实例 | `aws rds describe-db-instances --db-instance-identifier <ID>` | `Engine`、`DBClusterIdentifier`、`MultiAZ` |
| Aurora / RDS 集群 | `aws rds describe-db-clusters --db-cluster-identifier <ID>` | `Engine`、`EngineMode`、`MultiAZ`、reader 数量 |
| EC2 实例 | `aws ec2 describe-instances --instance-ids <ID>` | `InstanceLifecycle`、`Placement.AvailabilityZone` |
| ElastiCache | `aws elasticache describe-replication-groups --replication-group-id <ID>` | `MultiAZ`、`AutomaticFailover`、`ClusterEnabled` |
| EKS 集群 | `aws eks describe-cluster --name <NAME>` | `accessConfig.authenticationMode`（FIS `aws:eks:pod-*` 需要 `API` 或 `API_AND_CONFIG_MAP`） |
| ASG | `aws autoscaling describe-auto-scaling-groups --auto-scaling-group-names <NAME>` | `AvailabilityZones`、每个 AZ 的实例数 |

已知的不兼容组合：

| Action | 目标类型 | 不兼容的对象 | 判断依据 | 替代方案 |
|---|---|---|---|---|
| `aws:rds:failover-db-cluster` | `aws:rds:cluster` | 独立 RDS（非 Aurora、非 Multi-AZ 集群） | `DBClusterIdentifier` 为 null | `aws:rds:reboot-db-instances` 配合 `forceFailover=true`（Multi-AZ 实例） |
| `aws:rds:reboot-db-instances` | `aws:rds:db` | 期望在 Aurora 上做集群级故障转移 | `Engine` 以 `aurora` 开头 | `aws:rds:failover-db-cluster` |
| `aws:elasticache:replicationgroup-interrupt-az-power` | `aws:elasticache:replicationgroup` | 独立缓存节点、单 AZ 复制组 | 没有复制组 / `MultiAZ` 未启用 | 先修正拓扑；或使用 SSM 模板 `elasticache-redis-primary-node-reboot` |
| `aws:ec2:stop-instances` | `aws:ec2:instance` | Spot 实例 | `InstanceLifecycle` = `spot` | `aws:ec2:send-spot-instance-interruptions` |
| `aws:ec2:send-spot-instance-interruptions` | `aws:ec2:spot-instance` | On-Demand 实例 | 不存在 `InstanceLifecycle` | `aws:ec2:stop-instances` / `terminate-instances` |
| `aws:fis:inject-api-*` | `aws:iam:role` | `ec2` / `kinesis` 以外的任何服务 | `service` 参数 | 该服务的专用 action（见 `fault-catalog.yaml` 的 `NOT_supported`） |
| Aurora MySQL 故障注入 SQL（`ALTER SYSTEM CRASH` 等） | — | `aurora-postgresql` | `Engine` | `aws:rds:reboot-db-instances` / `failover-db-cluster` |

同时检查 target 语法（[FIS targets](https://docs.aws.amazon.com/fis/latest/userguide/targets.html)）：
同一个 target 不能同时使用 `resourceArns` 和 `resourceTags`，也不能同时使用 `resourceArns` 和
`filters`。要限定在某个 AZ，要么只列出该 AZ 的 ARN，要么使用 `resourceTags` + 类似
`Placement.AvailabilityZone` 的 filter。

判定：兼容 → 继续。不兼容 → 用你读到的字段值说明不匹配之处，从上表给出替代
action，由用户确认替换或放弃该实验。**不得**悄悄更换 action 来"修复"。把每项检查记录到
`step2-assessment.json` 的 `compatibility[]` 中，格式为
`{action_id, target_type, resource_arn, decisive_field, value, result}`。

### 2.2 影响目标发现（依赖工作负载）

评估报告中的依赖链说明了哪些*服务*依赖某个资源，但很少说明是哪些 *pod*。在确认
爆炸半径之前，找出本 Region 内所有实际指向 Injection Target 的 EKS 工作负载：

```bash
bash scripts/discover-dependencies.sh --region "$REGION" \
    --resource rds-cluster:<db-cluster-id> \
    --resource elasticache:<replication-group-id> \
    --output-dir output/
# 其他类型：rds-instance:<id>  msk:<cluster-arn>  opensearch:<domain>  ec2:<instance-id>
# 额外的匹配字符串（资源前面的 CNAME）：--match label=db.internal.example.com
# 也扫描 Secret 的 KEY 名称（需要对 secrets 的 RBAC list 权限，绝不读取值）：--scan-secret-keys
```

它做的事：
- 通过 AWS API 解析每个资源的全部真实端点（集群的 writer、reader、自定义端点及成员
  实例；ElastiCache 的每个节点端点；MSK 的全部 bootstrap broker；OpenSearch 域端点和
  VPC 端点；EC2 的私有 IP 和 DNS）。
- 并行扫描本 Region 内的**全部** EKS 集群（其他集群往往共用同一个数据库），每个集群
  使用 `output/kubeconfigs/` 下各自的 kubeconfig——绝不改动用户的 `~/.kube/config`。
- 查找范围：容器和 init 容器的 env 值；通过 `configMapKeyRef` / `envFrom` / volume /
  projected volume 引用的 ConfigMap；ExternalName Service（以及按名称调用这些 Service
  的工作负载）；可选的 Secret key 名称。
- 把每个 pod 解析到其所属的 Deployment / StatefulSet / DaemonSet / Job。
- 匹配是锚定的：`orders-db` 不会匹配 `orders-db-replica`，`10.0.1.25` 不会匹配
  `10.0.1.250`。这类近似匹配单独列出，绝不计入。
- URL 中的凭证和 `password=` 形式的值在证据中会被掩码。

退出码 2 表示**一个集群都没能扫描**：影响列表为空是因为什么都没读到，而不是因为没有
任何东西依赖该资源。按这个意思报告。

处理结果：
1. 向用户展示脚本打印的摘要（✅ verified / ⚠️ unverified / ✖ near miss，以及被跳过的
   集群和原因）。
2. `unverified` 条目（Secret key 名称或单独的 Service 名称）需要用户确认。在
   `output/monitoring/app-map.json` 中把已确认的条目标记出来：
   ```bash
   jq '(.[] | select(.namespace=="billing" and .workload=="billing-api") | .status) = "confirmed"' \
      output/monitoring/app-map.json > output/monitoring/app-map.json.tmp \
      && mv output/monitoring/app-map.json.tmp output/monitoring/app-map.json
   ```
   扫描看不到的工作负载（例如运行时从 Secrets Manager 读取端点的工作负载），作为额外条目
   加入，并设置 `"status": "confirmed"`。
3. 在 `step2-assessment.json` 中把每个已确认的工作负载标记为 `Impact Target`，并用这份列表
   写爆炸半径说明和步骤 3 的假设（"这 N 个工作负载在 RTO 内恢复"）。
4. 匹配上但没有消费者的 ConfigMap（`unreferenced_configmaps`）值得向用户问一句：它可能是
   通过 Kubernetes API 读取的，也可能已经过时。

**输出**：`output/checkpoints/step2-assessment.json`，以及 § 2.2 产出的
`output/checkpoints/step2-dependencies.json`（完整证据，报告中引用）和
`output/monitoring/app-map.json`（步骤 5 中由 `log-collector.sh --app-map` 消费）。

**用户交互**：确认爆炸半径可接受；ARN 验证失败 → 更新或跳过

## 步骤 3：定义假设和实验

**消费**：业务功能 (2.3) + 建议实验 (2.5) + 监控就绪度 (2.6)

### 3.1 稳态假设

基于 2.3 节的 RTO/RPO 自动生成：

```
假设：在 {fault} 发生后，系统应在 {target_RTO}s 内恢复，
且请求成功率 >= {threshold}%，数据零丢失。
```

关键指标：请求成功率、P99 延迟、恢复时间、数据完整性。

### 3.2 实验设计

从 2.5 节的建议实验出发，生成完整配置：注入工具、Action、目标资源 ARN、持续时间、停止条件、爆炸半径。

> **必需输出**：Agent **必须**在生成 `output/checkpoints/step3-experiment.json` 的同时生成 `output/monitoring/metric-queries.json`。该文件包含步骤 5 中 `monitor.sh` 使用的 CloudWatch `GetMetricData` 查询定义。没有它，指标采集会被跳过，实验将在没有观测的情况下运行。未生成该文件前不要进入步骤 4。

### 3.3 监控就绪度

| 状态 | 处理 |
|------|------|
| 🟢 就绪 | 使用现有 CloudWatch Alarm 作为 Stop Condition |
| 🟡 部分就绪 | 创建缺失的 Alarm |
| 🔴 未就绪 | **阻断** — 必须先建立基线监控 |

### 3.4 工具选择

查阅**统一故障目录**（[references/fault-catalog.yaml](fault-catalog.yaml)），获取可用故障类型、默认参数和前置条件的完整列表：

- **AZ/Region 复合故障** → FIS Scenario Library → [references/scenario-library_zh.md](scenario-library_zh.md)
- **AWS 基础设施层** → AWS FIS 单 action → [references/fis-actions_zh.md](fis-actions_zh.md)
- **K8s Pod/容器层** → Chaos Mesh → [references/chaosmesh-crds_zh.md](chaosmesh-crds_zh.md)

> ⚠️ Pod 级故障**优先使用 Chaos Mesh**，而不是 FIS `aws:eks:pod-*` action（更快，RBAC 更简单）。

> ⚠️ **API 故障注入守卫**：选择 `api_throttle` / `api_internal_error` / `api_unavailable_error` 时，
> **必须**确认目标服务是 `ec2` 或 `kinesis`。只支持这两个服务。
> 如果目标是其他服务（DynamoDB、Lambda、S3、RDS、EBS 等）→ 改用该服务专用的 FIS Action。
> 映射关系见 `fault-catalog.yaml` 的 `NOT_supported` 字段。

> ⚠️ FIS Scenario Library 有**三种创建路径**：(1) Console → 导出；(2) Content 标签页 → API；(3) 直接用 [references/scenario-library_zh.md](scenario-library_zh.md) 中的 JSON skeleton 调用 API。详见该文件。

### 3.5 配置生成策略

MCP 优先 → 降级为 Schema + CLI：
- **MCP 可用**：带参数直接调用 MCP 工具（有类型约束）
- **MCP 不可用**：`aws fis get-action` 获取 schema → 填充 → `aws fis create-experiment-template`

验证链：配置生成 → API 验证 → Dry-run → 用户确认 → 执行

### 3.6 组合实验设计（多 Action FIS 模板）

复合故障场景使用 **FIS 原生多 action 模板**配合 `startAfter`：

| 模式 | `startAfter` | 效果 |
|---------|-------------|--------|
| 并行（默认） | _(不设置)_ | 同时启动 |
| 串行 | `["action-A"]` | 在 action-A 开始后启动 |
| 多依赖 | `["action-A", "action-B"]` | 在两者都开始后启动 |
| 定时延迟 | `aws:fis:wait` | 插入间隔 |

设计步骤：从 fault-catalog 选择 action → 在同一个模板的 `actions` 中定义 → 设置 `startAfter` → 添加共享的 `stopConditions` → 通过 API 创建 → 用 `experiment-runner.sh` 执行（无需改动）。

带 `{{placeholder}}` 的参数化模板见 `references/templates/`。

示例：[组合 AZ 降级](../examples/05-composite-az-degradation_zh.md)

### 3.7 混合后端实验（FIS + Chaos Mesh）

编排顺序：
1. CM 先注入（`kubectl apply`）→ 确认 AllInjected=True
2. FIS 后注入（`aws fis start-experiment`）
3. 并行监控（两个 `experiment-runner.sh` 进程）
4. 中止顺序：先停 FIS（立即生效），再删 CM（kubectl delete 有传播延迟）
5. 确认全部清理完毕

脚本用法见：[scripts/README.md](../scripts/README.md)

### 3.8 停止条件（必须）

每个实验必须绑定：CloudWatch Alarm + 时间上限 + 手动终止能力。

#### 处理 INSUFFICIENT_DATA 状态

FIS 要求实验启动前所有 Stop Condition 告警都处于 `OK` 状态。
绑定在低流量资源（如 Lambda、不常用的 API）上的告警经常显示
`INSUFFICIENT_DATA`，因为 CloudWatch 近期没有数据点。

**解决顺序（依次尝试）：**

1. **把 `TreatMissingData` 设为 `notBreaching`**（多数混沌告警推荐这样做）：
   ```bash
   aws cloudwatch put-metric-alarm \
     --alarm-name "chaos-{service}-sr-critical" \
     --treat-missing-data notBreaching \
     ... (other params unchanged)
   ```
   这样告警在缺少数据时报告 OK，这对混沌实验的停止条件是正确的——没有数据就意味着
   没有错误。

2. **制造流量预热告警**（告警已存在且你不想修改它时）：
   ```bash
   # Lambda 示例：调用几次以产生数据点
   for i in {1..5}; do
     aws lambda invoke --function-name <FUNCTION_NAME> --region <REGION> /tmp/out.json
     sleep 10
   done
   # 等待 1-2 分钟，让告警转为 OK
   aws cloudwatch describe-alarms --alarm-names "chaos-..." \
     --query 'MetricAlarms[0].StateValue'
   ```

3. **临时把该告警从 Stop Condition 中移除**（最后手段）：
   - 从 FIS 模板中移除，运行实验，结束后再加回来。
   - ⚠️ 仅限非生产环境。

### FIS 成本估算

| 成本项 | 定价 | 示例（3 个实验 × 5 分钟） |
|---------------|---------|-------------------------|
| FIS action-minutes | $0.10/action-minute | $1.50 |
| Chaos Mesh | 免费（集群资源约 0.5 vCPU） | $0.00 |
| CloudWatch 自定义指标 | $0.30/指标/月 | 约 $1-5/月 |

见 [AWS FIS 定价](https://aws.amazon.com/fis/pricing/)。

**输出**：`output/checkpoints/step3-experiment.json` + `output/templates/`

## 步骤 4：确保实验准备就绪（Pre-flight）

**消费**：监控就绪度 (2.6) + 约束 (2.8)

```
环境：
□ AWS 凭证有效且权限充足
□ FIS IAM Role 已创建（用 `aws iam get-role` 验证）
□ 目标资源处于健康状态

监控：
□ Stop Condition Alarm 已就绪**且处于 OK 状态**
  - 检查：`aws cloudwatch describe-alarms --alarm-names <names> --query 'MetricAlarms[].StateValue'`
  - 如果有告警显示 `INSUFFICIENT_DATA`：
    → 自动修复：`aws cloudwatch put-metric-alarm ... --treat-missing-data notBreaching`
    → 60 秒后重新检查状态
    → 仍不是 OK：警告用户，建议流量预热或临时移除
□ output/monitoring/metric-queries.json 存在（步骤 3 生成）

安全：
□ 爆炸半径 ≤ 最大限制
□ 回滚方案已验证
□ 数据备份已确认（涉及数据层时）
□ Lambda FIS Extension（计划做 lambda_delay 或 lambda_error 实验时）
  - 检查：`aws lambda get-function-configuration --function-name <name> --query 'Layers[].Arn'`
  - 没有 FIS Extension Layer → 根据 fault-catalog.yaml 的 `setup_commands` 生成配置命令
  - 检查环境变量：`aws lambda get-function-configuration --function-name <name> --query 'Environment.Variables.AWS_FIS_CONFIGURATION_LOCATION'`

团队：
□ 相关方已通知
□ 值班人员已就位
```

自动补救：FIS Role 缺失 → 生成创建命令；Alarm 缺失 → 生成 `put-metric-alarm`；监控 🔴 → 阻断。

**输出**：`output/checkpoints/step4-validation.json`

## 步骤 5：运行受控实验

**脚本**：全部参数见 [scripts/README.md](../scripts/README.md)。

> **MCP 写权限检查**：首次执行实验前，确认 AWS MCP Server 能执行写操作。
> 尝试一个无害的写操作（例如对现有模板执行 `fis:TagResource`）。
> 写权限由 IAM（你的凭证）和代理共同决定：如果 `aws-mcp` 条目带了 `--read-only` 启动，具备写能力的工具会被隐藏，
> 去掉该参数并重启 MCP 客户端即可。返回 `AccessDenied` → 修正 IAM 策略（或拒绝 `aws:ViaAWSMCPService` 的 SCP）。否则所有 FIS 操作都改用 AWS CLI 兜底。

### 阶段 0：基线采集（T-5min）
采集稳态基线，保存为 `output/baseline-{timestamp}.json`。

### 阶段 1：故障注入 + 观测

> ⚠️ **CRITICAL**：不要在 Agent 循环中轮询实验状态。使用 `experiment-runner.sh`，它在后台进程中处理注入、轮询、超时和状态输出。
>
> **立即失败检测**：启动 `experiment-runner.sh` 后，等待 5 秒再检查 `$STATE_FILE`。
> 如果 `immediate_failure: true`，读取 `reason` 并立即报告用户。
> 常见的立即失败：
> - "Stop condition alarm is in ALARM or INSUFFICIENT_DATA state"
> - "Access denied"（IAM 权限问题）
> - "Resource not found"（目标 ARN 无效）
>
> 不要默默等到超时——尽早检查，快速失败。

启动所有后台进程，然后 `wait`：

> ⚠️ **MANDATORY**：每个实验都必须启动全部三个后台进程，
> 无论实验类型（FIS 或 Chaos Mesh）或预计时长：
> 1. `experiment-runner.sh` — 管理实验生命周期
> 2. `monitor.sh` — 采集 CloudWatch 指标 + 心跳（FIS 实验设置 `EXPERIMENT_ID`，CM 实验不设置）
> 3. `log-collector.sh` — 采集 Pod 日志用于事后分析
>
> 即使是很短的实验也不要跳过 log-collector。注入窗口期间的 Pod 日志
> 是报告中错误分类和 MTTR 计算的必要数据（Section 4: Log Analysis）。

```bash
# FIS 实验：
nohup bash scripts/experiment-runner.sh --mode fis --template-id "$TEMPLATE_ID" \
    --region "$REGION" --state-exp-id "EXP-001" --output-dir output/ &
RUNNER_PID=$!

# Chaos Mesh 实验（pod-kill 等一次性 action）：
nohup bash scripts/experiment-runner.sh --mode chaosmesh \
    --manifest output/templates/pod-kill.yaml --namespace "$NAMESPACE" \
    --one-shot --pod-label "app=petsite" --deployment "petsite-deployment" \
    --state-exp-id "EXP-001" --output-dir output/ &
RUNNER_PID=$!

# Monitor — FIS：experiment-runner 写出实验 ID；FIS 实验结束时 monitor 自动停止
sleep 5; EXPERIMENT_ID=$(cat output/monitoring/experiment_id.txt) NAMESPACE="$CW_NAMESPACE" REGION="$REGION" \
    nohup bash scripts/monitor.sh &
# Monitor — Chaos Mesh：没有 EXPERIMENT_ID，因此必须设置 DURATION（默认 0 = 一直运行直到被终止）
# NAMESPACE="$CW_NAMESPACE" REGION="$REGION" DURATION=600 nohup bash scripts/monitor.sh &
# Log collector（所有实验 MANDATORY）。
# 首选：步骤 2.2 得到的全部 Impact Target，跨 namespace 和集群：
nohup bash scripts/log-collector.sh --app-map output/monitoring/app-map.json \
    --duration "$DURATION_SECONDS" --mode live --output-dir output/ &
# 未运行依赖发现时的兜底：单个 namespace
# nohup bash scripts/log-collector.sh --namespace {NS} --services "{svcs}" --mode live ... &
wait $RUNNER_PID
```

> 💡 monitor 默认采样间隔为 15s。实验超过 30 分钟时，设置 `INTERVAL=30` 或 `INTERVAL=60`。

退出码：0=完成，1=失败，2=超时

> **Monitor 健康检查**：启动后定期检查
> `output/monitoring/monitor-status.json`。如果 `last_collect` 时间戳
> 早于 2× INTERVAL（默认 `INTERVAL=15` 时为 30s），monitor 可能卡住了——报告用户。
>
> **看板**：启动后台脚本后，告知用户：
> "📊 **看板选项：**
>  1. **IDE 预览**：用 Markdown 预览打开 `output/dashboard.md`
>  2. **终端（实时）**：在另一个终端运行：
>     ```bash
>     watch -n 5 -c bash scripts/render-dashboard.sh
>     ```
>  3. **快速查看**：`cat output/dashboard.md`
>
> 看板在每个监控周期（每个 `INTERVAL`，默认 15s）自动更新。
> 可以放心关闭本对话——实验会在后台继续运行。"

### 阶段 2：日志分类
5 类：timeout、connection、5xx、oom、other

### Duration 覆盖
```bash
# FIS：jq
jq '.actions[].parameters.duration = "PT2M"' template.json > template-short.json
# CM：kubectl patch
kubectl patch networkchaos my-exp -n ns --type merge -p '{"spec":{"duration":"2m"}}'
```

### 阶段 3：恢复（T+duration → T+recovery）
等待自动恢复 → 记录恢复时间 → 与目标 RTO 对比。
基于日志的检测：错误连续 30s 归零 → 标记为已恢复。

### 阶段 4：稳态验证
重新采集指标 → 与基线对比 → 确认完全恢复。

### 执行模式

| 模式 | 说明 |
|------|-------------|
| Interactive | 每一步暂停（首次运行 / 生产环境） |
| Semi-auto | 在关键检查点确认（staging） |
| Dry-run | 走完流程但不注入 |
| Game Day | 跨团队演练，见 [references/gameday_zh.md](gameday_zh.md) |

**输出**：`output/checkpoints/step5-experiment.json` + 监控文件

## 步骤 6：学习与报告

### 6.0 结果验证（MANDATORY — 首先执行）

> ⚠️ 写任何报告之前，先从 AWS/K8s 验证实际实验状态。

**FIS 结果映射**：
| FIS `state.status` | 报告结果 |
|---------------------|---------------|
| `completed` | 检查假设 → PASSED ✅ 或 FAILED ❌ |
| `failed` | **FAILED ❌**（FIS 错误） |
| `stopped` / `cancelled` | **ABORTED ⚠️** |

对于 `completed`：还要检查假设是否被违反、RTO 是否超出 → 任一成立 → FAILED ❌。

**Chaos Mesh 结果映射**：
| 场景 | 报告结果 |
|----------|---------------|
| `AllInjected=True` + `AllRecovered=True` | 检查假设 |
| `AllInjected=False` | **FAILED ❌** |
| `AllRecovered=False`（超时后） | **FAILED ❌** |
| CR 不存在 | **ABORTED ⚠️** |

实验后清理检查：
```bash
kubectl get podchaos,networkchaos,httpchaos,stresschaos,iochaos -n {NAMESPACE} 2>/dev/null
```

### 6.0.5 数据完整性检查（MANDATORY，verdict 前必须执行）

生成报告前，确认观测数据存在：

| 文件 | 是否必需 | 缺失时 |
|------|----------|-----------|
| `output/monitoring/step5-metrics.jsonl` | ✅ | ⚠️ 报告**必须**包含警告："未采集到 CloudWatch 指标 — RTO/性能数据不可用" |
| `output/monitoring/step5-logs.jsonl` | 推荐 | 警告："未采集到应用日志" |
| `output/checkpoints/step2-dependencies.json` | 推荐 | 警告："未执行 Impact Target 发现 — 应用影响仅限评估报告中列出的服务"。如果文件存在，把每个 `accessible: false` 的集群列为"未扫描" |
| `output/baseline-*.json` | ✅ | ⚠️ 报告**必须**包含警告："无基线数据 — 无法对比实验前后性能" |
| `output/checkpoints/step5-experiment.json` | ✅ | ❌ 阻断报告生成 — 实验状态未知 |

如果缺少指标或基线文件：
1. 报告头部**必须**包含：`⚠️ LIMITED DATA: This report lacks quantitative metrics. Experiment execution was observed, but RTO/performance claims are not data-backed.`
2. 所有 RTO/延迟/成功率字段**必须**显示 "No data"，而不是 "N/A (idle)"
3. Verdict 只能是 "OBSERVED (not validated)"，不能是 "PASSED"

> 没有指标数据却声称 PASSED 的报告，比没有报告更糟。

#### Verdict 决策树（Agent 必须遵循）

```
有完整指标 + baseline
  └── Probe 验证假设 → PASSED ✅ 或 FAILED ❌

有指标但无 baseline
  └── OBSERVED (baseline unknown) ⚠️

无指标数据（monitor.sh 未运行或数据丢失）
  └── OBSERVED (not validated) ⚠️

无实验结果文件（step5-experiment.json 缺失）
  └── BLOCKED (no data) ❌ — 不生成报告
```

Agent 不得自行判断 verdict，必须按决策树选择。

### 6.1 分析

报告包含：
1. 结果摘要：`Total: {N} = Passed: {P} + Failed: {F} + Aborted: {A}`
2. 稳态假设与实际表现对比表
3. SLO/RTO 合规表（目标 vs. 实际）
4. MTTR 分阶段分析（检测 → 分诊 → 响应 → 恢复）
5. 应用日志分析（错误时间线、模式、传播、恢复）——按 `step2-dependencies.json` 中的每个 Impact Target 分析，包括**没有**出现错误的那些（依赖方工作负载保持干净本身也是一个发现）
6. 韧性评分更新（与 9 个维度对比）
7. 回填新发现的风险
8. 改进建议（P0/P1/P2）
9. 清理状态（FIS 模板、CM CR、临时告警）

报告模板详情：[references/report-templates_zh.md](report-templates_zh.md)

### 报告生成策略：逐节生成

分节生成报告，每节写入文件后再继续下一节：

1. **头部 + 摘要** → 写入 `output/step6-report.md`
   - 实验列表、通过/失败汇总、日期、环境
2. **追加：实验详情** → 每个实验：
   - 假设、配置、时间线、结果
3. **追加：指标分析** → 读取 `step5-metrics.jsonl`
   - 基线 vs 实际对比表、时序摘要
4. **追加：日志分析** → 读取 `step5-logs.jsonl` / `step5-log-summary.json`
   - 错误时间线、模式、恢复标记
5. **追加：MTTR 分析** → 根据指标 + 日志计算
   - 检测 → 分诊 → 响应 → 恢复的分解
6. **追加：改进建议** → P0/P1/P2 改进项
7. **追加：清理状态** → 确认所有实验都已清理

> 每节之间使用 `edit`（追加模式）写入报告文件。
> 这样即使会话中断，已完成的部分也会保留。
>
> 每写完一节，确认进度：
> "✅ 第 N 节（{section_name}）已写入（{byte_count} 字节）— {N}/7 完成"

**输出**：`output/step6-report.md` + `output/step6-report.html`

---

## 进阶：SSM 自动化编排实验

步骤 1-5 中的示例使用单个 FIS action（终止实例、集群故障转移等）。
对于更复杂的故障注入场景，FIS 可以触发 SSM 自动化文档来编排
多步实验。以下三种关键模式来自 [aws-samples/fis-template-library](https://github.com/aws-samples/fis-template-library)：

### 模式 1：动态资源注入

创建临时基础设施来注入故障，然后自动清理。

**流程：**
1. FIS 触发 SSM 自动化文档
2. SSM 创建临时资源（例如作为负载生成器的 EC2 实例）
3. SSM 安装工具，并在临时资源上执行故障注入
4. SSM 等待指定的持续时间
5. SSM 清理（释放资源，终止临时实例）

**示例**：`database-connection-limit-exhaustion` — 动态创建 EC2，安装数据库客户端，
打开连接耗尽连接池并保持，然后释放连接并终止实例。

**适用场景**：故障需要目标环境中不存在的负载生成器或中间节点时
（例如制造连接压力、流量洪泛）。

参见：`references/fis-templates/database-connection-exhaustion/`

### 模式 2：安全组操作

通过修改安全组规则阻断特定的服务间流量。

**流程：**
1. SSM 发现目标资源及其安全组
2. SSM 记录原始安全组规则（用于回滚）
3. SSM 删除/修改入站规则，阻断特定流量
4. 中断保持指定的持续时间
5. SSM 恢复原始安全组规则

**示例**：`elasticache-redis-connection-failure` — 删除安全组入站规则，阻断
应用 → Redis 的流量，在服务级别模拟网络分区。

**相比 FIS 原生网络 action 的优势**：FIS `aws:network:disrupt-connectivity` 在子网级别
操作（通过 NACL）。安全组操作针对特定的服务连接，故障注入更精确
（例如阻断 Redis，但不影响同一子网访问 DynamoDB）。

参见：`references/fis-templates/redis-connection-failure/`

### 模式 3：资源策略拒绝

通过在 IAM/资源策略层应用拒绝策略来模拟服务不可用。

**流程：**
1. SSM 按标签发现目标资源
2. SSM 向资源的访问策略添加全部拒绝的声明
3. 对该资源的所有 API 操作都返回 `AccessDenied`
4. 持续时间结束后，SSM 移除拒绝声明
5. 服务恢复正常运行

**示例**：`sqs-queue-impairment` — 向 SQS 队列策略附加拒绝策略。
`cloudfront-impairment` — 向 S3 源站存储桶策略应用拒绝策略。

**优势**：适用于任何支持基于资源的策略的 AWS 服务。无需网络层中断即可模拟
服务不可用。支持渐进式损伤（逐轮升级的拒绝 + 恢复窗口）。

参见：`references/fis-templates/sqs-queue-impairment/`、`references/fis-templates/cloudfront-impairment/`

### 模式选择指南

| 模式 | 最适合 | 复杂度 | 回滚安全性 |
|---------|----------|-----------|----------------|
| 动态资源注入 | 负载/连接压力测试 | 高 | 高（临时资源自动清理） |
| 安全组操作 | 服务级网络隔离 | 中 | 中（必须恢复精确的原始规则） |
| 资源策略拒绝 | 服务不可用模拟 | 低 | 高（移除拒绝声明即可） |

> **注意**：三种模式都需要 FIS 和 SSM 两个 IAM 角色。`references/fis-templates/` 中的
> 内嵌模板包含所需的 IAM 策略和信任关系。
