# Makefile for morbac_pg PostgreSQL Extension
# Multi-OrBAC: Organization-Based Access Control

EXTENSION = morbac_pg

# Read version from control file
EXTVERSION = $(shell grep default_version $(EXTENSION).control | sed "s/default_version = '\(.*\)'/\1/")

# For development, work on unversioned file
DEV_SQL = $(EXTENSION).sql
DATA = $(EXTENSION)--$(EXTVERSION).sql
DOCS = README.md

# PostgreSQL extension build
PG_CONFIG = pg_config
PGXS := $(shell $(PG_CONFIG) --pgxs)
include $(PGXS)

# Custom targets

# Create versioned release file from development file
.PHONY: release
release:
	@echo "Preparing release $(EXTVERSION)..."
	@if [ ! -f $(DEV_SQL) ]; then \
		echo "Error: $(DEV_SQL) not found"; \
		exit 1; \
	fi
	cp $(DEV_SQL) $(DATA)
	@echo "Created $(DATA)"
	@echo "Ready to commit and tag with: git tag v$(EXTVERSION)"

# Install extension in PostgreSQL (creates versioned file if needed)
.PHONY: install
install: release
	@echo "Installing morbac_pg extension..."
	$(MAKE) -f Makefile install

# Run tests with development file in temporary database
.PHONY: test
test:
	@echo "Testing with development file..."
	-dropdb morbac_test 2>/dev/null || true
	createdb morbac_test
	psql -d morbac_test -f $(DEV_SQL)
	psql -d morbac_test -f test_morbac.sql
	dropdb morbac_test
	@echo "Test completed."

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
	@echo "Development:"
	@echo "  Edit morbac_pg.sql (unversioned) for daily development"
	@echo ""
	@echo "  make test         - Test with development file"
	@echo "  make release      - Create versioned file from morbac_pg.sql"
	@echo "  make install      - Create release and install extension"
	@echo "  make uninstall    - Uninstall extension from PostgreSQL"
	@echo "  make help         - Show this help"
	@echo ""
	@echo "Workflow:"
	@echo "  1. Edit morbac_pg.sql (version-free development)"
	@echo "  2. make test (test your changes)"
	@echo "  3. Update version in morbac_pg.control"
	@echo "  4. make release (creates morbac_pg--X.Y.Z.sql)"
	@echo "  5. git tag vX.Y.Z && git push --tags"
	@echo ""
