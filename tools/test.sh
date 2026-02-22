#!/bin/bash

# test.sh - Run tests against the PostgreSQL extension using psql
# Usage: ./test.sh [database_name] [sql_file]

set -e # Exit immediately if a command exits with a non-zero status

DB="${1:-morbac_test}"
SQL_FILE="${2:-pg_morbac.sql}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
TEST_DIR="$PROJECT_DIR/tests"

if [ ! -f "$PROJECT_DIR/$SQL_FILE" ]; then
    echo "Error: SQL file not found: $SQL_FILE" >&2
    echo "Run 'make build' to generate the required file" >&2
    exit 1
fi

if [ ! -d "$TEST_DIR" ]; then
    echo "Error: test directory not found: $TEST_DIR" >&2
    exit 1
fi

if ! psql -d "$DB" -c '\q' 2>/dev/null; then
    echo "Error: cannot connect to database: $DB" >&2
    echo "Ensure the database exists and is accessible" >&2
    exit 1
fi

echo "Testing $SQL_FILE on database $DB"

psql -d "$DB" -f "$PROJECT_DIR/$SQL_FILE" -q

if [ -f "$TEST_DIR/00_setup.sql" ]; then
    psql -d "$DB" -f "$TEST_DIR/00_setup.sql" -q
fi

for test_file in "$TEST_DIR"/[0-9][0-9]_*.sql; do
    if [ -f "$test_file" ]; then
        test_name=$(basename "$test_file" .sql)
        echo "Running: $test_name"
        psql -d "$DB" -f "$test_file" -q
    fi
done

echo "All tests completed"
