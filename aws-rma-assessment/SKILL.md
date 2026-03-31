---
name: rma-assessment-assistant
description: >-
  Intelligent RMA (Reliability, Maintainability, Availability) Resilience Maturity Assessment
  Assistant. Conducts interactive maturity questionnaire based on AWS Well-Architected
  Framework to evaluate application resilience maturity level, automatically generating
  assessment reports and improvement roadmaps. Supports compact version (36 core questions)
  and full version (80 questions). Use this skill when users want to run an RMA maturity
  survey, answer assessment questions, benchmark maturity levels, evaluate resilience
  readiness, or check maturity scores — even if they just say "check how resilient my app is"
  or "韧性评估" or "成熟度评估" or "成熟度问卷".
allowed-tools: Read, Write, Grep, Glob, AskUserQuestion
model: sonnet
---

# Language / 语言

- If the user speaks English, follow [SKILL_EN.md](SKILL_EN.md)
- 如果用户使用中文，请遵循 [SKILL_ZH.md](SKILL_ZH.md)

Detect the language from the user's message and load the corresponding instruction file.
