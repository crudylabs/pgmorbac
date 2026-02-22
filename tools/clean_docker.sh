#!/bin/bash

# clean_docker.sh - Remove a PostgreSQL Docker container
# Usage: ./clean_docker.sh [container_name]

set -e # Exit immediately if a command exits with a non-zero status

CONTAINER="${1:-postgres}"

if ! docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER}$"; then
    echo "Container $CONTAINER does not exist"
    exit 0
fi

if docker ps --format '{{.Names}}' | grep -q "^${CONTAINER}$"; then
    echo "Stopping container $CONTAINER"
    docker stop "$CONTAINER"
fi

echo "Removing container $CONTAINER"
docker rm "$CONTAINER"
