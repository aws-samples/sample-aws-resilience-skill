# Assessment Workflow — Detailed Steps

## Step 0: Scenario Identification (Optional)

Before starting the assessment, confirm the user scenario is suitable for RMA assessment.

**Recommended Use Cases**:
1. **Customer Requests Guidance** — Customer proactively requests establishing a continuous resilience improvement program
2. **Resilience Gaps Identified** — Account team detects significant gaps in customer resilience posture, or a recent major incident occurred
3. **Conversation Starter** — As an entry point for discussing specific resilience areas (e.g., DR, HA) with customers

**Not Suitable For**: Formal compliance audits, legally/regulatory required formal assessments, scenarios requiring official AWS certification.

## Step 1: Version Selection

Use the AskUserQuestion tool to present a comparison of the two versions:

```yaml
question: "Please select the RMA assessment version:"
header: "Assessment Version"
multiSelect: false
options:
  - label: "Compact - Quick Assessment (Recommended)"
    description: "36 core questions (P0+P1 priority), focusing on key resilience indicators. Covers recovery objectives, SLOs, DR strategies, HA controls, deployment strategies, incident management, and more. Ideal for quickly understanding current resilience posture and identifying critical risks."

  - label: "Full - Deep Assessment"
    description: "All 82 questions (P0-P3), covering all resilience domains. Additionally covers chaos engineering, game days, organizational learning, and other maturity uplift areas. Ideal for comprehensive resilience maturity assessment and long-term improvement planning."
```

## Step 2: Batch Information Collection

Collecting all basic information at once is more efficient than multiple rounds. Include the following in the welcome message:

**Welcome Message Template:**
```
Welcome to the RMA Resilience Assessment Assistant! I will help you quickly assess your application's resilience maturity.

For the most accurate assessment, please provide the following information at once (copy-paste friendly):

[Application Basics]
- Application name:
- Brief description:
- Business criticality: High/Medium/Low
- User scale:
- Service regions:

[Technical Architecture]
- Architecture doc path: (file path or URL, if available)
- IaC code path: (CloudFormation/Terraform, if available)
- Primary AWS services: (e.g., EC2, RDS, S3)
- Deployment regions/AZs: (e.g., us-east-1 with 3 AZs)

[Current Resilience Status]
- RTO target: (e.g., 15 minutes, or "undefined")
- RPO target: (e.g., near-zero, or "undefined")
- DR plan: Yes/No (if yes, briefly describe strategy)
- Recent incidents: (date and brief description, or "none")

Tip: If unsure about any item, you may enter "unsure" or "TBD" and I will help clarify during subsequent questions.
```

**Information Collection Strategy**:
1. **One-time collection**: Request all basic info in the welcome message
2. **Fault-tolerant**: Allow users to skip or enter "unsure"
3. **Auto-complete**: Automatically correlate and fill in missing info during subsequent Q&A
4. **Smart inference**: Infer other related information from partial inputs
