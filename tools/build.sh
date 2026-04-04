#!/bin/bash

# build.sh - Build the PostgreSQL extension SQL file from source components
# Usage: ./build.sh [source_directory] [output_file]

set -e  # Exit immediately if a command exits with a non-zero status

SRC_DIR="${1:-src}"
OUTPUT="${2:-pgmorbac.sql}"

if [ ! -d "$SRC_DIR" ]; then
    echo "Error: source directory not found: $SRC_DIR" >&2
    echo "Ensure the source directory exists in the project root" >&2
    exit 1
fi

rm -f "$OUTPUT"

BUILD_FILES=(
    "header.sql"
    "types.sql"
    "config.sql"
    "organizations.sql"
    "activities.sql"
    "views.sql"
    "roles.sql"
    "hierarchy_functions.sql"
    "materialized_views.sql"
    "contexts.sql"
    "rules.sql"
    "cross_org_rules.sql"
    "user_rules.sql"
    "global_rules.sql"
    "system_principals.sql"
    "activity_view_bindings.sql"
    "obligations.sql"
    "audit.sql"
    "rls.sql"
    "role_assignments.sql"
    "auth_cache.sql"
    "validation.sql"
    "authorization.sql"
    "system_rls.sql"
    "footer.sql"
)

file_count=0

for filename in "${BUILD_FILES[@]}"; do
    filepath="$SRC_DIR/$filename"
    if [ -f "$filepath" ]; then
        cat "$filepath" >> "$OUTPUT"
        echo "" >> "$OUTPUT"
        ((file_count++))
    else
        echo "Warning: $filename not found, skipping" >&2
    fi
done

echo "Built $OUTPUT ($file_count files)"
