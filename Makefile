# Makefile for morbac_pg PostgreSQL Extension
# Multi-OrBAC: Organization-Based Access Control

EXTENSION = morbac_pg
EXTVERSION = 1.0

DATA = $(EXTENSION)--$(EXTVERSION).sql
DOCS = README.md

# PostgreSQL extension build
PG_CONFIG = pg_config
PGXS := $(shell $(PG_CONFIG) --pgxs)
include $(PGXS)

# Custom targets

# Install extension in PostgreSQL
.PHONY: install
install:
	@echo "Installing morbac_pg extension..."
	$(MAKE) -f Makefile install

# Run tests
.PHONY: test
test:
	@echo "Running morbac_pg tests..."
	psql -f test_morbac.sql

# Run tests on specific database
.PHONY: test-db
test-db:
	@if [ -z "$(DB)" ]; then \
		echo "Usage: make test-db DB=your_database"; \
		exit 1; \
	fi
	@echo "Running tests on database $(DB)..."
	psql -d $(DB) -f test_morbac.sql

# Run tests in dedicated test database
.PHONY: test
test:
	@echo "Creating test database morbac_test..."
	-dropdb morbac_test 2>/dev/null || true
	createdb morbac_test
	@echo "Running tests..."
	psql -d morbac_test -f test_morbac.sql
	@echo ""
	@echo "Tests completed. Database 'morbac_test' is available."
	@echo "To explore: psql -d morbac_test"
	@echo "To cleanup: dropdb morbac_test"

# Cleanup test database
.PHONY: cleanup
cleanup:
	@echo "Dropping test database..."
	-dropdb morbac_test 2>/dev/null && echo "Test database dropped." || echo "No test database found."

# Uninstall extension
.PHONY: uninstall
uninstall:
	@echo "Uninstalling morbac_pg extension..."
	$(MAKE) -f Makefile uninstall

# Show help
.PHONY: help
help:
	@echo "morbac_pg Makefile targets:"
	@echo ""
	@echo "  make install      - Install extension in PostgreSQL"
	@echo "  make uninstall    - Uninstall extension from PostgreSQL"
	@echo "  make test         - Run tests on default database"
	@echo "  make test-db DB=name - Run tests on specified database"
	@echo "  make test    - Create test DB, run tests, keep DB"
	@echo "  make cleanup      - Drop test database"
	@echo "  make help         - Show this help"
	@echo ""
	@echo "Quick start:"
	@echo "  make test    # Run complete test in isolated database"
	@echo ""
