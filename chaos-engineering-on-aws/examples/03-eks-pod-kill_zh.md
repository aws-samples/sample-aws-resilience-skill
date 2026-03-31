# 示例 3: EKS Pod Kill — 微服务自愈验证

**架构模式**：EKS 微服务（Deployment + Service + Ingress）
**工具**：Chaos Mesh PodChaos（需集群已安装）
**验证点**：ReplicaSet 自动重建 Pod、流量通过 Service 无缝切换

---

## 前提

- 集群已安装 Chaos Mesh：`kubectl get crd | grep chaos-mesh`
- 目标 Deployment replicas >= 2

如果 Chaos Mesh 未安装，可用 FIS `aws:eks:terminate-nodegroup-instances` 做**节点级**故障替代（爆炸半径更大）。

> ⚠️ 不推荐用 FIS `aws:eks:pod-delete` 做 Pod 级故障 — 需额外配置 K8s ServiceAccount + RBAC + EKS access entry，且故障注入器 Pod 初始化慢（>2min）。Pod 级故障首选 Chaos Mesh。

## 稳态假设

当杀死目标服务的 1 个 Pod 后：
- Service 请求成功率 >= 99.9%
- P99 延迟 <= 300ms
- Pod 在 60s 内重建并进入 Ready 状态
- 无请求丢失（其他 Pod 接管流量）

## Chaos Mesh Manifest

```yaml
apiVersion: chaos-mesh.org/v1alpha1
kind: PodChaos
metadata:
  name: pod-kill-web-frontend
  namespace: chaos-testing
spec:
  action: pod-kill
  mode: one
  selector:
    namespaces:
      - production
    labelSelectors:
      app: web-frontend
  duration: "30s"
  gracePeriod: 0
```

## 使用 MCP（如可用）

```python
# chaosmesh-mcp 调用
pod_kill(
    service="web-frontend",
    duration="30s",
    mode="one",
    namespace="production"
)
```

## 执行命令

```bash
# 检查目标 Pod 数量
kubectl get pods -n production -l app=web-frontend

# 注入故障
kubectl apply -f examples/pod-kill-web-frontend.yaml

# 观察 Pod 重建
kubectl get pods -n production -l app=web-frontend -w

# 清理（到期自动清理，或手动）
kubectl delete -f examples/pod-kill-web-frontend.yaml
```

## 观测指标

| 指标 | 来源 | 说明 |
|------|------|------|
| Pod Ready 数量 | `kubectl get pods` | 应快速恢复到期望值 |
| 请求成功率 | Ingress / ALB 指标 | 不应低于 99.9% |
| P99 延迟 | 应用指标 / CloudWatch | 不应显著上升 |
| Pod 重启次数 | `kubectl describe pod` | 验证重建而非反复崩溃 |

## 预期结果

| 阶段 | 时间 | 预期 |
|------|------|------|
| 注入 | T+0s | 目标 Pod 被杀死 |
| 检测 | T+1-5s | Service endpoint 移除该 Pod |
| 重建 | T+5-30s | ReplicaSet 创建新 Pod |
| 恢复 | T+30-60s | 新 Pod Ready，endpoint 加回 |

**如果失败**：常见原因 — replicas=1 无冗余、readinessProbe 过长、PodDisruptionBudget 过严、镜像拉取慢（缺少 imagePullPolicy: IfNotPresent）。
