#!/bin/bash
# Installation script for morbac_pg extension

set -e

echo "=================================="
echo "morbac_pg Extension Installer"
echo "=================================="
echo ""

# Check if running as root or with sudo
if [ "$EUID" -ne 0 ] && [ -z "$SUDO_USER" ]; then
    echo "This script needs to copy files to PostgreSQL extension directory."
    echo "Please run with sudo or as root."
    echo ""
    echo "Usage: sudo ./install.sh"
    exit 1
fi

# Check if pg_config is available
if ! command -v pg_config &> /dev/null; then
    echo "Error: pg_config not found in PATH"
    echo "Please install PostgreSQL development packages:"
    echo "  Ubuntu/Debian: sudo apt-get install postgresql-server-dev-all"
    echo "  RedHat/CentOS: sudo yum install postgresql-devel"
    echo "  macOS: brew install postgresql"
    exit 1
fi

# Get PostgreSQL extension directory
EXTDIR=$(pg_config --sharedir)/extension

echo "PostgreSQL extension directory: $EXTDIR"
echo ""

# Check if directory exists
if [ ! -d "$EXTDIR" ]; then
    echo "Error: Extension directory does not exist: $EXTDIR"
    exit 1
fi

# Detect version from control file
CONTROL_FILE="morbac_pg.control"
if [ ! -f "$CONTROL_FILE" ]; then
    echo "Error: $CONTROL_FILE not found"
    echo "Please run this script from the morbac_pg directory"
    exit 1
fi

VERSION=$(grep "default_version" "$CONTROL_FILE" | sed "s/default_version = '\(.*\)'/\1/")
if [ -z "$VERSION" ]; then
    echo "Error: Could not detect version from $CONTROL_FILE"
    exit 1
fi

SQL_FILE="morbac_pg--${VERSION}.sql"

echo "Detected version: $VERSION"
echo ""

# Check if versioned SQL file exists
if [ ! -f "$SQL_FILE" ]; then
    echo "Error: $SQL_FILE not found"
    echo "Please run 'make build' first to create the versioned SQL file"
    exit 1
fi

# Copy extension files
echo "Installing extension files..."
cp -v morbac_pg.control "$EXTDIR/"
cp -v "$SQL_FILE" "$EXTDIR/"

echo ""
echo "=================================="
echo "Installation complete!"
echo "=================================="
echo ""
echo "To use the extension in your database:"
echo ""
echo "  psql -d your_database -c 'CREATE EXTENSION morbac_pg;'"
echo ""
echo "To run tests:"
echo ""
echo "  make test"
echo ""
echo "For more information, see README.md"
echo ""
