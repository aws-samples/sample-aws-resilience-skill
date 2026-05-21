# CJIS Policy Areas — Detailed AWS Implementation Guide

Deep-dive on each of the 13 CJIS Security Policy areas with specific AWS implementation guidance.

---

## PA 1 — Information Exchange Agreements (Section 5.1)

### Requirements
- A CJIS Security Addendum must be executed with any private contractor or non-criminal justice agency with access to CJI
- A Management Control Agreement (MCA) must be in place for outsourced CJI operations
- Agreements must specify security responsibilities, breach notification, audit rights, and data handling

### AWS Implementation
- **AWS Artifact**: Download the AWS CJIS Security Addendum for your state. AWS has signed addendums with multiple state CSAs.
- **AWS Organizations**: Use SCPs to enforce that CJI workloads only run in approved accounts and regions
- Verify your state CSA has a current addendum with AWS — contact your AWS account team if unsure
- Document the shared responsibility model: AWS secures the infrastructure; the customer secures their workloads, data, IAM, and application layer

### Key Pitfall
Not all states have a CJIS Security Addendum with AWS. Verify before deploying. If your state doesn't have one, work with your CSA and AWS to establish one.

---

## PA 2 — Security Awareness Training (Section 5.2)

### Requirements
- All personnel with access to CJI must complete security awareness training
- Training within 6 months of initial assignment, refreshed every 2 years
- Topics: social engineering, password security, media protection, physical security, incident reporting, acceptable use

### AWS Implementation
- This is primarily an organizational/HR process — AWS doesn't directly satisfy this
- Use AWS IAM Identity Center to track which users have CJI access — cross-reference with training records
- Consider tagging IAM roles/users with training completion dates for automated compliance checks
- Deny CJI resource access via IAM conditions if training is expired (advanced: use ABAC with training-date tags)

---

## PA 3 — Incident Response (Section 5.3)

### Requirements
- Documented IR plan covering detection, containment, eradication, recovery
- Report security incidents to the CSO and FBI CJIS Division
- Test the IR plan at least annually

### AWS Implementation
- **GuardDuty**: Enable in all CJI accounts for threat detection (malicious activity, unauthorized access, crypto mining)
- **Security Hub**: Aggregate findings from GuardDuty, Inspector, Macie, Config
- **Detective**: Investigate security findings with graph-based analysis
- **EventBridge + Lambda**: Automate containment actions (e.g., isolate compromised EC2 instance by swapping security group)
- **SNS**: Alert IR team on critical findings
- **Systems Manager Incident Manager**: Formalize runbooks for CJI-specific incidents
- **CloudTrail Lake**: Query historical events during investigation

### IR Reporting
- CJI breaches must be reported to the state CSO — timeframes vary by state (often immediate)
- Document the reporting chain: Local TAC → CSO → CSA → FBI CJIS Division
- Include AWS support escalation in the IR plan (AWS Support, AWS Trust & Safety)

---

## PA 4 — Auditing and Accountability (Section 5.4)

### Requirements
- Log all events related to CJI access and system security
- Minimum events: successful/failed logins, privilege changes, data access, system events
- Retain audit logs for minimum 1 year
- Protect logs from unauthorized modification
- Review logs regularly

### AWS Implementation
- **CloudTrail**: Enable in all regions. Enable data events for S3 buckets containing CJI and Lambda functions processing CJI.
- **CloudTrail log integrity**: Enable log file validation to detect tampering
- **CloudTrail encryption**: Use KMS CMK for log encryption
- **VPC Flow Logs**: Enable for all CJI VPCs — send to CloudWatch Logs or S3
- **CloudWatch Logs**: Centralize application logs. Set retention to ≥365 days.
- **S3 for log storage**: Use a dedicated logging account. Enable Object Lock (WORM) to prevent deletion.
- **Athena**: Query CloudTrail and VPC Flow Logs for investigations
- **OpenSearch Service**: Real-time log analysis and dashboarding
- **Application-level logging**: Ensure your application logs CJI access events (who viewed/modified what record, when). This is NOT covered by AWS infrastructure logging alone.

### Critical Detail
AWS CloudTrail logs API calls — it does NOT log application-level CJI access. If a user queries a database for criminal history records, CloudTrail logs the API call to RDS but not which records were accessed. Your application must implement its own CJI access audit trail.

---

## PA 5 — Access Control (Section 5.5)

### Requirements
- Least privilege and need-to-know basis for all CJI access
- Account management: provisioning, review, de-provisioning
- Session lock after 30 minutes of inactivity
- Remote access only via encrypted channel

### AWS Implementation
- **IAM Policies**: Use least-privilege policies. Avoid `*` actions and resources. Use IAM Access Analyzer to identify overly permissive policies.
- **IAM Identity Center**: Centralized access management with permission sets scoped to CJI accounts
- **SCPs**: Restrict CJI accounts to approved services and regions only
- **S3 Bucket Policies**: Restrict CJI buckets to specific IAM roles
- **Lake Formation**: Fine-grained access control for data lakes containing CJI
- **Session timeout**: Configure IAM role session duration. For console, set STS session to ≤30 minutes or use Identity Center session policies.
- **VPN**: All remote access via Site-to-Site VPN or Client VPN with encryption
- **S3 Block Public Access**: Enable at the account level for all CJI accounts
- **EC2 Instance Connect / SSM Session Manager**: Use instead of SSH for instance access — provides audit trail and eliminates need for open SSH ports

---

## PA 6 — Identification and Authentication (Section 5.6)

### Requirements
- **Advanced authentication (AA)** required for CJI access — this means MFA
- AA required at the point of access to CJI, not just network perimeter
- Password policy: complexity requirements, maximum 90-day age, lockout after 5 failed attempts
- Unique identification — no shared accounts

### AWS Implementation
- **IAM Identity Center**: Enforce MFA for all users. Support hardware tokens (FIDO2) or virtual MFA.
- **IAM MFA**: Enforce MFA via IAM policies using `aws:MultiFactorAuthPresent` condition key
- **Cognito**: If building a CJI application with end-user authentication, use Cognito with MFA enabled
- **IAM Password Policy**: Set via account settings — minimum length, complexity, 90-day expiration, prevent reuse
- **Root account**: Enable MFA, delete access keys, restrict usage via SCP
- **No shared accounts**: Each person gets a unique IAM Identity Center user or IAM user

### Advanced Authentication Detail
CJIS defines AA as authentication that uses at least two of: something you know, something you have, something you are. Standard username/password alone is NOT sufficient for CJI access. This is the single most common CJIS audit finding.

---

## PA 7 — Configuration Management (Section 5.7)

### Requirements
- Establish and maintain secure baseline configurations
- Formal change management process
- Patch management with defined timelines
- Restrict software installation to authorized programs

### AWS Implementation
- **AWS Config**: Enable in all CJI accounts. Deploy managed rules and custom rules for CJIS checks.
- **Systems Manager State Manager**: Enforce desired state configurations on EC2 instances
- **Systems Manager Patch Manager**: Automate patching with maintenance windows. Define patch baselines aligned with CJIS timelines.
- **Firewall Manager**: Centrally manage security groups, WAF rules, Shield protections
- **Service Catalog**: Restrict resource provisioning to approved templates
- **AMI hardening**: Use CIS Benchmark or DISA STIG hardened AMIs. Scan with Inspector before deployment.
- **ECR image scanning**: Scan container images for vulnerabilities before deployment

---

## PA 8 — Media Protection (Section 5.8)

### Requirements
- Encrypt CJI at rest using FIPS 140-2/3 validated cryptographic modules
- Sanitize media before disposal or reuse
- Control physical and digital media containing CJI

### AWS Implementation
- **KMS**: AWS KMS uses FIPS 140-2 Level 2 validated HSMs by default. Use CMKs for CJI data.
- **EBS encryption**: Enable default EBS encryption at the account level
- **RDS encryption**: Enable at instance creation (cannot be added later — must migrate)
- **S3 encryption**: Use SSE-KMS. Set bucket policy to deny unencrypted uploads.
- **DynamoDB encryption**: Enabled by default with AWS-owned keys; use CMK for CJI tables
- **Macie**: Detect unencrypted or publicly accessible CJI data in S3
- **S3 Lifecycle Policies**: Automate deletion of CJI data past retention period
- **AWS media sanitization**: AWS handles physical media destruction per NIST 800-88 — documented in SOC 2 reports

---

## PA 9 — Physical Protection (Section 5.9)

### Requirements
- Physically secure facilities that house CJI systems
- Visitor controls, access logs, environmental protections

### AWS Implementation
- **Inherited from AWS**: AWS data centers meet or exceed CJIS physical security requirements. Documented in AWS SOC 2 Type II reports and FedRAMP High authorization.
- **Customer responsibility**: Secure on-premises facilities (offices, data centers) that access CJI
- **AWS Artifact**: Download SOC 2 and FedRAMP reports as evidence for auditors

---

## PA 10 — Systems and Communications Protection (Section 5.10)

### Requirements
- Encrypt CJI in transit using FIPS 140-2/3 validated modules (TLS 1.2+ minimum)
- Boundary protection — control traffic entering/leaving CJI systems
- Partition CJI systems from non-CJI systems

### AWS Implementation
- **FIPS endpoints**: Use FIPS-validated TLS endpoints for all AWS API calls. Set `AWS_USE_FIPS_ENDPOINT=true` or use FIPS-specific endpoint URLs.
- **VPC isolation**: Dedicated VPC(s) for CJI workloads. No shared VPCs with non-CJI systems.
- **Security Groups**: Stateful firewall — allow only required ports/protocols between tiers
- **NACLs**: Stateless subnet-level filtering as defense in depth
- **VPN (Site-to-Site)**: IPsec with AES-256 and SHA-256+ for agency connectivity
- **Direct Connect**: Private dedicated connection — add MACsec encryption for link-layer protection
- **VPC Endpoints (PrivateLink)**: Access AWS services without traversing the internet
- **Network Firewall**: Stateful inspection and IDS/IPS for CJI VPC traffic
- **ACM**: Manage TLS certificates for application endpoints
- **Route 53 Resolver**: Keep DNS resolution private within VPC

---

## PA 11 — Formal Audits (Section 5.11)

### Requirements
- Triennial audit by state CSA or FBI CJIS Division
- Agencies should conduct self-assessments between audits
- Maintain evidence of compliance

### AWS Implementation
- **Audit Manager**: Set up assessments using CJIS-relevant frameworks. Automate evidence collection.
- **Security Hub**: Continuous compliance posture dashboard
- **Config Conformance Packs**: Deploy packs aligned to CJIS requirements
- **AWS Artifact**: Pull AWS compliance reports (SOC 2, FedRAMP) as inherited control evidence
- **Evidence collection**: Export Config snapshots, Security Hub findings, CloudTrail logs, IAM credential reports as audit evidence

---

## PA 12 — Personnel Security (Section 5.12)

### Requirements
- Fingerprint-based background check for all personnel with unescorted access to unencrypted CJI
- Screening before access is granted
- Re-screening per state CSA schedule

### AWS Implementation
- This is primarily an organizational/HR process
- **IAM tagging**: Tag IAM users/roles with background check status and expiration date
- **ABAC policies**: Deny CJI resource access if the `background-check-expiry` tag is past due
- **SCPs + IAM**: Ensure only authorized (screened) principals can assume CJI-access roles
- **AWS personnel**: AWS GovCloud staff undergo background screening — documented in FedRAMP authorization

### Key Consideration
If a cloud administrator can access unencrypted CJI (e.g., SSH into an EC2 instance with CJI in memory or on disk), they need a fingerprint-based background check. Mitigate by encrypting CJI at all layers and restricting admin access patterns (use SSM Session Manager with logging instead of direct SSH).

---

## PA 13 — Mobile Devices (Section 5.13)

### Requirements
- MDM for any mobile device accessing CJI
- Full-device encryption, remote wipe, authentication
- Prohibit CJI storage on unauthorized devices

### AWS Implementation
- **WorkSpaces**: Virtual desktops — CJI stays in the cloud, not on the device. Supports MFA.
- **AppStream 2.0**: Application streaming — users access CJI apps without local data storage
- **MDM**: Customer-managed (Intune, JAMF, etc.) — AWS does not provide MDM
- **Cognito + application controls**: If building a mobile CJI app, enforce MFA and prevent local caching of CJI data
- WorkSpaces and AppStream are the recommended pattern — they eliminate the need for CJI on mobile devices entirely
