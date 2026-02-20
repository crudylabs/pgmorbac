# morbac_pg

**Multi-Organization Based Access Control for PostgreSQL**

A PostgreSQL extension implementing the Multi-OrBAC access control model - enabling organization-centric, context-aware, and hierarchical access control with advanced features like delegation, separation of duty, and cross-organizational policies.

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![PostgreSQL 12+](https://img.shields.io/badge/PostgreSQL-12%2B-blue.svg)](https://www.postgresql.org/)

## Features

- Multi-organization with organizational hierarchy
- Role-based access with full hierarchy support
- Activity and view hierarchies with transitive permission inheritance
- Prohibition precedence over permissions
- Temporal delegation with time bounds
- Temporal constraints on rules with validity periods
- Separation of duty constraints
- Derived roles computed from application logic
- Cross-organizational policies
- Context-aware rules
- Audit logging for security-critical operations
- Row-level security integration

## Installation

### Prerequisites

- PostgreSQL 12 or higher
- `pgcrypto` extension (included with PostgreSQL)
- Development tools: `make`, `bash`

### Quick Install

```bash
# Clone repository
git clone https://github.com/yourusername/morbac_pg.git
cd morbac_pg

# Build and install extension
make build          # Build versioned file from src/
sudo make install   # Install to PostgreSQL

# Enable in your database
psql -d mydb -c "CREATE EXTENSION morbac_pg;"
```

### Alternative: Using install script

```bash
# Build first
make build

# Run installer
sudo ./tools/install.sh
```

### Manual Install

```bash
# Build versioned file from source
make build          # Concatenates src/ files into morbac_pg--1.0.0.sql

# Copy files to PostgreSQL extension directory
sudo cp morbac_pg.control $(pg_config --sharedir)/extension/
sudo cp morbac_pg--1.0.0.sql $(pg_config --sharedir)/extension/

# Enable in PostgreSQL
psql -d mydb -c "CREATE EXTENSION morbac_pg;"
```

## Quick Start

```sql
-- 1. Create organization
INSERT INTO morbac.orgs (name) VALUES ('Acme Corp');

-- 2. Create role
INSERT INTO morbac.roles (org_id, name)
SELECT id, 'employee' FROM morbac.orgs WHERE name = 'Acme Corp';

-- 3. Assign user to role
INSERT INTO morbac.user_roles (user_id, role_id, org_id)
SELECT
    '00000000-0000-0000-0000-000000000001'::uuid,
    r.id,
    o.id
FROM morbac.orgs o
JOIN morbac.roles r ON r.org_id = o.id
WHERE o.name = 'Acme Corp' AND r.name = 'employee';

-- 4. Define policy
INSERT INTO morbac.policy (org_name, role_name, activity, view, modality)
VALUES ('Acme Corp', 'employee', 'read', 'documents', 'permission');

-- 5. Compile policy
SELECT * FROM morbac.compile_policy();

-- 6. Check authorization
SELECT morbac.is_allowed(
    '00000000-0000-0000-0000-000000000001'::uuid,
    (SELECT id FROM morbac.orgs WHERE name = 'Acme Corp'),
    'read',
    'documents'
); -- Returns: true

-- 7. Initialize performance cache (recommended for production)
SELECT morbac.refresh_hierarchy_cache();
```

## Usage

### Authorization Check

```sql
-- Production (cached by default)
SELECT morbac.is_allowed(user_id, org_id, activity, view);

-- Debugging (bypasses cache)
SELECT morbac.is_allowed_nocache(user_id, org_id, activity, view);
```

See [PERFORMANCE.md](docs/PERFORMANCE.md) for optimization details.

### Row-Level Security (RLS)

```sql
-- Enable RLS on your table
ALTER TABLE app.documents ENABLE ROW LEVEL SECURITY;

-- Create policy using Multi-OrBAC
CREATE POLICY doc_access ON app.documents
    FOR SELECT
    USING (morbac.rls_check('read', 'documents'));
```

### Advanced Features

```sql
-- Temporal rules: Rule active only during business hours or specific period
INSERT INTO morbac.rules (org_id, role_id, activity, view, context_id, modality, valid_from, valid_until)
VALUES (org_id, role_id, 'write', 'sensitive_data', ctx_id, 'permission',
        '2024-01-01 00:00:00', '2024-12-31 23:59:59');

-- Delegation: Alice delegates role to Bob for 1 week
INSERT INTO morbac.delegations (delegator_user_id, delegate_user_id, role_id, org_id, valid_until)
VALUES (alice_id, bob_id, role_id, org_id, NOW() + INTERVAL '7 days');

-- Separation of Duty: Preparer and approver are mutually exclusive
INSERT INTO morbac.sod_conflicts (role1_id, role2_id, org_id)
VALUES (preparer_role_id, approver_role_id, org_id);

-- Cross-Org: Global auditor can access subsidiary
INSERT INTO morbac.cross_org_rules (source_org_id, target_org_id, role_id, activity, view, modality)
VALUES (global_org_id, subsidiary_org_id, auditor_role_id, 'read', 'reports', 'permission');

-- Audit logging: Track changes to user roles
SELECT morbac.enable_audit('user_roles');

-- Query audit log
SELECT * FROM morbac.audit_log
WHERE table_name = 'user_roles'
ORDER BY timestamp DESC
LIMIT 10;
```

## Development & Testing

```bash
# Development workflow
# 1. Edit source files in src/ directory
# 2. Build and test
make build         # Build versioned morbac_pg--X.Y.Z.sql from src/
make test          # Build and run test suite

# Manual testing
make build
createdb morbac_test
psql -d morbac_test -f morbac_pg.sql
# ... test manually ...
dropdb morbac_test
```

See [src/README.md](src/README.md) for source code organization.

## Documentation

- [DOCUMENTATION.md](docs/DOCUMENTATION.md) - Architecture, API reference, integration guides
- [PERFORMANCE.md](docs/PERFORMANCE.md) - Performance optimization and caching guide
- [ADMIN_GUIDE.md](docs/ADMIN_GUIDE.md) - Organization administrator setup and delegation
- [DEVELOPMENT.md](docs/DEVELOPMENT.md) - Development workflow and version management
- [SECURITY.md](docs/SECURITY.md) - Security policy
- [CONTRIBUTING.md](docs/CONTRIBUTING.md) - Contribution guidelines
- [src/README.md](src/README.md) - Source code organization
- [tests/README.md](tests/README.md) - Test structure and setup
- [CHANGELOG.md](CHANGELOG.md) - Version history

## Architecture

Authorization decision flow:

1. Collect all roles for user (direct, delegated, derived, hierarchy)
2. Filter out negative role assignments
3. Check for prohibitions - if found, deny access
4. Check for permissions - if found, allow access
5. Default deny

Prohibitions always override permissions.

## Research

Based on the CNRS research paper:
["Extending the OrBAC model to handle multi-organization environments"](https://webhost.laas.fr/TSF/deswarte/Publications/06427.pdf)

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Contributing

See [CONTRIBUTING.md](docs/CONTRIBUTING.md) for guidelines.

```bash
git clone https://github.com/yourusername/morbac_pg.git
cd morbac_pg

# Edit source files in src/
vim src/authorization.sql

# Build and test your changes
make test          # Run test suite

# When ready to release
# 1. Update version in morbac_pg.control
# 2. Build versioned file
make build         # Creates morbac_pg--X.Y.Z.sql
# 3. Tag in git
git tag v1.0.1
git push --tags
```

## Support

- Read the [documentation](docs/DOCUMENTATION.md)
- Report bugs via [GitHub Issues](https://github.com/yourusername/morbac_pg/issues)
- Ask questions in [Discussions](https://github.com/yourusername/morbac_pg/discussions)
- Security issues: see [SECURITY.md](docs/SECURITY.md)

## Comparison with Traditional RBAC

| Feature | Traditional RBAC | morbac_pg |
|---------|-----------------|-----------|
| Multi-tenancy | No | Yes |
| Prohibitions | No | Yes |
| Context-aware | No | Yes |
| Hierarchies | Basic roles only | Organizations, roles, activities, views |
| Delegation | No | Yes |
| Separation of Duty | No | Yes |
| Cross-organization | No | Yes |
