#!/bin/bash

# docker_test.sh - Run tests in a Docker container
# Usage: ./docker_test.sh [container_name] [database_name] [sql_file]

set -e # Exit immediately if a command exits with a non-zero status

CONTAINER="${1:-postgres}"
DB="${2:-morbac_test}"
SQL_FILE="${3:-pg_morbac.sql}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

if [ ! -f "$PROJECT_DIR/$SQL_FILE" ]; then
    echo "Error: SQL file not found: $SQL_FILE" >&2
    exit 1
fi

if ! docker ps --format '{{.Names}}' | grep -q "^${CONTAINER}$"; then
    echo "Error: Docker container not running: $CONTAINER" >&2
    exit 1
fi

if ! docker exec "$CONTAINER" psql -U postgres -c '\q'; then
    echo "Error: PostgreSQL not accessible in container: $CONTAINER" >&2
    exit 1
fi

docker exec "$CONTAINER" psql -U postgres -c "DROP DATABASE IF EXISTS $DB" -q
docker exec "$CONTAINER" psql -U postgres -c "CREATE DATABASE $DB" -q

docker exec "$CONTAINER" mkdir -p /tmp/pg_morbac_test/tools
docker cp "$PROJECT_DIR/$SQL_FILE" "$CONTAINER:/tmp/pg_morbac_test/"
docker cp "$PROJECT_DIR/tests" "$CONTAINER:/tmp/pg_morbac_test/"
docker cp "$SCRIPT_DIR/test.sh" "$CONTAINER:/tmp/pg_morbac_test/tools/"

docker exec -w /tmp/pg_morbac_test "$CONTAINER" bash tools/test.sh "$DB" "$SQL_FILE"

docker exec "$CONTAINER" psql -U postgres -c "DROP DATABASE $DB" -q
docker exec "$CONTAINER" rm -rf /tmp/pg_morbac_test
