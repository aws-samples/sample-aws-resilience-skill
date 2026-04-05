# Emergency Stop Procedures

> **Use this document when a chaos experiment goes out of control and must be stopped immediately.**

Three escalating levels of emergency stop — use the lowest level that achieves full containment.

---

## Level 1: Graceful Stop (Preferred)

**Use when**: The experiment is still running normally but you need to halt it immediately.

Stop FIS experiment by ID:

```bash
# Get the running experiment ID (if you don't have it on hand)
aws fis list-experiments --query 'experiments[?state.status==`running`].[id,experimentTemplateId]' --output table

# Stop the experiment
aws fis stop-experiment --id <EXPERIMENT_ID>

# Verify it stopped
aws fis get-experiment --id <EXPERIMENT_ID> --query 'experiment.state.status'
```

Stop Chaos Mesh experiment by deleting the CR:

```bash
# List running Chaos Mesh resources
kubectl get podchaos,networkchaos,httpchaos,stresschaos,iochaos,dnschaos -A

# Delete by name (fastest)
kubectl delete podchaos <NAME> -n <NAMESPACE>
kubectl delete networkchaos <NAME> -n <NAMESPACE>

# Or delete all in a namespace at once
kubectl delete podchaos,networkchaos,httpchaos,stresschaos,iochaos,dnschaos --all -n <NAMESPACE>
```

**Expected recovery time**: FIS auto-reverts within seconds to minutes (e.g., NACLs restored, stopped instances restarted if configured). Chaos Mesh CR deletion triggers immediate cleanup.

---

## Level 2: Force Delete Experiment Manifest (If Level 1 Fails)

**Use when**: Level 1 did not stop the experiment, or the experiment is stuck in a non-terminal state.

```bash
# Force-delete the Chaos Mesh CR
kubectl delete -f chaos-experiment.yaml --force --grace-period=0

# For FIS: if stop-experiment hangs, check experiment state
aws fis get-experiment --id <EXPERIMENT_ID>

# If FIS NACLs are not restored automatically, restore them manually:
# 1. Find the temporary NACL created by FIS (tagged with FIS experiment ID)
aws ec2 describe-network-acls \
  --filters "Name=tag-key,Values=aws:fis:experiment-id" \
  --query 'NetworkAcls[*].[NetworkAclId,Associations[*].SubnetId]'

# 2. Restore original NACL associations (replace with your subnet/NACL IDs)
aws ec2 replace-network-acl-association \
  --association-id <ASSOCIATION_ID> \
  --network-acl-id <ORIGINAL_NACL_ID>

# 3. Delete the FIS-created temporary NACL
aws ec2 delete-network-acl --network-acl-id <TEMP_NACL_ID>
```

**Expected recovery time**: Within 1–2 minutes after force deletion. Monitor CloudWatch alarms to confirm.

---

## Level 3: Nuclear Option — Delete Chaos Mesh CRD (Last Resort)

> ⚠️ **WARNING**: This removes Chaos Mesh entirely from the cluster. All in-flight experiments are instantly terminated. Use ONLY when Levels 1 and 2 have failed and the system is experiencing unacceptable impact.

```bash
# Step 1: Delete all Chaos Mesh custom resources first (best effort)
kubectl delete podchaos,networkchaos,httpchaos,stresschaos,iochaos,dnschaos --all -A --force --grace-period=0 2>/dev/null || true

# Step 2: Delete the CRDs (this terminates ALL Chaos Mesh experiments immediately)
kubectl delete crd podchaos.chaos-mesh.org
kubectl delete crd networkchaos.chaos-mesh.org
kubectl delete crd httpchaos.chaos-mesh.org
kubectl delete crd stresschaos.chaos-mesh.org
kubectl delete crd iochaos.chaos-mesh.org
kubectl delete crd dnschaos.chaos-mesh.org
kubectl delete crd physicalmachinechaos.chaos-mesh.org
kubectl delete crd workflownode.chaos-mesh.org
kubectl delete crd workflow.chaos-mesh.org

# Step 3: Remove Chaos Mesh Helm release (prevents controller from re-creating CRDs)
helm uninstall chaos-mesh -n chaos-mesh

# Step 4: Verify no chaos pods remain
kubectl get pods -n chaos-mesh
kubectl delete namespace chaos-mesh --force --grace-period=0
```

**To reinstall Chaos Mesh after the incident**:

```bash
helm repo add chaos-mesh https://charts.chaos-mesh.org
helm install chaos-mesh chaos-mesh/chaos-mesh \
  --namespace chaos-mesh --create-namespace \
  --set chaosDaemon.runtime=containerd \
  --set chaosDaemon.socketPath=/run/containerd/containerd.sock
```

---

## Post-Emergency Verification Checklist

After any emergency stop, verify system health before resuming normal operations:

```bash
# 1. Confirm experiment is stopped
aws fis get-experiment --id <EXPERIMENT_ID> --query 'experiment.state.status'

# 2. Check FIS-modified network resources have been reverted
aws ec2 describe-network-acls \
  --filters "Name=tag-key,Values=aws:fis:experiment-id" \
  --query 'NetworkAcls[*].NetworkAclId'
# Should return empty list

# 3. Confirm target resources are healthy
aws ec2 describe-instance-status --include-all-instances \
  --filters "Name=instance-state-name,Values=running"
aws rds describe-db-clusters --query 'DBClusters[*].[DBClusterIdentifier,Status]'
kubectl get pods -n <TARGET_NAMESPACE>

# 4. Check CloudWatch alarms are back to OK
aws cloudwatch describe-alarms --state-value ALARM \
  --query 'MetricAlarms[*].[AlarmName,StateReason]'

# 5. Verify application health (replace with your health check endpoint)
curl -I https://<YOUR_APP_ENDPOINT>/health
```

---

## Quick Reference Card

| Situation | Command |
|-----------|---------|
| Stop FIS experiment | `aws fis stop-experiment --id <ID>` |
| Stop Chaos Mesh CR | `kubectl delete podchaos <NAME> -n <NS>` |
| Force-stop all chaos in namespace | `kubectl delete podchaos,networkchaos,httpchaos,stresschaos --all -n <NS> --force` |
| Nuclear option | `kubectl delete crd podchaos.chaos-mesh.org` (then other CRDs) |
| Check FIS experiment status | `aws fis get-experiment --id <ID> --query 'experiment.state.status'` |
| Find running FIS experiments | `aws fis list-experiments --query 'experiments[?state.status==\`running\`].[id]'` |

---

> **See also**: [prerequisites-checklist.md](prerequisites-checklist.md) — pre-experiment safety checks
> **See also**: [gameday.md](gameday.md) — structured exercise procedures with designated safety officers
