# 快速开始：EKS 韧性评估 → 混沌实验

5 分钟内从评估到混沌实验。

## 前置条件
- 已配置 kubectl 访问的 EKS 集群
- AWS CLI 已配置
- 已安装 jq

## 步骤 1：部署示例应用（2 分钟）

```bash
kubectl create namespace quickstart-demo
kubectl apply -f sample-app/ -n quickstart-demo
kubectl get pods -n quickstart-demo
```

等待所有 Pod 进入 Running 状态。

## 步骤 2：运行韧性评估（3 分钟）

告诉你的 AI 助手：

> "对我的集群运行 EKS 韧性评估，namespace=quickstart-demo"

`eks-resilience-checker` 技能将扫描你的部署并生成 `output/assessment.json`。

## 步骤 3：查看评估结果

检查 `output/assessment.json` — 你应该看到以下 FAIL 项：
- **A1**（副本数量）：两个 Deployment 都只有 1 个副本
- **A2**（Pod Disruption Budget）：未配置 PDB
- **A4**（存活探针）：未配置 Liveness Probe
- **A5**（就绪探针）：未配置 Readiness Probe

参考 [expected-output/assessment-sample.json](expected-output/assessment-sample.json) 了解预期输出。

## 步骤 4：运行混沌实验（可选）

告诉你的 AI 助手：

> "根据评估结果，对失败项运行混沌实验"

`chaos-engineering-on-aws` 技能将以方式 3 消费 `assessment.json`，自动设计针对已识别弱点的实验。

## 下一步

- 修复 FAIL 项（添加副本、探针、PDB），重新评估查看改进效果
- 探索完整的 4 技能韧性生命周期：
  1. **aws-rma-assessment** — 组织韧性成熟度评估
  2. **aws-resilience-modeling** — 技术架构风险分析
  3. **eks-resilience-checker** — Kubernetes 专项韧性检查
  4. **chaos-engineering-on-aws** — 通过受控实验验证韧性
