# Compliance Alignment (NIST 800-53 / DoD SRG Context)

## Scope

This document describes how the multi-tenant PostgreSQL design in this repository supports common security and compliance requirements, particularly those based on:

- NIST SP 800-53 Rev. 5 (as profiled by FedRAMP Moderate)
- DoD Cloud Computing SRG (which builds on FedRAMP/NIST controls)
- Typical internal platform security requirements for multi-tenant systems

This project focuses on **database-level multi-tenancy** and **data-plane isolation**. It does not, by itself, address all control requirements for an entire system (e.g., application-layer access control, identity management, network zoning, etc.).

## Assumptions

- Production deployment uses a managed database service such as AWS RDS PostgreSQL or Aurora PostgreSQL.
- Underlying IaaS/PaaS platform is already assessed against FedRAMP / DoD SRG controls.
- Application-level authentication and authorization are implemented separately and out of scope for this repository.
- Network access to the database is restricted via security groups, VPC, and IAM controls (Terraform to be added).

## Control Mapping (Selected NIST 800-53 Families)

### Access Control (AC)

**AC-3: Access Enforcement**

- Intent: Enforce approved authorizations for logical access to information and system resources.
- This design:
  - Uses **one database per tenant** (`db_tenant_a`, `db_tenant_b`, etc.).
  - Revokes `CONNECT` on tenant databases from `PUBLIC`.
  - Grants `CONNECT` only to the corresponding tenant role (e.g., `tenant_a_app` → `db_tenant_a`).
  - Uses dedicated schemas (`app`) with `USAGE` and `CREATE` confined to the tenant role.
- Evidence:
  - `init/01_init_tenants.sql` defines the database and role grants.
  - `scripts/test_isolation.sh` attempts cross-database connections and expects failures.

**AC-4: Information Flow Enforcement**

- Intent: Enforce approved authorizations for controlling the flow of information within the system and between interconnected systems.
- This design:
  - Prevents tenant roles from accessing other databases or schemas.
  - Does not enable cross-database extensions or foreign data wrappers for tenant roles.
  - Uses schemas as boundaries within each database (`app` only).
- Evidence:
  - No `CREATE EXTENSION` or FDW configuration for tenant roles in initialization script.
  - Planned negative tests can show attempts to create extensions as tenant roles fail.

**AC-6: Least Privilege**

- Intent: Employ the principle of least privilege, allowing only authorized accesses necessary to accomplish assigned tasks.
- This design:
  - Creates one application role per tenant, with only:
    - `CONNECT` to that tenant’s database.
    - `USAGE` and `CREATE` on that tenant’s `app` schema.
  - Provides no access to `public` schema for tenant data.
  - Does not grant any admin or superuser privileges to tenant roles.
- Evidence:
  - Role and grant definitions in `init/01_init_tenants.sql`.
  - Isolation tests confirm tenant roles cannot access other tenant databases.

### Identification and Authentication (IA)

**IA-2: Identification and Authentication (Organizational Users)**

- Intent: Ensure unique user/credential identities.
- This design:
  - Uses distinct database roles per tenant application (e.g., `tenant_a_app`).
  - In production, can be bound to IAM authentication (e.g., RDS IAM auth), which is addressed in the broader system design.
- Note:
  - End-user authentication and SSO are handled at the application layer and are out of scope for this repository.

### System and Communications Protection (SC)

**SC-7: Boundary Protection**

- Intent: Monitor and control communications at external boundaries and key internal boundaries.
- This design (when deployed on RDS):
  - Relies on VPC, security groups, and subnet design to restrict which applications can reach the RDS endpoint.
  - Uses database-level controls to enforce isolation between tenants on the same database server.
- Note:
  - Network zoning and firewall rules are managed outside this repo (e.g., Terraform for VPC and security groups).

**SC-28: Protection of Information at Rest**

- Intent: Protect the confidentiality and integrity of information at rest.
- This design (when deployed on RDS/Aurora):
  - Relies on RDS / KMS encryption for data at rest.
  - Uses one multi-tenant instance with per-tenant databases; snapshots and backups are protected via AWS IAM/KMS.
- Note:
  - Key management and encryption policies are addressed at the cloud provider / platform level.

### Audit and Accountability (AU)

**AU-2: Event Logging**

- Intent: Determine which events to log and implement logging.
- This design:
  - Can be combined with RDS logging (e.g., PostgreSQL logs to CloudWatch).
  - Optionally can use pgAudit for more granular DDL and access logging.
- Evidence:
  - Database-level controls ensure that logs can distinguish connections by role and database.

**AU-6: Audit Review, Analysis, and Reporting**

- Intent: Regularly review audit logs.
- This design:
  - Facilitates per-tenant analysis through database and role separation (events tagged by `current_database` and `current_user`).
  - Relies on a broader logging pipeline (e.g., CloudWatch, SIEM) to be implemented via platform tools.

### Configuration Management (CM)

**CM-2: Baseline Configuration**

- Intent: Develop, document, and maintain under configuration control a current baseline configuration.
- This design:
  - Uses a repeatable SQL initialization script for local testing.
  - Is intended to be migrated to Terraform and other IaC tools for production, ensuring consistent configuration of databases and roles.
- Evidence:
  - `init/01_init_tenants.sql` and planned Terraform modules provide a documented, version-controlled baseline.

**CM-6: Configuration Settings**

- Intent: Establish and enforce security configuration parameters.
- This design:
  - Centralizes database security settings (role grants, schema usage, connections) in code.
  - Future RDS parameter groups and Terraform resources will control PostgreSQL configuration (e.g., logging, SSL enforcement).

### Contingency Planning (CP)

**CP-9: System Backup**

- Intent: Conduct backups of user-level and system-level information.
- This design (when on RDS):
  - Leverages automated RDS backups and snapshots for the entire multi-tenant instance.
- Multi-tenant considerations:
  - Snapshots contain all tenant data; access must be tightly controlled.
  - Per-tenant logical backups can be added where contractual/legal requirements mandate tenant-specific data export.

## DoD Cloud Computing SRG Considerations

The DoD Cloud Computing SRG places emphasis on:

- **Data separation in multi-tenant environments**.
- **Strong isolation controls** for tenants operating at the same impact level.

This design supports those expectations by:

- Using per-tenant databases as clear logical boundaries.
- Enforcing access at the database and schema level.
- Providing an automated test suite to demonstrate that no tenant role can reach another tenant’s database.

Additional SRG requirements (e.g., cross-domain solutions, higher classification handling, IL4/IL5 overlays) are out of scope for this repository but can be addressed in the broader system architecture.

We integrate pgAudit in production to provide a complete SQL-level audit trail for each tenant. pgAudit records every security-relevant action—queries, DDL, privilege changes, failed attempts, and cross-tenant violations. Combined with our database-per-tenant and role-based isolation model, pgAudit provides provable evidence of access enforcement, least privilege, and attempted policy violations. This strengthens our multi-tenant RDS architecture and aligns with key NIST 800-53 controls (AC-3, AC-6, AU-2, AU-6) and DoD SRG requirements.

## Summary

This repository does not, by itself, complete an ATO or fully satisfy all controls of NIST 800-53, FedRAMP, or the DoD SRG. Instead, it provides:

- A concrete, testable model for **database-level tenant isolation**.
- Evidence (via tests and configuration) that supports key controls for access control, least privilege, configuration management, and data separation.
- A foundation to be integrated with:
  - Terraform/IaC for RDS provisioning.
  - Network and IAM configurations.
  - Centralized logging and auditing.

These artifacts are intended to be reused as part of a larger accreditation package for multi-tenant, cost-efficient database deployments in sensitive environments.

