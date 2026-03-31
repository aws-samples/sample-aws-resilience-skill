# Chaos Mesh CRD 参考（按故障域分类）

> Chaos Mesh 为**可选增强**。Agent 启动时自动检测：`kubectl get crd | grep chaos-mesh`。
> 已安装 → 推荐中包含 CM 场景；未安装 → 跳过，仅使用 FIS。
>
> ⚠️ **Pod/容器级故障注入首选 Chaos Mesh**，不推荐 FIS `aws:eks:pod-*`。
> Chaos Mesh 秒级生效、配置简单；FIS Pod action 需额外 SA/RBAC，初始化慢（>2min）。

## PodChaos — Pod 生命周期
| Action | 说明 |
|--------|------|
| `pod-failure` | Pod 不可用（替换为 pause 镜像） |
| `pod-kill` | 杀死 Pod |
| `container-kill` | 杀死指定容器 |

## NetworkChaos — 网络
| Action | 说明 |
|--------|------|
| `delay` | 网络延迟（可配抖动） |
| `loss` | 丢包（可配概率） |
| `duplicate` | 包重复 |
| `corrupt` | 包损坏 |
| `partition` | 网络分区（to/from/both） |
| `bandwidth` | 带宽限制 |

## HTTPChaos — HTTP 层
| Action | 说明 |
|--------|------|
| `abort` | HTTP 连接中断 |
| `delay` | HTTP 响应延迟 |
| `replace` | 替换请求/响应内容 |
| `patch` | 向请求/响应附加内容 |

## StressChaos — 资源压力
| Action | 说明 |
|--------|------|
| `cpu` | CPU 压力 |
| `memory` | 内存压力 |

## IOChaos — 文件系统
| Action | 说明 |
|--------|------|
| `latency` | 文件 IO 延迟 |
| `fault` | 文件 IO 错误 |
| `attrOverride` | 文件属性覆写 |
| `mistake` | 读写随机错误 |

## DNSChaos — DNS
| Action | 说明 |
|--------|------|
| `error` | DNS 解析返回错误 |
| `random` | DNS 解析返回随机 IP |

## 其他 CRD
| CRD | 说明 |
|-----|------|
| `TimeChaos` | 容器时钟偏移 |
| `KernelChaos` | 内核故障注入（BPF） |
| `JVMChaos` | Java 应用故障 |
| `PhysicalMachineChaos` | 物理机/VM 故障 |

## MCP Server (chaosmesh-mcp)

已封装 30 个 tool，覆盖全部 CRD 类型。调用示例：

```python
pod_kill(service="web-frontend", duration="30s", mode="all", namespace="app")
network_delay(service="api-gateway", duration="60s", latency="200ms", namespace="app")
http_chaos(service="order-svc", duration="60s", abort=True, namespace="app")
```

> 完整文档：[Chaos Mesh](https://chaos-mesh.org/zh/docs/)
> MCP Server：[RadiumGu/Chaosmesh-MCP](https://github.com/RadiumGu/Chaosmesh-MCP)
