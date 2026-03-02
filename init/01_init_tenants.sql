-----------------------------------------------------------------------
-- 01_init_tenants.sql
-- Initial database, roles, schemas, and sample data
-- CORRECTED VERSION - use SET ROLE to create objects as platform_owner
-----------------------------------------------------------------------

-------------------------------
-- 0. Neutral platform owner role
-------------------------------
-- Must exist BEFORE creating tenant schemas.
CREATE ROLE platform_owner NOLOGIN;

-------------------------------
-- 1. Create tenant databases
-------------------------------
CREATE DATABASE db_tenant_a OWNER postgres;
CREATE DATABASE db_tenant_b OWNER postgres;
CREATE DATABASE db_tenant_c OWNER postgres;

-------------------------------
-- 2. Create tenant application roles
-------------------------------
CREATE ROLE tenant_a_app LOGIN PASSWORD 'tenant_a_pw';
CREATE ROLE tenant_b_app LOGIN PASSWORD 'tenant_b_pw';
CREATE ROLE tenant_c_app LOGIN PASSWORD 'tenant_c_pw';


-----------------------------------------------------------------------
-- 3. Configure each tenant DB
-----------------------------------------------------------------------

-----------------------------------------------------------------------
-- TENANT A
-----------------------------------------------------------------------
\connect db_tenant_a

-- Lock down public schema
REVOKE ALL ON SCHEMA public FROM PUBLIC;
REVOKE ALL ON SCHEMA public FROM postgres;

-- Create app schema owned by platform_owner
CREATE SCHEMA app AUTHORIZATION platform_owner;

-- Switch to platform_owner to create objects
SET ROLE platform_owner;

-- Create sample table (will be owned by platform_owner)
CREATE TABLE app.sample_data (
    id   serial PRIMARY KEY,
    note text NOT NULL
);

INSERT INTO app.sample_data (note) VALUES ('tenant A row 1');

-- Reset back to postgres
RESET ROLE;


-----------------------------------------------------------------------
-- TENANT B
-----------------------------------------------------------------------
\connect db_tenant_b

REVOKE ALL ON SCHEMA public FROM PUBLIC;
REVOKE ALL ON SCHEMA public FROM postgres;

CREATE SCHEMA app AUTHORIZATION platform_owner;

SET ROLE platform_owner;

CREATE TABLE app.sample_data (
    id   serial PRIMARY KEY,
    note text NOT NULL
);

INSERT INTO app.sample_data (note) VALUES ('tenant B row 1');

RESET ROLE;


-----------------------------------------------------------------------
-- TENANT C
-----------------------------------------------------------------------
\connect db_tenant_c

REVOKE ALL ON SCHEMA public FROM PUBLIC;
REVOKE ALL ON SCHEMA public FROM postgres;

CREATE SCHEMA app AUTHORIZATION platform_owner;

SET ROLE platform_owner;

CREATE TABLE app.sample_data (
    id   serial PRIMARY KEY,
    note text NOT NULL
);

INSERT INTO app.sample_data (note) VALUES ('tenant C row 1');

RESET ROLE;


-----------------------------------------------------------------------
-- END OF FILE - 01_init_tenants.sql
-----------------------------------------------------------------------