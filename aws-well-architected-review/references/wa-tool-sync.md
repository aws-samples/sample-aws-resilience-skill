# AWS WA Tool Sync — Optional Post-Assessment

> **This step is OPTIONAL.** It requires write permissions to the AWS WA Tool API (`wellarchitected:*`).
> Use separate credentials from the read-only assessment credentials.

## Prerequisites

- Completed WA Review assessment with findings
- IAM role/user with `wellarchitected:*` permissions
- AWS CLI configured with the write-capable credentials

## Required IAM Policy

```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Action": [
      "wellarchitected:CreateWorkload",
      "wellarchitected:UpdateWorkload",
      "wellarchitected:GetWorkload",
      "wellarchitected:ListWorkloads",
      "wellarchitected:AssociateLenses",
      "wellarchitected:ListLensReviews",
      "wellarchitected:ListAnswers",
      "wellarchitected:UpdateAnswer",
      "wellarchitected:GetAnswer",
      "wellarchitected:CreateMilestone",
      "wellarchitected:GetLensReview",
      "wellarchitected:GetLensReviewReport",
      "wellarchitected:TagResource"
    ],
    "Resource": "*"
  }]
}
```

## Sync Flow

### Step 1: Create or Find Workload

```bash
# List existing workloads
aws wellarchitected list-workloads --query 'WorkloadSummaries[].{Id:WorkloadId,Name:WorkloadName}' --output table

# Create new workload
aws wellarchitected create-workload \
  --workload-name "{workload_name}" \
  --description "WA Review - {date}" \
  --environment PRODUCTION \
  --aws-regions "{region}" \
  --review-owner "{owner_email}" \
  --lenses wellarchitected \
  --query 'WorkloadId' --output text
```

### Step 2: Associate Lenses

```bash
aws wellarchitected associate-lenses \
  --workload-id {workload_id} \
  --lens-aliases wellarchitected
```

### Step 3: Populate Answers

For each pillar, list questions and update answers based on assessment findings:

```bash
# List questions for a pillar
aws wellarchitected list-answers \
  --workload-id {workload_id} \
  --lens-alias wellarchitected \
  --pillar-id security \
  --query 'AnswerSummaries[].{QuestionId:QuestionId,QuestionTitle:QuestionTitle}' \
  --output table

# Update an answer
aws wellarchitected update-answer \
  --workload-id {workload_id} \
  --lens-alias wellarchitected \
  --question-id {question_id} \
  --selected-choices {choice_id_1} {choice_id_2} \
  --notes "Assessment finding: {finding_summary}" \
  --is-applicable
```

### Step 4: Create Milestone

```bash
aws wellarchitected create-milestone \
  --workload-id {workload_id} \
  --milestone-name "AI-WA Review {date}" \
  --query 'MilestoneNumber' --output text
```

### Step 5: Generate WA Tool Report

```bash
aws wellarchitected get-lens-review \
  --workload-id {workload_id} \
  --lens-alias wellarchitected \
  --output json

aws wellarchitected get-lens-review-report \
  --workload-id {workload_id} \
  --lens-alias wellarchitected \
  --query 'LensReviewReport.Base64String' --output text | base64 -d > wa-tool-report.pdf
```

## Pillar ID Mapping

| Pillar | WA Tool Pillar ID |
|--------|------------------|
| Security | `security` |
| Operational Excellence | `operationalExcellence` |
| Reliability | `reliability` |
| Performance Efficiency | `performance` |
| Cost Optimization | `costOptimization` |
| Sustainability | `sustainability` |

## Error Handling

| Error | Action |
|-------|--------|
| ConflictException (workload exists) | Offer to update existing workload |
| ValidationException (invalid choice) | Log and skip that question |
| ThrottlingException (429) | Exponential backoff |
| AccessDeniedException | Missing WA Tool permissions — guide IAM setup |
