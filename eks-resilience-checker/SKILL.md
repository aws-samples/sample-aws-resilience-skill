---
name: eks-resilience-checker
description: Assess Amazon EKS cluster resilience against 26 best practice checks covering application workloads, control plane, and data plane. Outputs structured assessment.json for chaos-engineering-on-aws integration. Use when the user wants to evaluate EKS cluster resilience, run resilience assessment, check EKS best practices, or prepare for chaos experiments. Triggers on EKS resilience, 韧性评估, cluster assessment, resilience check, EKS best practices, 集群评估, resiliency check.
allowed-tools: Bash(kubectl *), Bash(aws *), Bash(jq *), Bash(bash *), Bash(cat *), Read, Write, Grep, Glob, awslabs.eks-mcp-server, awslabs.aws-api-mcp-server, awslabs.cloudwatch-mcp-server, awslabs.aws-pricing-mcp-server
model: sonnet
---

# Language / 语言

- If the user speaks English, follow [SKILL_EN.md](SKILL_EN.md)
- 如果用户使用中文，请遵循 [SKILL_ZH.md](SKILL_ZH.md)

Detect the language from the user's message and load the corresponding instruction file.
