# Example 3: EKS Pod Kill — Microservice Self-Healing Validation

**Architecture pattern**: EKS microservices (Deployment + Service + Ingress)
**Tool**: Chaos Mesh PodChaos (requires cluster installation)
**Validation target**: ReplicaSet auto-recreates Pod, traffic switches seamlessly via Service

---

## Prerequisites

- Cluster has Chaos Mesh installed: `kubectl get crd | grep chaos-mesh`
- Target Deployment replicas >= 2

If Chaos Mesh is not installed, use FIS `aws:eks:terminate-nodegroup-instances` for **node-level** fault as an alternative (larger blast radius).

> ⚠️ Not recommended to use FIS `aws:eks:pod-delete` for Pod-level faults — requires additional K8s ServiceAccount + RBAC + EKS access entry, and fault injector Pod initialization is slow (>2min). Prefer Chaos Mesh for Pod-level faults.

## Steady-State Hypothesis

After killing 1 Pod of the target service:
- Service request success rate >= 99.9%
- P99 latency <= 300ms
- Pod rebuilt and enters Ready state within 60s
- Zero request loss (other Pods take over traffic)

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

## Using MCP (if available)

```python
# chaosmesh-mcp call
pod_kill(
    service="web-frontend",
    duration="30s",
    mode="one",
    namespace="production"
)
```

## Execution Commands

```bash
# Check target Pod count
kubectl get pods -n production -l app=web-frontend

# Inject fault
kubectl apply -f examples/pod-kill-web-frontend.yaml

# Observe Pod recreation
kubectl get pods -n production -l app=web-frontend -w

# Cleanup (auto-cleans on expiry, or manual)
kubectl delete -f examples/pod-kill-web-frontend.yaml
```

## Observation Metrics

| Metric | Source | Description |
|------|------|------|
| Pod Ready count | `kubectl get pods` | Should quickly recover to desired count |
| Request success rate | Ingress / ALB metrics | Should not drop below 99.9% |
| P99 latency | Application metrics / CloudWatch | Should not significantly increase |
| Pod restart count | `kubectl describe pod` | Verify recreation, not repeated crashes |

## Expected Results

| Phase | Time | Expected |
|------|------|------|
| Injection | T+0s | Target Pod killed |
| Detection | T+1-5s | Service endpoint removes the Pod |
| Recreation | T+5-30s | ReplicaSet creates new Pod |
| Recovery | T+30-60s | New Pod Ready, endpoint added back |

**If failed**: Common causes — replicas=1 (no redundancy), readinessProbe too long, PodDisruptionBudget too strict, slow image pull (missing imagePullPolicy: IfNotPresent).
