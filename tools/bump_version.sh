#!/bin/bash

# bump_version.sh - Bump pgmorbac version across all relevant files
# Usage: ./tools/bump_version.sh <new_version>
# Example: ./tools/bump_version.sh 1.1.0

set -e

NEW_VERSION="${1:-}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
CONTROL_FILE="$ROOT_DIR/pgmorbac.control"
META_FILE="$ROOT_DIR/META.json"
README_FILE="$ROOT_DIR/README.md"

# --- Validate input ---
if [ -z "$NEW_VERSION" ]; then
    echo "Usage: $0 <new_version>"
    echo "Example: $0 1.1.0"
    exit 1
fi

if ! echo "$NEW_VERSION" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+$'; then
    echo "Error: version must follow semver format X.Y.Z (e.g. 1.1.0)"
    exit 1
fi

# --- Get current version ---
OLD_VERSION=$(./tools/get_version.sh "$CONTROL_FILE")

if [ "$OLD_VERSION" = "$NEW_VERSION" ]; then
    echo "Already at version $NEW_VERSION, nothing to do."
    exit 0
fi

echo "Bumping version: $OLD_VERSION → $NEW_VERSION"

# --- pgmorbac.control ---
sed -i.bak "s/default_version = '$OLD_VERSION'/default_version = '$NEW_VERSION'/" "$CONTROL_FILE"
echo "  Updated $CONTROL_FILE"

# --- META.json ---
sed -i.bak \
    -e "s/\"version\": \"$OLD_VERSION\"/\"version\": \"$NEW_VERSION\"/g" \
    -e "s/pgmorbac--$OLD_VERSION\.sql/pgmorbac--$NEW_VERSION.sql/g" \
    "$META_FILE"
echo "  Updated $META_FILE"

# --- README.md (hardcoded version references in manual install section) ---
sed -i.bak \
    -e "s/pgmorbac--$OLD_VERSION\.sql/pgmorbac--$NEW_VERSION.sql/g" \
    "$README_FILE"
echo "  Updated $README_FILE"

# --- Clean up .bak files ---
find "$ROOT_DIR" -maxdepth 1 -name "*.bak" -delete
find "$ROOT_DIR/tools" -maxdepth 1 -name "*.bak" -delete

echo ""
echo "Done. Version is now $NEW_VERSION."
echo ""
echo "Next steps:"
echo "  1. Add a [$NEW_VERSION] section to CHANGELOG.md"
echo "  2. Run: make build"
echo "  3. Run: make test"
echo "  4. Commit: git commit -am \"chore: bump version to $NEW_VERSION\""
echo "  5. Tag:    git tag -a v$NEW_VERSION -m \"Release $NEW_VERSION\""
echo "  6. Push:   git push && git push --tags"
