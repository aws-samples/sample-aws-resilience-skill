# CJIS Control Families — NIST SP 800-53 Alignment

> Based on CJIS Security Policy v6.0 (effective December 2024).
> Last verified against official source: 2026-05-21.
> Check https://le.fbi.gov/cjis-division/cjis-security-policy-resource-center for newer versions.

CJIS Security Policy v6.0 replaced the "13 Policy Areas" (PA 1-13) structure with NIST SP 800-53 control families. This document maps all 18 control families, their priority ratings, assessability, and key changes from v5.9.5.

---

## Control Family Overview

| Family | Name | Priority | Assessable | v5.9.5 Equivalent |
|---|---|---|---|---|
| **AC** | Access Control | P1 | Technical | PA 5 |
| **AU** | Audit and Accountability | P2 | Technical | PA 4 |
| **IA** | Identification and Authentication | P1 | Technical | PA 6 |
| **CM** | Configuration Management | P1 | Technical | PA 7 |
| **SC** | Systems and Communications Protection | P1 | Technical | PA 10 |
| **MP** | Media Protection | P1 | Technical (partial) | PA 8 |
| **IR** | Incident Response | P2 | Questionnaire (partial) | PA 3 |
| **AT** | Awareness and Training | P3 | Questionnaire | PA 2 |
| **PE** | Physical and Environmental Protection | P3 | Questionnaire | PA 9 |
| **PS** | Personnel Security | P2 | Questionnaire | PA 12 |
| **CP** | Contingency Planning | P2 | Technical | NEW |
| **RA** | Risk Assessment | P2 | Technical (partial) | NEW |
| **SA** | System and Services Acquisition | P3 | Questionnaire | NEW |
| **SR** | Supply Chain Risk Management | P3 | Questionnaire | NEW |
| **SI** | System and Information Integrity | P1 | Technical | NEW |
| **MA** | Maintenance | P3 | Questionnaire | NEW |
| **PL** | Planning | P3 | Questionnaire | NEW |
| **CA** | Assessment, Authorization, and Monitoring | P2 | Questionnaire (partial) | PA 11 |

Plus standalone sections:
- **Section 5.1** — Information Exchange Agreements (unchanged from v5.9.5 PA 1)
- **Section 5.20** — Mobile Devices (formerly PA 13, now a special section)

---

## Technically Assessable Families (Programmatic Checks)

These families can be verified via read-only AWS CLI commands:

### AC — Access Control (P1)
IAM policies, public exposure, session settings, MFA enforcement, information flow control, separation of duties, remote access controls. Controls AC-1 through AC-22.

### AU — Audit and Accountability (P2)
CloudTrail configuration, VPC Flow Logs, log retention, log encryption, log integrity, delivery monitoring. Controls AU-1 through AU-12.

### IA — Identification and Authentication (P1)
MFA enforcement, password policy, access key rotation, Identity Center configuration, FIPS 140-2/3 module usage. Controls IA-0 through IA-12.

### CM — Configuration Management (P1)
AWS Config, SSM, patch compliance, Inspector, baseline configs, Security Hub benchmarks, system component inventory. Controls CM-1 through CM-12.

### SC — Systems and Communications Protection (P1)
FIPS endpoints, VPC isolation, TLS enforcement, encryption at rest/transit, boundary protection, GuardDuty. Controls SC-1 through SC-39.

### SI — System and Information Integrity (P1)
Inspector vulnerability findings, GuardDuty Malware Protection, system monitoring, software integrity verification. Controls SI-1 through SI-16.

### CP — Contingency Planning (P2)
AWS Backup verification, backup encryption, cross-region replication, RDS Multi-AZ, recovery testing evidence. Controls CP-1 through CP-10.

### RA — Risk Assessment (P2, partial)
Inspector findings, Security Hub aggregated risk posture. Limited programmatic coverage — most RA controls are organizational.

---

## Questionnaire-Only Families

These families require organizational documentation and cannot be verified via AWS APIs:

### AT — Awareness and Training (P3)
Security awareness training program, training completion records, refresher schedule (within 6 months, every 2 years). Controls AT-1 through AT-4.

### PE — Physical and Environmental Protection (P3)
Facility security, visitor controls, environmental protections. Largely inherited from AWS (SOC 2, FedRAMP). Controls PE-1 through PE-17.

### PS — Personnel Security (P2)
Fingerprint-based background checks, personnel screening, termination procedures. Controls PS-1 through PS-9.

### PL — Planning (P3)
Security planning, rules of behavior, system security plan documentation. Controls PL-1 through PL-11.

### MA — Maintenance (P3)
System maintenance procedures, maintenance tools, remote maintenance controls. Controls MA-1 through MA-6.

### SA — System and Services Acquisition (P3)
System development lifecycle, acquisition process, developer security testing. Controls SA-1 through SA-22.

### SR — Supply Chain Risk Management (P3)
Supply chain controls, component authenticity, acquisition agreements. Controls SR-1 through SR-12.

### IR — Incident Response (P2, partial)
IR plan, detection/containment/recovery procedures, reporting to CSO/FBI. GuardDuty/Security Hub are technically checkable but the plan itself is organizational. Controls IR-1 through IR-8.

### CA — Assessment, Authorization, and Monitoring (P2, partial)
Triennial audit readiness, self-assessments, evidence collection. Security Hub and Audit Manager provide some technical evidence. Controls CA-1 through CA-9.

---

## Priority System

v6.0 uses a P1-P4 priority system:

| Priority | Meaning | Assessment Impact |
|---|---|---|
| **P1** | Highest — immediate compliance requirement | Non-compliance = AUDIT BLOCKER |
| **P2** | High — required, important for audit | Non-compliance = FINDING RISK |
| **P3** | Moderate — expected but lower audit weight | Non-compliance = GAP |
| **P4** | Lower — recommended/hardening | Non-compliance = INFO |

Controls marked with an asterisk (*) in the official document existed in v5.9.5 and carry forward.

---

## Key Differences from v5.9.5

| Change | Impact |
|---|---|
| PA structure eliminated | All controls now use NIST 800-53 identifiers (AC-2, SC-7, etc.) |
| 6 new control families added | CP, RA, SA, SR, SI, MA, PL — broadens scope significantly |
| Priority system formalized | P1-P4 replaces informal "audit heat" weighting |
| Contingency Planning (CP) now explicit | Backup and DR requirements are mandatory, not just implied |
| System Integrity (SI) standalone | Vulnerability management elevated from a CM sub-topic to its own family |
| Supply Chain (SR) added | New requirement for supply chain risk documentation |
| Log retention increased | AU-11 aligns with federal records (3+ years vs 1 year in v5.9.5) |
| Mobile Devices restructured | Moved from PA 13 to Section 5.20 standalone |
| Information Exchange Agreements retained | Section 5.1 unchanged in structure |

---

## Execution Order (by priority and audit impact)

For programmatic assessments, execute in this order:

1. **IA** (P1) — #1 audit finding area — MFA, password, identity
2. **SC** (P1) — boundary protection + encryption
3. **AC** (P1) — access control, least privilege
4. **AU** (P2) — auditing (must be working for everything else to be verifiable)
5. **CM** (P1) — configuration management, patching
6. **SI** (P1) — flaw remediation, monitoring
7. **CP** (P2) — contingency planning, backups

This order maximizes value when a scan is interrupted — the highest-risk findings surface first.
