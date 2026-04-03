# Modern Observability Standards

> Part of the [AWS Resilience Analysis Framework Reference](resilience-framework.md).

## 4.1 OpenTelemetry

**Core Definition**:
> "An observability framework and toolkit designed to facilitate the generation, export, and collection of telemetry data (traces, metrics, logs)."

**Key Principles**:
- **Data Ownership**: Users have full control over telemetry data
- **Unified Learning Curve**: One set of APIs and conventions
- **Vendor Neutral**: Avoid vendor lock-in

**Main Components**:

```yaml
Specification and Protocol:
  - OTLP (OpenTelemetry Protocol)
  - Unified telemetry data format

Language SDKs:
  - Java, Python, Go, .NET, JavaScript
  - Ruby, PHP, Rust, C++
  - Auto-instrumentation + manual instrumentation

Pre-built Instrumentation Libraries:
  - HTTP clients/servers
  - Databases (MySQL, PostgreSQL, DynamoDB)
  - Message queues (Kafka, SQS, SNS)
  - RPC frameworks (gRPC)

OpenTelemetry Collector:
  - Receive telemetry data
  - Process, filter, transform
  - Export to multiple backends
  - Support multiple formats

Kubernetes Integration:
  - Operator
  - Helm Charts
  - Auto-injection (Sidecar)
```

**Architecture**:

```
Application
    |
    | OpenTelemetry SDK
    | (Instrumentation)
    v
OpenTelemetry Collector
    |
    | Processing and Routing
    |
    +----------+----------+----------+
    v          v          v          v
CloudWatch  X-Ray   Prometheus  Jaeger
(Metrics)  (Traces)  (Metrics)  (Traces)
```

## 4.2 Three Pillars

### 1. Logs

**Structured Logging Best Practices**:

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

**Best Practices**:
- Use JSON format (easy to parse)
- Include context (request ID, user ID, trace ID)
- Include timestamp and severity
- Avoid sensitive information (passwords, credit card numbers)
- Use log levels (DEBUG, INFO, WARN, ERROR, FATAL)
- Centralize log aggregation (CloudWatch Logs, ELK)

**AWS Implementation**:

```yaml
CloudWatch Logs:
  Collection:
    - CloudWatch Logs Agent
    - Firelens (ECS/EKS)
    - Lambda automatic collection

  Analysis:
    - CloudWatch Logs Insights
    - Query language (SQL-like)
    - Visualization charts

  Retention:
    - Set retention policy (7 days, 30 days, 1 year)
    - Archive to S3 (low-cost long-term storage)
    - Lifecycle policies

Alerting:
  - Metric Filters (extract metrics)
  - Subscription Filters (real-time processing)
  - Lambda triggers
```

### 2. Metrics

**Metric Types**:

| Type | Description | Example | Aggregation |
|------|-------------|---------|-------------|
| **Counter** | Incrementing count | Total requests, total errors | Sum, Rate |
| **Gauge** | Instantaneous value | CPU usage, memory usage | Average, Max, Min |
| **Histogram** | Distribution | Request latency distribution | P50, P95, P99 |
| **Summary** | Quantiles | Pre-computed P95, P99 | N/A (client-computed) |

**Key Monitoring Metrics**:

```yaml
Latency:
  Metrics:
    - request_duration_seconds (Histogram)
    - request_latency_p95
    - request_latency_p99

  Alerts:
    - P95 > 200ms for 5 minutes
    - P99 > 1s

Traffic:
  Metrics:
    - requests_per_second (Counter)
    - active_connections (Gauge)
    - throughput_bytes (Counter)

  Alerts:
    - Traffic drop > 50% (possible failure)
    - Traffic spike > 300% (possible attack)

Errors:
  Metrics:
    - errors_total (Counter)
    - error_rate (Gauge)
    - http_5xx_count (Counter)

  Alerts:
    - Error rate > 1%

Saturation:
  Metrics:
    - cpu_utilization (Gauge)
    - memory_utilization (Gauge)
    - disk_usage_percent (Gauge)
    - connection_pool_utilization (Gauge)

  Alerts:
    - CPU > 80% for 10 minutes
    - Memory > 90%
    - Disk > 85%
```

**AWS Implementation**:

```yaml
CloudWatch Metrics:
  Standard Metrics:
    - EC2: CPUUtilization, NetworkIn/Out
    - RDS: DatabaseConnections, ReadLatency
    - ALB: TargetResponseTime, HTTPCode_5XX

  Custom Metrics:
    - PutMetricData API
    - CloudWatch Agent
    - EMF (Embedded Metric Format)

  Math Expressions:
    - Error rate = errors / total * 100
    - Availability = (total - errors) / total * 100

Prometheus + Grafana:
  Collection:
    - Prometheus Exporter
    - Service Discovery (ECS, EKS)

  Storage:
    - Amazon Managed Prometheus (AMP)

  Visualization:
    - Amazon Managed Grafana (AMG)
```

### 3. Traces

**Distributed Tracing Concepts**:

```yaml
Trace:
  Definition: Complete request path
  Example: User request -> API Gateway -> Lambda -> DynamoDB

Span:
  Definition: Single operation
  Example: "Lambda execution", "DynamoDB query"

  Attributes:
    - span_id: Unique identifier
    - parent_span_id: Parent Span
    - trace_id: Owning Trace
    - operation_name: Operation name
    - start_time: Start time
    - duration: Duration
    - tags: Metadata (http.method, db.statement)

Context:
  Definition: Metadata propagated across services
  Propagation:
    - HTTP Headers: traceparent, tracestate
    - Message Queues: Message Attributes

Baggage:
  Definition: User-defined metadata
  Example: user_id, request_id, feature_flag
```

**Use Cases**:
- Identify performance bottlenecks (which service is slowest?)
- Understand service dependencies (call graph)
- Diagnose latency issues (which operation takes longest?)
- Visualize request flow (Waterfall diagram)

**AWS X-Ray Implementation**:

```yaml
Instrumentation:
  Auto-Instrumentation:
    - AWS SDK calls (DynamoDB, S3, SQS)
    - HTTP calls (via X-Ray SDK)
    - SQL queries (via X-Ray SDK)

  Manual Instrumentation:
    - Custom Subsegments
    - Add Annotations (searchable)
    - Add Metadata (detailed info)

Lambda:
  - Automatic tracing (enable Active Tracing)
  - Automatic cold start capture
  - Automatic AWS SDK call capture

ECS/EKS:
  - X-Ray Daemon Sidecar
  - Application sends traces to Daemon
  - Daemon batch-uploads to X-Ray

Analysis:
  - Service Map (service dependency diagram)
  - Trace Timeline (Waterfall diagram)
  - Analytics (query and filter)
  - Alerts (latency anomalies, error rate)
```

## 4.3 Health Models

**Health State Definitions**:

```yaml
Healthy:
  Definition: All metrics within normal range
  Metrics:
    - Request success rate: > 99.9%
    - Latency P95: < 200ms
    - Error rate: < 0.1%
    - Resource utilization: < 70%

  Action: None, continue monitoring

Degraded:
  Definition: Some functionality affected
  Metrics:
    - Request success rate: 99% - 99.9%
    - Latency P95: 200ms - 500ms
    - Some dependencies unavailable

  Action:
    - Auto-trigger degradation mode
    - Notify on-call
    - Prepare rollback

Unhealthy:
  Definition: Critical functionality failed
  Metrics:
    - Request success rate: < 99%
    - Latency P95: > 500ms
    - Primary database unavailable

  Action:
    - Immediate alert (pager)
    - Auto failover
    - Incident response process
```

**Health Check Types**:

| Type | Purpose | Example | Kubernetes | AWS |
|------|---------|---------|-----------|-----|
| **Liveness** | Is the application running? | HTTP 200 /health | livenessProbe | ELB Health Check |
| **Readiness** | Ready to accept traffic? | Database connection OK | readinessProbe | Target Health |
| **Startup** | Finished starting? | Initialization complete | startupProbe | N/A |

**Implementation**:

```yaml
Health Check Endpoints:
  /health:
    - Liveness check
    - Only checks the application itself
    - Fast response (< 100ms)
    - Example: { "status": "healthy" }

  /ready:
    - Readiness check
    - Checks dependencies (database, cache)
    - Can be slightly slower (< 1s)
    - Example:
      {
        "status": "ready",
        "checks": {
          "database": "ok",
          "cache": "ok"
        }
      }

  /health/deep:
    - Deep health check
    - Checks all dependencies
    - For diagnostics only (not for automation)
    - Example:
      {
        "status": "healthy",
        "checks": {
          "database": { "status": "ok", "latency": "5ms" },
          "cache": { "status": "ok", "hit_rate": "95%" },
          "queue": { "status": "ok", "depth": 10 }
        }
      }

Load Balancer Integration:
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
