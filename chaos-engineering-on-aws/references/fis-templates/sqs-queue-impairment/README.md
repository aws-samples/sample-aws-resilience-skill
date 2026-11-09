# SQS Queue Impairment — FIS Template

> Source: [aws-samples/fis-template-library](https://github.com/aws-samples/fis-template-library/tree/main/sqs-queue-impairment) (commit ee74d58) | License: MIT-0

## Hypothesis Template

> When the SQS service is experiencing an impairment in a region which impacts my application, an alarm
> should be raised and the DevOps team notified within 5 minutes. Functionality relating to component A
> should not be available to end users during the impairment; however, other components should continue
> to operate normally. Once the SQS impairment has been resolved, component A should become available to
> end users within 5 minutes.

## How It Works

The experiment simulates a worsening impairment in 4 rounds. Each round is one `aws:ssm:start-automation-execution` action (`maxDuration` PT1H each), separated by `aws:fis:wait` actions:

| Round | Block Duration | Recovery Window after it |
|-------|---------------|--------------------------|
| 1 | 2 minutes | 3 minutes |
| 2 | 5 minutes | 3 minutes |
| 3 | 7 minutes | 2 minutes |
| 4 | 15 minutes | — |

Total: about 37 minutes plus automation overhead. Each round:

1. `getTargetQueues` finds the queues tagged `FIS-Ready=True`.
2. `applyDenyAllPolicyToQueues` reads the queue policy and `QueueArn`, then adds a statement with `Sid: FISTemporaryDeny` through `SetQueueAttributes`. Despite the step name it is a **scoped** deny:
   - Actions: data-plane only — `SendMessage`, `ReceiveMessage`, `DeleteMessage`, `ChangeMessageVisibility`, `PurgeQueue`. Management actions (`SetQueueAttributes`, `AddPermission`, `RemovePermission`) are never denied, so the cleanup step (and your admins) can always remove the statement.
   - Resource: the queue's own ARN (not `*`).
   - Principal: `*` by default (full service partition). Set the optional document parameter `targetPrincipalArn` to your application's role ARN to impair only that principal and leave admins, monitoring and other consumers unaffected.
3. `waitForDuration` holds the impairment; callers in scope get `AccessDenied`.
4. `removeDenyAllPolicyFromQueues` removes the statement the same way it was added (`SetQueueAttributes`). If `FISTemporaryDeny` was the only statement it sets `Policy` to `''`. If removal fails on any queue the step **raises and fails** instead of reporting success, so a queue left impaired is visible in FIS.

**Key technique**: resource-policy denial — simulates service unavailability at the authorization layer.

## Prerequisites

- Target queues tagged `FIS-Ready=True` (the SSM role can only read/change policies of queues carrying this tag).
- FIS role: trust policy `fis-iam-trust-relationship.json` now carries a confused-deputy guard (`aws:SourceAccount` = your account, `aws:SourceArn` = `arn:aws:fis:<REGION>:<ACCOUNT>:experiment/*`); replace both placeholders. Permissions: start/get/stop the automation on your document and `iam:PassRole` on the SSM role only.
- SSM Automation role, split into two statements:
  - `AllowQueueDiscovery`: `sqs:ListQueues`, `sqs:ListQueueTags` on the account's queues.
  - `AllowPolicyChangeOnTaggedQueues`: `sqs:GetQueueAttributes`, `sqs:SetQueueAttributes`, conditioned on `aws:ResourceTag/FIS-Ready=True`. `AddPermission` / `RemovePermission` are no longer used or granted.
- Replace `<AUTOMATION DOCUMENT NAME>` consistently in the FIS role policy and the experiment template's `documentArn`.

## Files

| File | Description |
|------|-------------|
| `sqs-queue-impairment-tag-based-experiment-template.json` | FIS experiment template |
| `sqs-queue-impairment-tag-based-automation.yaml` | SSM Automation document |
| `sqs-queue-impairment-tag-based-fis-role-iam-policy.json` | IAM policy for FIS role |
| `sqs-queue-impairment-tag-based-ssm-automation-role-iam-policy.json` | IAM policy for SSM role |
| `fis-iam-trust-relationship.json` | Trust policy for FIS role (with `aws:SourceAccount` / `aws:SourceArn` condition) |
| `ssm-iam-trust-relationship.json` | Trust policy for SSM role |
| `AWSFIS.json` | Template-library metadata |

## Deployment

```bash
# 1. Create IAM roles (replace <YOUR REGION>/<YOUR AWS ACCOUNT> placeholders in all policies first)
aws iam create-role --role-name FIS-SqsImpairment --assume-role-policy-document file://fis-iam-trust-relationship.json
aws iam put-role-policy --role-name FIS-SqsImpairment --policy-name fis-policy --policy-document file://sqs-queue-impairment-tag-based-fis-role-iam-policy.json

aws iam create-role --role-name SSM-SqsImpairment --assume-role-policy-document file://ssm-iam-trust-relationship.json
aws iam put-role-policy --role-name SSM-SqsImpairment --policy-name ssm-policy --policy-document file://sqs-queue-impairment-tag-based-ssm-automation-role-iam-policy.json

# 2. Create SSM Automation document (name must match <AUTOMATION DOCUMENT NAME> in the FIS policy and template)
aws ssm create-document --name sqs-queue-impairment --document-type Automation --content file://sqs-queue-impairment-tag-based-automation.yaml --document-format YAML

# 3. Tag target SQS queues with FIS-Ready=True

# 4. Update experiment template with your role ARNs and document ARN
#    (optionally add "targetPrincipalArn" to each documentParameters), then:
aws fis create-experiment-template --cli-input-json file://sqs-queue-impairment-tag-based-experiment-template.json
```

## Stop Conditions and What a Stop Does

- The template ships with `"stopConditions": [{"source": "none"}]`. Add a customer-impact alarm before anything beyond a short test.
- **Do not** alarm on the metrics this experiment perturbs on the source queue (`ApproximateAgeOfOldestMessage`, `NumberOfMessagesSent`, `ApproximateNumberOfMessagesVisible`): they move by design and would abort the run in round 1. Use an application error-rate / transaction-success metric, ALB 5xx or target response time, or the **DLQ**'s `ApproximateNumberOfMessagesVisible`.
- A stop cancels the running automation. `applyDenyAllPolicyToQueues` and `waitForDuration` route `onCancel` / `onFailure` to `removeDenyAllPolicyFromQueues`, so a stop during a round removes the deny; later rounds are not started.

## Cleanup

Normally none — each round removes its own statement. After a failed or interrupted run, inspect each tagged queue's policy for `Sid: FISTemporaryDeny` and remove only that statement (`aws sqs get-queue-attributes --attribute-names Policy`, then `aws sqs set-queue-attributes`). Because the deny never covers `SetQueueAttributes`, this always works.

## What to Verify

- [ ] SQS monitoring alarm fires within 5 minutes of first impairment
- [ ] Affected component becomes unavailable but other components unaffected
- [ ] Dead letter queue captures failed messages (if configured)
- [ ] Producer implements backpressure when queue is unavailable
- [ ] Between impairment rounds, message processing resumes normally
- [ ] After final round, full recovery within 5 minutes
- [ ] No `FISTemporaryDeny` statement remains on any queue after the run
