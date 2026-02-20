#!/bin/bash
# =============================================================================
# Build Script for morbac_pg Extension
# =============================================================================
# Concatenates SQL source files in src/ into a single morbac_pg.sql file
# Order: header first, then specific order for dependencies, footer last
# =============================================================================

set -e

SRC_DIR="src"
OUTPUT="morbac_pg.sql"

echo "Building morbac_pg.sql from source files..."

# Check if src directory exists
if [ ! -d "$SRC_DIR" ]; then
    echo "Error: $SRC_DIR directory not found"
    exit 1
fi

# Remove old output file
rm -f "$OUTPUT"

# Define build order (dependencies matter)
BUILD_ORDER=(
    "header.sql"
    "types.sql"
    "config.sql"
    "organizations.sql"
    "roles.sql"
    "activities.sql"
    "views.sql"
    "contexts.sql"
    "rules.sql"
    "cross_org_rules.sql"
    "admin_rules.sql"
    "audit.sql"
    "hierarchy_functions.sql"
    "materialized_views.sql"
    "validation.sql"
    "auth_cache.sql"
    "authorization.sql"
    "policy_dsl.sql"
    "rls.sql"
    "obligations.sql"
    "admin_helpers.sql"
    "footer.sql"
)

file_count=0

# Build in specified order
for filename in "${BUILD_ORDER[@]}"; do
    filepath="$SRC_DIR/$filename"
    if [ -f "$filepath" ]; then
        echo "  Adding: $filename"
        cat "$filepath" >> "$OUTPUT"
        echo "" >> "$OUTPUT"
        ((file_count++))
    else
        echo "  Warning: $filename not found, skipping"
    fi
done

echo "Built $OUTPUT successfully ($file_count source files)"
