#!/usr/bin/env bash
set -u  # keep -u for unset vars, drop -e so failures don't kill the script

CONTAINER_NAME="pg-multitenant"
FAILURES=0

section() {
  echo
  echo "---------------------------------------------------"
  echo "$1"
  echo "---------------------------------------------------"
}

# Run a test that is expected to SUCCEED
run_test() {
  local description="$1"
  shift
  section "$description"
  if docker exec -it "$CONTAINER_NAME" "$@"; then
    echo "[OK] $description"
  else
    local exit_code=$?
    echo "[FAIL] $description (exit code: $exit_code)"
    FAILURES=$((FAILURES + 1))
  fi
}

# Run a test that is expected to FAIL (e.g., forbidden action)
run_expect_fail() {
  local description="$1"
  shift
  section "EXPECTED FAILURE: $description"
  if docker exec -it "$CONTAINER_NAME" "$@"; then
    echo "[FAIL] $description (command succeeded but should have failed)"
    FAILURES=$((FAILURES + 1))
  else
    local exit_code=$?
    echo "[OK] $description (failed as expected, exit code: $exit_code)"
  fi
}

echo "==================================================="
echo "  MULTI-TENANT POSTGRES HARDENED TEST SUITE"
echo "==================================================="

# -----------------------------------------------------
# Cluster overview
# -----------------------------------------------------

run_test "Cluster overview: list databases" \
  psql -U postgres -c "\l"

# -----------------------------------------------------
# Schema and sample data checks (as postgres)
# -----------------------------------------------------

run_test "Schema layout for db_tenant_a" \
  psql -U postgres -d db_tenant_a \
  -c "SELECT schema_name, schema_owner FROM information_schema.schemata ORDER BY schema_name;"

run_test "Sample data in db_tenant_a.app.sample_data" \
  psql -U postgres -d db_tenant_a \
  -c "SELECT * FROM app.sample_data;"

run_test "Schema layout for db_tenant_b" \
  psql -U postgres -d db_tenant_b \
  -c "SELECT schema_name, schema_owner FROM information_schema.schemata ORDER BY schema_name;"

run_test "Sample data in db_tenant_b.app.sample_data" \
  psql -U postgres -d db_tenant_b \
  -c "SELECT * FROM app.sample_data;"

run_test "Schema layout for db_tenant_c" \
  psql -U postgres -d db_tenant_c \
  -c "SELECT schema_name, schema_owner FROM information_schema.schemata ORDER BY schema_name;"

run_test "Sample data in db_tenant_c.app.sample_data" \
  psql -U postgres -d db_tenant_c \
  -c "SELECT * FROM app.sample_data;"

# -----------------------------------------------------
# Tenant A tests
# -----------------------------------------------------

run_test "Tenant A: can connect to db_tenant_a" \
  psql -U tenant_a_app -d db_tenant_a \
  -c "SELECT current_user, current_database(), current_schema;"

run_test "Tenant A: can read its own app.sample_data" \
  psql -U tenant_a_app -d db_tenant_a \
  -c "SELECT * FROM app.sample_data;"

run_expect_fail "Tenant A: cannot connect to db_tenant_b" \
  psql -U tenant_a_app -d db_tenant_b \
  -c "SELECT current_user, current_database();"

run_expect_fail "Tenant A: cannot create table in public schema" \
  psql -U tenant_a_app -d db_tenant_a \
  -c "CREATE TABLE public.hacked_a (id int);"

run_expect_fail "Tenant A: cannot create extension dblink" \
  psql -U tenant_a_app -d db_tenant_a \
  -c "CREATE EXTENSION dblink;"

run_expect_fail "Tenant A: cannot CREATE SCHEMA other_app" \
  psql -U tenant_a_app -d db_tenant_a \
  -c "CREATE SCHEMA other_app;"

run_expect_fail "Tenant A: cannot use search_path=public,app to create unqualified table" \
  psql -U tenant_a_app -d db_tenant_a \
  -c "SET search_path = public, app; CREATE TABLE hacked_unqualified_a (id int);"

run_expect_fail "Tenant A: cannot GRANT on its schema to another tenant role" \
  psql -U tenant_a_app -d db_tenant_a \
  -c "GRANT SELECT ON app.sample_data TO tenant_b_app;"

# -----------------------------------------------------
# Tenant A: Additional security tests
# -----------------------------------------------------

# Privilege escalation attempts
run_expect_fail "Tenant A: cannot ALTER ROLE to gain superuser" \
  psql -U tenant_a_app -d db_tenant_a \
  -c "ALTER ROLE tenant_a_app SUPERUSER;"

run_expect_fail "Tenant A: cannot CREATE ROLE" \
  psql -U tenant_a_app -d db_tenant_a \
  -c "CREATE ROLE malicious_role;"

run_expect_fail "Tenant A: cannot ALTER ROLE for other users" \
  psql -U tenant_a_app -d db_tenant_a \
  -c "ALTER ROLE tenant_b_app PASSWORD 'hacked';"

run_expect_fail "Tenant A: cannot SET ROLE to impersonate other tenants" \
  psql -U tenant_a_app -d db_tenant_a \
  -c "SET ROLE tenant_b_app;"

# Database object manipulation
run_expect_fail "Tenant A: cannot DROP other tenants' databases" \
  psql -U tenant_a_app -d db_tenant_a \
  -c "DROP DATABASE db_tenant_b;"

run_expect_fail "Tenant A: cannot ALTER DATABASE settings for other tenants" \
  psql -U tenant_a_app -d db_tenant_a \
  -c "ALTER DATABASE db_tenant_b SET timezone = 'UTC';"

run_expect_fail "Tenant A: cannot CREATE DATABASE" \
  psql -U tenant_a_app -d db_tenant_a \
  -c "CREATE DATABASE malicious_db;"

# Additional extension attacks
run_expect_fail "Tenant A: cannot create postgres_fdw extension" \
  psql -U tenant_a_app -d db_tenant_a \
  -c "CREATE EXTENSION postgres_fdw;"

run_expect_fail "Tenant A: cannot create file_fdw extension" \
  psql -U tenant_a_app -d db_tenant_a \
  -c "CREATE EXTENSION file_fdw;"

run_expect_fail "Tenant A: cannot use COPY TO file system" \
  psql -U tenant_a_app -d db_tenant_a \
  -c "COPY app.sample_data TO '/tmp/data_exfil.csv';"

run_expect_fail "Tenant A: cannot use COPY FROM file system" \
  psql -U tenant_a_app -d db_tenant_a \
  -c "COPY app.sample_data FROM '/etc/passwd';"

# Information disclosure
run_expect_fail "Tenant A: cannot query pg_shadow to see passwords" \
  psql -U tenant_a_app -d db_tenant_a \
  -c "SELECT * FROM pg_shadow;"

run_expect_fail "Tenant A: cannot query pg_authid to see passwords" \
  psql -U tenant_a_app -d db_tenant_a \
  -c "SELECT * FROM pg_authid;"

run_expect_fail "Tenant A: cannot access pg_stat_activity for other tenants" \
  psql -U tenant_a_app -d db_tenant_a \
  -c "SELECT * FROM pg_stat_activity WHERE datname = 'db_tenant_b';"

# Function/procedure security
run_expect_fail "Tenant A: cannot create SECURITY DEFINER function to escalate privileges" \
  psql -U tenant_a_app -d db_tenant_a \
  -c "CREATE FUNCTION app.escalate() RETURNS void SECURITY DEFINER AS \$\$ DROP DATABASE db_tenant_b; \$\$ LANGUAGE SQL;"

run_expect_fail "Tenant A: cannot create functions in pg_catalog" \
  psql -U tenant_a_app -d db_tenant_a \
  -c "CREATE FUNCTION pg_catalog.malicious() RETURNS void AS \$\$ SELECT 1; \$\$ LANGUAGE SQL;"

# Tablespace and file system
run_expect_fail "Tenant A: cannot create tablespaces" \
  psql -U tenant_a_app -d db_tenant_a \
  -c "CREATE TABLESPACE malicious_ts LOCATION '/tmp';"

run_expect_fail "Tenant A: cannot use pg_read_file() admin function" \
  psql -U tenant_a_app -d db_tenant_a \
  -c "SELECT pg_read_file('/etc/passwd');"

run_expect_fail "Tenant A: cannot use pg_ls_dir() admin function" \
  psql -U tenant_a_app -d db_tenant_a \
  -c "SELECT pg_ls_dir('/etc');"

# -----------------------------------------------------
# Tenant B tests
# -----------------------------------------------------

run_test "Tenant B: can connect to db_tenant_b" \
  psql -U tenant_b_app -d db_tenant_b \
  -c "SELECT current_user, current_database(), current_schema;"

run_test "Tenant B: can read its own app.sample_data" \
  psql -U tenant_b_app -d db_tenant_b \
  -c "SELECT * FROM app.sample_data;"

run_expect_fail "Tenant B: cannot connect to db_tenant_c" \
  psql -U tenant_b_app -d db_tenant_c \
  -c "SELECT current_user, current_database();"

run_expect_fail "Tenant B: cannot create table in public schema" \
  psql -U tenant_b_app -d db_tenant_b \
  -c "CREATE TABLE public.hacked_b (id int);"

run_expect_fail "Tenant B: cannot create extension dblink" \
  psql -U tenant_b_app -d db_tenant_b \
  -c "CREATE EXTENSION dblink;"

# -----------------------------------------------------
# Tenant C tests
# -----------------------------------------------------

run_test "Tenant C: can connect to db_tenant_c" \
  psql -U tenant_c_app -d db_tenant_c \
  -c "SELECT current_user, current_database(), current_schema;"

run_test "Tenant C: can read its own app.sample_data" \
  psql -U tenant_c_app -d db_tenant_c \
  -c "SELECT * FROM app.sample_data;"

run_expect_fail "Tenant C: cannot connect to db_tenant_a" \
  psql -U tenant_c_app -d db_tenant_a \
  -c "SELECT current_user, current_database();"

run_expect_fail "Tenant C: cannot create table in public schema" \
  psql -U tenant_c_app -d db_tenant_c \
  -c "CREATE TABLE public.hacked_c (id int);"

run_expect_fail "Tenant C: cannot create extension dblink" \
  psql -U tenant_c_app -d db_tenant_c \
  -c "CREATE EXTENSION dblink;"

echo
echo "==================================================="
echo "  Hardened isolation tests complete."
echo "==================================================="

if [ "$FAILURES" -gt 0 ]; then
  echo "One or more tests FAILED. Total failures: $FAILURES"
  exit 1
else
  echo "All tests PASSED."
  exit 0
fi
