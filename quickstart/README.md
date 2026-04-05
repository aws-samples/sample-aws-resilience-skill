# Quick Start: EKS Resilience Assessment → Chaos Experiment

Get from assessment to chaos experiment in 5 minutes.

## Prerequisites
- EKS cluster with kubectl access
- AWS CLI configured
- jq installed

## Step 1: Deploy sample app (2 min)

```bash
kubectl create namespace quickstart-demo
kubectl apply -f sample-app/ -n quickstart-demo
kubectl get pods -n quickstart-demo
```

Wait until all pods are Running.

## Step 2: Run resilience assessment (3 min)

Tell your AI agent:

> "Run EKS resilience assessment on my cluster, namespace=quickstart-demo"

The `eks-resilience-checker` skill will scan your deployments and generate `output/assessment.json`.

## Step 3: Review findings

Check `output/assessment.json` — you should see FAIL on:
- **A1** (Replica Count): Both deployments have only 1 replica
- **A2** (Pod Disruption Budget): No PDB configured
- **A4** (Liveness Probe): No liveness probe configured
- **A5** (Readiness Probe): No readiness probe configured

See [expected-output/assessment-sample.json](expected-output/assessment-sample.json) for reference.

## Step 4: Run chaos experiment (optional)

Tell your AI agent:

> "Based on the assessment results, run chaos experiments on the failed items"

The `chaos-engineering-on-aws` skill will consume `assessment.json` as Method 3 input, automatically designing experiments targeting the identified weaknesses.

## What's Next

- Fix the FAIL items (add replicas, probes, PDB) and re-assess to see improvements
- Explore the full 4-skill resilience lifecycle:
  1. **aws-rma-assessment** — Organizational resilience maturity assessment
  2. **aws-resilience-modeling** — Technical architecture risk analysis
  3. **eks-resilience-checker** — Kubernetes-specific resilience checks
  4. **chaos-engineering-on-aws** — Validate resilience through controlled experiments
