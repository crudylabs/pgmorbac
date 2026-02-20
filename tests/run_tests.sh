#!/bin/bash
# =============================================================================
# Test Runner for morbac_pg Extension
# =============================================================================
# Runs all tests in order, loading setup data and executing each test file.
# Usage: ./run_tests.sh [database_name]
# =============================================================================

set -e

# Database name (default: morbac_test)
DB="${1:-morbac_test}"
TEST_DIR="$(dirname "$0")"

echo "======================================"
echo "morbac_pg Extension Test Suite"
echo "======================================"
echo "Database: $DB"
echo ""

# Install extension
echo "=== Installing Extension ==="
psql -d "$DB" -f "$TEST_DIR/../morbac_pg.sql"

# Load common setup
echo ""
echo "=== Loading Test Setup ==="
psql -d "$DB" -f "$TEST_DIR/00_setup.sql"

# Run all test files in order
echo ""
echo "=== Running Tests ==="

for test_file in "$TEST_DIR"/[0-9][0-9]_*.sql; do
    if [ -f "$test_file" ]; then
        test_name=$(basename "$test_file" .sql)
        echo ""
        echo "--- Running: $test_name ---"
        psql -d "$DB" -f "$test_file"
    fi
done

echo ""
echo "======================================"
echo "All Tests Completed"
echo "======================================"
