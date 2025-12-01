-- 01_init_tenants.sql (hardened multi-tenant version, fixed table ownership)

------------------------------------------------------------
-- 1. Create tenant roles
------------------------------------------------------------

CREATE ROLE tenant_a_app LOGIN PASSWORD 'tenant_a_password';
CREATE ROLE tenant_b_app LOGIN PASSWORD 'tenant_b_password';
CREATE ROLE tenant_c_app LOGIN PASSWORD 'tenant_c_password';

------------------------------------------------------------
-- 2. Create tenant databases
------------------------------------------------------------

CREATE DATABASE db_tenant_a;
CREATE DATABASE db_tenant_b;
CREATE DATABASE db_tenant_c;

------------------------------------------------------------
-- 3. Restrict CONNECT and CREATE on tenant databases
------------------------------------------------------------

REVOKE CONNECT ON DATABASE db_tenant_a FROM PUBLIC;
REVOKE CONNECT ON DATABASE db_tenant_b FROM PUBLIC;
REVOKE CONNECT ON DATABASE db_tenant_c FROM PUBLIC;

GRANT CONNECT ON DATABASE db_tenant_a TO tenant_a_app;
GRANT CONNECT ON DATABASE db_tenant_b TO tenant_b_app;
GRANT CONNECT ON DATABASE db_tenant_c TO tenant_c_app;

REVOKE CREATE ON DATABASE db_tenant_a FROM PUBLIC;
REVOKE CREATE ON DATABASE db_tenant_b FROM PUBLIC;
REVOKE CREATE ON DATABASE db_tenant_c FROM PUBLIC;

REVOKE CREATE ON DATABASE db_tenant_a FROM tenant_a_app;
REVOKE CREATE ON DATABASE db_tenant_b FROM tenant_b_app;
REVOKE CREATE ON DATABASE db_tenant_c FROM tenant_c_app;

------------------------------------------------------------
-- 4. Per-DB hardening and sample data
------------------------------------------------------------

------------------------------------------------------------
-- Tenant A
------------------------------------------------------------
\connect db_tenant_a

-- 4.1 Lock down public schema
REVOKE ALL ON SCHEMA public FROM PUBLIC;
REVOKE ALL ON SCHEMA public FROM tenant_a_app;

-- 4.2 Dedicated tenant schema "app"
CREATE SCHEMA app AUTHORIZATION tenant_a_app;

-- 4.3 Tenant role can use and create in its own schema
GRANT USAGE, CREATE ON SCHEMA app TO tenant_a_app;

-- 4.4 Safe search_path
ALTER ROLE tenant_a_app IN DATABASE db_tenant_a
  SET search_path = app, pg_catalog;

-- 4.5 Default privileges for future objects
ALTER DEFAULT PRIVILEGES FOR ROLE tenant_a_app IN SCHEMA app
  REVOKE ALL ON TABLES FROM PUBLIC;
ALTER DEFAULT PRIVILEGES FOR ROLE tenant_a_app IN SCHEMA app
  GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO tenant_a_app;

ALTER DEFAULT PRIVILEGES FOR ROLE tenant_a_app IN SCHEMA app
  REVOKE ALL ON SEQUENCES FROM PUBLIC;
ALTER DEFAULT PRIVILEGES FOR ROLE tenant_a_app IN SCHEMA app
  GRANT USAGE, SELECT ON SEQUENCES TO tenant_a_app;

ALTER DEFAULT PRIVILEGES FOR ROLE tenant_a_app IN SCHEMA app
  REVOKE ALL ON FUNCTIONS FROM PUBLIC;
ALTER DEFAULT PRIVILEGES FOR ROLE tenant_a_app IN SCHEMA app
  GRANT EXECUTE ON FUNCTIONS TO tenant_a_app;

-- 4.6 Sample table and row in app schema (owned by tenant)
CREATE TABLE app.sample_data (
  id   serial PRIMARY KEY,
  note text NOT NULL
);
ALTER TABLE app.sample_data OWNER TO tenant_a_app;
INSERT INTO app.sample_data (note) VALUES ('tenant A row 1');

------------------------------------------------------------
-- Tenant B
------------------------------------------------------------
\connect db_tenant_b

REVOKE ALL ON SCHEMA public FROM PUBLIC;
REVOKE ALL ON SCHEMA public FROM tenant_b_app;

CREATE SCHEMA app AUTHORIZATION tenant_b_app;
GRANT USAGE, CREATE ON SCHEMA app TO tenant_b_app;

ALTER ROLE tenant_b_app IN DATABASE db_tenant_b
  SET search_path = app, pg_catalog;

ALTER DEFAULT PRIVILEGES FOR ROLE tenant_b_app IN SCHEMA app
  REVOKE ALL ON TABLES FROM PUBLIC;
ALTER DEFAULT PRIVILEGES FOR ROLE tenant_b_app IN SCHEMA app
  GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO tenant_b_app;

ALTER DEFAULT PRIVILEGES FOR ROLE tenant_b_app IN SCHEMA app
  REVOKE ALL ON SEQUENCES FROM PUBLIC;
ALTER DEFAULT PRIVILEGES FOR ROLE tenant_b_app IN SCHEMA app
  GRANT USAGE, SELECT ON SEQUENCES TO tenant_b_app;

ALTER DEFAULT PRIVILEGES FOR ROLE tenant_b_app IN SCHEMA app
  REVOKE ALL ON FUNCTIONS FROM PUBLIC;
ALTER DEFAULT PRIVILEGES FOR ROLE tenant_b_app IN SCHEMA app
  GRANT EXECUTE ON FUNCTIONS TO tenant_b_app;

CREATE TABLE app.sample_data (
  id   serial PRIMARY KEY,
  note text NOT NULL
);
ALTER TABLE app.sample_data OWNER TO tenant_b_app;
INSERT INTO app.sample_data (note) VALUES ('tenant B row 1');

------------------------------------------------------------
-- Tenant C
------------------------------------------------------------
\connect db_tenant_c

REVOKE ALL ON SCHEMA public FROM PUBLIC;
REVOKE ALL ON SCHEMA public FROM tenant_c_app;

CREATE SCHEMA app AUTHORIZATION tenant_c_app;
GRANT USAGE, CREATE ON SCHEMA app TO tenant_c_app;

ALTER ROLE tenant_c_app IN DATABASE db_tenant_c
  SET search_path = app, pg_catalog;

ALTER DEFAULT PRIVILEGES FOR ROLE tenant_c_app IN SCHEMA app
  REVOKE ALL ON TABLES FROM PUBLIC;
ALTER DEFAULT PRIVILEGES FOR ROLE tenant_c_app IN SCHEMA app
  GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO tenant_c_app;

ALTER DEFAULT PRIVILEGES FOR ROLE tenant_c_app IN SCHEMA app
  REVOKE ALL ON SEQUENCES FROM PUBLIC;
ALTER DEFAULT PRIVILEGES FOR ROLE tenant_c_app IN SCHEMA app
  GRANT USAGE, SELECT ON SEQUENCES TO tenant_c_app;

ALTER DEFAULT PRIVILEGES FOR ROLE tenant_c_app IN SCHEMA app
  REVOKE ALL ON FUNCTIONS FROM PUBLIC;
ALTER DEFAULT PRIVILEGES FOR ROLE tenant_c_app IN SCHEMA app
  GRANT EXECUTE ON FUNCTIONS TO tenant_c_app;

CREATE TABLE app.sample_data (
  id   serial PRIMARY KEY,
  note text NOT NULL
);
ALTER TABLE app.sample_data OWNER TO tenant_c_app;
INSERT INTO app.sample_data (note) VALUES ('tenant C row 1');
