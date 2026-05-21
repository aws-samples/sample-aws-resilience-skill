# CJIS Requirements → AWS Service Mapping

Complete mapping of CJIS Security Policy requirements to specific AWS services and configurations.

---

## Encryption

| CJIS Requirement | AWS Service | Configuration |
|---|---|---|
| Encrypt CJI at rest (FIPS 140-2/3) | KMS | Use CMKs; KMS HSMs are FIPS 140-2 Level 2 validated by default |
| EBS encryption | EBS + KMS | Enable default encryption at account level: `aws ec2 enable-ebs-encryption-by-default` |
| S3 encryption | S3 + KMS | Bucket policy to deny `s3:PutObject` without `s3:x-amz-server-side-encryption: aws:kms` |
| RDS encryption | RDS + KMS | Enable at creation; cannot retrofit — migrate via snapshot if needed |
| DynamoDB encryption | DynamoDB + KMS | Use customer-managed CMK: `SSESpecification: { SSEEnabled: true, SSEType: KMS, KMSMasterKeyId: <key> }` |
| Encrypt CJI in transit (TLS 1.2+) | ACM, ALB/NLB, CloudFront | Enforce TLS 1.2 minimum on load balancers and CloudFront distributions |
| FIPS-validated TLS endpoints | AWS FIPS endpoints | Set `AWS_USE_FIPS_ENDPOINT=true` or use `<service>-fips.<region>.amazonaws.com` |
| VPN encryption (FIPS) | Site-to-Site VPN | Use AES-256-GCM + SHA-256+ cipher suites in tunnel options |
| Direct Connect encryption | Direct Connect + MACsec | Enable MACsec on dedicated connections for link-layer encryption |

## Access Control & Authentication

| CJIS Requirement | AWS Service | Configuration |
|---|---|---|
| MFA for all CJI access | IAM Identity Center | Enable MFA requirement in Identity Center settings; support FIDO2 + TOTP |
| MFA enforcement on IAM | IAM | Policy condition: `"Condition": {"BoolIfExists": {"aws:MultiFactorAuthPresent": "true"}}` |
| Root account MFA | IAM | Enable hardware MFA on root; delete root access keys |
| Least privilege | IAM + Access Analyzer | Use Access Analyzer to identify unused permissions; scope policies to specific resources |
| RBAC | IAM Identity Center | Define permission sets per role (CJI-Admin, CJI-ReadOnly, CJI-Operator) |
| Account lockout | Cognito / AD | Cognito: configure advanced security with lockout. AD: Group Policy for lockout after 5 attempts |
| Password policy | IAM | `aws iam update-account-password-policy --minimum-password-length 20 --require-symbols --max-password-age 90 --password-reuse-prevention 24` |
| Session timeout (30 min) | IAM Identity Center | Set session duration on permission sets; STS role max session |
| No shared accounts | IAM Identity Center | One user per person; audit with credential report |
| Remote access encryption | Client VPN / SSM | Client VPN with MFA; SSM Session Manager for instance access |

## Network Protection

| CJIS Requirement | AWS Service | Configuration |
|---|---|---|
| Network segmentation | VPC | Dedicated CJI VPC(s); no peering with non-CJI VPCs unless strictly controlled |
| Boundary protection | Security Groups, NACLs | SGs: allow only required ports between tiers. NACLs: deny all except explicit allows. |
| No internet exposure | VPC design | No IGW in CJI VPC; use NAT Gateway only if outbound is required (patching) |
| IDS/IPS | Network Firewall | Deploy in CJI VPC with Suricata-compatible rules for threat detection |
| DDoS protection | Shield Advanced | Enable on any internet-facing endpoints (if applicable) |
| DNS privacy | Route 53 Resolver | Use private hosted zones; no public DNS records for CJI resources |
| Private AWS API access | VPC Endpoints | Create interface/gateway endpoints for S3, KMS, CloudTrail, SSM, etc. |
| Agency connectivity | Site-to-Site VPN / Direct Connect | IPsec VPN or DX with encryption for all agency-to-cloud traffic |
| Web application protection | WAF | Deploy on ALB/CloudFront if any CJI app has web interface |

## Auditing & Logging

| CJIS Requirement | AWS Service | Configuration |
|---|---|---|
| API audit logging | CloudTrail | Enable in all regions; enable data events for CJI S3 buckets and Lambda |
| Log integrity | CloudTrail | Enable log file validation |
| Log encryption | CloudTrail + KMS | Encrypt logs with CMK |
| Network flow logging | VPC Flow Logs | Enable for all CJI VPC subnets; send to CloudWatch Logs or S3 |
| Log retention (1 year) | S3 / CloudWatch | S3 lifecycle: retain ≥365 days. CloudWatch: set retention to 365 days. |
| Log protection | S3 Object Lock | Enable Governance or Compliance mode on log buckets |
| Centralized logging | CloudWatch, OpenSearch | Aggregate all logs in dedicated logging account |
| Log analysis / alerting | CloudWatch Alarms, EventBridge | Alert on: root login, MFA disable, SG changes, unauthorized API calls |
| Log querying | Athena, CloudTrail Lake | Query CloudTrail and Flow Logs for investigations |

## Threat Detection & Incident Response

| CJIS Requirement | AWS Service | Configuration |
|---|---|---|
| Threat detection | GuardDuty | Enable in all CJI accounts and regions; enable S3 and EKS protection |
| Sensitive data detection | Macie | Enable on CJI S3 buckets; create custom data identifiers for CJI patterns |
| Vulnerability scanning | Inspector | Enable for EC2, Lambda, ECR; auto-scan on deploy |
| Investigation | Detective | Enable for graph-based security investigation |
| Automated response | EventBridge + Lambda | Auto-isolate compromised instances, revoke leaked credentials |
| IR management | Incident Manager | Define response plans and runbooks for CJI incidents |
| Alerting | SNS, ChatBot | Route Security Hub critical findings to IR team |

## Configuration Management

| CJIS Requirement | AWS Service | Configuration |
|---|---|---|
| Configuration compliance | Config | Enable recording; deploy managed rules for CJIS checks |
| Conformance packs | Config | Deploy packs: encryption checks, public access checks, logging checks |
| Patch management | Systems Manager Patch Manager | Define patch baselines; schedule maintenance windows; auto-approve critical patches |
| Desired state | Systems Manager State Manager | Enforce configurations (CIS benchmarks, agent installations) |
| Image hardening | EC2 Image Builder + Inspector | Build hardened AMIs from CIS/STIG baselines; scan before publishing |
| Container scanning | ECR + Inspector | Enable scan-on-push for container images |
| Change tracking | Config, CloudTrail | Config records resource changes; CloudTrail records who made them |
| Approved services | Organizations SCPs | Deny access to non-approved AWS services in CJI accounts |

## Compliance & Audit Evidence

| CJIS Requirement | AWS Service | Configuration |
|---|---|---|
| Compliance posture | Security Hub | Enable; review findings dashboard regularly |
| Automated evidence | Audit Manager | Create CJIS assessment; schedule automated evidence collection |
| AWS compliance reports | Artifact | Download SOC 2, FedRAMP High, ISO 27001 reports for inherited controls |
| Resource inventory | Config, Systems Manager | Config: full resource inventory. SSM: managed instance inventory. |
| Credential report | IAM | `aws iam generate-credential-report` — review MFA status, key age, last login |

## Data Protection & Privacy

| CJIS Requirement | AWS Service | Configuration |
|---|---|---|
| Data classification | Macie | Auto-discover and classify CJI in S3 |
| Data loss prevention | S3 Block Public Access, VPC endpoints | Account-level S3 BPA; VPC endpoints to prevent data exfil via internet |
| Data retention | S3 Lifecycle | Define retention rules aligned with CJI retention requirements |
| Data deletion | S3 Lifecycle, KMS key deletion | Crypto-shred: delete KMS key to render encrypted CJI unrecoverable |
| Backup encryption | AWS Backup + KMS | Ensure all backups are encrypted with CMK |

## Mobile / Remote Access

| CJIS Requirement | AWS Service | Configuration |
|---|---|---|
| Virtual desktop (avoid CJI on device) | WorkSpaces | Deploy in CJI VPC; enable MFA; restrict clipboard/printing |
| Application streaming | AppStream 2.0 | Stream CJI applications; no local data storage |
| Secure remote access | Client VPN | Deploy in CJI VPC with MFA and certificate-based auth |
| Instance access (no SSH) | SSM Session Manager | Encrypted, logged sessions without open inbound ports |
