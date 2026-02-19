# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] - 2026-02-19

### Added
- Initial release of Multi-OrBAC PostgreSQL extension
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
  - Negative role assignments
  - Separation of Duty (SoD) constraints
  - Role cardinality constraints (min/max users)
  - Derived roles (computed via functions)
  - Cross-organizational rules
  - Administration rules (meta-policies)
- Policy DSL with idempotent compiler
- RLS helper functions for PostgREST integration
- Comprehensive test suite with 20 test scenarios
- Complete documentation
- Build and installation automation (Makefile, install.sh)

[1.0.0]: https://github.com/yourusername/morbac_pg/releases/tag/v1.0.0
