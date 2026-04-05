# 应急停止程序

> **当混沌实验失控、必须立即终止时，请使用本文档。**

三级应急停止，从低到高依次升级——优先使用能实现完全控制的最低级别。

---

## 第一级：优雅停止（首选）

**适用场景**：实验仍在正常运行，但需要立即中止。

通过 ID 停止 FIS 实验：

```bash
# 获取运行中的实验 ID（如手头没有）
aws fis list-experiments --query 'experiments[?state.status==`running`].[id,experimentTemplateId]' --output table

# 停止实验
aws fis stop-experiment --id <EXPERIMENT_ID>

# 确认已停止
aws fis get-experiment --id <EXPERIMENT_ID> --query 'experiment.state.status'
```

通过删除 CR 停止 Chaos Mesh 实验：

```bash
# 列出运行中的 Chaos Mesh 资源
kubectl get podchaos,networkchaos,httpchaos,stresschaos,iochaos,dnschaos -A

# 按名称删除（最快）
kubectl delete podchaos <NAME> -n <NAMESPACE>
kubectl delete networkchaos <NAME> -n <NAMESPACE>

# 或一次删除某命名空间下所有混沌资源
kubectl delete podchaos,networkchaos,httpchaos,stresschaos,iochaos,dnschaos --all -n <NAMESPACE>
```

**预期恢复时间**：FIS 在数秒至数分钟内自动回滚（如 NACL 恢复、已配置的实例重启）。Chaos Mesh CR 删除后立即触发清理。

---

## 第二级：强制删除实验清单（第一级失败时使用）

**适用场景**：第一级未能停止实验，或实验卡在非终态。

```bash
# 强制删除 Chaos Mesh CR
kubectl delete -f chaos-experiment.yaml --force --grace-period=0

# FIS 方面：如果 stop-experiment 挂起，先检查实验状态
aws fis get-experiment --id <EXPERIMENT_ID>

# 如果 FIS 创建的 NACL 未自动恢复，手动恢复：
# 1. 找到 FIS 创建的临时 NACL（带有 FIS 实验 ID 标签）
aws ec2 describe-network-acls \
  --filters "Name=tag-key,Values=aws:fis:experiment-id" \
  --query 'NetworkAcls[*].[NetworkAclId,Associations[*].SubnetId]'

# 2. 恢复原始 NACL 关联（替换为实际的子网/NACL ID）
aws ec2 replace-network-acl-association \
  --association-id <ASSOCIATION_ID> \
  --network-acl-id <ORIGINAL_NACL_ID>

# 3. 删除 FIS 创建的临时 NACL
aws ec2 delete-network-acl --network-acl-id <TEMP_NACL_ID>
```

**预期恢复时间**：强制删除后 1–2 分钟内恢复。通过 CloudWatch 告警确认状态。

---

## 第三级：核弹选项 — 删除 Chaos Mesh CRD（最后手段）

> ⚠️ **警告**：此操作会将 Chaos Mesh 从集群中完全移除，所有进行中的实验会立即终止。**仅在第一、二级均失败且系统正在遭受不可接受的影响时使用。**

```bash
# 步骤 1：尽力删除所有 Chaos Mesh 自定义资源
kubectl delete podchaos,networkchaos,httpchaos,stresschaos,iochaos,dnschaos --all -A --force --grace-period=0 2>/dev/null || true

# 步骤 2：删除 CRD（立即终止所有 Chaos Mesh 实验）
kubectl delete crd podchaos.chaos-mesh.org
kubectl delete crd networkchaos.chaos-mesh.org
kubectl delete crd httpchaos.chaos-mesh.org
kubectl delete crd stresschaos.chaos-mesh.org
kubectl delete crd iochaos.chaos-mesh.org
kubectl delete crd dnschaos.chaos-mesh.org
kubectl delete crd physicalmachinechaos.chaos-mesh.org
kubectl delete crd workflownode.chaos-mesh.org
kubectl delete crd workflow.chaos-mesh.org

# 步骤 3：卸载 Chaos Mesh Helm release（防止 controller 重建 CRD）
helm uninstall chaos-mesh -n chaos-mesh

# 步骤 4：确认无 chaos pod 残留
kubectl get pods -n chaos-mesh
kubectl delete namespace chaos-mesh --force --grace-period=0
```

**事件处理完毕后重新安装 Chaos Mesh**：

```bash
helm repo add chaos-mesh https://charts.chaos-mesh.org
helm install chaos-mesh chaos-mesh/chaos-mesh \
  --namespace chaos-mesh --create-namespace \
  --set chaosDaemon.runtime=containerd \
  --set chaosDaemon.socketPath=/run/containerd/containerd.sock
```

---

## 应急停止后验证清单

任何应急停止操作后，在恢复正常运营之前，务必验证系统健康状态：

```bash
# 1. 确认实验已停止
aws fis get-experiment --id <EXPERIMENT_ID> --query 'experiment.state.status'

# 2. 确认 FIS 修改的网络资源已回滚
aws ec2 describe-network-acls \
  --filters "Name=tag-key,Values=aws:fis:experiment-id" \
  --query 'NetworkAcls[*].NetworkAclId'
# 应返回空列表

# 3. 确认目标资源健康
aws ec2 describe-instance-status --include-all-instances \
  --filters "Name=instance-state-name,Values=running"
aws rds describe-db-clusters --query 'DBClusters[*].[DBClusterIdentifier,Status]'
kubectl get pods -n <TARGET_NAMESPACE>

# 4. 确认 CloudWatch 告警已恢复 OK
aws cloudwatch describe-alarms --state-value ALARM \
  --query 'MetricAlarms[*].[AlarmName,StateReason]'

# 5. 验证应用健康（替换为实际健康检查端点）
curl -I https://<YOUR_APP_ENDPOINT>/health
```

---

## 快速参考卡

| 场景 | 命令 |
|------|------|
| 停止 FIS 实验 | `aws fis stop-experiment --id <ID>` |
| 停止 Chaos Mesh CR | `kubectl delete podchaos <NAME> -n <NS>` |
| 强制停止命名空间内所有混沌 | `kubectl delete podchaos,networkchaos,httpchaos,stresschaos --all -n <NS> --force` |
| 核弹选项 | `kubectl delete crd podchaos.chaos-mesh.org`（然后删除其他 CRD） |
| 查询 FIS 实验状态 | `aws fis get-experiment --id <ID> --query 'experiment.state.status'` |
| 查找运行中的 FIS 实验 | `aws fis list-experiments --query 'experiments[?state.status==\`running\`].[id]'` |

---

> **参见**：[prerequisites-checklist_zh.md](prerequisites-checklist_zh.md) — 实验前安全检查
> **参见**：[gameday_zh.md](gameday_zh.md) — 含指定安全官的结构化演练程序
