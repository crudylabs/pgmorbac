#!/bin/bash

# install.sh - Install the PostgreSQL extension to the system's extension directory
# Usage: ./install.sh [project_name] [version]

set -e # Exit immediately if a command exits with a non-zero status

PROJECT_FILENAME="${1:-pg_morbac}"
PROJECT_VERSION="${2}"

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

CONTROL_FILE="${PROJECT_FILENAME}.control"
if [ ! -f "$CONTROL_FILE" ]; then
    echo "Error: control file not found: $CONTROL_FILE" >&2
    echo "Run this script from the project root directory" >&2
    exit 1
fi

if [ -z "$PROJECT_VERSION" ]; then
    SCRIPT_DIR=$(dirname "$0")
    PROJECT_VERSION=$("$SCRIPT_DIR/get_version.sh" "$CONTROL_FILE")
fi

if [ -z "$PROJECT_VERSION" ]; then
    echo "Error: could not detect version from $CONTROL_FILE" >&2
    exit 1
fi

SQL_FILE="${PROJECT_FILENAME}--${PROJECT_VERSION}.sql"
if [ ! -f "$SQL_FILE" ]; then
    echo "Error: versioned SQL file not found: $SQL_FILE" >&2
    echo "Run 'make build' to generate the required file" >&2
    exit 1
fi

echo "Installing ${PROJECT_FILENAME} v${PROJECT_VERSION} to ${EXTDIR}"
cp "$CONTROL_FILE" "$EXTDIR/"
mv "$SQL_FILE" "$EXTDIR/"

echo "Installation complete. Enable with: CREATE EXTENSION ${PROJECT_FILENAME};"
