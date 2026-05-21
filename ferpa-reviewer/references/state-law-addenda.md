# State Student-Privacy Law Addenda

> Last verified against official sources: 2026-05-21.
> State laws change frequently — always verify against the current statute when signing a contract.

FERPA is the federal floor. Every state layers on additional requirements via state student-privacy laws, state breach-notification laws, and standard DPA templates adopted by school districts. This file covers the four most common states in EdTech sales cycles (CA, NY, TX, IL), plus a short reference to other states that appear often, plus a note on COPPA (federal but frequently co-invoked with FERPA for K-12 under-13).

---

## California — SOPIPA (Student Online Personal Information Protection Act)

**Statute**: California Business & Professions Code §22584–22585 (enacted SB 1177, 2014; effective Jan 1 2016)
**Scope**: "Operators" of Internet websites, online services, or applications used primarily for K-12 school purposes and marketed to K-12 schools
**Enforcement**: California Attorney General

### Requirements beyond federal FERPA

1. **No targeted advertising** based on any info acquired through the K-12 operator's service, including by amalgamating profiles (§22584(b)(1))
2. **No advertising based on covered info** even on *other* sites/apps (§22584(b)(1)(B))
3. **No profile-building** about a K-12 student except in furtherance of K-12 school purposes (§22584(b)(2))
4. **No selling of student information** (§22584(b)(3))
5. **No disclosure of covered information** except to provide the service, for legitimate research, to another provider under equivalent terms, by consent, or as required by law (§22584(c))
6. **Reasonable security procedures and practices** appropriate to the nature of the covered information (§22584(b)(4))
7. **Delete covered information upon district request** (§22584(b)(5))

### FCD mapping
- SOPIPA §22584(b)(4) "reasonable security" → FCD 5, 6, 7 (baseline technical safeguards)
- SOPIPA §22584(b)(5) deletion-on-request → FCD 8 (retention & destruction)
- SOPIPA §22584(b)(1)–(3) no-advertising / no-profiling / no-sale → FCD 3 (disclosure controls), FCD 10 (subprocessor management)
- SOPIPA §22584(c) disclosure limits → FCD 3

### Common contract clauses
- Explicit acknowledgment operator is subject to SOPIPA
- Deletion of covered information within 30 days of district request
- No use of covered information for product improvement without de-identification (de-identification standard stricter than HIPAA Safe Harbor)

### Also in California
- **SB 1460 (student personal information, higher-ed)** — extends similar protections to higher-ed
- **AB 1584 (contract requirements for K-12)** — districts must include specific clauses in operator contracts
- **CCPA / CPRA student exemption** — CCPA generally does not apply to personal info collected by operators subject to SOPIPA, but the interaction is nuanced; consult counsel.

---

## New York — Education Law §2-d + NYSED Parts 121

**Statute**: New York Education Law §2-d (enacted 2014, amended substantially 2020); implementing regulation 8 NYCRR Part 121 (effective 2020)
**Scope**: Any third-party contractor receiving PII from an educational agency (K-12 district, BOCES, charter school, SED-approved preschool, or NYSED)
**Enforcement**: Chief Privacy Officer of NYSED, Attorney General

### Requirements beyond federal FERPA

1. **Parents' Bill of Rights for Data Privacy and Security** — the educational agency must publish; contracts must include it (§2-d(3))
2. **Data Security and Privacy Plan** — every contract must include a plan covering the third-party contractor's compliance with NIST CSF and with the Parents' Bill of Rights (Part 121.9)
3. **NIST Cybersecurity Framework alignment** — NYSED requires alignment (Part 121.5)
4. **Data elements list** — contract must identify data elements to be shared with the contractor (Part 121.6(d))
5. **Use limitation** — contractor may use PII only for exclusive purposes for which it was shared (§2-d(3)(c))
6. **Subcontractor flow-down** — all subcontractors must agree to equivalent or more stringent terms (Part 121.6(e))
7. **Challenge-and-correction procedure** (Part 121.6(f))
8. **Annual data privacy and security awareness training** for contractor employees with PII access (Part 121.6(b))
9. **Breach notification** — contractor must notify the educational agency "in the most expedient way possible and without unreasonable delay" of an unauthorized release (§2-d(5)); agency must notify NYSED within 10 days; agency must notify parents
10. **NYSED reporting** — unauthorized release must be reported to the SED Chief Privacy Officer

### FCD mapping
- §2-d(3)(c) use limitation → FCD 3
- Part 121.5 NIST CSF alignment → FCD 4, 5, 6, 7 (broad technical controls)
- Part 121.6(b) training → FCD 10 (organizational)
- §2-d(5) breach notification → FCD 9
- Part 121.6(e) subcontractor flow-down → FCD 10

### Common contract clauses
- Attached Parents' Bill of Rights
- Data Security and Privacy Plan (DSPP) as a contract exhibit
- NIST CSF category-by-category mapping
- NYSED Chief Privacy Officer notification path in the IR plan

### Key pitfall
Ed Law 2-d has real teeth — NYSED has investigated and publicly reported multiple vendor breaches. The breach-notification SLA ("most expedient way possible") is more aggressive than most other state laws.

---

## Texas — SB 820 + TX-RAMP for EdTech

**Statutes**: Texas Business & Commerce Code §§521.001 et seq. (breach notification); Texas Education Code §32.151 (SB 820, 2019, cybersecurity framework for school districts); TX-RAMP administered by the Texas Department of Information Resources
**Scope**: School districts must adopt a cybersecurity framework; vendors serving K-12 must meet the district's framework requirements; TX-RAMP certification is required for cloud services handling certain state data categories

### Requirements beyond federal FERPA

1. **Cybersecurity coordinator** — each district must designate one (Tex. Ed. Code §11.175)
2. **Cybersecurity framework adoption** — SB 820 requires districts to adopt a cybersecurity framework (commonly NIST CSF)
3. **TX-RAMP certification** — for cloud services processing certain types of state data. Two levels:
   - **TX-RAMP Level 1** — low-impact (roughly FedRAMP Tailored)
   - **TX-RAMP Level 2** — moderate-impact (roughly FedRAMP Moderate); commonly required for student-record data
4. **FIPS 140-2/3 validated crypto** — TX-RAMP L2 requires this
5. **Breach notification** (§521.053) — notify affected individuals "as quickly as possible" after determining breach; notify AG if >250 Texans affected; 60-day maximum timeline
6. **Encryption safe harbor** — §521.053 provides breach-notification safe harbor for encrypted data if the encryption key was not also compromised
7. **Data security assessment** — annual for districts subject to SB 820

### FCD mapping
- TX-RAMP L2 encryption + FIPS → FCD 7
- TX-RAMP L2 access control → FCD 5, 6
- TX-RAMP L2 auditing → FCD 4
- §521.053 breach notification → FCD 9
- SB 820 framework alignment → cross-cutting

### Common contract clauses
- TX-RAMP Level 1 or Level 2 certification evidence
- Annual cybersecurity posture attestation
- AG notification path for breaches >250 Texans

### Key pitfall
TX-RAMP certification is a months-long process. Vendors targeting Texas K-12 should start TX-RAMP Level 2 engagement well before first contract. AWS has StateRAMP / TX-RAMP-aligned offerings available via Artifact.

---

## Illinois — SOPPA (Student Online Personal Protection Act)

**Statute**: 105 ILCS 85 (enacted 2017, amended 2019 — the 2019 amendment is the substantive one)
**Scope**: Operators of websites, services, or apps used primarily for K-12 school purposes; also any K-12 "school" acting as operator
**Enforcement**: Attorney General; also private right of action implied in some interpretations

### Requirements beyond federal FERPA

1. **Reasonable security** (105 ILCS 85/25) — similar to SOPIPA
2. **Data breach notification specific to SOPPA** (105 ILCS 85/30) — operator must notify the school within 30 days of determining breach; school must notify parents within 30 days of the school's knowledge
3. **Written agreement required** before covered information is shared (105 ILCS 85/27) — ISBE produced a standard DPA template
4. **Published list of operators** — ISBE maintains and publishes a list of approved operators and their DPAs
5. **Website transparency** — operators must publish a list of school districts they contract with (105 ILCS 85/33)
6. **No targeted advertising / profile-building / sale** — parallel to SOPIPA
7. **Deletion on district request**
8. **Annual training** for school staff with access to covered information

### FCD mapping
- 105 ILCS 85/25 reasonable security → FCD 5, 6, 7
- 105 ILCS 85/30 breach notification → FCD 9
- 105 ILCS 85/27 written agreement → FCD 10
- Deletion → FCD 8

### Illinois Student Data Privacy DPA template
Illinois districts overwhelmingly use the ISBE standard DPA template (largely derived from the national Student Data Privacy Consortium template). Vendors should plan to sign variations of this template, not custom DPAs.

### Key pitfall
The 30-day vendor→school breach-notification SLA is aggressive and codified in statute, not just contract. Plan IR SLAs accordingly.

---

## Quick reference — other states

| State | Law(s) | Key incremental requirement |
|---|---|---|
| **Colorado** | HB 16-1423; Student Data Transparency and Security Act | Public posting of vendor contracts; annual education-department compliance review |
| **Connecticut** | Public Act 16-189 | Contract clauses mirroring SOPIPA; data-inventory publication |
| **Virginia** | Code §22.1-289.01 | School board must adopt policies; vendor contracts must address use limitations |
| **Washington** | RCW 28A.604.010 | State ED department maintains list of compliant operators |
| **Utah** | Student Data Protection Act (53E-9-3) | Parental consent for certain data collection; expedited breach notification |
| **Florida** | §1002.22 F.S. | Florida Education Privacy Act — parallel to FERPA; some additional disclosure restrictions |
| **Massachusetts** | 201 CMR 17.00 | State "WISP" (Written Information Security Program) requirements apply to student PII |
| **Ohio** | ORC §3319.321 | State-level student-data-privacy requirements; recent 2024 amendments |

This list is not exhaustive. For any state not listed, check for:
1. The state's variant on a student-data-privacy law (SOPIPA-like statutes in ~20 states)
2. The state data-breach notification statute (all 50 states have one)
3. Any state-DOE-approved vendor list or standard DPA template

---

## COPPA note (federal, often co-invoked with FERPA)

**Statute**: Children's Online Privacy Protection Act, 15 U.S.C. §§6501–6506; FTC regulations at 16 CFR Part 312
**Scope**: Operators of commercial online services that collect personal information from children under 13
**Enforcement**: Federal Trade Commission (different regulator than FERPA's SPPO)

### Relationship to FERPA

- **FERPA** covers education records; **COPPA** covers under-13 online data collection.
- **Both apply** when a K-12 EdTech vendor handles records of under-13 students.
- **The FTC accepts "school consent in lieu of parental consent"** for services used solely for educational purposes at the school's direction (FTC 2014 COPPA guidance). This parallels the §99.31(a)(1)(i)(B) school-official exception but with different requirements.
- **School-consent safe harbor** requires the vendor to use the data only for educational purposes and to provide appropriate transparency to the school.

### This skill is FERPA-only

COPPA is flagged in Phase 1 (Bootstrap) for user awareness but is not assessed by this skill. COPPA warrants its own assessment:
- Specific FTC-required disclosures
- Parental-consent mechanisms (verifiable parental consent, VPC)
- Special rules for persistent identifiers, geolocation, photos, audio
- FTC enforcement posture (sizeable fines, consent decrees)

If the user confirms under-13 users are in scope, recommend a separate COPPA review by counsel and/or a dedicated COPPA assessment skill (future work).

---

## How this skill uses state addenda

During Phase 1, the user declares which states are in scope. During Phase 3 (Analyze), the skill:

1. Checks whether the technical findings match each applicable state's requirements.
2. Surfaces state-specific **incremental** items (e.g., "TX-RAMP L2 requires FIPS endpoints — this environment does not use FIPS endpoints" — even if this is not a federal FERPA finding, it blocks Texas K-12 contracts).
3. Emits a state-law rollup section in the final report with per-state findings.

The technical scan itself doesn't change per state; the interpretation of findings does. A HARDENING GAP under federal FERPA may be a BREACH RISK under NY Ed Law 2-d if the Parents' Bill of Rights is tied to the same control.
