# CJIS Readiness Checklist

> Based on CJIS Security Policy v6.0 (effective December 2024).
> Last verified against official source: 2026-05-21.
> Check https://le.fbi.gov/cjis-division/cjis-security-policy-resource-center for newer versions.

Use this checklist when performing a CJIS compliance gap assessment. Flag each item
as: ✅ Met | ⚠️ Partial | ❌ Not Met | N/A

Items are grouped by control family and priority. **P1/P2 items are mandatory for compliance. P3/P4 items are recommended.**

---

## IA — Identification and Authentication (P1) — MANDATORY

- [ ] Advanced authentication (MFA) required for all CJI access
- [ ] MFA enforced on AWS console access for all IAM users
- [ ] MFA enforced on VPN/remote access to CJI environment
- [ ] Root account has MFA enabled and no access keys
- [ ] Password policy: minimum 20 characters, complexity requirements
- [ ] Passwords changed at maximum 90-day intervals
- [ ] Account lockout after no more than 5 consecutive failed attempts
- [ ] Service accounts use IAM roles (not long-lived access keys) where possible
- [ ] Access keys rotated every 90 days
- [ ] Unique user IDs — no shared accounts for CJI access
- [ ] FIPS 140-2/3 validated cryptographic modules in use (GovCloud or FIPS endpoints)

## SC — Systems and Communications Protection (P1) — MANDATORY

- [ ] All CJI data encrypted in transit using TLS 1.2+ with FIPS 140-2/3 validated modules
- [ ] FIPS endpoints enabled for AWS API calls (`AWS_USE_FIPS_ENDPOINT=true` or GovCloud)
- [ ] VPN connections use FIPS-compliant cipher suites (AES-256, SHA-256+, IKEv2)
- [ ] CJI workloads isolated in dedicated VPCs (no IGW or strictly controlled)
- [ ] VPC endpoints configured for AWS services to avoid internet transit
- [ ] Network segmentation enforced via security groups and NACLs
- [ ] GuardDuty enabled for boundary threat detection
- [ ] WAF deployed on internet-facing load balancers (if applicable)
- [ ] All CJI data encrypted at rest (EBS, RDS, S3, DynamoDB, EFS) using KMS CMKs
- [ ] EBS encryption-by-default enabled at account level
- [ ] KMS customer-managed keys have automatic rotation enabled
- [ ] Direct Connect or Site-to-Site VPN for agency connectivity

## AC — Access Control (P1) — MANDATORY

- [ ] Access to CJI based on least privilege and need-to-know
- [ ] Role-based access control (RBAC) implemented via IAM roles/policies
- [ ] Account provisioning/de-provisioning procedures documented
- [ ] Access reviews performed at least annually
- [ ] Inactive accounts disabled after 90 days
- [ ] Session lock after 30 minutes of inactivity
- [ ] Remote access to CJI only via encrypted channel (SSM Session Manager or VPN)
- [ ] No public S3 buckets, public EC2 instances, or public RDS instances in CJI environment
- [ ] S3 Block Public Access enabled at account level
- [ ] SCPs restrict CJI account actions to authorized services and regions
- [ ] IAM Access Analyzer enabled with no active external-access findings
- [ ] No overly-permissive IAM policies (`*:*` on CJI resources)

## CM — Configuration Management (P1) — MANDATORY

- [ ] Secure baseline configurations defined (CIS Benchmarks or DISA STIGs)
- [ ] AWS Config enabled and recording in CJI accounts
- [ ] Config rules or conformance packs deployed for CJIS-relevant checks
- [ ] Security Hub enabled with NIST 800-53 or FedRAMP standard
- [ ] Patch management process defined with SLAs
- [ ] Critical/high patches applied within 30 days
- [ ] Systems Manager Patch Manager or equivalent in use
- [ ] All EC2 instances managed by SSM
- [ ] Change management process documented and followed
- [ ] Security groups reviewed regularly for least privilege
- [ ] AMIs/container images hardened and scanned before deployment
- [ ] Software/system component inventory maintained

## SI — System and Information Integrity (P1) — MANDATORY

- [ ] Inspector enabled for EC2, Lambda, and ECR scanning
- [ ] Critical vulnerabilities remediated within defined SLAs
- [ ] GuardDuty Malware Protection enabled
- [ ] Security Hub aggregating findings from all detection services
- [ ] CloudWatch alarms configured for security events
- [ ] ECR image scanning enabled (scan-on-push)
- [ ] Lambda code signing considered for CJI-processing functions

## AU — Audit and Accountability (P2) — MANDATORY

- [ ] CloudTrail enabled in all regions with management events
- [ ] CloudTrail data events for S3 buckets containing CJI and Lambda functions
- [ ] CloudTrail log file validation enabled
- [ ] CloudTrail logs encrypted with KMS CMK
- [ ] VPC Flow Logs enabled for all CJI VPCs
- [ ] Application-level logging captures CJI access events (who accessed what, when)
- [ ] Log retention minimum 3 years (CJIS v6.0 requirement)
- [ ] Logs protected from unauthorized modification (S3 Object Lock, separate account)
- [ ] CloudTrail delivery failure alarms configured
- [ ] Centralized log aggregation in place (CloudWatch, OpenSearch, or third-party SIEM)
- [ ] Audit review capability (CloudTrail Lake, Athena, or Security Hub)

## CP — Contingency Planning (P2) — MANDATORY

- [ ] AWS Backup plans exist for all CJI resources
- [ ] Backup vaults encrypted with KMS CMKs
- [ ] RDS automated backups enabled with adequate retention (>= 7 days)
- [ ] RDS Multi-AZ enabled for CJI databases
- [ ] Cross-region backup replication configured for disaster recovery
- [ ] Contingency plan documented and tested at least annually
- [ ] Recovery time objectives (RTO) and recovery point objectives (RPO) defined

## PS — Personnel Security (P2) — MANDATORY

- [ ] Fingerprint-based background checks completed for all personnel with unescorted access to unencrypted CJI
- [ ] Background checks completed BEFORE granting CJI access
- [ ] Background check renewal schedule defined (per state CSA, typically every 5 years)
- [ ] Screening applies to: employees, contractors, cloud admins with potential CJI access
- [ ] Termination procedures include immediate CJI access revocation
- [ ] Personnel security records maintained and auditable

## IR — Incident Response (P2) — MANDATORY

- [ ] Incident Response Plan (IRP) documented and approved
- [ ] IRP covers: detection, containment, eradication, recovery, post-incident analysis
- [ ] Reporting procedures defined — notify CSO/CSA and FBI CJIS Division
- [ ] IR team roles and contact information documented
- [ ] IRP tested (tabletop or functional exercise) at least annually
- [ ] GuardDuty or equivalent threat detection enabled
- [ ] Automated alerting configured for security events

## CA — Assessment, Authorization, and Monitoring (P2) — MANDATORY

- [ ] Prepared for triennial CJIS audit by state CSA or FBI
- [ ] Self-assessment completed using CJIS Security Policy audit checklist
- [ ] Security Hub enabled with findings reviewed regularly
- [ ] Evidence collection process defined (config exports, policy docs, reports)
- [ ] Previous audit findings remediated and documented

---

## AT — Awareness and Training (P3) — RECOMMENDED

- [ ] Security awareness training program established for all CJI-authorized personnel
- [ ] Training completed within 6 months of initial assignment and refreshed every 2 years
- [ ] Training covers: rules of behavior, incident response, media protection, social engineering
- [ ] Training records maintained and auditable

## PE — Physical and Environmental Protection (P3) — RECOMMENDED

- [ ] Physical security of on-premises facilities documented (if applicable)
- [ ] AWS physical security inherited — documented via SOC 2 / FedRAMP reports
- [ ] Visitor access controls in place for on-premises CJI facilities

## SA — System and Services Acquisition (P3) — RECOMMENDED

- [ ] System development lifecycle (SDLC) includes security requirements
- [ ] Security testing performed during development
- [ ] Third-party services assessed for CJIS compliance

## SR — Supply Chain Risk Management (P3) — RECOMMENDED

- [ ] Supply chain risk management plan documented
- [ ] Component/service provenance tracked
- [ ] Acquisition agreements include security requirements

## MA — Maintenance (P3) — RECOMMENDED

- [ ] System maintenance procedures documented
- [ ] Remote maintenance performed via approved tools (SSM)
- [ ] Maintenance activities logged

## PL — Planning (P3) — RECOMMENDED

- [ ] System security plan documented
- [ ] Rules of behavior defined and acknowledged by all users
- [ ] Security architecture documented

## Section 5.1 — Information Exchange Agreements — MANDATORY

- [ ] CJIS Security Addendum signed by AWS for applicable state(s)
- [ ] Management Control Agreement (MCA) in place with contractors/vendors
- [ ] All contractor personnel with CJI access have individually signed the Security Addendum
- [ ] Interconnection Security Agreements (ISAs) documented

## Section 5.20 — Mobile Devices — IF APPLICABLE

- [ ] MDM solution deployed if mobile devices access CJI
- [ ] Remote wipe capability enabled
- [ ] Mobile devices encrypted (full-device encryption)
- [ ] Consider AWS WorkSpaces or AppStream as alternatives to CJI on mobile devices
