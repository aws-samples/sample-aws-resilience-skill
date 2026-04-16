---
name: aws-well-architected-review
description: >-
  Conduct automated AWS Well-Architected Framework Review across all 6 pillars.
  Use when the user wants a full architecture review, security assessment, cost optimization,
  reliability check, performance audit, or sustainability evaluation of their AWS environment.
  Automatically runs programmatic checks via AWS CLI (read-only), identifies risks (HRI/MRI),
  and generates comprehensive reports. Supports autopilot mode with minimal human interaction.
  Also use for AWS架构评审, Well-Architected评估, 安全评估, 成本优化, 可靠性检查, 性能审计.
allowed-tools: Bash(aws *), Read, Write, Grep, Glob
model: sonnet
---

# Language / 语言

- If the user speaks English, follow [SKILL_EN.md](SKILL_EN.md)
- 如果用户使用中文，请遵循 [SKILL_ZH.md](SKILL_ZH.md)

Detect the language from the user's message and load the corresponding instruction file.
