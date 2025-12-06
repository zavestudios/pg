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

The project includes comprehensive security testing in `scripts/test_isolation.sh` that validates the isolation model against real-world attack scenarios. These tests can be run in CI or as part of a deployment verification phase, and their output can be captured as evidence for ATO or security reviews.

### Test Categories and Attack Scenarios

#### 1. Database Isolation Tests

**What we test:**
- Tenants can only connect to their own database
- Cross-database connection attempts fail

**Attack scenario prevented:**
A malicious tenant attempts to connect directly to another tenant's database to read or manipulate their data.

**Example test:**
```bash
# This must fail - tenant A cannot connect to tenant B's database
psql -U tenant_a_app -d db_tenant_b -c "SELECT current_user;"
```

**Why it fails:**
The initialization script revokes PUBLIC connect privileges and grants CONNECT only to the owning tenant:
```sql
REVOKE CONNECT ON DATABASE db_tenant_b FROM PUBLIC;
GRANT CONNECT ON DATABASE db_tenant_b TO tenant_b_app;
```

#### 2. Schema Isolation Tests

**What we test:**
- Tenants cannot create tables in the `public` schema
- Tenants can only access their dedicated `app` schema

**Attack scenario prevented:**
A malicious tenant tries to create objects in the `public` schema, which might be accessible across databases or could pollute the shared namespace.

**Example test:**
```bash
# This must fail - tenant cannot use public schema
psql -U tenant_a_app -d db_tenant_a -c "CREATE TABLE public.hacked_a (id int);"
```

**Why it fails:**
All privileges on `public` are revoked from tenant roles:
```sql
REVOKE ALL ON SCHEMA public FROM tenant_a_app;
```

#### 3. Search Path Manipulation Tests

**What we test:**
- Tenants cannot manipulate `search_path` to bypass schema isolation

**Attack scenario prevented:**
A malicious tenant attempts to change their session `search_path` to prioritize the `public` schema, hoping to create unqualified tables there.

**Example test:**
```bash
# This must fail - even with manipulated search_path
psql -U tenant_a_app -d db_tenant_a \
  -c "SET search_path = public, app; CREATE TABLE hacked_unqualified_a (id int);"
```

**Why it fails:**
Even though tenants can modify their session `search_path`, they still have no CREATE privilege on `public`. When PostgreSQL tries to create the table in the first writable schema in the path, it finds `public` (no CREATE privilege) and fails before trying `app`.

#### 4. Extension and Foreign Data Wrapper Tests

**What we test:**
- Tenants cannot create `dblink` extension
- Tenants cannot create `postgres_fdw` extension
- Tenants cannot create `file_fdw` extension

**Attack scenario prevented:**
These extensions allow cross-database queries and file system access, which would completely bypass the database-level isolation model.

**Example attack with dblink:**
```sql
CREATE EXTENSION dblink;
-- Now tenant A could query tenant B's database
SELECT * FROM dblink(
  'dbname=db_tenant_b user=some_user password=guessed',
  'SELECT * FROM app.sample_data'
) AS stolen_data(id int, note text);
```

**Why it fails:**
Only superusers or roles with CREATE privilege on the database can create extensions. Tenant roles have this privilege explicitly revoked:
```sql
REVOKE CREATE ON DATABASE db_tenant_a FROM tenant_a_app;
```

#### 5. Privilege Escalation Tests

**What we test:**
- Tenants cannot ALTER ROLE to gain superuser privileges
- Tenants cannot CREATE ROLE to make new users
- Tenants cannot ALTER ROLE for other users (password theft)
- Tenants cannot SET ROLE to impersonate other tenants

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

**Why these fail:**
PostgreSQL requires superuser privileges or specific role attributes to execute these commands. Tenant roles are created as basic LOGIN roles with no administrative privileges.

#### 6. Database Object Manipulation Tests

**What we test:**
- Tenants cannot DROP other tenants' databases
- Tenants cannot ALTER DATABASE settings for other tenants
- Tenants cannot CREATE DATABASE

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

**Why these fail:**
Database-level operations require either database ownership or superuser privileges. Tenant roles own only their own database and have no privileges on others.

#### 7. Filesystem Access Tests

**What we test:**
- Tenants cannot use COPY TO to write files to the filesystem
- Tenants cannot use COPY FROM to read files from the filesystem
- Tenants cannot use `pg_read_file()` to read server files
- Tenants cannot use `pg_ls_dir()` to list server directories

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

**Why these fail:**
- COPY TO/FROM file paths requires superuser privileges (not just table ownership)
- `pg_read_file()` and `pg_ls_dir()` are restricted to superusers and roles with `pg_read_server_files` privilege
- Tenant roles have neither

#### 8. Information Disclosure Tests

**What we test:**
- Tenants cannot query `pg_shadow` to see password hashes
- Tenants cannot query `pg_authid` to see authentication info
- Tenants cannot access `pg_stat_activity` for other tenant databases

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

**Why these fail:**
- `pg_shadow` and `pg_authid` are system catalogs with restricted access (superuser or `pg_read_all_settings` only)
- `pg_stat_activity` shows only sessions in databases the role can connect to; tenant A cannot connect to `db_tenant_b`, so those rows are filtered out

#### 9. Function Security Tests

**What we test:**
- Tenants cannot create SECURITY DEFINER functions to escalate privileges
- Tenants cannot create functions in `pg_catalog`

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

**Why these fail:**
- While tenants can create SECURITY DEFINER functions in their own schema, those functions execute with the tenant's privileges (not elevated)
- Creating functions in `pg_catalog` requires superuser privileges
- The test verifies that even if created, SECURITY DEFINER functions cannot perform privileged operations

#### 10. Tablespace Tests

**What we test:**
- Tenants cannot create tablespaces

**Attack scenario prevented:**
```sql
CREATE TABLESPACE malicious_ts LOCATION '/tmp';
-- Potentially write data to arbitrary filesystem locations
-- or cause disk exhaustion in unmonitored locations
```

**Why it fails:**
Creating tablespaces requires superuser privileges, as it involves filesystem operations and can affect server-wide storage layout.

#### 11. Cross-Tenant Grant Tests

**What we test:**
- Tenants cannot GRANT privileges on their objects to other tenant roles

**Attack scenario prevented:**
```sql
GRANT SELECT ON app.sample_data TO tenant_b_app;
-- Attempt to establish cross-tenant data sharing
```

**Why it fails:**
While tenants own their tables and normally could grant privileges on them, `tenant_b_app` has no CONNECT privilege on `db_tenant_a`. Even if the grant succeeded, tenant B could never connect to the database to use it. This test validates defense-in-depth: multiple layers prevent cross-tenant access.

### pgAudit Integration

We integrate pgAudit in production to provide a complete SQL-level audit trail for each tenant. pgAudit records every security-relevant action—queries, DDL, privilege changes, failed attempts, and cross-tenant violations. Combined with our database-per-tenant and role-based isolation model, pgAudit provides provable evidence of access enforcement, least privilege, and attempted policy violations. This strengthens our multi-tenant RDS architecture and aligns with key NIST 800-53 controls (AC-3, AC-6, AU-2, AU-6) and DoD SRG requirements.

## Future Work

- Add automated tests for:
  - `search_path` immutability for tenant roles.
  - `CREATE EXTENSION`, `CREATE SERVER`, and other privileged commands failing for tenants.
- Integrate with Terraform-managed RDS instances and document RDS-specific controls:
  - parameter groups, security groups, IAM, KMS, backup retention.
- Integrate audit log configuration with centralized logging and monitoring solutions.
