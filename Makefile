# ------------------------------------------------------------
# Multi-Tenant PostgreSQL Makefile
# ------------------------------------------------------------

CONTAINER=pg-multitenant
RESULTS_FILE=test-results.txt
PSQL=docker exec $(CONTAINER) psql -U postgres

# ANSI Colors
GREEN=\033[0;32m
RED=\033[0;31m
YELLOW=\033[1;33m
NC=\033[0m

# ------------------------------------------------------------
# Help (default target)
# ------------------------------------------------------------
help:
	@echo ""
	@echo "Available targets:"
	@echo ""
	@echo "  make up        - Start PostgreSQL container"
	@echo "  make down      - Stop container (keep data)"
	@echo "  make reset     - Destroy volumes and recreate DB from scratch"
	@echo "  make logs      - Tail PostgreSQL logs"
	@echo "  make psql      - Open psql shell inside container"
	@echo "  make test      - Run full isolation test suite (color output + tee)"
	@echo "  make status    - Show Docker container status"
	@echo ""

.DEFAULT_GOAL := help

# ------------------------------------------------------------
# Start PostgreSQL
# ------------------------------------------------------------
up:
	@echo "$(YELLOW)Starting PostgreSQL...$(NC)"
	docker compose up -d
	@echo "$(GREEN)PostgreSQL is up.$(NC)"

# ------------------------------------------------------------
# Stop PostgreSQL (keep volumes)
# ------------------------------------------------------------
down:
	@echo "$(YELLOW)Stopping PostgreSQL container...$(NC)"
	docker compose down
	@echo "$(GREEN)Container stopped.$(NC)"

# ------------------------------------------------------------
# Reset database completely
# ------------------------------------------------------------
reset:
	@echo "$(RED)WARNING: Destroying database volumes...$(NC)"
	docker compose down --volumes --remove-orphans
	@echo "$(YELLOW)Recreating PostgreSQL from scratch...$(NC)"
	docker compose up -d
	@echo "$(GREEN)Database reset complete.$(NC)"


# ------------------------------------------------------------
# Logs
# ------------------------------------------------------------
logs:
	docker compose logs -f $(CONTAINER)

# ------------------------------------------------------------
# Open psql session as postgres
# ------------------------------------------------------------
psql:
	$(PSQL)

# ------------------------------------------------------------
# Status
# ------------------------------------------------------------
status:
	docker ps | grep $(CONTAINER) || true

# ------------------------------------------------------------
# Tests (color + tee output)
# ------------------------------------------------------------
test:
	@echo "$(YELLOW)Running test suite...$(NC)"
	./scripts/test_isolation.sh 2>&1 | tee $(RESULTS_FILE)
	@echo ""
	@echo "$(GREEN)Test results written to $(RESULTS_FILE).$(NC)"
