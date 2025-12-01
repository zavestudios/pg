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
  - attempts to create extensions (dblink)
  - attempts to bypass search_path
  - attempts to grant rights to other tenants

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
   Convert the SQL-based tenant configuration into Terraform resources using:
   - `postgresql_database`
   - `postgresql_role`
   - `postgresql_schema`
   - `postgresql_grant`
   - `postgresql_default_privileges`

2. AWS Deployment  
   Introduce RDS or Aurora PostgreSQL infrastructure using Terraform.
   Configure:
   - Parameter groups (pgAudit, logging, settings)
   - Security groups and networking
   - KMS encryption
   - Backup and snapshot policies

3. CI/CD Integration  
   Use GitLab CI/CD to:
   - Run the full Docker test suite on each merge request
   - Execute terraform plan/apply pipelines
   - Add optional post-deploy verification tests against RDS

4. pgAudit Integration in Production  
   Enable pgAudit via RDS parameter groups and surface logs to CloudWatch/SIEM.

5. Tenant Onboarding Automation  
   Drive new tenant creation entirely through Terraform modules and CI/CD workflows.

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
