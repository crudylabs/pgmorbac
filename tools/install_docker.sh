#!/bin/bash

# install_docker.sh - Install the PostgreSQL extension to a Docker container
# Usage: ./install_docker.sh [container_name] [project_name] [version]

set -e # Exit immediately if a command exits with a non-zero status

CONTAINER="${1:-postgres}"
PROJECT_FILENAME="${2:-pg_morbac}"
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

docker exec "$CONTAINER" mkdir -p /tmp/pg_morbac
docker cp "$CONTROL_FILE" "$CONTAINER:/tmp/pg_morbac/"
docker cp "$SQL_FILE" "$CONTAINER:/tmp/pg_morbac/"

docker exec "$CONTAINER" sh -c "
    EXTDIR=\$(pg_config --sharedir)/extension
    cp /tmp/pg_morbac/${CONTROL_FILE} \$EXTDIR/
    cp /tmp/pg_morbac/${SQL_FILE} \$EXTDIR/
    rm -rf /tmp/pg_morbac
"

echo "Installed ${PROJECT_FILENAME} v${PROJECT_VERSION} to container ${CONTAINER}"
