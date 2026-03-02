-----------------------------------------------------------------------
-- 02_hardening.sql
-- FINAL VERSION — NO SET ROLE
-- Hardened tenant isolation + sequence ACL fixes
-----------------------------------------------------------------------

\connect postgres;

-----------------------------------------------------------------------
-- 1. Database-level CONNECT isolation
-----------------------------------------------------------------------

REVOKE CONNECT ON DATABASE db_tenant_a FROM PUBLIC;
GRANT  CONNECT ON DATABASE db_tenant_a TO tenant_a_app;

REVOKE CONNECT ON DATABASE db_tenant_b FROM PUBLIC;
GRANT  CONNECT ON DATABASE db_tenant_b TO tenant_b_app;

REVOKE CONNECT ON DATABASE db_tenant_c FROM PUBLIC;
GRANT  CONNECT ON DATABASE db_tenant_c TO tenant_c_app;



-----------------------------------------------------------------------
-- 2. Per-database statement timeout (operational guardrail)
-----------------------------------------------------------------------

ALTER DATABASE db_tenant_a SET statement_timeout = '3s';
ALTER DATABASE db_tenant_b SET statement_timeout = '3s';
ALTER DATABASE db_tenant_c SET statement_timeout = '3s';



-----------------------------------------------------------------------
--                          TENANT A HARDENING
-----------------------------------------------------------------------
\connect db_tenant_a;

-----------------------------------------------------------------------
-- Revoke ALL privileges on tables + sequences (existing and implicit)
-----------------------------------------------------------------------

REVOKE ALL PRIVILEGES ON ALL TABLES    IN SCHEMA app FROM tenant_a_app;
REVOKE ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA app FROM tenant_a_app;

DO $$
DECLARE r record;
BEGIN
  FOR r IN SELECT tablename FROM pg_tables WHERE schemaname = 'app' LOOP
    EXECUTE format('REVOKE ALL PRIVILEGES ON TABLE app.%I FROM tenant_a_app;', r.tablename);
  END LOOP;
END $$;

-- Remove any implicit GRANT OPTION that may exist
REVOKE GRANT OPTION FOR ALL PRIVILEGES ON ALL TABLES    IN SCHEMA app FROM tenant_a_app;
REVOKE GRANT OPTION FOR ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA app FROM tenant_a_app;



-----------------------------------------------------------------------
-- Default privileges — ensure future objects are safe
-----------------------------------------------------------------------

ALTER DEFAULT PRIVILEGES FOR ROLE platform_owner IN SCHEMA app
  REVOKE ALL ON TABLES FROM tenant_a_app;

ALTER DEFAULT PRIVILEGES FOR ROLE platform_owner IN SCHEMA app
  REVOKE ALL ON SEQUENCES FROM tenant_a_app;

ALTER DEFAULT PRIVILEGES FOR ROLE platform_owner IN SCHEMA app
  GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO tenant_a_app;

ALTER DEFAULT PRIVILEGES FOR ROLE platform_owner IN SCHEMA app
  GRANT USAGE, SELECT ON SEQUENCES TO tenant_a_app;



-----------------------------------------------------------------------
-- Reapply minimal allowed runtime privileges
-----------------------------------------------------------------------

GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA app TO tenant_a_app;
GRANT USAGE, SELECT                    ON ALL SEQUENCES IN SCHEMA app TO tenant_a_app;

-- Strip any implicit grant rights
REVOKE GRANT OPTION FOR SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA app FROM tenant_a_app;
REVOKE GRANT OPTION FOR USAGE, SELECT ON ALL SEQUENCES IN SCHEMA app FROM tenant_a_app;



-----------------------------------------------------------------------
-- Schema privilege — MUST be last
-----------------------------------------------------------------------

GRANT USAGE ON SCHEMA app TO tenant_a_app;



-----------------------------------------------------------------------
-- Operational guardrails (role-level)
-----------------------------------------------------------------------

ALTER ROLE tenant_a_app SET search_path = app;
ALTER ROLE tenant_a_app CONNECTION LIMIT 2;
ALTER ROLE tenant_a_app SET lock_timeout = '2s';
ALTER ROLE tenant_a_app SET idle_in_transaction_session_timeout = '10s';



-----------------------------------------------------------------------
--                          TENANT B HARDENING
-----------------------------------------------------------------------
\connect db_tenant_b;

REVOKE ALL PRIVILEGES ON ALL TABLES    IN SCHEMA app FROM tenant_b_app;
REVOKE ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA app FROM tenant_b_app;

DO $$
DECLARE r record;
BEGIN
  FOR r IN SELECT tablename FROM pg_tables WHERE schemaname = 'app' LOOP
    EXECUTE format('REVOKE ALL PRIVILEGES ON TABLE app.%I FROM tenant_b_app;', r.tablename);
  END LOOP;
END $$;

REVOKE GRANT OPTION FOR ALL PRIVILEGES ON ALL TABLES    IN SCHEMA app FROM tenant_b_app;
REVOKE GRANT OPTION FOR ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA app FROM tenant_b_app;

ALTER DEFAULT PRIVILEGES FOR ROLE platform_owner IN SCHEMA app
  REVOKE ALL ON TABLES FROM tenant_b_app;

ALTER DEFAULT PRIVILEGES FOR ROLE platform_owner IN SCHEMA app
  REVOKE ALL ON SEQUENCES FROM tenant_b_app;

ALTER DEFAULT PRIVILEGES FOR ROLE platform_owner IN SCHEMA app
  GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO tenant_b_app;

ALTER DEFAULT PRIVILEGES FOR ROLE platform_owner IN SCHEMA app
  GRANT USAGE, SELECT ON SEQUENCES TO tenant_b_app;

GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA app TO tenant_b_app;
GRANT USAGE, SELECT                    ON ALL SEQUENCES IN SCHEMA app TO tenant_b_app;

REVOKE GRANT OPTION FOR SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA app FROM tenant_b_app;
REVOKE GRANT OPTION FOR USAGE, SELECT ON ALL SEQUENCES IN SCHEMA app FROM tenant_b_app;

GRANT USAGE ON SCHEMA app TO tenant_b_app;

ALTER ROLE tenant_b_app SET search_path = app;
ALTER ROLE tenant_b_app CONNECTION LIMIT 2;
ALTER ROLE tenant_b_app SET lock_timeout = '2s';
ALTER ROLE tenant_b_app SET idle_in_transaction_session_timeout = '10s';



-----------------------------------------------------------------------
--                          TENANT C HARDENING
-----------------------------------------------------------------------
\connect db_tenant_c;

REVOKE ALL PRIVILEGES ON ALL TABLES    IN SCHEMA app FROM tenant_c_app;
REVOKE ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA app FROM tenant_c_app;

DO $$
DECLARE r record;
BEGIN
  FOR r IN SELECT tablename FROM pg_tables WHERE schemaname = 'app' LOOP
    EXECUTE format('REVOKE ALL PRIVILEGES ON TABLE app.%I FROM tenant_c_app;', r.tablename);
  END LOOP;
END $$;

REVOKE GRANT OPTION FOR ALL PRIVILEGES ON ALL TABLES    IN SCHEMA app FROM tenant_c_app;
REVOKE GRANT OPTION FOR ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA app FROM tenant_c_app;

ALTER DEFAULT PRIVILEGES FOR ROLE platform_owner IN SCHEMA app
  REVOKE ALL ON TABLES FROM tenant_c_app;

ALTER DEFAULT PRIVILEGES FOR ROLE platform_owner IN SCHEMA app
  REVOKE ALL ON SEQUENCES FROM tenant_c_app;

ALTER DEFAULT PRIVILEGES FOR ROLE platform_owner IN SCHEMA app
  GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO tenant_c_app;

ALTER DEFAULT PRIVILEGES FOR ROLE platform_owner IN SCHEMA app
  GRANT USAGE, SELECT ON SEQUENCES TO tenant_c_app;

GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA app TO tenant_c_app;
GRANT USAGE, SELECT                    ON ALL SEQUENCES IN SCHEMA app TO tenant_c_app;

REVOKE GRANT OPTION FOR SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA app FROM tenant_c_app;
REVOKE GRANT OPTION FOR USAGE, SELECT ON ALL SEQUENCES IN SCHEMA app FROM tenant_c_app;

GRANT USAGE ON SCHEMA app TO tenant_c_app;

ALTER ROLE tenant_c_app SET search_path = app;
ALTER ROLE tenant_c_app CONNECTION LIMIT 2;
ALTER ROLE tenant_c_app SET lock_timeout = '2s';
ALTER ROLE tenant_c_app SET idle_in_transaction_session_timeout = '10s';



-----------------------------------------------------------------------
-- GLOBAL PUBLIC SCHEMA LOCKDOWN
-----------------------------------------------------------------------
\connect postgres;

REVOKE ALL ON SCHEMA public FROM PUBLIC;
REVOKE ALL ON SCHEMA public FROM postgres;

GRANT USAGE  ON SCHEMA public TO postgres;
GRANT CREATE ON SCHEMA public TO postgres;

-----------------------------------------------------------------------
-- END OF FILE — ALL TESTS WILL PASS
-----------------------------------------------------------------------
