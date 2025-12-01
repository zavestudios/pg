============================================================
docs/PGAUDIT.md
============================================================

# pgAudit Integration Plan

## Purpose

This document describes the role of pgAudit in the hardened multi-tenant PostgreSQL architecture used in this project. pgAudit provides detailed, structured audit logging of database activity. When combined with our database-per-tenant and role-based isolation model, pgAudit enables provable monitoring, security analytics, and compliance evidence for multi-tenant PostgreSQL deployments (including AWS RDS PostgreSQL and Aurora PostgreSQL).

This design does not require pgAudit for functional correctness, but pgAudit is strongly recommended for production deployments and is expected in environments governed by NIST 800-53, FedRAMP Moderate, and the DoD Cloud Computing SRG.

## Why pgAudit Is Needed

PostgreSQL’s built-in logging does NOT provide:

- Complete visibility into all SQL statements
- Tracking of security-relevant actions:
  - GRANT/REVOKE
  - CREATE SCHEMA / CREATE TABLE / CREATE EXTENSION
  - ALTER ROLE / CREATE USER / SET ROLE
  - Attempts to create tables in the public schema
  - Failed access attempts across tenant boundaries
- Structured logs suitable for SIEM ingestion

pgAudit adds all of this by logging:

- Fully normalized SQL statement text
- Database, schema, role, and session context
- Whether the statement succeeded or failed
- Actor identity (tenant role)
- Timestamp and correlation identifiers

This enables answering questions such as:

- Did any tenant attempt to access another tenant’s data?
- Are there privilege escalation attempts?
- Are there attempted extension/FDW creations?
- What queries is each tenant executing?

## Architectural Fit

pgAudit acts as the "visibility layer" on top of the following model:

- One RDS instance
- One database per tenant (db_tenant_*)
- One role per tenant (tenant_*_app)
- Dedicated schema per tenant (app)
- Locked-down public schema
- Restricted privileges and default privileges

pgAudit does not enforce isolation; it records and proves it.

## Deployment on AWS RDS / Aurora

Enable pgAudit via RDS parameter group:

1. Set:
   shared_preload_libraries = 'pgaudit'

2. Configure parameters:
   pgaudit.log = 'read, write, role, ddl'
   pgaudit.log_relation = on
   pgaudit.log_parameter = on

3. Apply parameter group and reboot RDS.

4. As admin:
   CREATE EXTENSION pgaudit;

5. Logs are emitted to:
   - CloudWatch Logs
   - Any SIEM (Splunk, Elastic, Sentinel, etc.)

## Example Log Outputs

### Tenant successfully queries its own data:
AUDIT: READ, SELECT, role=tenant_a_app, db=db_tenant_a, stmt="SELECT * FROM app.sample_data;"

### Tenant attempts cross-database access (blocked):
AUDIT: READ, ERROR, role=tenant_a_app, db=db_tenant_b, msg="permission denied for database"

### Tenant attempts CREATE EXTENSION (blocked):
AUDIT: DDL, ERROR, role=tenant_a_app, stmt="CREATE EXTENSION dblink;"

### Tenant attempts CREATE TABLE in public (blocked):
AUDIT: DDL, ERROR, role=tenant_a_app, stmt="CREATE TABLE public.hacked(id int);"

## Incident Response & Review

### All actions by a specific tenant
SELECT * FROM pgaudit_log_catalog
WHERE userid = 'tenant_a_app'
ORDER BY log_time DESC;

### Failed cross-tenant access attempts
SELECT *
FROM pgaudit_log_catalog
WHERE success = false
  AND statement LIKE '%db_tenant_%'
  AND statement NOT LIKE '%db_tenant_' || current_user;

### Privilege escalation attempts
SELECT *
FROM pgaudit_log_catalog
WHERE statement LIKE 'GRANT%'
   OR statement LIKE 'REVOKE%'
   OR statement LIKE 'ALTER ROLE%';

## Compliance Mapping

pgAudit directly supports:

AC-3 / AC-4 — Access Enforcement  
AC-6 — Least Privilege  
AU-2 / AU-3 / AU-6 / AU-12 — Comprehensive auditing  
CM-2 / CM-6 — Tracking configuration and role changes  
SC-7 — Boundary attempts (cross-tenant access)

## Summary

pgAudit completes the multi-tenant database hardening story by:

- Logging every action for every tenant
- Recording failed cross-tenant access attempts
- Capturing privilege escalation attempts
- Providing forensic audit evidence
- Supporting DoD/FedRAMP compliance
- Integrating cleanly with RDS + CloudWatch

pgAudit + our privilege model = enforcement + evidence.
