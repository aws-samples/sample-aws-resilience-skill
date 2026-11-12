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

### What does this enable you to verify?

- Kubernetes liveness/readiness probe configuration effectiveness
- HPA scaling response when pod count drops below threshold
- Service mesh / load balancing redistribution speed
- PodDisruptionBudget enforcement during voluntary disruptions
- Application graceful shutdown handling (SIGTERM → preStop hook)

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

# Using experiment-runner.sh (recommended — handles polling + state):
nohup bash scripts/experiment-runner.sh --mode chaosmesh \
    --manifest examples/pod-kill-web-frontend.yaml --namespace production \
    --one-shot --pod-label "app=web-frontend" --deployment "web-frontend" \
    --state-exp-id "EXP-001" --output-dir output/ --yes &
RUNNER_PID=$!

# Monitor (omit EXPERIMENT_ID for Chaos Mesh):
export NAMESPACE="production" REGION="ap-northeast-1" DURATION=300
nohup bash scripts/monitor.sh &

# Log collector (MANDATORY for all experiments):
nohup bash scripts/log-collector.sh --namespace production \
    --services "web-frontend" --mode live --duration 300 --output-dir output/ &

wait $RUNNER_PID
# Exit code: 0=completed (one-shot), 1=failed, 2=timeout

# Manual alternative (without scripts):
kubectl apply -f examples/pod-kill-web-frontend.yaml
kubectl get pods -n production -l app=web-frontend -w
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
