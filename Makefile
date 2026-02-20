# Makefile for morbac_pg PostgreSQL Extension
# Multi-OrBAC: Organization-Based Access Control

EXTENSION = morbac_pg

# Read version from control file
EXTVERSION = $(shell grep default_version $(EXTENSION).control | sed "s/default_version = '\(.*\)'/\1/")

# For development, work on source files in src/
SRC_DIR = src
DEV_SQL = $(EXTENSION).sql
DATA = $(EXTENSION)--$(EXTVERSION).sql
DOCS = README.md

# PostgreSQL extension build
PG_CONFIG = pg_config
PGXS := $(shell $(PG_CONFIG) --pgxs)
include $(PGXS)

# Custom targets

# Build development SQL from source files
.PHONY: build
build:
	@echo "Building $(DEV_SQL) from source files..."
	@./tools/build.sh

# Create versioned release file from development file
.PHONY: release
release: build
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
test: build
	@echo "Testing with development file..."
	-dropdb morbac_test 2>/dev/null || true
	createdb morbac_test
	@./tools/test.sh morbac_test
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
	@echo "  Edit source files in src/ directory"
	@echo ""
	@echo "  make build        - Build morbac_pg.sql from src/ files"
	@echo "  make test         - Build and test in temporary database"
	@echo "  make release      - Build and create versioned file"
	@echo "  make install      - Build, release, and install extension"
	@echo "  make uninstall    - Uninstall extension from PostgreSQL"
	@echo "  make help         - Show this help"
	@echo ""
	@echo "Workflow:"
	@echo "  1. Edit source files in src/ directory"
	@echo "  2. make test (build and test your changes)"
	@echo "  3. Update version in morbac_pg.control"
	@echo "  4. make release (builds and creates morbac_pg--X.Y.Z.sql)"
	@echo "  5. git tag vX.Y.Z && git push --tags"
	@echo ""
	@echo ""
