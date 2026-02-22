#!/bin/bash

# get_version.sh - Extract version from PostgreSQL extension control file
# Usage: ./get_version.sh [control_file]

set -e  # Exit immediately if a command exits with a non-zero status

CONTROL_FILE="${1:-pgmorbac.control}"

if [ ! -f "$CONTROL_FILE" ]; then
    echo "Error: control file not found: $CONTROL_FILE" >&2
    exit 1
fi

VERSION=$(grep "default_version" "$CONTROL_FILE" | sed "s/default_version = '\(.*\)'/\1/")

if [ -z "$VERSION" ]; then
    echo "Error: could not extract version from $CONTROL_FILE" >&2
    exit 1
fi

echo "$VERSION"
