#!/bin/bash

# docker_test.sh - Run tests in a Docker container
# Usage: ./docker_test.sh [container_name] [database_name] [postgres_user]

set -e # Exit immediately if a command exits with a non-zero status

CONTAINER="${1:-postgres}"
DB="${2:-morbac_test}"
PG_USER="${3:-postgres}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

if ! docker ps --format '{{.Names}}' | grep -q "^${CONTAINER}$"; then
    echo "Error: Docker container not running: $CONTAINER" >&2
    exit 1
fi

if ! docker exec "$CONTAINER" psql -U "$PG_USER" -c '\q' 2>/dev/null; then
    echo "Error: PostgreSQL not accessible in container: $CONTAINER" >&2
    exit 1
fi

if [ ! -d "$PROJECT_DIR/tests" ]; then
    echo "Error: tests directory not found" >&2
    exit 1
fi

echo "Creating test database..."
docker exec "$CONTAINER" psql -U "$PG_USER" -c "DROP DATABASE IF EXISTS $DB" -q
docker exec "$CONTAINER" psql -U "$PG_USER" -c "CREATE DATABASE $DB" -q

echo "Copying test files to container..."
docker exec "$CONTAINER" mkdir -p /tmp/pg_morbac_test/tools
docker cp "$PROJECT_DIR/tests" "$CONTAINER:/tmp/pg_morbac_test/"
docker cp "$SCRIPT_DIR/test.sh" "$CONTAINER:/tmp/pg_morbac_test/tools/"

echo "Running tests..."
docker exec -w /tmp/pg_morbac_test "$CONTAINER" bash tools/test.sh "$DB" "$PG_USER"

# Cleanup
docker exec "$CONTAINER" psql -U "$PG_USER" -c "DROP DATABASE $DB" -q
docker exec "$CONTAINER" rm -rf /tmp/pg_morbac_test
