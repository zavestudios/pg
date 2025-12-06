# Multi-Tenant PostgreSQL Isolation Pattern

This project demonstrates a hardened, production-grade approach to running multiple tenants on a single PostgreSQL server while maintaining strict, testable isolation between tenants. The model is designed to be portable from local Docker development environments to AWS RDS PostgreSQL and Aurora PostgreSQL.

The primary motivations are:
1. Reduce infrastructure cost by consolidating tenant databases into a single RDS instance.
2. Maintain strong tenant data isolation through PostgreSQL-native security controls.
3. Provide compliance-ready evidence (tests, docs, audit strategy) for environments such as DoD, FedRAMP Moderate, and NIST 800-53.
4. Prepare the configuration for full migration to Infrastructure-as-Code using Terraform.

This repository includes:
- A hardened tenant isolation model (database-per-tenant, role-per-tenant, dedicated schema, locked-down public schema, safe search_path, and default privilege hardening)
- A reproducible Docker environment
- A comprehensive test suite including both happy-path and negative “attack” tests
- Architectural, security, compliance, and auditing documentation
- A roadmap toward Terraform implementation and RDS deployment

-----------------------------------------------------------------------

## Project Structure

```
pg-multitenant/
├── docker-compose.yml
├── init/
│   └── 01_init_tenants.sql
├── scripts/
│   ├── test_isolation.sh
│   └── (future) test_isolation_rds.sh
├── docs/
│   ├── ARCHITECTURE.md
│   ├── SECURITY.md
│   ├── THREAT_MODEL.md
│   ├── COMPLIANCE.md
│   ├── COST_MODEL.md
│   ├── PGAUDIT.md
│   └── (future) TERRAFORM_PLAN.md
└── README.md
```

-----------------------------------------------------------------------

## Overview of the Isolation Model

Each tenant receives:

- A dedicated PostgreSQL database (`db_tenant_a`, `db_tenant_b`, etc.)
- A dedicated login role (`tenant_a_app`, `tenant_b_app`)
- A dedicated schema inside its database (`app`)
- Exclusive access to its schema
- No ability to connect to or view other tenant databases
- No rights on the `public` schema
- A controlled `search_path`: `app, pg_catalog`
- Hardened default privileges for future objects
- No ability to create extensions or foreign data wrappers

Admin and tenant behavior is validated through a comprehensive test suite.

-----------------------------------------------------------------------

## Running the Environment

Start PostgreSQL and initialize the tenant databases:

```
docker compose up -d
```

Wait a few seconds for initialization to complete.

To tear down and reset all data:

```
docker compose down -v
```

-----------------------------------------------------------------------

## Running the Isolation Test Suite

The test script validates:

- Correct database creation
- Correct schema creation
- Ownership and privilege correctness
- Tenant ability to access its own data
- Negative tests (expected failures):
  - cross-database connections
  - attempts to create tables in the public schema
  - attempts to create extensions (dblink, postgres_fdw, file_fdw)
  - attempts to bypass search_path
  - attempts to grant rights to other tenants
  - privilege escalation attempts (ALTER ROLE, CREATE ROLE, SET ROLE)
  - database object manipulation (DROP DATABASE, ALTER DATABASE, CREATE DATABASE)
  - filesystem access attempts (COPY TO/FROM, pg_read_file, pg_ls_dir)
  - information disclosure attacks (pg_shadow, pg_authid, cross-tenant pg_stat_activity)
  - malicious function creation (SECURITY DEFINER, pg_catalog functions)
  - tablespace creation attempts

Run the full suite:

```
./scripts/test_isolation.sh
```

The script reports success or failure for each test and summarizes total failures at the end.

-----------------------------------------------------------------------

## Documentation

Detailed design, security, and compliance documentation is available under `docs/`.

- `docs/ARCHITECTURE.md`  
  High-level design of the multi-tenant PostgreSQL model.

- `docs/SECURITY.md`  
  Security controls (access control, schema isolation, privileges).

- `docs/THREAT_MODEL.md`  
  Threat modeling for tenant isolation and boundary enforcement.

- `docs/COMPLIANCE.md`  
  Mapping of the model to NIST 800-53, FedRAMP Moderate, and DoD SRG controls.

- `docs/COST_MODEL.md`  
  Cost comparison between per-tenant RDS vs. multi-tenant RDS.

- `docs/PGAUDIT.md`  
  Audit strategy for production deployments using pgAudit with RDS.

These documents serve as a reference implementation for building secure, compliant tenant-isolated database platforms.

-----------------------------------------------------------------------

## Roadmap

Planned next steps include:

1. Terraform Migration  
   Convert the database initialization logic (currently in SQL) into Terraform resources using the Terraform **PostgreSQL provider**, including:
   - `postgresql_database`
   - `postgresql_role`
   - `postgresql_schema`
   - `postgresql_grant`
   - `postgresql_default_privileges`

   These resources will allow Terraform to connect directly to a PostgreSQL instance (initially your local Docker instance, later AWS RDS) and create tenant databases, roles, schemas, and hardened privileges in a fully declarative manner.

2. AWS Deployment  
   Introduce AWS infrastructure using Terraform’s `aws` provider:
   - `aws_db_instance` or `aws_rds_cluster` for PostgreSQL
   - Subnet group, security groups, parameter group (pgAudit, logging)
   - KMS encryption and backup policies

   The PostgreSQL provider will then target the RDS endpoint to apply the same tenant isolation model used in the local Docker environment.

3. CI/CD Integration  
   Use GitLab CI/CD to:
   - Run the Docker-based isolation tests on each merge request
   - Execute Terraform `plan` for review
   - Execute Terraform `apply` on protected branches
   - Optionally run a post-deploy verification test suite against RDS

4. pgAudit Integra

-----------------------------------------------------------------------

## Purpose and Use Cases

This repository can serve as:

- A reference design for multi-tenant PostgreSQL
- A foundation for platform engineering patterns in DoD environments
- A compliance-ready data isolation model
- A cost-optimization model for consolidating RDS instances
- A training or demonstration environment for DB security and hardening
- A basis for Terraform-based production infrastructure

-----------------------------------------------------------------------

## License

Choose any license you prefer. By default this project may be considered MIT unless otherwise noted.
