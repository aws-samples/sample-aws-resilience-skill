> 属于 [AWS 韧性分析框架参考](resilience-framework_zh.md) 的一部分。

## 5. 云设计模式（韧性相关）

### 5.1 容错和韧性模式

#### Bulkhead 模式（舱壁模式）

**目的**：故障隔离

```
反模式（共享资源池）:
┌──────────────────────────────┐
│     共享线程池 (100 线程)     │
│   ┌─────┬─────┬─────┬─────┐   │
│   │租户A│租户B│租户C│租户D│   │
│   └─────┴─────┴─────┴─────┘   │
└──────────────────────────────┘
           ↓
    租户 A 消耗所有线程
           ↓
    所有租户受影响 ❌

Bulkhead 模式:
┌──────────────────────────────┐
│ ┌────────┐ ┌────────┐        │
│ │ 租户 A │ │ 租户 B │        │
│ │25 线程 │ │25 线程 │        │
│ └────────┘ └────────┘        │
│ ┌────────┐ ┌────────┐        │
│ │ 租户 C │ │ 租户 D │        │
│ │25 线程 │ │25 线程 │        │
│ └────────┘ └────────┘        │
└──────────────────────────────┘
           ↓
    租户 A 故障仅影响自己 ✅
```

**AWS 实施**：
- 每个租户独立 Lambda 函数
- 每个优先级独立 SQS 队列
- DynamoDB 表级隔离

#### Circuit Breaker 模式（断路器）

**状态机**：

```
Closed (正常)
    │
    │ 失败率 > 阈值
    ▼
Open (断开)
    │
    │ 超时后
    ▼
Half-Open (测试)
    │
    ├─ 成功 → Closed
    └─ 失败 → Open
```

**实施示例（伪代码）**：

```python
class CircuitBreaker:
    def __init__(self, failure_threshold=5, timeout=60):
        self.failure_count = 0
        self.failure_threshold = failure_threshold
        self.timeout = timeout
        self.state = "CLOSED"  # CLOSED, OPEN, HALF_OPEN
        self.last_failure_time = None

    def call(self, func):
        if self.state == "OPEN":
            if time.now() - self.last_failure_time > self.timeout:
                self.state = "HALF_OPEN"
            else:
                raise CircuitBreakerOpen("Circuit is OPEN")

        try:
            result = func()
            self.on_success()
            return result
        except Exception as e:
            self.on_failure()
            raise e

    def on_success(self):
        self.failure_count = 0
        self.state = "CLOSED"

    def on_failure(self):
        self.failure_count += 1
        self.last_failure_time = time.now()
        if self.failure_count >= self.failure_threshold:
            self.state = "OPEN"
```

**AWS 服务**：
- API Gateway Throttling
- Lambda Reserved Concurrency
- Application Load Balancer Connection Draining

#### Retry 模式（重试）

**策略**：

| 策略 | 描述 | 适用场景 | 实施 |
|------|------|---------|------|
| **固定间隔** | 每次重试间隔相同 | 网络抖动 | `sleep(1s)` |
| **指数退避** | 间隔指数增长 | API 限流 | `sleep(2^n)` |
| **指数退避+抖动** | 增加随机性 | 避免惊群 | `sleep(2^n + random())` |
| **渐进间隔** | 自定义间隔序列 | 复杂场景 | `[1s, 5s, 30s]` |

**实施示例**：

```python
def retry_with_exponential_backoff(
    func,
    max_retries=3,
    base_delay=1,
    max_delay=60,
    jitter=True
):
    for attempt in range(max_retries):
        try:
            return func()
        except TransientError as e:
            if attempt == max_retries - 1:
                raise

            delay = min(base_delay * (2 ** attempt), max_delay)
            if jitter:
                delay += random.uniform(0, delay * 0.1)

            time.sleep(delay)
```

**AWS SDK 自动重试**：
- AWS SDK 内置指数退避
- DynamoDB：自动重试限流（ProvisionedThroughputExceededException）
- S3：自动重试 5xx 错误

**最佳实践**：
- 区分临时和永久故障
- 设置最大重试次数（避免无限重试）
- 记录重试尝试（审计和调试）
- 幂等性（确保重试安全）

#### Queue-Based Load Leveling（基于队列的负载均衡）

**架构**：

```
同步（反模式）:
Client → API → Heavy Processing
              ↑ 阻塞等待
        超时 / 失败 ❌

异步（最佳实践）:
Client → API → SQS Queue → Worker Pool
         ↓                    ↓
      立即返回 ✅          处理任务
```

**优势**：
- 解耦生产者和消费者
- 缓冲突发流量
- 自动重试（DLQ）
- 水平扩展 Worker

**AWS 实施**：
```yaml
架构:
  Producer:
    - API Gateway + Lambda
    - 发送消息到 SQS

  Queue:
    - SQS Standard Queue
    - Visibility Timeout: 30s
    - Dead Letter Queue (3 次重试后)

  Consumer:
    - Lambda (Event Source Mapping)
    - 或 ECS/EKS Worker
    - Auto Scaling 基于队列深度

监控:
  - ApproximateNumberOfMessagesVisible
  - ApproximateAgeOfOldestMessage
  - NumberOfMessagesDeleted
```

#### Throttling（限流）

**目的**：控制资源消耗，防止过载

**限流算法**：

| 算法 | 描述 | 优点 | 缺点 |
|------|------|------|------|
| **固定窗口** | 每个时间窗口固定配额 | 简单 | 窗口边界突增 |
| **滑动窗口** | 平滑的时间窗口 | 精确 | 实施复杂 |
| **漏桶** | 固定速率处理 | 平滑流量 | 不适应突增 |
| **令牌桶** | 允许突增（令牌积累） | 灵活 | 需维护状态 |

**AWS 实施**：

```yaml
API Gateway:
  Rate Limiting:
    - 每秒请求数（RPS）
    - 突增容量（Burst）

  Throttling:
    - Account-level: 10,000 RPS
    - Stage-level: 自定义
    - Method-level: 细粒度控制

  Usage Plans:
    - 每个 API Key 独立配额
    - 按租户限流

Lambda:
  Concurrency Limits:
    - Account-level: 1000 并发（默认）
    - Function-level: Reserved Concurrency
    - Provisioned Concurrency: 预热实例

  Throttling:
    - 超过并发限制时返回 429

DynamoDB:
  Capacity Modes:
    - Provisioned: 固定 RCU/WCU
    - On-Demand: 自动扩展

  Throttling:
    - 超过容量时返回 ProvisionedThroughputExceededException
    - Adaptive Capacity: 自动应对热分区
```

---

## 总结

本参考文档整合了 2025 年系统韧性领域的最新知识和最佳实践：

1. **AWS Well-Architected Framework（可靠性支柱）**
   - 五大设计原则
   - 四种灾难恢复策略
   - 多 AZ 和多区域架构
   - 结构化变更管理

2. **AWS 韧性分析核心原则**
   - 错误预算管理
   - SLI/SLO/SLA 定义
   - 关键监控指标
   - 无责任事后复盘文化
   - 有效故障排查方法

3. **混沌工程方法论**
   - 四步实验流程
   - AWS FIS 实验模板
   - 持续自动化验证

4. **AWS 可观测性最佳实践**
   - CloudWatch + X-Ray 统一框架
   - 三大支柱（日志、指标、追踪）
   - 健康检查模型
   - AWS 可观测性服务

5. **云设计模式**
   - Bulkhead（故障隔离）
   - Circuit Breaker（断路器）
   - Retry（重试）
   - Queue-Based Load Leveling（异步解耦）
   - Throttling（限流）

在进行 AWS 系统韧性分析时，应综合运用这些框架和模式，根据业务需求和约束条件，设计和实施适合的韧性策略。
