# FERPA Readiness Checklist

Use this checklist when performing a FERPA gap assessment or preparing for a state-contract annual review, DPA renewal, SOC 2 engagement, or SPPO complaint response. Flag each item as: ✅ Met | ⚠️ Partial | ❌ Not Met | N/A

The checklist covers all 10 FCDs. The programmatic scan automates many technical items in FCDs 3, 4, 5, 6, 7, 8 — this checklist still includes them for questionnaire-only mode and for organizational/procedural items the scan cannot verify.

---

## FCD 1 — Directory Information & Consent Management

- [ ] Annual directory-information notice delivered to parents/eligible students (K-12/higher-ed)
- [ ] Directory-info fields identified and documented (name, address, phone, DOB, etc.)
- [ ] Opt-out mechanism available and functioning
- [ ] Opt-out signals propagate from SIS of record to all downstream systems (vendor products, LMS, assessment platforms)
- [ ] Records of disclosures of directory information maintained where state law requires (some states, e.g., NY, require)
- [ ] Consent-management system itself meets all FERPA safeguards (it contains student records)
- [ ] Procedure for handling consent revocation documented

## FCD 2 — Student/Parent Rights (Inspect, Amend, Opt-out)

- [ ] Inspect-and-review procedure documented
- [ ] 45-day SLA for inspect-and-review achievable with current tooling (data-lineage discipline, cross-service search)
- [ ] Amendment-request procedure documented
- [ ] Hearing process defined if amendment is denied (§99.21–99.22)
- [ ] Rights notice delivered annually (§99.7)
- [ ] Complaint procedure documented — parents/students can file with SPPO at ed.gov/ferpa
- [ ] Staff training on handling DSARs (Data Subject Access Requests)
- [ ] Audit trail of DSARs maintained
- [ ] Higher-ed: rights transfer to the eligible student at 18 or matriculation (§99.5)

## FCD 3 — Disclosure Controls & "School Official" Data Sharing

- [ ] §99.31 exception relied upon for each disclosure is identified and documented
- [ ] If operating under the school-official exception (§99.31(a)(1)(i)(B)): district retains direct control over use and maintenance of records
- [ ] Redisclosure restrictions (§99.33(a)) documented in every downstream subprocessor agreement
- [ ] Application-level controls enforce purpose limitation (record used only for the contracted educational function)
- [ ] ML/AI training on student data (if any) explicitly authorized in the DPA
- [ ] No targeted advertising or profiling based on student records (required by CA SOPIPA, IL SOPPA, and most state DPAs)
- [ ] Cross-account AWS shares to districts/subprocessors enumerated and matched to contracts
- [ ] IAM Access Analyzer enabled with periodic review of external-access findings
- [ ] SCPs restrict student-data accounts to approved services and regions

## FCD 4 — Auditing & Access Logging

### Infrastructure (automated)
- [ ] CloudTrail enabled in all regions
- [ ] CloudTrail log file validation enabled
- [ ] CloudTrail logs encrypted with KMS CMK
- [ ] CloudTrail data events enabled for student-data S3 buckets and Lambdas
- [ ] VPC Flow Logs enabled on all student-data VPCs
- [ ] Log retention aligned with student-record retention schedule (commonly 7+ years)
- [ ] Log storage with Object Lock or equivalent tamper protection
- [ ] GuardDuty enabled in all student-data accounts
- [ ] CloudWatch alarms for critical security events (root login, MFA disable, IAM policy changes)

### §99.32 disclosure log (application-level — the critical FERPA-specific item)
- [ ] **Application emits a structured disclosure record for every external disclosure of education records**
- [ ] Record includes: timestamp, student_id, requesting party, legitimate interest / §99.31 exception invoked, records disclosed
- [ ] Log stored immutably (S3 Object Lock or equivalent)
- [ ] Log retention matches student-record retention (for the life of the record)
- [ ] Log is queryable by student_id to support parental-access requests
- [ ] Disclosure log is itself a student record and meets all FERPA safeguards

## FCD 5 — Access Control & Least Privilege

- [ ] Access to student records based on least privilege and need-to-know
- [ ] Role-based access control (RBAC) implemented via IAM roles / Identity Center permission sets
- [ ] Account provisioning/de-provisioning tied to HR/SIS status changes (automation preferred)
- [ ] Annual or more frequent access reviews
- [ ] Inactive accounts disabled after 90 days (or per state contract)
- [ ] Session timeout after 30 minutes of inactivity (or per state contract)
- [ ] Remote access only via encrypted channel (Client VPN + MFA, or SSM Session Manager)
- [ ] No publicly-accessible student-data resources (S3, RDS, RDS snapshots, EBS snapshots)
- [ ] S3 Block Public Access enabled account-wide
- [ ] SCPs restrict student-data accounts (US-region-only, no IAM user creation outside Identity Center, etc.)
- [ ] Application-level authorization tested: a user cannot view records outside their authorized scope

## FCD 6 — Authentication (MFA, SSO, Password Hygiene)

- [ ] MFA required for all administrative access to student-data environments
- [ ] MFA enforced on AWS console access (IAM or Identity Center)
- [ ] MFA enforced on VPN/remote access
- [ ] Root account has hardware MFA; access keys deleted
- [ ] Password policy: ≥14 characters, complexity, ≤90-day age, reuse prevention ≥10 (state contract may exceed)
- [ ] Account lockout after ≤5 failed attempts
- [ ] Access keys rotated ≤90 days
- [ ] Service accounts use IAM roles, not long-lived keys
- [ ] Unique user IDs — no shared accounts
- [ ] If Cognito is used for end-user auth: advanced security features enabled; MFA enforced where age-appropriate
- [ ] SAML/OIDC federation from district IdP (Google Workspace for Education, ClassLink, Clever, Okta) for student/teacher auth

## FCD 7 — Encryption at Rest & In Transit

### At rest
- [ ] KMS CMKs used for all student-data encryption (not AWS-managed keys)
- [ ] KMS automatic rotation enabled
- [ ] All EBS volumes encrypted; default encryption on at account level
- [ ] All RDS / Aurora instances encrypted (not retroactively possible — designed in)
- [ ] All RDS snapshots encrypted; no public snapshot shares
- [ ] All S3 buckets SSE-KMS encrypted with deny-plaintext policies
- [ ] DynamoDB tables containing student data use CMK
- [ ] OpenSearch domains: at-rest + node-to-node encryption
- [ ] AWS Backup vaults encrypted with CMK

### In transit
- [ ] TLS 1.2+ minimum on all ALBs, NLBs, API Gateway, CloudFront
- [ ] S3 bucket policies deny plain HTTP
- [ ] RDS `require_secure_transport` or `rds.force_ssl` enabled
- [ ] Internal service-to-service traffic uses TLS
- [ ] FIPS endpoints in use if state framework requires (StateRAMP, TX-RAMP L2)
- [ ] Certificates managed via ACM with automated renewal

## FCD 8 — Data Minimization, Retention & Secure Destruction

- [ ] Data collection minimized — each field in the data model has a documented educational purpose
- [ ] Retention schedule defined per record category, aligned with state records-retention requirements
- [ ] S3 lifecycle policies automate transition / deletion per category
- [ ] RDS backup retention configured per policy (typically ≥7 days, many states require ≥35 days)
- [ ] AWS Backup plans with lifecycle rules covering cross-service resources
- [ ] DynamoDB TTL on transient records
- [ ] Dedicated CMKs per district (or per data category) for crypto-shred capability
- [ ] Contract-termination procedure documented: export if required, then crypto-shred district-specific keys
- [ ] Destruction attestation procedure (who signs, what evidence)
- [ ] Tag-based inventory of student-data resources with `district` and `retention-expiry` tags

## FCD 9 — Incident Response & Breach Notification

- [ ] Written Incident Response Plan (IRP) covering student-data breach scenarios
- [ ] IRP includes: detection, containment, eradication, recovery, lessons-learned
- [ ] IR team roles and contact info documented (vendor side + district-notification path)
- [ ] Breach-scope-determination procedure: enumerate affected students, export §99.32 log for impacted records, preserve evidence
- [ ] Vendor-to-district notification SLA documented (commonly ≤24 hours of confirmed breach)
- [ ] State-law breach-notification requirements understood per state in scope (see state-law-addenda.md)
- [ ] IRP tested (tabletop or functional exercise) at least annually
- [ ] AWS GuardDuty / Security Hub findings routed to IR team with on-call rotation
- [ ] EventBridge + Lambda automation for containment actions
- [ ] SNS / PagerDuty / Opsgenie alerting configured
- [ ] CloudTrail Lake or equivalent for historical investigation
- [ ] IRP integrated with AWS Support and AWS Trust & Safety escalation paths

## FCD 10 — Vendor / Subprocessor Management

### For vendors (EdTech as school official)
- [ ] DPA on file with every district customer
- [ ] DPA explicitly designates vendor as school official under §99.31(a)(1)(i)(B)
- [ ] DPA includes: data-use limitation, redisclosure prohibition, retention/destruction, breach-notification SLA, audit rights, subprocessor disclosure
- [ ] Subprocessor register maintained and current
- [ ] Subprocessor register includes AWS (region, services used), each named service (Datadog, Segment, Google Analytics, etc.), and any ML/AI providers
- [ ] Subprocessor additions pre-approved by districts (or at minimum, districts notified with opt-out window)
- [ ] Subprocessor agreements bind each subprocessor to equivalent-or-stricter FERPA terms
- [ ] Annual SOC 2 Type II audit in scope of relevant controls
- [ ] AWS Artifact reports pulled and available as DPA attachments (AWS SOC 2, ISO 27001, FedRAMP, StateRAMP)

### For institutions (K-12 / higher-ed as customer)
- [ ] Due-diligence process for adding new EdTech vendors (questionnaire, security review, DPA)
- [ ] Inventory of current EdTech vendors with records of: data categories shared, DPA date, breach-notification SLA
- [ ] Annual review of each vendor's security posture
- [ ] Vendor access to student data revocable on notice (access-review discipline)

---

## Assessment-mode-specific subsets

### Quick Scan — just the questions that drive breach/complaint risk
Focus on: FCD 4 §99.32 log (automated), FCD 5 public-exposure items (automated), FCD 6 MFA (automated), FCD 7 encryption (automated).

### Standard — everything automated + key organizational questions
Add FCD 3 subprocessor alignment, FCD 8 contract-termination procedure, FCD 9 notification SLA.

### Full / Questionnaire — the complete checklist above
Walk through every item with the user. Expected time: 60–90 minutes with a Legal / Privacy Officer in the room.
