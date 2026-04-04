> 属于 [AWS 韧性分析框架参考](resilience-framework_zh.md) 的一部分。

## 4. 现代可观测性标准

### 4.1 OpenTelemetry

**核心定义**：
> "旨在促进遥测数据（追踪、指标、日志）的生成、导出和收集的可观测性框架和工具包"

**关键原则**：
- **数据所有权**：用户完全控制遥测数据
- **统一学习曲线**：一套 API 和约定
- **供应商中立**：避免供应商锁定

**主要组件**：

```yaml
规范和协议:
  - OTLP (OpenTelemetry Protocol)
  - 统一的遥测数据格式

语言 SDK:
  - Java, Python, Go, .NET, JavaScript
  - Ruby, PHP, Rust, C++
  - 自动插桩 + 手动插桩

预构建插桩库:
  - HTTP 客户端/服务器
  - 数据库（MySQL, PostgreSQL, DynamoDB）
  - 消息队列（Kafka, SQS, SNS）
  - RPC 框架（gRPC）

OpenTelemetry Collector:
  - 接收遥测数据
  - 处理、过滤、转换
  - 导出到多个后端
  - 支持多种格式

Kubernetes 集成:
  - Operator
  - Helm Charts
  - 自动注入（Sidecar）
```

**架构**：

```
应用程序
    │
    │ OpenTelemetry SDK
    │ (插桩)
    ▼
OpenTelemetry Collector
    │
    │ 处理和路由
    │
    ├──────────┬──────────┬──────────┐
    ▼          ▼          ▼          ▼
CloudWatch  X-Ray   Prometheus  Jaeger
(指标)     (追踪)    (指标)     (追踪)
```

### 4.2 三大支柱

#### 1. 日志 (Logs)

**结构化日志最佳实践**：

```json
{
  "timestamp": "2025-02-17T10:00:00.123Z",
  "level": "ERROR",
  "service": "api-gateway",
  "trace_id": "1234567890abcdef",
  "span_id": "abcdef1234567890",
  "user_id": "user_123",
  "request_id": "req_xyz",
  "message": "Failed to connect to database",
  "error": {
    "type": "DatabaseConnectionError",
    "message": "Connection timeout after 30s",
    "stack_trace": "..."
  },
  "context": {
    "db_host": "db.example.com",
    "db_port": 5432,
    "retry_count": 3
  }
}
```

**最佳实践**：
- 使用 JSON 格式（易于解析）
- 包含上下文（请求 ID、用户 ID、trace ID）
- 包含时间戳和严重性
- 避免敏感信息（密码、信用卡号）
- 使用日志级别（DEBUG、INFO、WARN、ERROR、FATAL）
- 集中日志聚合（CloudWatch Logs、ELK）

**AWS 实施**：

```yaml
CloudWatch Logs:
  收集:
    - CloudWatch Logs Agent
    - Firelens (ECS/EKS)
    - Lambda 自动收集

  分析:
    - CloudWatch Logs Insights
    - 查询语言（类似 SQL）
    - 可视化图表

  保留:
    - 设置保留策略（7 天、30 天、1 年）
    - 归档到 S3（低成本长期存储）
    - Lifecycle 策略

告警:
  - Metric Filters（提取指标）
  - Subscription Filters（实时处理）
  - Lambda 触发器
```

#### 2. 指标 (Metrics)

**指标类型**：

| 类型 | 描述 | 示例 | 聚合方式 |
|------|------|------|---------|
| **Counter** | 递增计数 | 请求总数、错误总数 | Sum, Rate |
| **Gauge** | 瞬时值 | CPU 使用率、内存使用 | Average, Max, Min |
| **Histogram** | 分布 | 请求延迟分布 | P50, P95, P99 |
| **Summary** | 分位数 | 预计算的 P95、P99 | N/A（客户端计算） |

**关键监控指标**：

```yaml
延迟 (Latency):
  指标:
    - request_duration_seconds (Histogram)
    - request_latency_p95
    - request_latency_p99

  告警:
    - P95 > 200ms 持续 5 分钟
    - P99 > 1s

流量 (Traffic):
  指标:
    - requests_per_second (Counter)
    - active_connections (Gauge)
    - throughput_bytes (Counter)

  告警:
    - 流量突降 > 50%（可能故障）
    - 流量突增 > 300%（可能攻击）

错误 (Errors):
  指标:
    - errors_total (Counter)
    - error_rate (Gauge)
    - http_5xx_count (Counter)

  告警:
    - 错误率 > 1%

饱和度 (Saturation):
  指标:
    - cpu_utilization (Gauge)
    - memory_utilization (Gauge)
    - disk_usage_percent (Gauge)
    - connection_pool_utilization (Gauge)

  告警:
    - CPU > 80% 持续 10 分钟
    - 内存 > 90%
    - 磁盘 > 85%
```

**AWS 实施**：

```yaml
CloudWatch Metrics:
  标准指标:
    - EC2: CPUUtilization, NetworkIn/Out
    - RDS: DatabaseConnections, ReadLatency
    - ALB: TargetResponseTime, HTTPCode_5XX

  自定义指标:
    - PutMetricData API
    - CloudWatch Agent
    - EMF (Embedded Metric Format)

  数学表达式:
    - 错误率 = errors / total * 100
    - 可用性 = (total - errors) / total * 100

Prometheus + Grafana:
  收集:
    - Prometheus Exporter
    - Service Discovery（ECS、EKS）

  存储:
    - Amazon Managed Prometheus (AMP)

  可视化:
    - Amazon Managed Grafana (AMG)
```

#### 3. 追踪 (Traces)

**分布式追踪概念**：

```yaml
Trace (追踪):
  定义: 完整的请求路径
  示例: 用户请求 → API Gateway → Lambda → DynamoDB

Span (跨度):
  定义: 单个操作
  示例: "Lambda 执行"、"DynamoDB 查询"

  属性:
    - span_id: 唯一标识符
    - parent_span_id: 父 Span
    - trace_id: 所属 Trace
    - operation_name: 操作名称
    - start_time: 开始时间
    - duration: 持续时间
    - tags: 元数据（http.method, db.statement）

Context (上下文):
  定义: 跨服务传播的元数据
  传播方式:
    - HTTP Headers: traceparent, tracestate
    - 消息队列: Message Attributes

Baggage (行李):
  定义: 用户定义的元数据
  示例: user_id, request_id, feature_flag
```

**用途**：
- 识别性能瓶颈（哪个服务最慢？）
- 理解服务依赖（调用图）
- 诊断延迟问题（哪个操作耗时最长？）
- 可视化请求流（Waterfall 图）

**AWS X-Ray 实施**：

```yaml
插桩:
  自动插桩:
    - AWS SDK 调用（DynamoDB、S3、SQS）
    - HTTP 调用（通过 X-Ray SDK）
    - SQL 查询（通过 X-Ray SDK）

  手动插桩:
    - 自定义 Subsegments
    - 添加 Annotations（可搜索）
    - 添加 Metadata（详细信息）

Lambda:
  - 自动追踪（启用 Active Tracing）
  - 自动捕获冷启动
  - 自动捕获 AWS SDK 调用

ECS/EKS:
  - X-Ray Daemon Sidecar
  - 应用发送追踪到 Daemon
  - Daemon 批量上传到 X-Ray

分析:
  - Service Map（服务依赖图）
  - Trace Timeline（Waterfall 图）
  - Analytics（查询和过滤）
  - 告警（延迟异常、错误率）
```

### 4.3 健康模型

**健康状态定义**：

```yaml
Healthy (健康):
  定义: 所有指标在正常范围内
  指标:
    - 请求成功率: > 99.9%
    - 延迟 P95: < 200ms
    - 错误率: < 0.1%
    - 资源利用率: < 70%

  行动: 无，继续监控

Degraded (降级):
  定义: 部分功能受影响
  指标:
    - 请求成功率: 99% - 99.9%
    - 延迟 P95: 200ms - 500ms
    - 部分依赖不可用

  行动:
    - 自动触发降级模式
    - 通知 On-call
    - 准备回滚

Unhealthy (不健康):
  定义: 关键功能失败
  指标:
    - 请求成功率: < 99%
    - 延迟 P95: > 500ms
    - 主数据库不可用

  行动:
    - 立即告警（寻呼机）
    - 自动故障转移
    - 事故响应流程
```

**健康检查类型**：

| 类型 | 目的 | 示例 | Kubernetes | AWS |
|------|------|------|-----------|-----|
| **Liveness** | 应用是否运行？ | HTTP 200 /health | livenessProbe | ELB Health Check |
| **Readiness** | 是否准备接受流量？ | 数据库连接成功 | readinessProbe | Target Health |
| **Startup** | 是否完成启动？ | 初始化完成 | startupProbe | N/A |

**实施**：

```yaml
健康检查端点:
  /health:
    - Liveness 检查
    - 仅检查应用本身
    - 快速响应（< 100ms）
    - 示例: { "status": "healthy" }

  /ready:
    - Readiness 检查
    - 检查依赖（数据库、缓存）
    - 可稍慢（< 1s）
    - 示例:
      {
        "status": "ready",
        "checks": {
          "database": "ok",
          "cache": "ok"
        }
      }

  /health/deep:
    - 深度健康检查
    - 检查所有依赖
    - 仅供诊断（不用于自动化）
    - 示例:
      {
        "status": "healthy",
        "checks": {
          "database": { "status": "ok", "latency": "5ms" },
          "cache": { "status": "ok", "hit_rate": "95%" },
          "queue": { "status": "ok", "depth": 10 }
        }
      }

负载均衡器集成:
  ALB:
    - Health Check Path: /health
    - Interval: 30s
    - Timeout: 5s
    - Healthy Threshold: 2
    - Unhealthy Threshold: 2

  Kubernetes:
    livenessProbe:
      httpGet:
        path: /health
        port: 8080
      initialDelaySeconds: 30
      periodSeconds: 10
      timeoutSeconds: 5
      failureThreshold: 3

    readinessProbe:
      httpGet:
        path: /ready
        port: 8080
      initialDelaySeconds: 10
      periodSeconds: 5
      timeoutSeconds: 3
      failureThreshold: 3
```

---

