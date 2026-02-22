#!/bin/bash

# docker_start.sh - Start a PostgreSQL Docker container
# Usage: ./docker_start.sh [container_name] [port]

set -e # Exit immediately if a command exits with a non-zero status

CONTAINER="${1:-postgres}"
PORT="${2:-5432}"
POSTGRES_PASSWORD="${POSTGRES_PASSWORD:-postgres}"
POSTGRES_USER="${POSTGRES_USER:-postgres}"

if docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER}$"; then
    if docker ps --format '{{.Names}}' | grep -q "^${CONTAINER}$"; then
        echo "Container $CONTAINER is already running"
        exit 0
    else
        echo "Starting existing container $CONTAINER"
        docker start "$CONTAINER"
        sleep 2
    fi
else
    echo "Creating and starting container $CONTAINER"
    docker run -d \
        --name "$CONTAINER" \
        -e POSTGRES_PASSWORD="$POSTGRES_PASSWORD" \
        -e POSTGRES_USER="$POSTGRES_USER" \
        -p "${PORT}:5432" \
        postgres:latest
    sleep 3
fi

echo "Waiting for PostgreSQL to be ready..."
for i in {1..30}; do
    if docker exec "$CONTAINER" psql -U "$POSTGRES_USER" -c '\q'; then
        echo "PostgreSQL is ready in container $CONTAINER"
        exit 0
    fi
    sleep 1
done

echo "Error: PostgreSQL did not become ready in time" >&2
exit 1
