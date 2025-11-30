# Multi-Tenant PostgreSQL Isolation Demo

This project demonstrates secure multi-tenant isolation in PostgreSQL using:

- One Postgres server (cluster)
- One database per tenant
- One dedicated schema per tenant (`app`)
- One login role per tenant
- Strict CONNECT privileges
- Locked-down public schema
- Safe search_path settings

It uses Docker and docker-compose to start a Postgres instance and automatically initialize tenant databases. A test script verifies that tenants cannot connect to or read data from each other’s databases.

## Project Structure
```
pg-multitenant/
├── docker-compose.yml
├── init/
│   └── 01_init_tenants.sql
└── scripts/
    └── test_isolation.sh
```
`docker-compose.yml`: Starts Postgres and runs initialization scripts.
`init/01_init_tenants.sql`: Creates tenant databases, roles, schemas, and privileges.
`test_isolation.sh`: Tests tenant isolation.

## Getting Started

Start PostgreSQL:

    docker compose up -d

On first startup, the initialization script:

- Creates three tenant databases:
  - db_tenant_a
  - db_tenant_b
  - db_tenant_c
- Creates three tenant login roles:
  - tenant_a_app
  - tenant_b_app
  - tenant_c_app
- Creates a dedicated schema named `app` in each database
- Locks down the public schema
- Applies safe default privileges

## Isolation Model

Each tenant receives:

1. Its own database  
   `Example: db_tenant_a`

2. Its own login role  
   `Example: tenant_a_app`  
   Only this role can CONNECT to this database.

3. Its own dedicated schema  
   `Example: the app schema inside db_tenant_a`  
   Owned by the tenant role.

4. A locked-down public schema  
   The `public` schema is not used for tenant objects.

5. A safe `search_path`  
   Each tenant role receives:
       `search_path = app, pg_catalog`

6. Restricted default privileges  
   New tables, sequences, and functions created by the tenant are not visible to PUBLIC.

## Testing Isolation

Run:

    ./scripts/test_isolation.sh

The script verifies:

- Each tenant can connect to its own database.
- Each tenant cannot connect to other tenant databases.
- Each tenant can read and write data only within its own app schema.
- Cross-database access attempts fail with non-zero exit codes.

Example expected failure:

    FATAL: permission denied for database "db_tenant_b"

## Resetting the Environment

To reset and reinitialize the cluster:

    docker compose down -v
    docker compose up -d

## Security Principles Demonstrated

- One tenant per database
- Dedicated schema per tenant
- Locked-down public schema
- Minimal privileges
- Safe search_path configuration
- Controlled default privileges

This pattern is suitable for both local development and production systems such as AWS RDS PostgreSQL or Aurora PostgreSQL.

## Future Improvements

Possible extensions:

- Terraform module for deploying this model on AWS RDS
- pgAudit integration for auditing DDL and role events
- Additional negative tests (extension creation blocking, schema tampering attempts)
- Performance isolation experiments
- Adding an application or API layer to demonstrate tenant-bound query paths

