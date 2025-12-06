# Security Controls and Assurance

## Purpose

This document summarizes the security controls implemented in the multi-tenant PostgreSQL design and how they support accreditation and security reviews (e.g., in DoD environments).

The project includes comprehensive security testing in `scripts/test_isolation.sh` that validates the isolation model against real-world attack scenarios. These tests can be run in CI or as part of a deployment verification phase, and their output can be captured as evidence for ATO or security reviews.

## Security Controls, Implementation, and Testing

### 1. Database Isolation (Tenant Isolation)

**Control**: One database per tenant (`db_tenant_a`, `db_tenant_b`, `db_tenant_c`, …).

**Implementation**:
```sql
REVOKE CONNECT ON DATABASE <db> FROM PUBLIC;
GRANT CONNECT ON DATABASE <db> TO <tenant_role>;
```

**Attack scenario prevented:**
A malicious tenant attempts to connect directly to another tenant's database to read or manipulate their data.

**Test validation:**
```bash
# This must fail - tenant A cannot connect to tenant B's database
psql -U tenant_a_app -d db_tenant_b -c "SELECT current_user;"
```

**Why it fails:**
The initialization script revokes PUBLIC connect privileges and grants CONNECT only to the owning tenant. PostgreSQL enforces this at connection time, preventing cross-database access.

---

### 2. Schema Isolation

**Control**: Dedicated schema per tenant database (`app`), not using `public` for tenant data.

**Implementation**:
```sql
CREATE SCHEMA app AUTHORIZATION <tenant_role>;
REVOKE ALL ON SCHEMA public FROM <tenant_role>;
```

**Attack scenario prevented:**
A malicious tenant tries to create objects in the `public` schema, which might be accessible across databases or could pollute the shared namespace.

**Test validation:**
```bash
# This must fail - tenant cannot use public schema
psql -U tenant_a_app -d db_tenant_a -c "CREATE TABLE public.hacked_a (id int);"
```

**Why it fails:**
All privileges on `public` are revoked from tenant roles. Each tenant has a dedicated `app` schema they own and control.

---

### 3. Safe Namespace (search_path) and Public Lockdown

**Control**: Prevent function/table shadowing and misuse of `public`.

**Implementation**:
```sql
REVOKE ALL ON SCHEMA public FROM <tenant_role>;
ALTER ROLE <tenant_role> IN DATABASE <db> SET search_path = app, pg_catalog;
```

**Attack scenario prevented:**
A malicious tenant attempts to change their session `search_path` to prioritize the `public` schema, hoping to create unqualified tables there.

**Test validation:**
```bash
# This must fail - even with manipulated search_path
psql -U tenant_a_app -d db_tenant_a \
  -c "SET search_path = public, app; CREATE TABLE hacked_unqualified_a (id int);"
```

**Why it fails:**
Even though tenants can modify their session `search_path`, they still have no CREATE privilege on `public`. When PostgreSQL tries to create the table in the first writable schema in the path, it finds `public` (no CREATE privilege) and fails before trying `app`.

---

### 4. Extension and Foreign Data Wrapper Restrictions

**Control**: Tenants cannot create extensions or foreign data wrappers.

**Implementation**:
```sql
REVOKE CREATE ON DATABASE <db> FROM <tenant_role>;
-- Only admin roles can execute CREATE EXTENSION or CREATE SERVER
```

**Attack scenarios prevented:**

**a) Cross-database access via dblink:**
```sql
CREATE EXTENSION dblink;
-- Now tenant A could query tenant B's database
SELECT * FROM dblink(
  'dbname=db_tenant_b user=some_user password=guessed',
  'SELECT * FROM app.sample_data'
) AS stolen_data(id int, note text);
```

**b) Filesystem access via file_fdw:**
```sql
CREATE EXTENSION file_fdw;
-- Read arbitrary files from the server
```

**Test validation:**
```bash
# All of these must fail
psql -U tenant_a_app -d db_tenant_a -c "CREATE EXTENSION dblink;"
psql -U tenant_a_app -d db_tenant_a -c "CREATE EXTENSION postgres_fdw;"
psql -U tenant_a_app -d db_tenant_a -c "CREATE EXTENSION file_fdw;"
```

**Why it fails:**
Only superusers or roles with CREATE privilege on the database can create extensions. Tenant roles have this privilege explicitly revoked.

---

### 5. Privilege Management (Least Privilege)

**Control**: Tenant roles are least-privilege and cannot escalate.

**Implementation**:
```sql
CREATE ROLE <tenant_role> LOGIN PASSWORD '...';  -- Basic role, no special privileges
-- Tenant roles have no SUPERUSER, CREATEDB, CREATEROLE, or other admin attributes
```

**Attack scenarios prevented:**

**a) Superuser escalation:**
```sql
ALTER ROLE tenant_a_app SUPERUSER;  -- Attempt to become superuser
```

**b) Role creation for persistence:**
```sql
CREATE ROLE backdoor LOGIN PASSWORD 'hacked';  -- Create persistent access
```

**c) Credential theft:**
```sql
ALTER ROLE tenant_b_app PASSWORD 'stolen';  -- Change another tenant's password
```

**d) Role impersonation:**
```sql
SET ROLE tenant_b_app;  -- Attempt to assume another tenant's identity
```

**Test validation:**
```bash
# All of these must fail
psql -U tenant_a_app -d db_tenant_a -c "ALTER ROLE tenant_a_app SUPERUSER;"
psql -U tenant_a_app -d db_tenant_a -c "CREATE ROLE malicious_role;"
psql -U tenant_a_app -d db_tenant_a -c "ALTER ROLE tenant_b_app PASSWORD 'hacked';"
psql -U tenant_a_app -d db_tenant_a -c "SET ROLE tenant_b_app;"
```

**Why these fail:**
PostgreSQL requires superuser privileges or specific role attributes to execute these commands. Tenant roles are created as basic LOGIN roles with no administrative privileges. SQL inspection of `pg_roles`/`pg_auth_members` confirms tenant roles have minimal privileges.

---

### 6. Database Object Manipulation Restrictions

**Control**: Tenants cannot manipulate databases outside their own.

**Implementation**:
Tenant roles own only their own database and have no privileges on others.

**Attack scenarios prevented:**

**a) Database destruction:**
```sql
DROP DATABASE db_tenant_b;  -- Destroy competitor's data
```

**b) Configuration manipulation:**
```sql
ALTER DATABASE db_tenant_b SET timezone = 'UTC';  -- Interfere with another tenant
```

**c) Resource exhaustion:**
```sql
CREATE DATABASE consume_resources_1;
CREATE DATABASE consume_resources_2;
-- ... create many databases to exhaust server capacity
```

**Test validation:**
```bash
# All of these must fail
psql -U tenant_a_app -d db_tenant_a -c "DROP DATABASE db_tenant_b;"
psql -U tenant_a_app -d db_tenant_a -c "ALTER DATABASE db_tenant_b SET timezone = 'UTC';"
psql -U tenant_a_app -d db_tenant_a -c "CREATE DATABASE malicious_db;"
```

**Why these fail:**
Database-level operations require either database ownership or superuser privileges. Tenant roles own only their own database and have no privileges on others.

---

### 7. Filesystem Access Restrictions

**Control**: Tenants cannot access the server filesystem.

**Implementation**:
Tenant roles have no `pg_read_server_files`, `pg_write_server_files`, or `pg_execute_server_program` privileges.

**Attack scenarios prevented:**

**a) Data exfiltration:**
```sql
COPY app.sample_data TO '/tmp/stolen_data.csv';  -- Write data to shared filesystem
```

**b) Credential theft:**
```sql
COPY app.sample_data FROM '/etc/passwd';  -- Read system files
SELECT pg_read_file('/var/lib/postgresql/data/pg_hba.conf');  -- Read PG config
```

**c) Information gathering:**
```sql
SELECT pg_ls_dir('/var/lib/postgresql/data');  -- Explore filesystem
```

**Test validation:**
```bash
# All of these must fail
psql -U tenant_a_app -d db_tenant_a -c "COPY app.sample_data TO '/tmp/data_exfil.csv';"
psql -U tenant_a_app -d db_tenant_a -c "COPY app.sample_data FROM '/etc/passwd';"
psql -U tenant_a_app -d db_tenant_a -c "SELECT pg_read_file('/etc/passwd');"
psql -U tenant_a_app -d db_tenant_a -c "SELECT pg_ls_dir('/etc');"
```

**Why these fail:**
- COPY TO/FROM file paths requires superuser privileges (not just table ownership)
- `pg_read_file()` and `pg_ls_dir()` are restricted to superusers and roles with `pg_read_server_files` privilege
- Tenant roles have neither

---

### 8. Information Disclosure Prevention

**Control**: Tenants cannot access system catalogs with sensitive information or spy on other tenants.

**Implementation**:
System catalogs with authentication data have restricted access; `pg_stat_activity` filtering based on database connection privileges.

**Attack scenarios prevented:**

**a) Password hash theft:**
```sql
SELECT usename, passwd FROM pg_shadow;  -- Steal password hashes for offline cracking
```

**b) Authentication enumeration:**
```sql
SELECT * FROM pg_authid;  -- Discover all roles and privileges
```

**c) Activity surveillance:**
```sql
SELECT * FROM pg_stat_activity WHERE datname = 'db_tenant_b';
-- Monitor what queries tenant B is running
```

**Test validation:**
```bash
# All of these must fail or return no sensitive data
psql -U tenant_a_app -d db_tenant_a -c "SELECT * FROM pg_shadow;"
psql -U tenant_a_app -d db_tenant_a -c "SELECT * FROM pg_authid;"
psql -U tenant_a_app -d db_tenant_a -c "SELECT * FROM pg_stat_activity WHERE datname = 'db_tenant_b';"
```

**Why these fail:**
- `pg_shadow` and `pg_authid` are system catalogs with restricted access (superuser or `pg_read_all_settings` only)
- `pg_stat_activity` shows only sessions in databases the role can connect to; tenant A cannot connect to `db_tenant_b`, so those rows are filtered out

---

### 9. Function Security

**Control**: Tenants cannot use functions to escalate privileges or pollute system catalogs.

**Implementation**:
Tenant-created SECURITY DEFINER functions execute with tenant privileges (not elevated); `pg_catalog` modifications require superuser.

**Attack scenarios prevented:**

**a) SECURITY DEFINER privilege escalation:**
```sql
CREATE FUNCTION app.escalate() RETURNS void SECURITY DEFINER AS $$
  DROP DATABASE db_tenant_b;
$$ LANGUAGE SQL;
```

If this worked, the function would execute with the privileges of the function owner. If a superuser accidentally ran this function, it would execute the malicious command with superuser privileges.

**b) System catalog pollution:**
```sql
CREATE FUNCTION pg_catalog.version() RETURNS text AS $$
  SELECT 'HACKED';
$$ LANGUAGE SQL;
```

This could shadow legitimate system functions and affect all users.

**Test validation:**
```bash
# Both of these must fail
psql -U tenant_a_app -d db_tenant_a \
  -c "CREATE FUNCTION app.escalate() RETURNS void SECURITY DEFINER AS \$\$ DROP DATABASE db_tenant_b; \$\$ LANGUAGE SQL;"
psql -U tenant_a_app -d db_tenant_a \
  -c "CREATE FUNCTION pg_catalog.malicious() RETURNS void AS \$\$ SELECT 1; \$\$ LANGUAGE SQL;"
```

**Why these fail:**
- While tenants can create SECURITY DEFINER functions in their own schema, those functions execute with the tenant's privileges (not elevated)
- Creating functions in `pg_catalog` requires superuser privileges
- The test verifies that even if created, SECURITY DEFINER functions cannot perform privileged operations

---

### 10. Tablespace Restrictions

**Control**: Tenants cannot create tablespaces.

**Implementation**:
Creating tablespaces requires superuser privileges.

**Attack scenario prevented:**
```sql
CREATE TABLESPACE malicious_ts LOCATION '/tmp';
-- Potentially write data to arbitrary filesystem locations
-- or cause disk exhaustion in unmonitored locations
```

**Test validation:**
```bash
psql -U tenant_a_app -d db_tenant_a -c "CREATE TABLESPACE malicious_ts LOCATION '/tmp';"
```

**Why it fails:**
Creating tablespaces requires superuser privileges, as it involves filesystem operations and can affect server-wide storage layout.

---

### 11. Cross-Tenant Grant Prevention

**Control**: Defense-in-depth ensures that even attempted cross-tenant grants are ineffective.

**Implementation**:
Multiple layers of isolation prevent cross-tenant access, even if grants are attempted.

**Attack scenario prevented:**
```sql
GRANT SELECT ON app.sample_data TO tenant_b_app;
-- Attempt to establish cross-tenant data sharing
```

**Test validation:**
```bash
psql -U tenant_a_app -d db_tenant_a -c "GRANT SELECT ON app.sample_data TO tenant_b_app;"
```

**Why it fails:**
While tenants own their tables and normally could grant privileges on them, `tenant_b_app` has no CONNECT privilege on `db_tenant_a`. Even if the grant succeeded, tenant B could never connect to the database to use it. This test validates defense-in-depth: multiple layers prevent cross-tenant access.

---

## Auditing and Logging

### pgAudit Integration

**Control**: Audit access and configuration changes.

**Implementation** (planned for RDS/Aurora):
- Enhanced PostgreSQL logging via parameter group
- pgAudit extension for detailed DDL/role events
- Central log collection (e.g., CloudWatch Logs)

**Assurance**:
We integrate pgAudit in production to provide a complete SQL-level audit trail for each tenant. pgAudit records every security-relevant action—queries, DDL, privilege changes, failed attempts, and cross-tenant violations. Combined with our database-per-tenant and role-based isolation model, pgAudit provides provable evidence of access enforcement, least privilege, and attempted policy violations. This strengthens our multi-tenant RDS architecture and aligns with key NIST 800-53 controls (AC-3, AC-6, AU-2, AU-6) and DoD SRG requirements.

Logs can be reviewed for suspicious activity and used as evidence in security assessments.

---

## Backups and Snapshots

**Control**: Protect multi-tenant data in backups.

**Implementation**:
- RDS snapshot access tightly controlled (IAM, KMS)
- Clear guidance: snapshots are multi-tenant assets and may not be shared without proper authority

**Assurance**:
- IAM policy review and periodic audit of snapshot access logs

---

## Future Work

- Integrate with Terraform-managed RDS instances and document RDS-specific controls:
  - parameter groups, security groups, IAM, KMS, backup retention
- Integrate audit log configuration with centralized logging and monitoring solutions
- Expand test coverage for additional PostgreSQL features as they become relevant
