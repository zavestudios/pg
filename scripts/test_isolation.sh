#!/usr/bin/env bash
# scripts/test_isolation.sh
#
# Multi-tenant Postgres isolation + guardrail tests
# - Runs psql inside the running container (docker exec)
# - Uses per-tenant passwords via PGPASSWORD (dev-only)
# - Designed to be run via: make test   (tee handled by Makefile)
#
# Exit codes:
#   0 = all tests passed
#   1 = one or more tests failed

set -euo pipefail

CONTAINER_NAME="pg-multitenant"

# Tenant DB passwords (dev-only; match init/01_init_tenants.sql)
TENANT_A_PW="tenant_a_pw"
TENANT_B_PW="tenant_b_pw"
TENANT_C_PW="tenant_c_pw"

# ANSI Colors
GREEN="\033[0;32m"
RED="\033[0;31m"
YELLOW="\033[1;33m"
NC="\033[0m"

FAILURES=0

# ------------------------------------------------------------
# Helpers
# ------------------------------------------------------------

section() {
  echo -e "\n${YELLOW}------------------------------------------------------------${NC}"
  echo -e "${YELLOW}$1${NC}"
  echo -e "${YELLOW}------------------------------------------------------------${NC}"
}

run_test() {
  local description="$1"
  shift

  echo -e "${YELLOW}[TEST]${NC} $description"
  if "$@" >/dev/null 2>&1; then
    echo -e "  ${GREEN}PASS${NC}"
  else
    echo -e "  ${RED}FAIL${NC}"
    FAILURES=$((FAILURES + 1))
  fi
}

run_expect_fail() {
  local description="$1"
  shift

  echo -e "${YELLOW}[NEG]${NC} $description"
  if "$@" >/dev/null 2>&1; then
    echo -e "  ${RED}UNEXPECTED SUCCESS${NC}"
    FAILURES=$((FAILURES + 1))
  else
    echo -e "  ${GREEN}PASS (blocked as expected)${NC}"
  fi
}

# psql wrappers (execute inside container with proper credentials)
psql_tenant_a() {
  docker exec "$CONTAINER_NAME" env \
    PGHOST=/var/run/postgresql \
    PGPASSWORD="$TENANT_A_PW" \
    psql -v ON_ERROR_STOP=1 -U tenant_a_app "$@"
}

psql_tenant_b() {
  docker exec "$CONTAINER_NAME" env \
    PGHOST=/var/run/postgresql \
    PGPASSWORD="$TENANT_B_PW" \
    psql -v ON_ERROR_STOP=1 -U tenant_b_app "$@"
}

psql_tenant_c() {
  docker exec "$CONTAINER_NAME" env \
    PGHOST=/var/run/postgresql \
    PGPASSWORD="$TENANT_C_PW" \
    psql -v ON_ERROR_STOP=1 -U tenant_c_app "$@"
}

# ------------------------------------------------------------
# TEST SUITE
# ------------------------------------------------------------

section "Connectivity & Basic Positive Tests (Tenant A)"

run_test "Tenant A: can connect to db_tenant_a" \
  psql_tenant_a -d db_tenant_a -c "SELECT current_user;"

run_test "Tenant A: can read own sample_data" \
  psql_tenant_a -d db_tenant_a -c "SELECT * FROM app.sample_data;"

section "Negative Isolation Tests (Tenant A)"

run_expect_fail "Tenant A: cannot connect to db_tenant_b" \
  psql_tenant_a -d db_tenant_b -c "SELECT 1;"

run_expect_fail "Tenant A: cannot create table in public schema" \
  psql_tenant_a -d db_tenant_a -c "CREATE TABLE public.hacked_a(id int);"

run_expect_fail "Tenant A: cannot create extension dblink" \
  psql_tenant_a -d db_tenant_a -c "CREATE EXTENSION dblink;"

run_test "Tenant A: cannot grant privileges to tenant_b_app" \
  bash -c "
    psql_tenant_a -d db_tenant_a -c \"GRANT SELECT ON app.sample_data TO tenant_b_app;\" >/dev/null 2>&1 || true
    docker exec pg-multitenant env PGPASSWORD=supersecret \
      psql -U postgres -d db_tenant_a -Atc \"
        SELECT count(*)
        FROM information_schema.role_table_grants
        WHERE grantee='tenant_b_app'
          AND table_schema='app'
          AND table_name='sample_data';
      \" | grep -qx '0'
  "

run_expect_fail "Tenant A: cannot bypass search_path to create unqualified table" \
  psql_tenant_a -d db_tenant_a -c "SET search_path = public, app; CREATE TABLE hacked_unqualified_a(id int);"

section "Operational Guardrails"

# If statement_timeout is set low (e.g., 3s), pg_sleep(10) should be canceled.
run_expect_fail "Tenant A: statement_timeout enforced (pg_sleep should be canceled)" \
  psql_tenant_a -d db_tenant_a -c "SELECT pg_sleep(10);"

section "Connection Limit Enforcement"

# This test assumes you've set a low per-role CONNECTION LIMIT for tenant_a_app
# (e.g., 2) so that starting 3 concurrent sessions will exceed it.
#
# Note: We intentionally do not count expected failures from this section as
# fatal unless *all* sessions succeed.
set +e

psql_tenant_a -d db_tenant_a -c "SELECT pg_sleep(8);" >/dev/null 2>&1 &
p1=$!
psql_tenant_a -d db_tenant_a -c "SELECT pg_sleep(8);" >/dev/null 2>&1 &
p2=$!
psql_tenant_a -d db_tenant_a -c "SELECT pg_sleep(8);" >/dev/null 2>&1 &
p3=$!

wait $p1; rc1=$?
wait $p2; rc2=$?
wait $p3; rc3=$?

set -e

if [ $rc1 -ne 0 ] || [ $rc2 -ne 0 ] || [ $rc3 -ne 0 ]; then
  echo -e "${GREEN}PASS: connection limit enforced${NC}"
else
  echo -e "${RED}FAIL: all sessions succeeded (limit too high or not applied)${NC}"
  FAILURES=$((FAILURES + 1))
fi

section "Final Result"

if [ "$FAILURES" -eq 0 ]; then
  echo -e "${GREEN}ALL TESTS PASSED${NC}"
  exit 0
else
  echo -e "${RED}${FAILURES} TESTS FAILED${NC}"
  exit 1
fi
