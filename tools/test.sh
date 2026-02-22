#!/bin/bash

# test.sh - Run tests against the PostgreSQL extension using psql
# Usage: ./test.sh [database_name] [postgres_user]
# Note: This script expects the extension to be already installed via 'make install'

set -e # Exit immediately if a command exits with a non-zero status

DB="${1:-morbac_test}"
PG_USER="${2:-$USER}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
TEST_DIR="$PROJECT_DIR/tests"

if [ ! -d "$TEST_DIR" ]; then
    echo "Error: test directory not found: $TEST_DIR" >&2
    exit 1
fi

if ! psql -U "$PG_USER" -d "$DB" -c '\q'; then
    echo "Error: cannot connect to database: $DB" >&2
    echo "Ensure the database exists and is accessible" >&2
    exit 1
fi

echo "Running tests on database $DB"

total=0
passed=0
failed=0

set +e  # Temporarily disable exit on error to capture test failures

for test_file in "$TEST_DIR"/[0-9][0-9]_*.sql; do
    if [ -f "$test_file" ]; then
        test_name=$(basename "$test_file" .sql)
        echo "  - $test_name"
        ((total++))

        output=$(psql -U "$PG_USER" -d "$DB" -f "$test_file" 2>&1)
        exit_code=$?
        echo "$output"

        if [ $exit_code -eq 0 ] && ! echo "$output" | grep -qE "ERROR|FAILED"; then
            ((passed++))
        else
            ((failed++))
            echo "    FAILED"
        fi
    fi
done

set -e  # Re-enable exit on error

echo "Tests: $total total, $passed passed, $failed failed"

if [ $failed -gt 0 ]; then
    exit 1
fi
