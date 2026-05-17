# CJIS Readiness Checklist

Use this checklist when performing a CJIS compliance gap assessment. Flag each item
as: ✅ Met | ⚠️ Partial | ❌ Not Met | N/A

---

## PA 1 — Information Exchange Agreements

- [ ] CJIS Security Addendum signed by AWS for applicable state(s)
- [ ] Management Control Agreement (MCA) in place between agency and any contractors/vendors
- [ ] All contractor personnel with potential CJI access have individually signed the Security Addendum
- [ ] Interconnection Security Agreements (ISAs) documented for all external system connections
- [ ] Data sharing agreements in place with other agencies accessing CJI through the system

## PA 2 — Security Awareness Training

- [ ] Security awareness training program established for all CJI-authorized personnel
- [ ] Training completed within 6 months of initial assignment and refreshed every 2 years
- [ ] Training covers: rules of behavior, incident response procedures, media protection, social engineering, password security, physical security
- [ ] Training records maintained and auditable
- [ ] Personnel acknowledge acceptable use policies

## PA 3 — Incident Response

- [ ] Incident Response Plan (IRP) documented and approved
- [ ] IRP covers: detection, containment, eradication, recovery, post-incident analysis
- [ ] Reporting procedures defined — notify CSO/CSA and FBI CJIS Division as required
- [ ] Reporting timeframe meets state CSA requirements (typically immediate for CJI breaches)
- [ ] IR team roles and contact information documented
- [ ] IRP tested (tabletop or functional exercise) at least annually
- [ ] GuardDuty or equivalent threat detection enabled in CJI accounts
- [ ] Automated alerting configured for security events (SNS, PagerDuty, etc.)

## PA 4 — Auditing and Accountability

- [ ] Audit logging enabled for all CJI systems and applications
- [ ] CloudTrail enabled in all regions with management and data events
- [ ] CloudTrail log file validation enabled
- [ ] CloudTrail logs encrypted with KMS
- [ ] VPC Flow Logs enabled for all CJI VPCs
- [ ] Application-level logging captures CJI access events (who accessed what CJI, when)
- [ ] Logs include: user ID, event type, date/time, success/failure, data accessed
- [ ] Log retention minimum 1 year (CJIS requirement)
- [ ] Logs protected from unauthorized modification or deletion (S3 Object Lock, separate account)
- [ ] Regular log review process defined (automated alerts + periodic manual review)
- [ ] Centralized log aggregation in place (CloudWatch, OpenSearch, or third-party SIEM)

## PA 5 — Access Control

- [ ] Access to CJI based on least privilege and need-to-know
- [ ] Role-based access control (RBAC) implemented via IAM roles/policies
- [ ] Account provisioning/de-provisioning procedures documented
- [ ] Access reviews performed at least annually
- [ ] Inactive accounts disabled after 90 days (or per state CSA policy)
- [ ] Session lock after 30 minutes of inactivity
- [ ] Concurrent session control implemented where applicable
- [ ] Remote access to CJI only via encrypted VPN or equivalent
- [ ] No public S3 buckets, public EC2 instances, or public RDS instances in CJI environment
- [ ] SCPs restrict CJI account actions to authorized services and regions

## PA 6 — Identification and Authentication

- [ ] Advanced authentication (MFA) required for all CJI access
- [ ] MFA enforced on AWS console access for all IAM users
- [ ] MFA enforced on VPN/remote access to CJI environment
- [ ] Password policy: minimum length per agency policy (CJIS recommends complexity + minimum 8 chars; many states require more)
- [ ] Passwords changed at maximum 90-day intervals
- [ ] Account lockout after no more than 5 consecutive failed attempts
- [ ] Root account has MFA enabled and no access keys
- [ ] Service accounts use IAM roles (not long-lived access keys) where possible
- [ ] Access keys rotated per policy (90 days recommended)
- [ ] Unique user IDs — no shared accounts for CJI access

## PA 7 — Configuration Management

- [ ] Secure baseline configurations defined for all system components (CIS Benchmarks or DISA STIGs)
- [ ] AWS Config enabled and recording in CJI accounts
- [ ] Config rules deployed for CJIS-relevant checks
- [ ] Patch management process defined with SLAs
- [ ] Critical/high patches applied within 30 days (or per state CSA policy)
- [ ] Systems Manager Patch Manager or equivalent in use
- [ ] Change management process documented and followed
- [ ] Security groups and NACLs reviewed regularly for least privilege
- [ ] AMIs/container images hardened and scanned before deployment
- [ ] Software inventory maintained

## PA 8 — Media Protection

- [ ] All CJI data encrypted at rest using FIPS 140-2/3 validated modules
- [ ] EBS volumes encrypted (KMS)
- [ ] RDS instances encrypted at rest
- [ ] S3 buckets use SSE-KMS or SSE-S3 encryption
- [ ] DynamoDB tables encrypted
- [ ] Backup/snapshot encryption enabled
- [ ] Media sanitization procedures documented for decommissioned resources
- [ ] S3 lifecycle policies configured for CJI data retention/deletion
- [ ] Macie enabled to detect and classify sensitive CJI data in S3

## PA 9 — Physical Protection

- [ ] Physical security of on-premises facilities documented (if applicable)
- [ ] AWS physical security inherited — documented via AWS SOC 2 / FedRAMP High reports
- [ ] Visitor access controls in place for on-premises CJI facilities
- [ ] Physical access logs maintained

## PA 10 — Systems and Communications Protection

- [ ] All CJI data encrypted in transit using TLS 1.2+ with FIPS 140-2/3 validated modules
- [ ] FIPS endpoints enabled for AWS API calls
- [ ] VPN connections use FIPS-compliant cipher suites (AES-256, SHA-256+)
- [ ] CJI workloads isolated in dedicated VPCs
- [ ] No internet gateways in CJI VPCs (or strictly controlled with WAF/proxy)
- [ ] VPC endpoints configured for AWS services to avoid internet transit
- [ ] Network segmentation enforced via security groups and NACLs
- [ ] Direct Connect or Site-to-Site VPN for agency connectivity
- [ ] DNS resolution kept private (Route 53 Resolver, no public DNS for CJI resources)
- [ ] Boundary protection: WAF, Shield, Network Firewall as applicable

## PA 11 — Formal Audits

- [ ] Prepared for triennial CJIS audit by state CSA or FBI
- [ ] Self-assessment completed using CJIS Security Policy audit checklist
- [ ] AWS Audit Manager configured with CJIS-relevant framework
- [ ] Security Hub enabled with findings reviewed regularly
- [ ] Evidence collection process defined (screenshots, config exports, policy docs)
- [ ] Previous audit findings remediated and documented

## PA 12 — Personnel Security

- [ ] Fingerprint-based background checks completed for all personnel with unescorted access to unencrypted CJI
- [ ] Background checks completed BEFORE granting CJI access
- [ ] Background check renewal schedule defined (per state CSA, typically every 5 years)
- [ ] Screening applies to: employees, contractors, cloud admins with potential CJI access
- [ ] Termination procedures include immediate CJI access revocation
- [ ] Personnel security records maintained and auditable

## PA 13 — Mobile Devices

- [ ] Mobile Device Management (MDM) solution deployed if mobile devices access CJI
- [ ] Remote wipe capability enabled
- [ ] Mobile devices encrypted (full-device encryption)
- [ ] Mobile device authentication required (PIN/biometric + MFA for CJI apps)
- [ ] Jailbroken/rooted device detection in place
- [ ] CJI data prohibited from being stored locally on mobile devices (or encrypted if stored)
- [ ] Consider AWS WorkSpaces or AppStream as alternatives to CJI on mobile devices
