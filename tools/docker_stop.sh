#!/bin/bash

# docker_stop.sh - Stop a PostgreSQL Docker container
# Usage: ./docker_stop.sh [container_name]

set -e # Exit immediately if a command exits with a non-zero status

CONTAINER="${1:-postgres}"

if ! docker ps --format '{{.Names}}' | grep -q "^${CONTAINER}$"; then
    echo "Container $CONTAINER is not running"
    exit 0
fi

echo "Stopping container $CONTAINER"
docker stop "$CONTAINER"
