#!/usr/bin/env bash
set -euo pipefail

CONTAINER_NAME="pg-multitenant"

# ANSI Colors
GREEN="\033[0;32m"
RED="\033[0;31m"
YELLOW="\033[1;33m"
NC="\033[0m"

FAILURES=0

# ------------------------------------------------------------
# Helper Functions
# ------------------------------------------------------------

run_test() {
  local description="$1"
  shift

  echo -e "${YELLOW}[TEST]${NC} $description"
  if docker exec "$CONTAINER_NAME" "$@" >/dev/null 2>&1; then
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
  if docker exec "$CONTAINER_NAME" "$@" >/dev/null 2>&1; then
    echo -e "  ${RED}UNEXPECTED SUCCESS${NC}"
    FAILURES=$((FAILURES + 1))
  else
    echo -e "  ${GREEN}PASS (blocked as expected)${NC}"
  fi
}

section() {
  echo -e "\n${YELLOW}------------------------------------------------------------${NC}"
  echo -e "${YELLOW}$1${NC}"
  echo -e "${YELLOW}------------------------------------------------------------${NC}"
}

# ------------------------------------------------------------
# TEST SUITE
# ------------------------------------------------------------

section "Connectivity & Basic Positive Tests (Tenant A)"

run_test "Tenant A: can connect to db_tenant_a" \
  psql -U tenant_a_app -d db_tenant_a -c "SELECT current_user;"

run_test "Tenant A: can read own sample_data" \
  psql -U tenant_a_app -d db_tenant_a -c "SELECT * FROM app.sample_data;"

# ------------------------------------------------------------
section "Negative Isolation Tests (Tenant A)"

run_expect_fail "Tenant A: cannot connect to db_tenant_b" \
  psql -U tenant_a_app -d db_tenant_b -c "SELECT 1;"

run_expect_fail "Tenant A: cannot create table in public schema" \
  psql -U tenant_a_app -d db_tenant_a -c "CREATE TABLE public.hacked_a(id int);"

run_expect_fail "Tenant A: cannot create extension dblink" \
  psql -U tenant_a_app -d db_tenant_a -c "CREATE EXTENSION dblink;"

run_expect_fail "Tenant A: cannot GRANT privileges to tenant_b_app" \
  psql -U tenant_a_app -d db_tenant_a -c "GRANT SELECT ON app.sample_data TO tenant_b_app;"

run_expect_fail "Tenant A: cannot bypass search_path to create unqualified table" \
  psql -U tenant_a_app -d db_tenant_a -c \
  "SET search_path = public, app; CREATE TABLE hacked_unqualified_a(id int);"

# ------------------------------------------------------------
section "Operational Guardrails"

run_expect_fail "statement_timeout enforced (pg_sleep should be canceled)" \
  psql -U tenant_a_app -d db_tenant_a -c "SELECT pg_sleep(10);"

# ------------------------------------------------------------
section "Connection Limit Enforcement"

set +e
docker exec "$CONTAINER_NAME" psql -U tenant_a_app -d db_tenant_a -c "SELECT pg_sleep(8);" >/dev/null 2>&1 &
p1=$!

docker exec "$CONTAINER_NAME" psql -U tenant_a_app -d db_tenant_a -c "SELECT pg_sleep(8);" >/dev/null 2>&1 &
p2=$!

docker exec "$CONTAINER_NAME" psql -U tenant_a_app -d db_tenant_a -c "SELECT pg_sleep(8);" >/dev/null 2>&1 &
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

# ------------------------------------------------------------
section "Final Result"

if [ "$FAILURES" -eq 0 ]; then
  echo -e "${GREEN}ALL TESTS PASSED${NC}"
  exit 0
else
  echo -e "${RED}$FAILURES TESTS FAILED${NC}"
  exit 1
fi
