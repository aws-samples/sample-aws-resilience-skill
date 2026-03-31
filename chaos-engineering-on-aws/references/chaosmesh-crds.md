# Chaos Mesh CRD Reference (by Fault Domain)

> Chaos Mesh is an **optional enhancement**. The agent auto-detects on startup: `kubectl get crd | grep chaos-mesh`.
> Installed → Include CM scenarios in recommendations; Not installed → Skip, use FIS only.
>
> ⚠️ **Prefer Chaos Mesh for Pod/container-level fault injection** over FIS `aws:eks:pod-*`.
> Chaos Mesh takes effect in seconds with simple config; FIS Pod actions require additional SA/RBAC and have slow initialization (>2min).

## PodChaos — Pod Lifecycle
| Action | Description |
|--------|------|
| `pod-failure` | Pod unavailable (replaced with pause image) |
| `pod-kill` | Kill Pod |
| `container-kill` | Kill specific container |

## NetworkChaos — Network
| Action | Description |
|--------|------|
| `delay` | Network delay (configurable jitter) |
| `loss` | Packet loss (configurable probability) |
| `duplicate` | Packet duplication |
| `corrupt` | Packet corruption |
| `partition` | Network partition (to/from/both) |
| `bandwidth` | Bandwidth limiting |

## HTTPChaos — HTTP Layer
| Action | Description |
|--------|------|
| `abort` | HTTP connection abort |
| `delay` | HTTP response delay |
| `replace` | Replace request/response content |
| `patch` | Append content to request/response |

## StressChaos — Resource Stress
| Action | Description |
|--------|------|
| `cpu` | CPU stress |
| `memory` | Memory stress |

## IOChaos — File System
| Action | Description |
|--------|------|
| `latency` | File IO latency |
| `fault` | File IO error |
| `attrOverride` | File attribute override |
| `mistake` | Random read/write errors |

## DNSChaos — DNS
| Action | Description |
|--------|------|
| `error` | DNS resolution returns error |
| `random` | DNS resolution returns random IP |

## Other CRDs
| CRD | Description |
|-----|------|
| `TimeChaos` | Container clock skew |
| `KernelChaos` | Kernel fault injection (BPF) |
| `JVMChaos` | Java application faults |
| `PhysicalMachineChaos` | Physical machine/VM faults |

## MCP Server (chaosmesh-mcp)

Wraps 30 tools covering all CRD types. Usage examples:

```python
pod_kill(service="web-frontend", duration="30s", mode="all", namespace="app")
network_delay(service="api-gateway", duration="60s", latency="200ms", namespace="app")
http_chaos(service="order-svc", duration="60s", abort=True, namespace="app")
```

> Full documentation: [Chaos Mesh](https://chaos-mesh.org/docs/)
> MCP Server: [RadiumGu/Chaosmesh-MCP](https://github.com/RadiumGu/Chaosmesh-MCP)
