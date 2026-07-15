---
name: selfhosted-stack-analyzer
description: >-
  Map the topology and analyze resilience weaknesses of self-hosted stateful
  middleware (MySQL, TiDB, TiKV, PD, Redis, Kafka, ZooKeeper) running as workloads
  on Amazon EKS, OR directly on dedicated EC2 hosts distinguished by their EC2
  Name tag. Runs in two phases: Phase 1 collects a comprehensive evidence
  bundle (EKS via kubectl, and/or raw EC2 via describe-instances grouped by Name
  tag) from the live environment (online), Phase 2 analyzes it offline to produce a
  topology diagram (Mermaid) and a prioritized weakness report. Use when the user
  wants to draw the architecture/topology of self-hosted components on EKS, find
  single points of failure, assess AZ-failure blast radius, or review the resilience
  of self-managed databases/message-queues on Kubernetes. Also invoked for
  自建组件拓扑, 自建中间件薄弱点, EKS 自建数据库分析, 拓扑图绘制, TiDB/TiKV 韧性,
  Redis 集群薄弱点, Kafka 韧性分析, 有状态服务 SPOF 分析, 分两阶段采集分析.
allowed-tools: Bash(kubectl *), Bash(aws *), Bash(jq *), Bash(bash *), Bash(cat *), Bash(tar *), Bash(mkdir *), Bash(helm *), Read, Write, Grep, Glob, awslabs.eks-mcp-server, awslabs.aws-api-mcp-server, awslabs.cloudwatch-mcp-server
model: sonnet
---

# Language / 语言

- If the user speaks English, follow [SKILL_EN.md](SKILL_EN.md)
- 如果用户使用中文，请遵循 [SKILL_ZH.md](SKILL_ZH.md)

Detect the language from the user's message and load the corresponding instruction file.
