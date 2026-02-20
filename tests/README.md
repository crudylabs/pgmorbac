# Test Organization

Tests are organized in the `tests/` directory:

- **00_setup.sql** - Common setup (organizations, roles, users, activities, views)
- **01_authorization.sql** - Basic authorization tests
- **02_hierarchies.sql** - Role, org, activity, view hierarchy tests
- **03_delegation.sql** - Role delegation tests
- **04_constraints.sql** - SoD and cardinality constraint tests
- **05_temporal.sql** - Temporal validity tests
- **06_cross_org.sql** - Cross-organization access tests
- **07_audit.sql** - Audit logging tests
- **08_admin.sql** - Administration permission tests
- **09_utilities.sql** - Utility function tests

## Running Tests

```bash
# Run all tests (creates temp database, runs tests, cleans up)
make test

# Run tests manually with persistent database
createdb morbac_test
./tests/run_tests.sh morbac_test
# Database remains for inspection
dropdb morbac_test  # when done

# Run individual test file
psql -d morbac_test -f tests/01_authorization.sql
```

## Test Data

All tests use common setup from `00_setup.sql`:

**Organizations:**
- Acme Corp (11111111-1111-1111-1111-111111111111)
- Beta Inc (22222222-2222-2222-2222-222222222222)
- Acme Subsidiary (child of Acme Corp)

**Test Users:**
- Alice: aaaaaaaa-0000-0000-0000-000000000001 (admin at Acme)
- Bob: bbbbbbbb-0000-0000-0000-000000000002 (employee at Acme)
- Charlie: cccccccc-0000-0000-0000-000000000003 (contractor at Acme, staff at Beta)
- Dave: dddddddd-0000-0000-0000-000000000004 (manager at Beta)
- Eve: eeeeeeee-0000-0000-0000-000000000005 (viewer at Acme)

**Activities:** read, write, delete, manage, export, approve

**Views:** documents, reports, confidential_data, public_data, financial_records, projects
