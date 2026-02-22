#!/bin/bash

# uninstall_docker.sh - Uninstall the PostgreSQL extension from a Docker container
# Usage: ./uninstall_docker.sh [container_name] [project_name]

set -e # Exit immediately if a command exits with a non-zero status

CONTAINER="${1:-postgres}"
PROJECT_FILENAME="${2:-pg_morbac}"

if ! docker ps --format '{{.Names}}' | grep -q "^${CONTAINER}$"; then
    echo "Error: Docker container not running: $CONTAINER" >&2
    exit 1
fi

docker exec "$CONTAINER" sh -c "
    EXTDIR=\$(pg_config --sharedir)/extension
    rm -f \$EXTDIR/${PROJECT_FILENAME}.control
    rm -f \$EXTDIR/${PROJECT_FILENAME}--*.sql
"

echo "Uninstalled ${PROJECT_FILENAME} from container ${CONTAINER}"
