---
name: aws-resilience-modeling
description: >-
  Conduct comprehensive AWS system architecture resilience analysis and risk identification.
  Use when the user wants to perform architecture analysis, identify failure modes,
  map system components and dependencies, assess risk priorities, or create disaster
  recovery plans. Also use for failure mode analysis, component dependency mapping,
  risk scoring, and mitigation strategy design — even if they don't explicitly say
  "resilience". Automatically invoked for AWS韧性分析, 架构分析, 系统风险评估,
  AWS弹性评估, 可靠性评估, 灾难恢复规划, 故障模式分析, 组件依赖分析, 风险识别.
allowed-tools: Bash(aws *), Bash(gh *), Read, Write, Grep, Glob
model: sonnet
---

# Language / 语言

- If the user speaks English, follow [SKILL_EN.md](SKILL_EN.md)
- 如果用户使用中文，请遵循 [SKILL_ZH.md](SKILL_ZH.md)

Detect the language from the user's message and load the corresponding instruction file.
