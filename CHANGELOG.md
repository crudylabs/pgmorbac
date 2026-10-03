# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] - 2026-07-25

### Added
- First stable release of the Multi-OrBAC PostgreSQL extension
- Complete Multi-OrBAC implementation based on CNRS research paper
- Core features:
  - Organization-centric access control
  - Role-based abstraction with organizational scope
  - Activity and view abstractions
  - Context-based rule evaluation
  - Four deontic modalities (permission, prohibition, obligation, recommendation)
  - Prohibition precedence over permissions
  - Multi-organization support
- Advanced features:
  - Organization, role, activity, and view hierarchies with transitive closure
  - Temporal delegation with time bounds
  - Temporal constraints on rules with validity periods (valid_from, valid_until)
  - Negative role assignments
  - Separation of Duty (SoD) constraints
  - Role cardinality constraints (min/max users)
  - Derived roles (computed via functions)
  - Cross-organizational rules with temporal support
  - Administration rules (meta-policies)
  - Audit logging for security-critical operations
- Audit logging system:
  - Generic audit trigger for tracking INSERT/UPDATE/DELETE operations
  - Comprehensive audit log with JSONB support for before/after states
  - Helper functions: `enable_audit()`, `disable_audit()`
  - Field-level change tracking
  - Client connection metadata capture (IP, application name, session user)
- Policy DSL with idempotent compiler
- RLS helper functions for PostgREST integration
- Comprehensive test suite with 20 test scenarios
- Complete documentation
- Build and installation automation (Makefile, install.sh)
- Unattributed (no-org) object support:
  - Org target vocabulary shared by every rule kind: a specific organization,
    `unattributed` (objects with no org), or `all` (every org, unattributed included)
  - `rules.scope` values `unattributed` and `all`
  - `user_rules.org_id` accepts NULL to target unattributed objects
  - `org_in_scope()` partitions the two object classes: `unattributed` matches only
    a NULL target, tree scopes never match one
  - `morbac.has_permission(user, activity, view)` capability probe for UI gating
  - `morbac.current_org_filter()` parses `morbac.org_ids` once into org UUIDs plus
    the unattributed-bucket flag (a JSON `null` element requests it)
  - `rls_check()` split by arity so NULL never carries two meanings:
    `rls_check(activity, view)` for tables with no org column,
    `rls_check(activity, view, row_org_id[, row_user_id])` for row-scoped tables
    where a NULL `row_org_id` means the record is unattributed

[1.0.0]: https://github.com/crudylabs/pgmorbac/releases/tag/v1.0.0
