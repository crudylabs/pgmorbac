# Makefile for pgmorbac PostgreSQL Extension
# Multi-OrBAC: Organization-Based Access Control

PROJECT_FILENAME = pgmorbac

# Read version from control file using centralized script
PROJECT_VERSION = $(shell ./tools/get_version.sh $(PROJECT_FILENAME).control)

# Docker configuration
DOCKER_CONTAINER ?= pgmorbac_postgres_test
DOCKER_PORT ?= 5432

# For development, work on source files in src/
SRC_DIR = src
OUTPUT_DEV_FILENAME = $(PROJECT_FILENAME).sql
OUTPUT_RELEASE_FILENAME = $(PROJECT_FILENAME)--$(PROJECT_VERSION).sql

# PostgreSQL Extension build
PG_CONFIG = pg_config
PGXS := $(shell $(PG_CONFIG) --pgxs)
include $(PGXS)

# Custom targets

# Build the extension SQL file from source components
.PHONY: build
build:
	@./tools/build.sh $(SRC_DIR) $(OUTPUT_DEV_FILENAME)
	@if [ ! -f $(OUTPUT_DEV_FILENAME) ]; then \
		echo "Error: Build failed" >&2; \
		exit 1; \
	fi

# Rename development file to versioned release file
.PHONY: release
release: build
	mv $(OUTPUT_DEV_FILENAME) $(OUTPUT_RELEASE_FILENAME)
	@echo "Release $(PROJECT_VERSION) built at $(OUTPUT_RELEASE_FILENAME)."

# Build and install extension in PostgreSQL
.PHONY: install
install: build
	@cp $(OUTPUT_DEV_FILENAME) $(OUTPUT_RELEASE_FILENAME)
	@./tools/install.sh $(PROJECT_FILENAME) $(PROJECT_VERSION)

.PHONY: test
test: install
	@echo "Running tests..."
	@dropdb morbac_test 2>/dev/null || true
	@createdb morbac_test
	@./tools/test.sh morbac_test
	@dropdb morbac_test

# Uninstall extension from PostgreSQL
.PHONY: uninstall
uninstall:
	@echo "Uninstalling $(PROJECT_FILENAME)..."
	@./tools/uninstall.sh $(PROJECT_FILENAME)

# Clean up generated files
.PHONY: clean
clean:
	@rm -f $(OUTPUT_DEV_FILENAME) $(OUTPUT_RELEASE_FILENAME)

# Start PostgreSQL Docker container
.PHONY: docker-start
docker-start:
	@./tools/docker_start.sh $(DOCKER_CONTAINER) $(DOCKER_PORT)

# Stop PostgreSQL Docker container
.PHONY: docker-stop
docker-stop:
	@./tools/docker_stop.sh $(DOCKER_CONTAINER)

# Remove PostgreSQL Docker container
.PHONY: docker-clean
docker-clean:
	@./tools/docker_clean.sh $(DOCKER_CONTAINER)

# Build and install extension in Docker container
.PHONY: docker-install
docker-install: build docker-start
	@cp $(OUTPUT_DEV_FILENAME) $(OUTPUT_RELEASE_FILENAME)
	@./tools/docker_install.sh $(DOCKER_CONTAINER) $(PROJECT_FILENAME) $(PROJECT_VERSION)

# Uninstall extension from Docker container
.PHONY: docker-uninstall
docker-uninstall:
	@./tools/docker_uninstall.sh $(DOCKER_CONTAINER) $(PROJECT_FILENAME)

# Build and run tests in Docker container
.PHONY: docker-test
docker-test: docker-install
	@echo "Running tests in Docker..."
	@./tools/docker_test.sh $(DOCKER_CONTAINER) morbac_test postgres

# Bump version across all relevant files
.PHONY: bump-version
bump-version:
	@if [ -z "$(VERSION)" ]; then \
		echo "Usage: make bump-version VERSION=X.Y.Z"; \
		exit 1; \
	fi
	@./tools/bump_version.sh $(VERSION)

# Show help
.PHONY: help
help:
	@echo "pgmorbac Makefile - Build and manage the PostgreSQL extension"
	@echo ""
	@echo "Makefile targets:"
	@echo "  make build            - Build $(OUTPUT_DEV_FILENAME) from src/"
	@echo "  make release          - Build versioned $(PROJECT_FILENAME)--X.Y.Z.sql from src/"
	@echo "  make check            - Build and run test suite"
	@echo "  make install          - Build and install $(PROJECT_FILENAME) to PostgreSQL"
	@echo "  make uninstall        - Uninstall $(PROJECT_FILENAME) from PostgreSQL"
	@echo "  make clean            - Clean up generated files"
	@echo "  make bump-version     - Bump version in all files (e.g. make bump-version VERSION=1.1.0)"
	@echo "  make help             - Show this help"
	@echo ""
	@echo "Docker targets:"
	@echo "  make docker-start     - Start PostgreSQL Docker container"
	@echo "  make docker-stop      - Stop PostgreSQL Docker container"
	@echo "  make docker-clean     - Remove PostgreSQL Docker container"
	@echo "  make docker-install   - Build and install extension in Docker container"
	@echo "  make docker-uninstall - Uninstall extension from Docker container"
	@echo "  make docker-check     - Build and run test suite in Docker container"
	@echo ""
