# CJIS Control Families — AWS Service Mapping

> Based on CJIS Security Policy v6.0 (effective December 2024).
> Last verified against official source: 2025-05-21.
> Check https://le.fbi.gov/cjis-division/cjis-security-policy-resource-center for newer versions.

Complete mapping of CJIS v6.0 control families to specific AWS services and configurations.

---

## AC — Access Control

| Control | Requirement | AWS Service | Configuration |
|---|---|---|---|
| AC-2 | Account management | IAM Identity Center, IAM | Centralized user lifecycle; credential report for health monitoring |
| AC-3 | Access enforcement | IAM Policies, S3 BPA, SGs | Least-privilege policies; account-level S3 Block Public Access |
| AC-4 | Information flow enforcement | VPC, NACLs, VPC Endpoints | Dedicated CJI VPCs; VPC endpoints for private AWS API access |
| AC-5 | Separation of duties | IAM Roles, Permission Sets | Distinct admin/operator/reader roles; SCPs for boundary |
| AC-6 | Least privilege | IAM Access Analyzer | Identify unused permissions; scope policies to specific resources |
| AC-7 | Unsuccessful logon attempts | Cognito, AD | Cognito advanced security lockout; AD Group Policy (5 attempts) |
| AC-11 | Session lock | IAM Identity Center, STS | Permission set session duration; STS role max session <= 30 min |
| AC-12 | Session termination | IAM Identity Center | Automatic session termination on inactivity |
| AC-17 | Remote access | Client VPN, SSM Session Manager | Encrypted audited access; no direct SSH/RDP from internet |
| AC-22 | Publicly accessible content | S3 BPA, CloudFront | Account-level block; origin access control on distributions |

## AU — Audit and Accountability

| Control | Requirement | AWS Service | Configuration |
|---|---|---|---|
| AU-2 | Event logging | CloudTrail | Enable in all regions; multi-region trail; management + data events |
| AU-3 | Content of audit records | CloudTrail Data Events | S3 object-level and Lambda invocation logging for CJI |
| AU-4 | Audit log storage capacity | S3, CloudWatch Logs | Dedicated log bucket with lifecycle; CloudWatch retention |
| AU-5 | Response to audit failures | CloudWatch Alarms, SNS | Alert on CloudTrail delivery failures |
| AU-6 | Audit record review | CloudTrail Lake, Athena, Security Hub | Query capability for investigations; aggregated findings |
| AU-8 | Time stamps | CloudTrail Log Validation | Log file validation ensures timestamp integrity |
| AU-9 | Protection of audit info | S3 Object Lock, KMS | WORM on log buckets; CMK encryption on CloudTrail logs |
| AU-11 | Audit record retention | S3 Lifecycle, CloudWatch | Retain >= 3 years per v6.0 requirements |
| AU-12 | Audit record generation | VPC Flow Logs | Enable for all CJI VPC subnets |

## IA — Identification and Authentication

| Control | Requirement | AWS Service | Configuration |
|---|---|---|---|
| IA-2 | Identification and authentication | IAM MFA, Identity Center | MFA required for all CJI access; root MFA; hardware tokens (FIDO2) |
| IA-4 | Identifier management | IAM, Identity Center | Unique user per person; no shared accounts; credential report audit |
| IA-5 | Authenticator management | IAM Password Policy | Min 20 chars, complexity, 90-day max age, 10+ reuse prevention |
| IA-7 | Cryptographic module auth | KMS, FIPS Endpoints | `AWS_USE_FIPS_ENDPOINT=true`; GovCloud for default FIPS |
| IA-8 | Non-organizational users | Identity Center, SAML, OIDC | Federated access for external users |
| IA-11 | Re-authentication | STS Session Duration | Max session <= 3600s for CJI roles; re-auth on sensitive ops |

## CM — Configuration Management

| Control | Requirement | AWS Service | Configuration |
|---|---|---|---|
| CM-2 | Baseline configuration | AWS Config | Enable recording all resource types; deploy compliance rules |
| CM-3 | Configuration change control | Config, CloudTrail | Config delivery channel with SNS; CloudTrail for who-changed-what |
| CM-6 | Configuration settings | Security Hub | CIS Benchmark, NIST 800-53, AWS FSBP standards enabled |
| CM-7 | Least functionality | Security Groups, Lambda | Block unnecessary ports; restrict function invocation |
| CM-8 | System component inventory | Config, SSM Inventory | Config resource counts; SSM managed instance coverage |
| CM-12 | Information location | Config Advanced Queries | Query resource locations for CJI data mapping |

## SC — Systems and Communications Protection

| Control | Requirement | AWS Service | Configuration |
|---|---|---|---|
| SC-7 | Boundary protection | VPC, NACLs, SGs, GuardDuty, WAF | No IGW on CJI VPC; GuardDuty enabled; WAF on internet-facing LBs |
| SC-8 | Transmission confidentiality | ALB/NLB TLS, RDS SSL, S3 Policy | TLS 1.2+ on LBs; force_ssl on RDS; `aws:SecureTransport` deny |
| SC-12 | Cryptographic key management | KMS | CMKs with annual rotation for all CJI encryption |
| SC-13 | Cryptographic protection | FIPS Endpoints, GovCloud | FIPS 140-2/3 validated TLS for all API calls |
| SC-28 | Protection of info at rest | EBS, RDS, S3, DynamoDB, EFS + KMS | Default encryption; CMKs for CJI resources |

## SI — System and Information Integrity

| Control | Requirement | AWS Service | Configuration |
|---|---|---|---|
| SI-2 | Flaw remediation | Inspector, SSM Patch Manager | Enable Inspector for EC2/Lambda/ECR; automate patching |
| SI-3 | Malicious code protection | GuardDuty Malware Protection | Enable EBS malware scanning |
| SI-4 | System monitoring | GuardDuty, Security Hub, CloudWatch | Threat detection + aggregation + alerting |
| SI-7 | Software integrity | ECR Image Scanning, Lambda Code Signing | Scan-on-push; code signing for CJI functions |

## CP — Contingency Planning

| Control | Requirement | AWS Service | Configuration |
|---|---|---|---|
| CP-9 | System backup | AWS Backup | Plans covering all CJI resources; KMS-encrypted vaults |
| CP-10 | System recovery | RDS Multi-AZ, S3 CRR, Backup copy rules | Multi-AZ for databases; cross-region replication for DR |

## MP — Media Protection

| Control | Requirement | AWS Service | Configuration |
|---|---|---|---|
| MP-2 | Media access | IAM, KMS Key Policies | Restrict who can decrypt CJI data via key policies |
| MP-4 | Media storage | S3, EBS, RDS (all encrypted) | Encryption at rest with CMK for all CJI stores |
| MP-5 | Media transport | TLS, VPN, Direct Connect | Encrypt all CJI in transit; MACsec on DX |
| MP-6 | Media sanitization | S3 Lifecycle, KMS Key Deletion | Crypto-shred via key deletion; lifecycle for retention |

## IR — Incident Response

| Control | Requirement | AWS Service | Configuration |
|---|---|---|---|
| IR-4 | Incident handling | GuardDuty, Detective, Incident Manager | Threat detection + investigation + response runbooks |
| IR-5 | Incident monitoring | Security Hub, EventBridge | Aggregated findings; automated routing to IR team |
| IR-6 | Incident reporting | SNS, ChatBot | Alert IR team on critical findings; escalation to CSO |

## RA — Risk Assessment

| Control | Requirement | AWS Service | Configuration |
|---|---|---|---|
| RA-5 | Vulnerability monitoring | Inspector, Security Hub | Continuous vulnerability scanning; risk aggregation |

## CA — Assessment, Authorization, and Monitoring

| Control | Requirement | AWS Service | Configuration |
|---|---|---|---|
| CA-2 | Control assessments | Audit Manager | Automated evidence collection for CJIS-relevant frameworks |
| CA-7 | Continuous monitoring | Security Hub, Config | Continuous compliance posture; Config conformance packs |

## Section 5.1 — Information Exchange Agreements

| Requirement | AWS Service | Configuration |
|---|---|---|
| CJIS Security Addendum | AWS Artifact | Download state-specific CJIS Security Addendum |
| Shared responsibility model | AWS Documentation | Document customer vs AWS responsibilities |
| Region/account isolation | Organizations, SCPs | Restrict CJI to approved accounts and regions |

## Section 5.20 — Mobile Devices

| Requirement | AWS Service | Configuration |
|---|---|---|
| Virtual desktop (CJI stays in cloud) | WorkSpaces | Deploy in CJI VPC; enable MFA; restrict clipboard |
| Application streaming | AppStream 2.0 | Stream CJI apps; no local data storage |
| Secure remote access | Client VPN | Deploy with MFA and certificate-based auth |
| Instance access (no SSH) | SSM Session Manager | Encrypted logged sessions without open ports |
