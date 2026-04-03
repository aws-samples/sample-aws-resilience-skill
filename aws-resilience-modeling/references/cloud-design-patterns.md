# Cloud Design Patterns (Resilience-Related)

> Part of the [AWS Resilience Analysis Framework Reference](resilience-framework.md).

## 5.1 Fault Tolerance and Resilience Patterns

### Bulkhead Pattern

**Purpose**: Fault isolation

```
Anti-pattern (Shared Resource Pool):
+------------------------------+
|  Shared Thread Pool (100)    |
| +-----+-----+-----+-----+   |
| |Ten A|Ten B|Ten C|Ten D|   |
| +-----+-----+-----+-----+   |
+------------------------------+
           |
    Tenant A consumes all threads
           |
    All tenants affected

Bulkhead Pattern:
+------------------------------+
| +--------+ +--------+        |
| | Tenant A| | Tenant B|      |
| |25 threads| |25 threads|    |
| +--------+ +--------+        |
| +--------+ +--------+        |
| | Tenant C| | Tenant D|      |
| |25 threads| |25 threads|    |
| +--------+ +--------+        |
+------------------------------+
           |
    Tenant A failure only affects itself
```

**AWS Implementation**:
- Separate Lambda functions per tenant
- Separate SQS queues per priority
- DynamoDB table-level isolation

### Circuit Breaker Pattern

**State Machine**:

```
Closed (Normal)
    |
    | Failure rate > threshold
    v
Open (Broken)
    |
    | After timeout
    v
Half-Open (Testing)
    |
    +-- Success -> Closed
    +-- Failure -> Open
```

**Implementation Example (Pseudocode)**:

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

**AWS Services**:
- API Gateway Throttling
- Lambda Reserved Concurrency
- Application Load Balancer Connection Draining

### Retry Pattern

**Strategies**:

| Strategy | Description | Use Case | Implementation |
|----------|-------------|----------|----------------|
| **Fixed Interval** | Same interval between retries | Network jitter | `sleep(1s)` |
| **Exponential Backoff** | Exponentially increasing interval | API throttling | `sleep(2^n)` |
| **Exponential Backoff + Jitter** | Added randomness | Avoid thundering herd | `sleep(2^n + random())` |
| **Progressive Interval** | Custom interval sequence | Complex scenarios | `[1s, 5s, 30s]` |

**Implementation Example**:

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

**AWS SDK Auto-Retry**:
- AWS SDK has built-in exponential backoff
- DynamoDB: Auto-retry on throttling (ProvisionedThroughputExceededException)
- S3: Auto-retry on 5xx errors

**Best Practices**:
- Distinguish transient from permanent failures
- Set maximum retry count (avoid infinite retries)
- Log retry attempts (auditing and debugging)
- Idempotency (ensure retries are safe)

### Queue-Based Load Leveling

**Architecture**:

```
Synchronous (Anti-pattern):
Client -> API -> Heavy Processing
              ^ Blocking wait
        Timeout / Failure

Asynchronous (Best Practice):
Client -> API -> SQS Queue -> Worker Pool
         |                    |
      Immediate return      Process tasks
```

**Benefits**:
- Decouples producers and consumers
- Buffers burst traffic
- Automatic retry (DLQ)
- Horizontally scale workers

**AWS Implementation**:
```yaml
Architecture:
  Producer:
    - API Gateway + Lambda
    - Send messages to SQS

  Queue:
    - SQS Standard Queue
    - Visibility Timeout: 30s
    - Dead Letter Queue (after 3 retries)

  Consumer:
    - Lambda (Event Source Mapping)
    - Or ECS/EKS Worker
    - Auto Scaling based on queue depth

Monitoring:
  - ApproximateNumberOfMessagesVisible
  - ApproximateAgeOfOldestMessage
  - NumberOfMessagesDeleted
```

### Throttling

**Purpose**: Control resource consumption, prevent overload

**Throttling Algorithms**:

| Algorithm | Description | Pros | Cons |
|-----------|-------------|------|------|
| **Fixed Window** | Fixed quota per time window | Simple | Window boundary spikes |
| **Sliding Window** | Smooth time window | Precise | Complex implementation |
| **Leaky Bucket** | Fixed-rate processing | Smooth traffic | Not adaptive to bursts |
| **Token Bucket** | Allow bursts (token accumulation) | Flexible | Requires state maintenance |

**AWS Implementation**:

```yaml
API Gateway:
  Rate Limiting:
    - Requests per second (RPS)
    - Burst capacity

  Throttling:
    - Account-level: 10,000 RPS
    - Stage-level: Custom
    - Method-level: Fine-grained control

  Usage Plans:
    - Independent quota per API Key
    - Per-tenant throttling

Lambda:
  Concurrency Limits:
    - Account-level: 1000 concurrent (default)
    - Function-level: Reserved Concurrency
    - Provisioned Concurrency: Pre-warmed instances

  Throttling:
    - Returns 429 when exceeding concurrency limit

DynamoDB:
  Capacity Modes:
    - Provisioned: Fixed RCU/WCU
    - On-Demand: Auto-scaling

  Throttling:
    - Returns ProvisionedThroughputExceededException when exceeding capacity
    - Adaptive Capacity: Automatically handles hot partitions
```
