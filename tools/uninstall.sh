#!/bin/bash

# uninstall.sh - Uninstall the PostgreSQL extension from the system's extension directory
# Usage: ./uninstall.sh [project_name]

set -e # Exit immediately if a command exits with a non-zero status

PROJECT_FILENAME="${1:-pgmorbac}"

if ! command -v pg_config &> /dev/null; then
    echo "Error: pg_config not found" >&2
    echo "Install: apt install postgresql-server-dev-all (Debian/Ubuntu), yum install postgresql-devel (RHEL/CentOS), or brew install postgresql (macOS)" >&2
    exit 1
fi

EXTDIR=$(pg_config --sharedir)/extension
if [ ! -d "$EXTDIR" ]; then
    echo "Error: extension directory not found: $EXTDIR" >&2
    exit 1
fi

CONTROL_FILE="$EXTDIR/${PROJECT_FILENAME}.control"
if [ ! -f "$CONTROL_FILE" ]; then
    echo "Warning: control file not found: $CONTROL_FILE" >&2
    echo "Extension may not be installed" >&2
fi

echo "Uninstalling ${PROJECT_FILENAME} from ${EXTDIR}"

# Remove control file
if [ -f "$CONTROL_FILE" ]; then
    rm -f "$CONTROL_FILE"
    echo "Removed: ${PROJECT_FILENAME}.control"
fi

# Remove all SQL files (versioned and upgrade scripts)
SQL_FILES_COUNT=$(find "$EXTDIR" -name "${PROJECT_FILENAME}--*.sql" -type f | wc -l)
if [ "$SQL_FILES_COUNT" -gt 0 ]; then
    find "$EXTDIR" -name "${PROJECT_FILENAME}--*.sql" -type f -exec rm -f {} \;
    echo "Removed: ${SQL_FILES_COUNT} SQL file(s)"
else
    echo "No SQL files found to remove"
fi

echo "Uninstallation complete. Drop the extension from databases with: DROP EXTENSION IF EXISTS ${PROJECT_FILENAME} CASCADE;"
