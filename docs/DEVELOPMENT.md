# Development Workflow

## Version Management

This extension uses a single-source version approach:

- **Version source of truth**: `pg_morbac.control` (the `default_version` field)
- **Development file**: `pg_morbac.sql` (unversioned, for daily work)
- **Release files**: `pg_morbac--X.Y.Z.sql` (generated, git-ignored)

## Daily Development

1. **Edit**: Work on `pg_morbac.sql` (no version numbers in the file)
2. **Test**: Run `make test` to test changes in a temporary database
3. **Commit**: Commit `pg_morbac.sql` to git regularly

## Release Process

When ready to release a new version:

1. **Update version**: Edit `pg_morbac.control` and change `default_version`
   ```
   default_version = '1.1.0'
   ```

2. **Create release**: Run `make release`
   - Reads version from `.control` file
   - Copies `pg_morbac.sql` → `pg_morbac--X.Y.Z.sql`

3. **Test**: Run `make test` with the versioned file

4. **Tag in git**:
   ```bash
   git add pg_morbac.control pg_morbac--X.Y.Z.sql
   git commit -m "Release vX.Y.Z"
   git tag vX.Y.Z
   git push origin main --tags
   ```

## Upgrade Scripts

For version migrations, create upgrade scripts:
```bash
# Example: upgrade from 1.0.0 to 1.1.0
touch pg_morbac--1.0.0--1.1.0.sql
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
