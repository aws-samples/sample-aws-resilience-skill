# FERPA Control Domains — Detailed AWS Implementation Guide

Deep-dive on each of the 10 FERPA Control Domains (FCDs) with specific AWS implementation guidance.

FERPA itself does not enumerate "control domains" — the statute and 34 CFR Part 99 describe rights, exceptions, and a general "reasonable methods" safeguard expectation. The 10 FCDs used here distill FERPA, the ED Privacy Technical Assistance Center (PTAC) "Data Security Checklist," and the NIST SP 800-171 controls most state EdTech contracts adopt into assessment-sized buckets.

Where relevant, each FCD includes a **K-12 note** (district/school-as-customer perspective) and a **Higher-ed note** (institution-as-customer perspective) and a **Vendor note** (EdTech-as-school-official perspective).

---

## FCD 1 — Directory Information & Consent Management

### Requirements

- Identify which fields in your data model are "directory information" (per 34 CFR §99.3) — name, address, phone, DOB, awards, enrollment status, etc.
- Notify parents/eligible students annually of directory-information designations and opt-out rights (§99.37)
- Honor opt-outs — once a parent/student opts out, directory information becomes protected and cannot be disclosed without consent
- Track consent: for disclosures that require it (§99.30), maintain a record of the signed consent including what info, to whom, and for what purpose

### AWS implementation

- **Data model tagging**: Tag S3 objects, DynamoDB items, and RDS columns that contain directory information vs. non-directory PII. Enables targeted policy enforcement.
- **Amazon Macie custom data identifiers**: Create identifiers matching your directory-info schema (student ID formats, names alongside school IDs) so you can detect leaks into non-approved buckets.
- **Fine-grained access control**: Lake Formation or row-level security in Redshift to expose only non-opted-out directory info for bulk uses.
- **Consent store**: Cognito user attributes, DynamoDB consent table, or external consent-management SaaS. The consent store itself is a student record and must itself meet all FERPA safeguards.
- **EventBridge automation**: When a consent record flips to "opted out," trigger a Lambda to update the student's data-access tags and invalidate any cached exports.

### Key pitfall

Vendors frequently assume "directory information = public" — it is only not-protected if the parent/student has not opted out AND the school has designated the field as directory information in its annual notice. Treat it as protected until you can prove both conditions.

### K-12 note
District is responsible for the annual notice and for collecting opt-outs. Vendor must honor opt-out signals from the district's SIS — test this end-to-end.

### Higher-ed note
Student (now adult, ≥18 or in postsecondary attendance) holds the opt-out right directly. Typically managed via student self-service portal.

### Vendor note
DPAs usually specify whether the vendor handles opt-out tracking or receives a filtered feed from the district. Know which — and log receipt of opt-out updates.

---

## FCD 2 — Student/Parent Rights (Inspect, Amend, Opt-out)

### Requirements

FERPA grants specific rights (§99.10–99.22):
- **Inspect and review**: The school must provide access to education records within 45 days of request
- **Amend**: Request amendment of records believed inaccurate; formal hearing process if denied (§99.20–99.22)
- **Opt-out of directory disclosure**: Covered in FCD 1
- **Complaint**: Right to file a complaint with SPPO

### AWS implementation

This FCD is primarily organizational/procedural — AWS does not directly satisfy it. Supporting technical capabilities:

- **Data subject access request (DSAR) tooling**: Build an internal runbook that enumerates every data store containing a given student's records. Leverage tags + Athena queries over cataloged data lakes.
- **Athena / AWS Glue Data Catalog**: Federate queries across S3, RDS, DynamoDB to produce a single student's full record on request.
- **Audit log of DSARs**: Log every student-initiated access/amendment request — itself becomes part of the §99.32 record.
- **Amendment workflow**: Typically a ticketing system (Jira, ServiceNow) with an integration that writes amended records back to the SIS — CloudTrail captures the API calls; the ticketing system captures the human-authorization chain.

### Key pitfall

"I can't find all of student X's records" is a real operational failure that becomes a FERPA finding if a DSAR can't be completed in 45 days. Data-lineage tagging discipline is the AWS-side preventive.

### Vendor note
DPA typically makes the district the point of contact for DSARs, with the vendor required to fulfill within a contracted SLA (often 10 business days to give the district time to turn it around to the parent).

---

## FCD 3 — Disclosure Controls & "School Official" Data Sharing

### Requirements

Under §99.31(a), education records may be disclosed without consent in specific exceptions, the most operationally important being:

- **§99.31(a)(1)(i)(B) "School Official" exception**: An outside party (vendor) may be treated as a school official if:
  1. It performs an institutional service/function for which the school would otherwise use its own employees
  2. It is under the direct control of the school regarding the use and maintenance of education records
  3. It is subject to the §99.33(a) use-and-redisclosure restrictions
- **§99.33(a) Redisclosure**: Cannot redisclose without consent except under another §99.31 exception
- **§99.32 Record of disclosures**: The school (and any party acting for the school) must maintain a record of each request for access and each disclosure of education records

### AWS implementation

- **Separation of student-record environments**: Use dedicated AWS accounts (ideally a separate OU under AWS Organizations) for student-record workloads. Apply SCPs to enforce region, service, and data-residency constraints.
- **Cross-account sharing controls**:
  - S3 bucket policies with explicit allow-list of school AWS account principals; deny all other cross-account access
  - RAM (Resource Access Manager) shares tracked and reviewed; no shares to unaffiliated accounts
  - Lake Formation cross-account data-catalog shares logged via CloudTrail
- **AWS Organizations + SCPs**: Deny any action that would share a student-record resource with a non-approved principal, e.g., `s3:PutBucketPolicy` with conditions blocking `*`-principal grants.
- **IAM Access Analyzer**: Continuously scan for cross-account / external-principal exposure of S3, RDS snapshots, KMS keys, Lambda functions, IAM roles. Any unexpected finding = a potential §99.33 redisclosure event.
- **Subprocessor management (ties to FCD 10)**: If a third-party SaaS or another AWS account is a subprocessor, document and restrict the connection. PrivateLink + VPC endpoints are the least-leaky pattern.
- **§99.32 disclosure log**: Application-level. Every export, download, API response that contains education records must log: date/time, requestor, purpose, records disclosed, authority (which §99.31 exception applied). CloudTrail logs the API call, not the semantic purpose — the application must emit the log. This is the single most common technical gap in vendor environments.

### Key pitfall

The "direct control" prong of the school-official exception is where DPAs get tight — the district must retain control over how the vendor uses records. If the vendor unilaterally changes data retention, adds subprocessors, or uses records for R&D / model-training without district sign-off, the school-official designation is invalid and every resulting disclosure becomes an unauthorized disclosure.

### Vendor note
Model-training on student data is the hottest current compliance topic. If you train ML models on student data, you must have explicit DPA language permitting it. AWS-side: log every training-job invocation that reads from a student-data S3 bucket; tie it back to a documented district authorization.

---

## FCD 4 — Auditing & Access Logging

### Requirements

- **§99.32 Record of disclosures**: Maintain a record of each request for access and each disclosure of education records from a student's record. Must include:
  - Parties who requested/received the record
  - Legitimate interest in the disclosure (which §99.31 exception or consent)
- **Retention**: §99.32(a)(2) — the record must be maintained with the education record as long as the record is maintained (effectively, for the life of the student record, often measured in decades)
- **Security logging** (PTAC/NIST 800-171 3.3.x): Log security-relevant events — authentication, privilege changes, data access, system events — with sufficient detail to reconstruct an incident
- **Log integrity**: Protect logs from modification
- **Log review**: Regular review of audit logs for anomalies

### AWS implementation

- **CloudTrail**: Enable in all regions. Enable data events for S3 buckets containing student records and for Lambda functions that process them. Enable log file validation. Encrypt with KMS CMK.
- **CloudTrail log storage**: Dedicated logging account per AWS Organizations best practice. Enable S3 Object Lock (Governance or Compliance mode) to prevent log deletion.
- **VPC Flow Logs**: Enable for all student-data VPCs.
- **CloudWatch Logs**: Centralize application logs, including the §99.32 disclosure log. Retention ≥7 years is a common state-contract floor; longer if matching student-record retention.
- **Athena / OpenSearch**: Query CloudTrail and application logs for investigations and periodic review.
- **§99.32 disclosure log — application-level** (this is the critical gap):
  - Every code path that returns education records to an external party emits a structured log event: `{timestamp, student_id, requestor, purpose, §99.31_exception, records_disclosed[]}`
  - Store in a dedicated, append-only CloudWatch Logs group or S3 bucket with Object Lock
  - Expose via a DSAR tool so a parent can see the record of disclosures about their child
- **GuardDuty** — detect anomalous access patterns (bulk data exfiltration, impossible-travel login, credential compromise).
- **Security Hub** — aggregate findings for periodic review.

### Critical detail

AWS CloudTrail logs API calls. It does NOT log application-level student-record access. If a teacher queries a database for a student's grades, CloudTrail logs the API call to RDS but not which student's record was viewed, who viewed it, or why. Your application must implement its own §99.32 disclosure log — this is not optional under FERPA, it is a statutory requirement.

### K-12 note
Districts often forget that the §99.32 record must survive re-procurements. If you switch LMS vendors, the disclosure log from the old vendor must be migrated, not deleted. DPAs should include a log-export clause.

### Higher-ed note
University registrars' offices typically maintain the canonical disclosure log; connected systems (LMS, library, food-service) feed into it.

### Vendor note
The disclosure log is audit evidence #1 in an SPPO complaint. Build it before you need it. Make it queryable by student ID so you can respond to "show me every time my child's record was disclosed" in minutes, not days.

---

## FCD 5 — Access Control & Least Privilege

### Requirements

- Need-to-know / least-privilege access to student records
- Role-based access control tied to job function (teacher sees their classes; counselor sees assigned caseload; registrar sees all; IT admin sees infrastructure but not content where possible)
- Account provisioning/de-provisioning tied to HR/SIS status
- Session timeout / inactivity lock
- Remote access only via encrypted channel
- No shared accounts — individual accountability

### AWS implementation

- **IAM Identity Center**: Centralized access management with permission sets scoped to student-data accounts. Federate from the district/institution's IdP (Azure AD, Okta, Google Workspace for Education).
- **Permission sets**:
  - `StudentData-ReadOnly` — analysts, QA
  - `StudentData-Operator` — scoped writes to specific services
  - `StudentData-Admin` — break-glass, MFA + ticket-required conditions
- **SCPs**: Restrict student-data accounts to approved AWS services and US regions. Deny `iam:PassRole` patterns that would enable privilege escalation.
- **S3 bucket policies**: Restrict each student-data bucket to a named list of IAM role ARNs. Deny anonymous or cross-account access unless explicitly allowed.
- **S3 Block Public Access**: Enable at the account level for all student-data accounts. Non-negotiable.
- **IAM Access Analyzer**: Continuous external-access monitoring.
- **Least privilege in application code**: The application's own authz model (teacher → their classes → their students) is the first line. AWS IAM protects the *infrastructure* around it but can't enforce "teacher X can only see their own students" unless data is partitioned that way.
- **Session timeout**: IAM Identity Center session duration ≤8 hours; console role session ≤1 hour for admin roles; application session timeout ≤30 minutes of inactivity.
- **Remote access**: Client VPN with MFA + cert-based auth. SSM Session Manager for instance shell access (logged, auditable, no open SSH).
- **No direct database access from engineers**: Access via least-privilege read-only replicas or bastion + SSM with full session logging.

### Key pitfall

"The app enforces row-level access" is only true if it actually does. PTAC guidance is clear that access controls must be tested. An attacker with any authenticated user's credentials should not be able to see records outside their authorized scope. Threat-model and pen-test accordingly.

---

## FCD 6 — Authentication (MFA, SSO, Password Hygiene)

### Requirements

FERPA does not specify authentication requirements — "reasonable methods." PTAC and NIST 800-171 establish the de facto baseline:

- **Multi-factor authentication** for all administrative access and for any access that touches bulk student records
- Strong password policy (length, complexity, rotation)
- Account lockout after failed attempts
- Unique IDs — no shared accounts
- Root/break-glass account hardening

### AWS implementation

- **IAM Identity Center**: MFA required for all users. Support FIDO2 hardware tokens (preferred) and TOTP as fallback.
- **IAM MFA enforcement**: For any remaining IAM users, policy condition `"Condition": {"BoolIfExists": {"aws:MultiFactorAuthPresent": "true"}}`.
- **Root account**: Hardware MFA enabled, access keys deleted, usage restricted via SCP, break-glass procedure documented.
- **IAM password policy**: Minimum 14 characters (state contracts commonly require 12–16), complexity enabled, 90-day max age, reuse prevention ≥10, lockout after 5 failed attempts.
- **Cognito for end-user (student/parent/teacher) authentication**: Enable advanced security features (compromised-credentials check, risk-based adaptive MFA). Integrate with district IdP via SAML federation where possible to avoid duplicate identity stores.
- **SAML federation**: For districts, federate vendor app logins from Google Workspace for Education or ClassLink / Clever rostering — student credentials never hit the vendor directly.
- **Access key rotation**: ≤90 days. Prefer IAM roles over long-lived keys.

### Key pitfall — student-facing MFA

MFA for admins is straightforward. MFA for students (especially K-12 students without personal email or phone) is harder. Common compromise: passkeys (WebAuthn) on school-issued devices, or SSO from the district's IdP which handles MFA upstream. Don't just skip MFA for student-facing auth — design around the constraint.

### Vendor note
When the district federates via SAML/OIDC, the vendor "authenticates" via the district's IdP. You still need MFA on your own admin backend. Don't confuse the two auth paths.

---

## FCD 7 — Encryption at Rest & In Transit

### Requirements

FERPA does not mandate encryption. PTAC guidance and every modern state EdTech DPA do.

- **At rest**: All student records encrypted. FIPS 140-2/3 validated modules preferred (required for StateRAMP Moderate, TX-RAMP Level 2, some other state frameworks).
- **In transit**: TLS 1.2+ for all traffic carrying student records, inside and outside the VPC.
- **Key management**: Customer-managed keys for auditability; automatic rotation enabled.

### AWS implementation

- **KMS**: AWS KMS HSMs are FIPS 140-2 Level 2 validated. Use CMKs (not AWS-managed keys) for student-data resources to enable cross-account access logging, key-policy-based access control, and rotation visibility.
- **EBS encryption**: Enable default EBS encryption at the account level.
- **RDS encryption**: Enable at instance creation (cannot retrofit — must migrate via snapshot). Use CMK.
- **S3 encryption**: SSE-KMS with CMK. Bucket policy to deny `s3:PutObject` without encryption headers. Enable Bucket Keys to reduce KMS cost.
- **DynamoDB encryption**: Enabled by default with AWS-owned keys. Switch to CMK for student-data tables.
- **OpenSearch encryption**: Enable at-rest encryption with CMK and node-to-node encryption.
- **Backup encryption**: AWS Backup with CMK; ensure snapshots and copies retain encryption.
- **FIPS endpoints**: For state frameworks requiring FIPS, set `AWS_USE_FIPS_ENDPOINT=true` or use `<service>-fips.<region>.amazonaws.com` endpoints. Most US regions support FIPS endpoints for KMS, S3, EC2, etc.
- **TLS enforcement**:
  - ALB/NLB: enforce TLS 1.2+ via security policy (`ELBSecurityPolicy-TLS13-1-2-2021-06` or newer).
  - API Gateway: same.
  - CloudFront: viewer protocol policy = redirect-to-https + min TLS 1.2.
  - S3: bucket policy with `"aws:SecureTransport": "false"` deny condition.
  - RDS/Aurora: parameter group `require_secure_transport=1` (MySQL) or `rds.force_ssl=1` (Postgres).
- **Certificate management**: ACM for public certs, ACM Private CA for internal. Automate renewal.
- **Macie**: Detect unencrypted or publicly-accessible student PII in S3.

### Key pitfall — retrofit encryption

RDS, Aurora, OpenSearch, and ElastiCache cannot be encrypted after creation. If you discover an unencrypted production student-data DB, you must migrate via snapshot-restore. Plan the cutover carefully — this is a multi-hour operation.

---

## FCD 8 — Data Minimization, Retention & Secure Destruction

### Requirements

- Collect only the student data needed for the institutional purpose (PTAC minimization principle; reinforced by SOPIPA, SOPPA, Ed Law 2-d, and most DPAs)
- Define retention periods aligned with educational record retention schedules (state records retention schedules, often 5–7 years post-graduation for education records, shorter for incidental data)
- Secure destruction when retention expires — NIST SP 800-88 Rev 1 standards
- Deletion on DPA termination — most state DPAs require vendor to destroy or return data within 30–60 days of contract end

### AWS implementation

- **S3 Lifecycle Policies**: Automate deletion or transition to Glacier Deep Archive. Configure per prefix matching the retention category.
- **S3 Object Lock**: Governance mode for retention-required records; Compliance mode where even root cannot delete before expiry.
- **RDS automated backups**: Configure retention period. Ensure deleted instances' final snapshots are also purged per schedule.
- **AWS Backup**: Define lifecycle rules on backup plans; test restore.
- **DynamoDB TTL**: Automated deletion of items past retention.
- **Crypto-shred**: For end-of-contract destruction, delete the KMS CMK that encrypts the student data (schedule key deletion, 7–30 day wait). This renders all encrypted records unrecoverable in all copies, including backups and DR sites. Document this as part of DPA offboarding.
- **AWS media sanitization**: AWS handles physical media destruction per NIST SP 800-88 — documented in SOC 2 and FedRAMP reports. Reference via AWS Artifact.
- **Tag-based retention**: Tag every student-data resource with a `retention-expiry` tag; Config rule to flag resources whose tag date has passed but resource still exists.

### Key pitfall — backups and replicas

Deleting the primary copy does not delete backups, read replicas, cross-region replicas, audit logs containing exported data, or cached exports in analytics systems. The retention schedule must enumerate all locations. Crypto-shred solves most of this by making all encrypted copies inert simultaneously.

### Vendor note — offboarding
When a district terminates a DPA, the vendor must destroy or return all district data within the contracted window. Practical pattern:
1. Export the district's data to a district-owned S3 bucket (return)
2. Delete district-specific tables/prefixes
3. Schedule deletion of the district's dedicated KMS key (crypto-shred any residual)
4. Produce a destruction attestation signed by the vendor's CISO

---

## FCD 9 — Incident Response & Breach Notification

### Requirements

- Documented incident response plan covering detection, containment, eradication, recovery
- **FERPA itself has no breach notification requirement**. State data-breach notification laws fill this gap — all 50 states + DC have them, all different.
- Most state EdTech contracts impose a contractual breach-notification timeline — commonly 24–72 hours for vendor-to-district, 30–60 days for district-to-parent
- Test the IR plan at least annually (tabletop or functional)

### AWS implementation

- **GuardDuty**: Enable in all student-data accounts for threat detection (unusual data access, credential compromise, exfil indicators).
- **Security Hub**: Aggregate findings from GuardDuty, Inspector, Macie, Config.
- **Detective**: Graph-based investigation for breach confirmation.
- **EventBridge + Lambda**: Automate containment — isolate compromised EC2, revoke suspicious IAM sessions, rotate compromised credentials.
- **SNS / PagerDuty / Opsgenie**: Alert IR team on critical findings.
- **Systems Manager Incident Manager**: Formalize runbooks for student-data incidents; include district-notification steps with contact info.
- **CloudTrail Lake**: Query historical events during investigation; retain 7+ years.
- **Breach-scope determination**: The IR runbook must include a "scope determination" step — enumerate affected students, export of disclosure logs for impacted records, preserve evidence. This is the input to any state-law breach-notification decision.

### State-law breach notification

See [`state-law-addenda.md`](state-law-addenda.md) for per-state specifics. The common dimensions to track in the IR plan:
- Trigger (what counts as "breach" — acquisition vs access vs reasonable belief)
- Timeline (CA: "most expedient time possible"; NY SHIELD: without unreasonable delay; TX: 60 days; etc.)
- Content (what the notice must say)
- Recipients (parents, AG, state ED dept, credit bureaus if >500)
- Documentation (what records to retain)

### Vendor note — district-notification clause
DPAs typically specify a very fast vendor→district notification window (often ≤24 hours of discovery). Miss this, and the district misses its own window to parents. Build the auto-notify path into the IR runbook.

---

## FCD 10 — Vendor / Subprocessor Management (Data Processing Agreements)

### Requirements

- Every party receiving education records must be bound by FERPA-equivalent terms
- If the vendor uses subprocessors (other AWS accounts, third-party SaaS, ML model providers), those subprocessors must be disclosed to the school and bound by equivalent or more restrictive terms
- Annual review of vendor and subprocessor security posture
- Right to audit / inspect

### AWS implementation

This FCD is primarily organizational/contractual — AWS does not directly satisfy it. Technical support:

- **AWS Artifact**: Pull AWS SOC 2 Type II, ISO 27001, FedRAMP High, StateRAMP, and TX-RAMP reports as inherited-control evidence to include in DPAs.
- **AWS as subprocessor**: AWS is a subprocessor to the vendor; the vendor is the school official. The vendor's DPA should list AWS in its subprocessor table with region and service scope.
- **Subprocessor enumeration**: Tag every AWS service in use + every third-party vendor with a "student-data-touching" flag. The list becomes the subprocessor table in the DPA.
- **PrivateLink / VPC endpoints**: Minimize the surface where third-party SaaS receives student data — keep traffic private where possible.
- **Access review**: Quarterly audit of: IAM roles, cross-account shares, RAM resources, Lake Formation grants. Every external-principal finding ties back to a named subprocessor.

### Key pitfall — ML/AI subprocessors

Embedding a third-party LLM API (including AWS Bedrock with certain non-default models) into a student-facing workflow makes that LLM provider a subprocessor. If the provider retains prompts for model training, that's an unauthorized redisclosure under §99.33(a). Use models with explicit no-retention terms and document the data flow.

### Vendor note
Maintain a living subprocessor register. When districts ask for it (they will), produce it within 5 business days. Missing subprocessors is an instant-credibility-killer in district security reviews.

---

## Summary — Which FCDs drive real audit/complaint/breach findings?

Based on publicly-disclosed EdTech data breaches and SPPO complaint resolutions over the past 5 years:

| Rank | FCD | Why it tops the list |
|---|---|---|
| 1 | FCD 4 — Auditing | Missing or incomplete §99.32 disclosure logs; inability to answer "who accessed this student's record" |
| 2 | FCD 7 — Encryption | Unencrypted S3 buckets exposed to the internet — breach vector #1 in state AG notifications |
| 3 | FCD 6 — Authentication | Credential compromise on unMFAed admin accounts |
| 4 | FCD 5 — Access Control | Over-privileged IAM roles; public RDS snapshots |
| 5 | FCD 3 — Disclosure Controls | Unauthorized subprocessor disclosure; ML training without district consent |
| 6 | FCD 10 — Vendor management | Undisclosed subprocessors surfaced during breach notification |

FCDs 1, 2, 8, 9 are important but show up less often in post-breach or post-complaint analyses — usually because problems there are caught contractually before becoming incidents.
