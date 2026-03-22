#!/bin/bash

# test.sh - Run tests against the PostgreSQL extension using psql
# Usage: ./test.sh [database_name] [postgres_user]
#
# Assertions in SQL test files must output rows whose value starts with:
#   CHECK PASS: <description>   — assertion passed
#   CHECK FAIL: <description>   — assertion failed
#
# Any SQL ERROR also counts as a failure.
# The script exits with code 1 if any file has failures or SQL errors.

set -e

DB="${1:-morbac_test}"
PG_USER="${2:-$USER}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
TEST_DIR="$PROJECT_DIR/tests"

if [ ! -d "$TEST_DIR" ]; then
    echo "Error: test directory not found: $TEST_DIR" >&2
    exit 1
fi

if ! psql -U "$PG_USER" -d "$DB" -c '\q' 2>/dev/null; then
    echo "Error: cannot connect to database: $DB" >&2
    echo "Ensure the database exists and is accessible" >&2
    exit 1
fi

echo "Running tests on database $DB"
echo ""

total_files=0
passed_files=0
failed_files=0
total_pass=0
total_fail=0

set +e  # Capture failures without aborting

for test_file in "$TEST_DIR"/[0-9][0-9]_*.sql; do
    [ -f "$test_file" ] || continue

    test_name=$(basename "$test_file" .sql)
    ((total_files++))

    output=$(psql -U "$PG_USER" -d "$DB" -f "$test_file" 2>&1)
    exit_code=$?

    # Count assertions
    file_pass=$(echo "$output" | grep -c "CHECK PASS:" || true)
    file_fail=$(echo "$output" | grep -c "CHECK FAIL:" || true)
    file_errors=$(echo "$output" | grep -c "^psql:.*ERROR:" || true)

    total_pass=$((total_pass + file_pass))
    total_fail=$((total_fail + file_fail))

    if [ $exit_code -ne 0 ] || [ "$file_fail" -gt 0 ] || [ "$file_errors" -gt 0 ]; then
        ((failed_files++))
        echo "  [FAIL] $test_name — ${file_pass} passed, ${file_fail} failed, ${file_errors} SQL error(s)"
        # Print only failing lines for a focused view
        if [ "$file_errors" -gt 0 ]; then
            echo "$output" | grep "^psql:.*ERROR:" | sed 's/^/         /'
        fi
        if [ "$file_fail" -gt 0 ]; then
            echo "$output" | grep "CHECK FAIL:" | sed 's/^/         /'
        fi
    else
        ((passed_files++))
        echo "  [PASS] $test_name — ${file_pass} assertion(s) passed"
    fi
done

set -e

echo ""
echo "========================================"
echo "Files  : $total_files total | $passed_files passed | $failed_files failed"
echo "Checks : $((total_pass + total_fail)) total | $total_pass passed | $total_fail failed"
echo "========================================"

if [ $failed_files -gt 0 ]; then
    exit 1
fi
