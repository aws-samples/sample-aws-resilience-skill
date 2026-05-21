# FERPA Requirements → AWS Service Mapping

> Based on 34 CFR Part 99 (FERPA), PTAC "Data Security Checklist," and NIST SP 800-171.
> Last verified against official sources: 2025-05-15.
> Check https://studentprivacy.ed.gov/ for PTAC updates and https://www.ecfr.gov/current/title-34/subtitle-A/part-99 for regulation changes.

Complete mapping of FERPA and PTAC-derived safeguard requirements to specific AWS services and configurations.

FERPA itself is regulation, not a security framework — the mappings below draw from 34 CFR Part 99, PTAC "Data Security Checklist," NIST SP 800-171 (the baseline adopted by most state EdTech contracts), and common state-law-specific clauses.

---

## Encryption (FCD 7)

| FERPA / PTAC requirement | AWS service | Configuration |
|---|---|---|
| Encrypt student records at rest | KMS | Customer-managed keys (CMKs) for all student-data resources; automatic rotation enabled |
| EBS encryption | EBS + KMS | Enable default encryption at account level: `aws ec2 enable-ebs-encryption-by-default` |
| S3 encryption | S3 + KMS | Bucket policy denying `s3:PutObject` without `s3:x-amz-server-side-encryption: aws:kms`; enable Bucket Keys |
| RDS / Aurora encryption | RDS + KMS | Enable at creation — cannot retrofit; migrate via snapshot if needed |
| DynamoDB encryption | DynamoDB + KMS | Customer-managed CMK: `SSESpecification: { SSEEnabled: true, SSEType: KMS, KMSMasterKeyId: <key> }` |
| OpenSearch encryption | OpenSearch + KMS | At-rest encryption + node-to-node encryption, both with CMK |
| Backup encryption | AWS Backup + KMS | Backup plans reference CMK; cross-region copies retain encryption |
| TLS 1.2+ in transit | ACM, ALB/NLB, API Gateway, CloudFront | Enforce TLS 1.2 minimum via security policy (`ELBSecurityPolicy-TLS13-1-2-2021-06`) |
| S3 deny-plaintext | S3 bucket policy | `Condition: {"Bool": {"aws:SecureTransport": "false"}}` → `Deny` |
| RDS force-SSL | RDS parameter group | MySQL: `require_secure_transport=1`; Postgres: `rds.force_ssl=1` |
| FIPS-validated endpoints (state contracts) | AWS FIPS endpoints | Set `AWS_USE_FIPS_ENDPOINT=true` or use `<service>-fips.<region>.amazonaws.com` |
| VPN encryption | Site-to-Site VPN | AES-256-GCM + SHA-256+ cipher suites |

## Access Control & Authentication (FCD 5, 6)

| FERPA / PTAC requirement | AWS service | Configuration |
|---|---|---|
| MFA for admin access to student data | IAM Identity Center | Enable MFA requirement; prefer FIDO2 hardware + TOTP fallback |
| MFA enforcement on IAM principals | IAM | Policy condition: `"Condition": {"BoolIfExists": {"aws:MultiFactorAuthPresent": "true"}}` |
| Root MFA + no root access keys | IAM | Hardware MFA on root; delete root access keys; SCP denies root usage |
| Student/parent/teacher authentication | Cognito | Enable advanced security features (compromised-credentials, adaptive MFA) |
| District SSO federation | IAM Identity Center / Cognito SAML | SAML/OIDC to Google Workspace for Education, Okta, Azure AD, ClassLink, Clever |
| Least privilege | IAM + Access Analyzer | Access Analyzer: identify unused permissions; policies scoped to specific resources |
| RBAC | IAM Identity Center | Permission sets: `StudentData-ReadOnly`, `StudentData-Operator`, `StudentData-Admin` |
| Account lockout | Cognito / AD | Cognito advanced security: lockout policy. AD: Group Policy for 5-attempt lockout |
| Password policy | IAM | `aws iam update-account-password-policy --minimum-password-length 14 --require-symbols --max-password-age 90 --password-reuse-prevention 10` |
| Session timeout (≤30 min) | IAM Identity Center | Set session duration on permission sets; STS role max session |
| No shared accounts | IAM Identity Center | One user per person; credential report for audit |
| Remote access encryption | Client VPN / SSM | Client VPN with MFA; SSM Session Manager for instance access (no SSH) |
| No public S3 / RDS / snapshots | S3 Block Public Access, RDS, EBS | Account-level S3 BPA; `PubliclyAccessible=false` on RDS; no public snapshot shares |

## Disclosure Controls & Data Sharing (FCD 3)

| FERPA requirement | AWS service | Configuration |
|---|---|---|
| Isolation of student-data workloads | AWS Organizations + SCPs | Dedicated OU for student-data accounts; SCPs restrict services, regions |
| Explicit cross-account sharing | S3 bucket policies, RAM, Lake Formation | Named-principal allow-lists; log all shares |
| Detect external exposure | IAM Access Analyzer | Continuous scan across S3, RDS snapshots, KMS keys, Lambda, IAM roles, SQS/SNS, Secrets Manager |
| Network isolation | VPC, PrivateLink | Dedicated VPC per environment; no peering to non-student-data VPCs; VPC endpoints for AWS services |
| Prevent data egress to non-approved endpoints | VPC endpoint policies, egress firewall | Restrict `s3:*` to student-data buckets; Network Firewall with allow-list |
| ML/AI subprocessor control | Bedrock, SageMaker | Use models with no-retention data policies; log every training-job read from student-data S3 |
| §99.32 disclosure log (API-level) | CloudTrail data events | Enable data events on student-record S3 buckets + Lambda functions |
| §99.32 disclosure log (application-level) | CloudWatch Logs / S3 Object Lock | Dedicated, append-only log group/bucket; structured records |

## Auditing & Logging (FCD 4)

| FERPA / PTAC requirement | AWS service | Configuration |
|---|---|---|
| API audit logging | CloudTrail | Enable in all regions; enable data events for student-data S3 buckets and Lambdas |
| Log integrity | CloudTrail | Enable log file validation |
| Log encryption | CloudTrail + KMS | Encrypt logs with CMK |
| Network flow logging | VPC Flow Logs | Enable for all student-data VPC subnets; send to CloudWatch Logs or S3 |
| Log retention | S3 / CloudWatch | Align with student-record retention schedule (typically 7+ years; some states require longer) |
| Log tamper-protection | S3 Object Lock | Governance or Compliance mode on log buckets |
| Centralized logging | CloudWatch, OpenSearch | Aggregate all logs in dedicated logging account |
| Log analysis / alerting | CloudWatch Alarms, EventBridge | Alert on: root login, MFA disable, SG changes, data-event anomalies |
| Log querying | Athena, CloudTrail Lake | Query CloudTrail and Flow Logs for investigations |
| §99.32 disclosure record | CloudWatch Logs + S3 Object Lock | Application-emitted structured events: `{timestamp, student_id, requestor, purpose, exception, records[]}` |

## Threat Detection & Incident Response (FCD 9)

| FERPA / PTAC requirement | AWS service | Configuration |
|---|---|---|
| Threat detection | GuardDuty | Enable in all student-data accounts and regions; enable S3 and EKS protection |
| Student-PII detection | Macie | Enable on student-data S3; create custom data identifiers matching your student-ID formats |
| Vulnerability scanning | Inspector | Enable for EC2, Lambda, ECR; auto-scan on deploy |
| Investigation | Detective | Enable for graph-based security investigation |
| Automated response | EventBridge + Lambda | Auto-isolate compromised instances, revoke leaked credentials, quarantine buckets |
| IR management | Incident Manager | Response plans and runbooks tailored to student-data incidents; include district-notification steps |
| Alerting | SNS, ChatBot, PagerDuty | Route Security Hub critical findings to IR team with on-call rotation |
| Breach-scope investigation | CloudTrail Lake + Athena | Query historical access patterns to determine impact scope |

## Data Minimization & Retention (FCD 8)

| FERPA / PTAC requirement | AWS service | Configuration |
|---|---|---|
| Minimize data collection | App-level + Macie | Macie to detect over-collected PII in S3 buckets |
| Automated retention | S3 Lifecycle, DynamoDB TTL, AWS Backup | Lifecycle rules per data category; TTL on DynamoDB; Backup lifecycle |
| WORM retention | S3 Object Lock | Governance (reversible) or Compliance (irreversible) mode |
| Secure destruction (NIST 800-88) | KMS key deletion (crypto-shred) | Schedule CMK deletion; 7-30 day wait; renders all encrypted copies unrecoverable |
| Physical media sanitization | AWS-managed | Documented in SOC 2 / FedRAMP — inherited control |
| Contract-termination destruction | Tag-based inventory + KMS deletion | Tag `district:<name>`; export if required; crypto-shred district-specific keys |
| Destruction attestation | Signed document | Out of AWS scope; log the key-deletion events from CloudTrail as evidence |

## Configuration & Compliance Posture

| FERPA / PTAC requirement | AWS service | Configuration |
|---|---|---|
| Configuration compliance | AWS Config | Enable recording; deploy managed rules for student-data checks |
| Conformance packs | AWS Config | Deploy packs: encryption checks, public access checks, logging checks |
| Patch management | Systems Manager Patch Manager | Patch baselines; maintenance windows; auto-approve critical patches |
| Desired state enforcement | SSM State Manager | Enforce CIS Benchmarks, agent installations |
| Image hardening | EC2 Image Builder + Inspector | Hardened AMIs from CIS/STIG; scan before publish |
| Container scanning | ECR + Inspector | Scan-on-push for container images |
| Change tracking | AWS Config + CloudTrail | Config records resource changes; CloudTrail records who made them |
| Approved services gate | Organizations SCPs | Deny non-approved AWS services in student-data accounts |

## Compliance & Audit Evidence

| FERPA / PTAC requirement | AWS service | Configuration |
|---|---|---|
| Compliance posture | Security Hub | Enable; review findings dashboard regularly |
| Automated evidence | Audit Manager | Create assessment mapping to NIST 800-171 / CIS Controls; schedule evidence collection |
| AWS compliance reports | AWS Artifact | Download SOC 2 Type II, ISO 27001, FedRAMP High, StateRAMP, TX-RAMP as DPA attachments |
| Resource inventory | AWS Config + SSM | Config: full resource inventory. SSM: managed instance inventory |
| Credential report | IAM | `aws iam generate-credential-report` — MFA status, key age, last login |
| Subprocessor registry | Tag + Config | Tag every external-facing resource with `subprocessor:<name>`; export register on demand |

## Data Sharing & Egress Controls

| FERPA / PTAC requirement | AWS service | Configuration |
|---|---|---|
| Data loss prevention | S3 BPA, VPC endpoints, Macie | Account-level S3 BPA; VPC endpoints prevent internet-path exfil; Macie flags anomalous PII movement |
| Private AWS API access | VPC Endpoints (PrivateLink) | Interface/gateway endpoints for S3, KMS, DynamoDB, CloudTrail, SSM |
| Egress filtering | Network Firewall | Domain allow-list for outbound HTTPS; deny by default |
| Cross-region replication scope | S3 CRR + KMS | Replicate only to approved regions; use in-region CMKs |

## Mobile / Student-Facing Access

| FERPA / PTAC requirement | AWS service | Configuration |
|---|---|---|
| Student-facing app authentication | Cognito | MFA (where age-appropriate); SAML federation from district IdP |
| Virtual desktop for sensitive access | WorkSpaces | Deploy in student-data VPC; MFA; restrict clipboard/printing |
| Application streaming | AppStream 2.0 | Stream student-data apps; no local data storage |
| Secure admin remote access | Client VPN + SSM Session Manager | MFA, cert-based auth on VPN; SSM for shell access with full session logging |

## State-Framework-Specific Hardening

| Requirement | AWS service | Configuration |
|---|---|---|
| US-only data residency (many state DPAs) | SCPs + Config | SCP deny non-US regions; Config rule flagging non-US resources |
| FIPS 140-2 validated crypto (StateRAMP, TX-RAMP L2) | FIPS endpoints + KMS | `AWS_USE_FIPS_ENDPOINT=true`; KMS HSMs are FIPS 140-2 Level 2 |
| Annual SOC 2 attestation | AWS Artifact + own SOC 2 | AWS Artifact for AWS SOC 2; engage auditor for own org's SOC 2 Type II |
| State-DOE approved vendor list | Organizational | Track status in contract system; not an AWS control |

See [`state-law-addenda.md`](state-law-addenda.md) for per-state incremental requirements.
