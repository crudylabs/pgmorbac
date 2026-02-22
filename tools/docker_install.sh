#!/bin/bash

# docker_install.sh - Install the PostgreSQL extension to a Docker container
# Usage: ./docker_install.sh [container_name] [project_name] [version]

set -e # Exit immediately if a command exits with a non-zero status

CONTAINER="${1:-postgres}"
PROJECT_FILENAME="${2:-pgmorbac}"
PROJECT_VERSION="${3}"

if [ -z "$PROJECT_VERSION" ]; then
    SCRIPT_DIR=$(dirname "$0")
    CONTROL_FILE="${PROJECT_FILENAME}.control"
    PROJECT_VERSION=$("$SCRIPT_DIR/get_version.sh" "$CONTROL_FILE")
fi

if [ -z "$PROJECT_VERSION" ]; then
    echo "Error: could not detect version" >&2
    exit 1
fi

SQL_FILE="${PROJECT_FILENAME}--${PROJECT_VERSION}.sql"
CONTROL_FILE="${PROJECT_FILENAME}.control"

if [ ! -f "$SQL_FILE" ]; then
    echo "Error: versioned SQL file not found: $SQL_FILE" >&2
    exit 1
fi

if [ ! -f "$CONTROL_FILE" ]; then
    echo "Error: control file not found: $CONTROL_FILE" >&2
    exit 1
fi

if ! docker ps --format '{{.Names}}' | grep -q "^${CONTAINER}$"; then
    echo "Error: Docker container not running: $CONTAINER" >&2
    exit 1
fi

docker exec "$CONTAINER" mkdir -p /tmp/pgmorbac
docker cp "$CONTROL_FILE" "$CONTAINER:/tmp/pgmorbac/"
docker cp "$SQL_FILE" "$CONTAINER:/tmp/pgmorbac/"

docker exec "$CONTAINER" sh -c "
    EXTDIR=\$(pg_config --sharedir)/extension
    cp /tmp/pgmorbac/${CONTROL_FILE} \$EXTDIR/
    cp /tmp/pgmorbac/${SQL_FILE} \$EXTDIR/
    rm -rf /tmp/pgmorbac
"

echo "Installed ${PROJECT_FILENAME} v${PROJECT_VERSION} to container ${CONTAINER}"
