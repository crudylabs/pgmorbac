#!/bin/bash

# build.sh - Build the PostgreSQL extension SQL file from source components
# Usage: ./build.sh [source_directory] [output_file]

set -e  # Exit immediately if a command exits with a non-zero status

SRC_DIR="${1:-src}"
OUTPUT="${2:-pg_morbac.sql}"

if [ ! -d "$SRC_DIR" ]; then
    echo "Error: source directory not found: $SRC_DIR" >&2
    echo "Ensure the source directory exists in the project root" >&2
    exit 1
fi

rm -f "$OUTPUT"

BUILD_FILES=("header.sql")

while IFS= read -r file; do
    BUILD_FILES+=("$file")
done < <(find "$SRC_DIR" -maxdepth 1 -name "*.sql" -type f ! -name "header.sql" ! -name "footer.sql" -exec basename {} \; | sort)

BUILD_FILES+=("footer.sql")

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
