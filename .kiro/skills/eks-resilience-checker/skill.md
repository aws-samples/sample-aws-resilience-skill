---
name: eks-resilience-checker
description: Assess Amazon EKS cluster resilience against 26 best practice checks covering application workloads, control plane, and data plane. Outputs structured assessment.json for chaos-engineering-on-aws integration. Use when the user wants to evaluate EKS cluster resilience, run resilience assessment, check EKS best practices, or prepare for chaos experiments. Triggers on EKS resilience, 韧性评估, cluster assessment, resilience check, EKS best practices, 集群评估, resiliency check.
allowed-tools: Bash(kubectl *), Bash(aws *), Bash(jq *), Bash(bash *), Bash(cat *), Read, Write, Grep, Glob, awslabs.eks-mcp-server, awslabs.aws-api-mcp-server, awslabs.cloudwatch-mcp-server, awslabs.aws-pricing-mcp-server
model: sonnet
---

# Working Directory

**IMPORTANT**: This skill's working directory is `eks-resilience-checker/`.
All file paths in the instruction files are relative to `eks-resilience-checker/`.

Before executing any commands or file operations, `cd` into `eks-resilience-checker/`:
```bash
cd eks-resilience-checker
```

When using Read/Write/Glob tools, always prefix paths with `eks-resilience-checker/`.

# Language Router

Detect the language from the user's message:

- **English** → Read and follow the instructions in `eks-resilience-checker/SKILL_EN.md`
- **中文** → 读取并遵循 `eks-resilience-checker/SKILL_ZH.md` 中的指令
