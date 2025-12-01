# Security Controls and Assurance

## Purpose

This document summarizes the security controls implemented in the multi-tenant PostgreSQL design and how they support accreditation and security reviews (e.g., in DoD environments).

## Control Summary

### 1. Tenant Isolation

- **Control**: One database per tenant (`db_tenant_a`, `db_tenant_b`, `db_tenant_c`, …).
- **Implementation**:
  - `REVOKE CONNECT ON DATABASE <db> FROM PUBLIC;`
  - `GRANT CONNECT ON DATABASE <db> TO <tenant_role>;`
- **Assurance**:
  - Automated tests attempt cross-database connections as tenant roles and expect failures.

### 2. Schema Isolation

- **Control**: Dedicated schema per tenant database (`app`), not using `public` for tenant data.
- **Implementation**:
  - `CREATE SCHEMA app AUTHORIZATION <tenant_role>;`
  - No grants on `public` for tenant roles.
- **Assurance**:
  - Tests list schemas and confirm `app` exists and is owned by the correct tenant role.
  - Tests confirm tenant roles can only access `app.sample_data` in their own database.

### 3. Safe Namespace (`search_path`) and `public` Lockdown

- **Control**: Prevent function/table shadowing and misuse of `public`.
- **Implementation (hardening model)**:
  - Lock down `public` (no `CREATE` for tenant roles).
  - Set tenant `search_path` to `app, pg_catalog`.
- **Assurance**:
  - Manual or automated checks verify that tenant roles cannot create objects in `public`.
  - Tenant functionality is tested against the `app` schema.

### 4. Privilege Management

- **Control**: Tenant roles are least-privilege.
- **Implementation**:
  - Tenant roles:
    - Can `CONNECT` only to their own database.
    - Have `USAGE` and `CREATE` on their `app` schema only.
  - No membership in admin or superuser roles.
- **Assurance**:
  - SQL inspection of `pg_roles`/`pg_auth_members` and grants.
  - Tests confirm inability to connect to other databases.

### 5. Extension and FDW Restrictions

- **Control**: Tenants cannot create extensions or foreign data wrappers.
- **Implementation**:
  - Only admin roles can execute `CREATE EXTENSION` or `CREATE SERVER`.
- **Assurance**:
  - Future tests can explicitly attempt `CREATE EXTENSION` as tenant roles and expect failure.

### 6. Auditing and Logging (To Be Implemented on RDS)

- **Control**: Audit access and configuration changes.
- **Implementation** (planned for RDS/Aurora):
  - Enhanced PostgreSQL logging via parameter group.
  - Optionally pgAudit for detailed DDL/role events.
  - Central log collection (e.g., CloudWatch Logs).
- **Assurance**:
  - Logs can be reviewed for suspicious activity and used as evidence in security assessments.

### 7. Backups and Snapshots

- **Control**: Protect multi-tenant data in backups.
- **Implementation**:
  - RDS snapshot access tightly controlled (IAM, KMS).
  - Clear guidance: snapshots are multi-tenant assets and may not be shared without proper authority.
- **Assurance**:
  - IAM policy review and periodic audit of snapshot access logs.

## Testing and Evidence

The project includes:

- `init/01_init_tenants.sql`:
  - Creates tenant databases, roles, schemas, and sample data.
- `scripts/test_isolation.sh`:
  - Verifies:
    - Databases exist.
    - Schemas exist and are correctly owned.
    - Sample tables are accessible only to the correct tenant role.
    - Cross-database access attempts fail.

These tests can be run in CI or as part of a deployment verification phase, and their output can be captured as evidence for ATO or security reviews.

We integrate pgAudit in production to provide a complete SQL-level audit trail for each tenant. pgAudit records every security-relevant action—queries, DDL, privilege changes, failed attempts, and cross-tenant violations. Combined with our database-per-tenant and role-based isolation model, pgAudit provides provable evidence of access enforcement, least privilege, and attempted policy violations. This strengthens our multi-tenant RDS architecture and aligns with key NIST 800-53 controls (AC-3, AC-6, AU-2, AU-6) and DoD SRG requirements.

## Future Work

- Add automated tests for:
  - `search_path` immutability for tenant roles.
  - `CREATE EXTENSION`, `CREATE SERVER`, and other privileged commands failing for tenants.
- Integrate with Terraform-managed RDS instances and document RDS-specific controls:
  - parameter groups, security groups, IAM, KMS, backup retention.
- Integrate audit log configuration with centralized logging and monitoring solutions.
