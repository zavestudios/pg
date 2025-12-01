# Compliance Alignment for Multi-Tenant PostgreSQL
NIST 800-53 Rev 5 • FedRAMP Moderate • DoD SRG IL2 / IL4

## Purpose

This document explains how the hardened multi-tenant PostgreSQL architecture in this repository aligns with the security and compliance expectations of:

- NIST SP 800-53 Rev. 5  
- FedRAMP Moderate  
- DoD Cloud Computing Security Requirements Guide (SRG)  
- DoD Impact Levels IL2 and IL4  

The goal is to demonstrate that a **single PostgreSQL server hosting multiple isolated tenant databases** can meet the technical isolation, access control, and auditability requirements of these frameworks when configured correctly.

This document focuses specifically on **database-level isolation controls**.  
Network, IAM, and SIEM controls are provided by the underlying platform (e.g., AWS).

---

# 1. Relationship Between Frameworks

Federal and DoD compliance frameworks build on each other:

- **NIST 800-53**  
  The root control catalog. Everyone starts here.

- **FedRAMP Moderate**  
  A cloud-specific profile of NIST 800-53 for civilian agencies.

- **DoD Cloud Computing SRG**  
  Builds on FedRAMP Moderate + NIST and introduces DoD-specific requirements.

- **Impact Levels (IL2, IL4, IL5, IL6)**  
  Defined exclusively in the DoD SRG.  
  IL levels describe the sensitivity of data and add DoD-specific constraints.

Important distinction:

**FedRAMP does NOT define IL2 or IL4**,  
but IL4 systems must meet FedRAMP Moderate + DoD overlays.

This project is designed to meet the Postgres-level separation expectations for IL2 and IL4.

---

# 2. Mapping to NIST 800-53 Controls

Below is a summary of how this design supports key control families.

## AC – Access Control

### AC-3: Access Enforcement  
- Tenants receive exclusive `CONNECT` rights to their own database.  
- No tenant can connect to other databases.  
- `public` schema has all rights revoked.  
- Enforcement is validated through automated tests.  
Supports IL2 and IL4.

### AC-4: Information Flow Enforcement  
- Schema-level and database-level boundaries control data flow.  
- Cross-tenant data flow is technically impossible.  
- Tests attempt cross-boundary access and confirm failure.  
Strongly supports IL4 separation expectations.

### AC-6: Least Privilege  
- Roles have only minimal permissions:
  - `CONNECT` to one database  
  - `USAGE` and `CREATE` in their own `app` schema  
  - No extension creation  
  - No rights on `public`  
- Default privilege hardening ensures future objects remain isolated.  
Supports IL2 and IL4.

---

## IA – Identification & Authentication

### IA-2  
- Unique database roles per tenant.  
- Compatible with IAM auth in RDS.  
- Application authentication remains out of scope.  
Supports IL2 and IL4 when combined with platform IAM.

---

## SC – System & Communications Protection

### SC-7: Boundary Protection  
- Database boundary enforced by privileges and role separation.  
- Negative tests confirm denied access attempts.  
- With pgAudit enabled (see docs/PGAUDIT.md), violations are logged and reviewable.  
Supports IL2; meets IL4 requirements for monitored boundaries.

### SC-28: Protection of Information at Rest  
- RDS provides KMS-based encryption.  
- DB privilege model protects object access.  
- IL4 requires controlled snapshot access (covered by platform IAM).  
Supports IL2 and IL4.

---

## AU – Audit & Accountability

### AU-2 / AU-6 / AU-12  
- pgAudit provides structured SQL audit trails:  
  - DDL, DML, role changes  
  - Failed access attempts  
  - Boundary violations  
- Logs can flow into CloudWatch or SIEM systems.  
Required for IL4; recommended for IL2.

---

## CM – Configuration Management

### CM-2 / CM-6  
- Configuration is fully documented and will be IaC-driven via Terraform.  
- SQL initialization is deterministic and testable.  
- Tests act as configuration verification artifacts.  
Supports IL2 and IL4.

---

# 3. DoD Impact Level Alignment

## IL2 Alignment Summary

IL2 (public / non-CUI data) requires:
- Basic access control  
- Basic auditing  
- Clear separation of customer workloads  

This project fully satisfies IL2 through:
- Database-per-tenant separation  
- Role-based access control  
- Locked-down `public` schema  
- Controlled `search_path`  
- Default privilege hardening  

No additional controls are needed for IL2.

---

## IL4 Alignment Summary

IL4 (Controlled Unclassified Information) demands:
- Demonstrated enforcement of tenant boundaries  
- Evidence that cross-tenant access cannot occur  
- Monitoring and auditing of boundary violations  
- Stronger configuration control and documentation  

This project supports IL4 through:

### 1. Technical Enforcement  
- Strict role/database mapping  
- Revoked `CONNECT` on all non-tenant databases  
- No CREATE privileges on the database or public schema  
- Prevented extension creation (dblink/FDW)  
- Hardened search_path (`app, pg_catalog`)  
- Default privilege hardening  

### 2. Testable Evidence  
The negative test suite provides concrete IL4 evidence:

- Cross-database access attempts fail  
- Attempts to create tables in `public` fail  
- Attempts to create extensions fail  
- Attempts to bypass search_path fail  
- Attempts to grant privileges to other tenants fail  

These test outputs can be archived as IL4 proof.

### 3. Auditability  
pgAudit captures:
- Cross-tenant access attempts  
- Privilege escalation attempts  
- DDL operations  
- Role modifications  
- Schema misuse attempts  

Cleanly supports IL4 AU-family requirements.

### 4. Documentation  
This repository contains:
- Architecture overview  
- Threat model  
- Security controls  
- pgAudit plan  
- Cost model  
- Compliance mapping  

This documentation aligns with IL4 expectations for technical documentation and ATO submissions.

---

# 4. Summary

**IL2:**  
Fully supported by the tenant isolation model with no additional controls required.

**IL4:**  
Supported through:
- Strong privilege model  
- Documented configuration  
- Negative isolation tests  
- pgAudit logging  
- Terraform-driven future deployment  

---

# IL2 vs IL4 Requirements Comparison

| Requirement Area | IL2 Expectation | IL4 Expectation | How This Project Satisfies It |
|-----------------|----------------|----------------|--------------------------------|
| Tenant Isolation | Logical separation acceptable | Strict data-plane isolation required | DB-per-tenant, schema-per-tenant, role-per-tenant isolation; negative tests |
| Access Control | Basic role separation | Least privilege + prevented escalation | Hardened privileges, revoked CONNECT, locked-down public |
| Audit Logging | Basic database logs | Full audit visibility, including denied events | pgAudit logs all SQL, including failures |
| Boundary Control | Network + basic DB auth | Demonstrated boundary enforcement | Negative tests proving cross-DB access fails |
| Configuration Management | Documented configuration | Deterministic, IaC-driven traces | SQL hardening + planned Terraform migration |
| Snapshot / Backup Controls | Basic access controls | Controlled access to multi-tenant snapshots | IAM + KMS (platform), documented in COST_MODEL |
| Evidence Requirements | Minimal | Explicit evidence of enforcement | Test output, pgAudit logs, compliance docs |


This project provides a secure, cost-optimized blueprint for multi-tenant PostgreSQL suitable for IL2 and IL4 workloads in DoD environments.

