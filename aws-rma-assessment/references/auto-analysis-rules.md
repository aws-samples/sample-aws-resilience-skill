# Auto-Analysis Rules — Intelligent Inference Engine

## Goal
Automatically answer 60-70% of questions, reducing user burden.

## 3.1 Document and Code Analysis

If the user provides architecture docs or IaC code, immediately perform auto-analysis:

| Analysis Item | Search Keywords/Patterns | Auto-Answerable Questions | Tool |
|---------------|--------------------------|---------------------------|------|
| **Multi-AZ Deployment** | `MultiAZ`, `multi_az_enabled`, `availability_zone` | Q36 (fault isolation), Q35 (hard deps) | Grep |
| **Backup Strategy** | `backup`, `snapshot`, `BackupRetentionPeriod` | Q30 (data recovery validation) | Grep |
| **Auto Scaling** | `AutoScaling`, `ScalingPolicy`, `min_size`, `max_size` | Q39 (service limits), Q12 (load changes) | Grep |
| **Monitoring Config** | `CloudWatch`, `Alarm`, `MetricFilter`, `monitoring` | Q13-26 (all observability questions) | Grep |
| **DR Config** | `ReplicationConfiguration`, `GlobalCluster`, `cross-region` | Q27-34 (disaster recovery questions) | Grep |
| **Deployment Strategy** | `DeploymentStrategy`, `BlueGreen`, `Canary`, `CodeDeploy` | Q40-46 (change management questions) | Grep |
| **Log Config** | `LogGroup`, `LogStream`, `logging_enabled` | Q14-15 (log-related) | Grep |
| **Health Checks** | `HealthCheck`, `health_check_path`, `TargetGroup` | Q38 (HA effectiveness) | Grep |

## 3.2 Context Inference Rules

Based on collected information and answered questions, automatically infer related question answers:

1. **If RTO < 1 hour** -> Q27 (DR strategy) >= Level 2 [Source: user-stated target, confidence: medium — verify with "Has this RTO been validated through DR testing?"], Q36 (fault isolation) >= Level 2, Q40 (deployment method) >= Level 2
2. **If deployment regions > 1** -> Q27 (DR strategy) >= Level 2 [Source: infrastructure config, confidence: high — but multi-region deployment alone does not imply mature DR; Level 3 requires verified automated failover + quarterly testing], Q36 (fault isolation) >= Level 2
3. **If CloudWatch Alarm config found** -> Q13 (metrics established) >= Level 2 [Source: IaC/config verified, confidence: high], Q19 (availability monitoring) >= Level 2, Q23 (alert strategy) >= Level 2
4. **If CodePipeline/CodeDeploy found** -> Q40 (deployment method) >= Level 2 [Source: IaC/config verified, confidence: high], Q43 (automation integration) >= Level 2
5. **If business criticality = "High"** -> Q3 (criticality) = Level 3, Q2 (SLO) suggest >= 99.99%

## 3.3 Inference Confidence Classification

- **Evidence-based** (high confidence): Directly extracted from IaC code, AWS config, or API output. Can be auto-answered without confirmation.
- **Goal-stated** (medium confidence): Based on user-declared targets (e.g., "our RTO is 1 hour"). Must ask: "Has this target been validated through testing?"
- **Inferred** (low confidence): Derived from other answers or assumptions. Must be presented to user for explicit confirmation.

### Confidence-Based Decision Matrix

| Confidence | Action | Report Display | Example |
|------------|--------|---------------|---------|
| **High** (Evidence-based) | Auto-fill, no confirmation needed | ✅ Auto-assessed (evidence: {source}) | CloudWatch Alarm found in IaC → Q13 ≥ Level 2 |
| **Medium** (Goal-stated) | Auto-fill + MUST ask confirmation question | ⚠️ Inferred from stated goal — please confirm | User says "RTO < 1h" → Q27 ≥ Level 2, ask "Has this RTO been validated through DR testing?" |
| **Low** (Inferred) | DO NOT auto-fill, MUST ask user | ❓ Unable to determine — user input required | Single region detected → cannot infer DR maturity level |

### Processing Rules

1. High-confidence: Apply immediately, show in report with evidence source. User can override.
2. Medium-confidence: Apply tentatively, generate a confirmation question. If user does not confirm within the session, downgrade to "Unverified" in report.
3. Low-confidence: Skip auto-fill entirely. Add to "Questions Requiring Input" queue.
4. When >5 low-confidence items remain after initial analysis, offer batch-question mode: present all remaining questions in a numbered list for efficient answering.

## 3.4 Auto-Answer Output Format

Generate auto-answer summary in three categories:
- **High-confidence auto-answers**: Directly extracted from files/configurations
- **Medium-confidence inferences**: Context-based inferences requiring user confirmation
- **Requires user input**: Will be asked during batch Q&A

Each auto-answer must include **confidence level** and **analysis basis**, allowing user corrections. Prioritize auto-answering P0/P1 questions.
