# Development Workflow

## Version Management

This extension uses a single-source version approach:

- **Version source of truth**: `morbac_pg.control` (the `default_version` field)
- **Development file**: `morbac_pg.sql` (unversioned, for daily work)
- **Release files**: `morbac_pg--X.Y.Z.sql` (generated, git-ignored)

## Daily Development

1. **Edit**: Work on `morbac_pg.sql` (no version numbers in the file)
2. **Test**: Run `make test` to test changes in a temporary database
3. **Commit**: Commit `morbac_pg.sql` to git regularly

## Release Process

When ready to release a new version:

1. **Update version**: Edit `morbac_pg.control` and change `default_version`
   ```
   default_version = '1.1.0'
   ```

2. **Create release**: Run `make release`
   - Reads version from `.control` file
   - Copies `morbac_pg.sql` → `morbac_pg--X.Y.Z.sql`

3. **Test**: Run `make test` with the versioned file

4. **Tag in git**:
   ```bash
   git add morbac_pg.control morbac_pg--X.Y.Z.sql
   git commit -m "Release vX.Y.Z"
   git tag vX.Y.Z
   git push origin main --tags
   ```

## Upgrade Scripts

For version migrations, create upgrade scripts:
```bash
# Example: upgrade from 1.0.0 to 1.1.0
touch morbac_pg--1.0.0--1.1.0.sql
```

These contain only the ALTER/ADD statements needed for the upgrade.

## Make Targets

- `make test` - Test with development file (temporary database)
- `make test` - Full test with persistent database
- `make release` - Generate versioned file from development file
- `make install` - Create release and install in PostgreSQL
- `make cleanup` - Drop test database
- `make help` - Show all targets

## Benefits

- No version numbers scattered in code
- Clean git diffs (only one file changes during development)
- Versioned files only created at release time
- Git tags provide version history
- Single source of truth for version number
