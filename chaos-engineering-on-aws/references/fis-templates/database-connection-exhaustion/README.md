# Database Connection Limit Exhaustion — FIS Template

> Source: [aws-samples/fis-template-library](https://github.com/aws-samples/fis-template-library/tree/main/database-connection-limit-exhaustion) (commit ee74d58) | License: MIT-0
>
> Local file names differ from upstream (other docs link to them): `experiment-template.json` = `database-connection-limit-exhaustion-experiment-template.json`, `ssm-automation.yaml` = `database-connection-limit-exhaustion-automation.yaml`, `fis-role-iam-policy.json` = `database-connection-limit-exhaustion-fis-role-iam-policy.json`, `ssm-role-iam-policy.json` = `database-connection-limit-exhaustion-ssm-automation-role-iam-policy.json`. Contents are byte-identical to upstream.

## Hypothesis Template

> When the {service1} database connection value is approaching its limit, users of {workload} should be able
> to complete the {service1} user journey within the SLA of 2 seconds and other critical user journeys should
> continue unaffected. The circuit breaker should remain closed, the steady state of {n} TPS should be
> maintained, and a leading alarm should notify the DevOps team within {y} minutes.
>
> When the connection limit is exhausted, the {service1} circuit breaker should open, the UI should degrade
> gracefully (no new connections to the {service1} database), an alarm should fire within {y} minutes and other
> journeys should continue unaffected. Once connections drain, the circuit breaker should close within {z}
> minutes and the steady state of {n} TPS should resume.

## How It Works

FIS runs one `aws:ssm:start-automation-execution` action (`maxDuration` PT180M). The SSM document:

1. Creates a temporary security group `FIS-ConnectionLimit-LoadGen-<execution-id>` in `VpcId`, adds an egress rule to the database port, and adds an ingress rule on `DatabaseSecurityGroupId` from that group.
2. Launches an Amazon Linux 2023 instance in `SubnetId` with instance profile `SSM-Managed-Instance-Profile` and **IMDSv2 required** (`MetadataOptions.HttpTokens: required`), tagged `FIS-Experiment=ConnectionLimitExhaustion`, `AutoCleanup=true`, `ManagedBy=FIS-SSM-Automation`.
3. Waits for the SSM Agent, installs the client for `DatabaseEngine` (`postgres`, `mysql` or `sqlserver`).
4. On the instance, reads the password from Secrets Manager (`DatabasePasswordSecretArn`), then opens `MaxConnections` connections over `RampTime` in `RampSteps` steps. Every connection sends `SELECT 1` every 30 seconds and is held until `ExperimentDuration` ends; all release together.
5. Cleanup chain: terminate instance → wait for termination → revoke the ingress rule on the database SG → delete the temporary SG.

**Failure/cancel routing (upstream fix)**: every step after the security group is created routes `onFailure` / `onCancel` into that cleanup chain (`LaunchLoadGenerator` → revoke/terminate, `WaitForSSMAgent` / `InstallDatabaseClient` / `ExhaustConnectionLimit` → `TerminateInstance` → `RevokeInboundFromLoadGenerator` → `CleanupSecurityGroup`), so the ephemeral EC2 instance and security group are removed on failure or stop, not only on success.

**Supported engines**: Aurora PostgreSQL, Aurora MySQL, RDS PostgreSQL, RDS MySQL, RDS SQL Server.

**Template values** (`experiment-template.json`): `MaxConnections` 1000, `ExperimentDuration` PT30M, `RampTime` PT15M, `RampSteps` 15, `InstanceType` t3.small. (The document's own default for `MaxConnections` is 100.) `ExhaustConnectionLimit` has a fixed 3600 s command timeout, so keep `ExperimentDuration` below one hour.

## Prerequisites

- Names are hard-coded and must be used as-is (or changed consistently in every file):
  - FIS role `ConnectionLimitExhaustion-FIS-Role` (template `roleArn`).
  - SSM Automation role `ConnectionLimitExhaustion-SSM-Automation-Role` — the document's `assumeRole` is fixed to this name, and the FIS policy may pass only this role.
  - SSM document `ConnectionLimitExhaustion-Automation` (template `documentArn`, FIS policy).
  - EC2 instance profile `SSM-Managed-Instance-Profile`. The SSM role's `iam:PassRole` is now on `role/SSM-Managed-Instance-Profile` (was `SSM-Managed-Instance-Profile-Role`), so the role inside the profile must carry that name.
- Instance profile role: `AmazonSSMManagedInstanceCore` **plus** `secretsmanager:GetSecretValue` on your database secret (and KMS decrypt if the secret uses a customer-managed key).
- **SecretsManager removed from the SSM role (upstream change)**: the automation role no longer has `secretsmanager:*`. This is correct: the document itself never calls Secrets Manager; the secret ARN is passed as an argument to the shell script, and the `boto3` `get_secret_value` call runs on the load-generator instance under the instance profile role.
- A subnet that can reach the database and the SSM / Secrets Manager endpoints and package repositories; the database SG ID; a database user and secret.

## Files

| File | Description |
|------|-------------|
| `experiment-template.json` | FIS experiment template |
| `ssm-automation.yaml` | SSM Automation document (multi-step orchestration) |
| `fis-role-iam-policy.json` | IAM policy for FIS execution role |
| `ssm-role-iam-policy.json` | IAM policy for SSM Automation execution role |
| `fis-iam-trust-relationship.json` | Trust policy for FIS role |
| `ssm-iam-trust-relationship.json` | Trust policy for SSM role |
| `AWSFIS.json` | Template-library metadata |

## Deployment

```bash
# 1. Create IAM roles with the names the files expect (replace <YOUR REGION>/<YOUR AWS ACCOUNT> first)
aws iam create-role --role-name ConnectionLimitExhaustion-FIS-Role --assume-role-policy-document file://fis-iam-trust-relationship.json
aws iam put-role-policy --role-name ConnectionLimitExhaustion-FIS-Role --policy-name fis-policy --policy-document file://fis-role-iam-policy.json

aws iam create-role --role-name ConnectionLimitExhaustion-SSM-Automation-Role --assume-role-policy-document file://ssm-iam-trust-relationship.json
aws iam put-role-policy --role-name ConnectionLimitExhaustion-SSM-Automation-Role --policy-name ssm-policy --policy-document file://ssm-role-iam-policy.json

# 1b. Instance profile + role named SSM-Managed-Instance-Profile (AmazonSSMManagedInstanceCore + secret read)

# 2. Create SSM Automation document
aws ssm create-document --name ConnectionLimitExhaustion-Automation --document-type Automation --content file://ssm-automation.yaml --document-format YAML

# 3. Fill documentParameters in experiment-template.json (endpoint, secret ARN, VPC, subnet, DB SG), then:
aws fis create-experiment-template --cli-input-json file://experiment-template.json
```

Do not add a target to the template: the database is addressed through the document parameters.

## Stop Conditions and What a Stop Does

- The template ships with `"stopConditions": [{"source": "none"}]`.
- A stop cancels the automation; the running step's `onCancel` routes to the cleanup chain, which terminates the instance (dropping all held connections), revokes the database SG ingress rule and deletes the temporary SG.
- A stop cannot undo load the database already absorbed (e.g. connection-storm side effects in the application).

## Cleanup

Normally automatic. After a failed run, check for leftover instances tagged `FIS-Experiment=ConnectionLimitExhaustion`, an ingress rule on the database SG whose source is a `FIS-ConnectionLimit-LoadGen-*` group, and the group itself.

## Upstream caveat

The SSM role's statements named `...ByTag` (`ec2:TerminateInstances`, `ec2:StopInstances`, security-group delete/authorize/revoke) carry **no tag condition** at ee74d58, so the role can act on any instance or security group in the account and Region. Add `aws:ResourceTag/FIS-Experiment=ConnectionLimitExhaustion` conditions if you need least privilege (the database SG ingress change would then need its own statement).

## What to Verify

- [ ] Connection pool monitoring alarm fires before limit is reached
- [ ] Circuit breaker activates when connections are exhausted
- [ ] Application degrades gracefully (no cascading failures)
- [ ] After connections drain, circuit breaker closes and traffic resumes
- [ ] Ephemeral EC2, its security group and the database SG ingress rule are gone (no resource leak)
