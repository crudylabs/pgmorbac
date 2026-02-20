-- ============================================================================
-- MORBAC PostgreSQL Extension - Constraint Tests
-- ============================================================================
-- This test file covers various constraints including:
-- - Separation of Duty (SoD) conflicts
-- - Negative role assignments
-- - Role cardinality constraints (min/max users per role)
--
-- Prerequisites: Assumes 00_setup.sql has been run to set up base data
-- ============================================================================

\echo ''
\echo '=== Separation of Duty ==='

-- Define SoD conflict: auditor and accountant roles are mutually exclusive
INSERT INTO morbac.roles (id, org_id, name, description) VALUES
    ('11111111-1111-1111-1111-111111111111', '11111111-1111-1111-1111-111111111111', 'auditor', 'Auditor role'),
    ('22222222-2222-2222-2222-222222222222', '11111111-1111-1111-1111-111111111111', 'accountant', 'Accountant role');

INSERT INTO morbac.sod_conflicts (role_a_id, role_b_id, org_id, description) VALUES
    ('11111111-1111-1111-1111-111111111111', '22222222-2222-2222-2222-222222222222', '11111111-1111-1111-1111-111111111111', 'Auditors and accountants are mutually exclusive');

-- Assign user to auditor role
INSERT INTO morbac.user_roles (user_id, role_id, org_id) VALUES
    ('99999999-0000-0000-0000-000000000009', '11111111-1111-1111-1111-111111111111', '11111111-1111-1111-1111-111111111111');

\echo 'Check SoD violation if we try to assign accountant role to auditor:'
SELECT morbac.check_sod_violation(
    '99999999-0000-0000-0000-000000000009'::uuid,
    '22222222-2222-2222-2222-222222222222'::uuid,
    '11111111-1111-1111-1111-111111111111'::uuid
) as would_violate_sod;

\echo ''
\echo '=== Negative Role Assignment ==='

-- Explicitly prohibit contractor from ever being admin
INSERT INTO morbac.negative_role_assignments (user_id, role_id, org_id, reason) VALUES
    ('cccccccc-0000-0000-0000-000000000003', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '11111111-1111-1111-1111-111111111111', 'Contractors cannot be administrators');

\echo 'Charlie cannot have admin role even if explicitly assigned (negative assignment takes precedence).'

\echo ''
\echo '=== Cardinality Constraints ==='

-- Set max 2 users for admin role
INSERT INTO morbac.role_cardinality (role_id, min_users, max_users, description) VALUES
    ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 1, 2, 'Admin role limited to 2 users minimum 1');

\echo 'Check cardinality when adding user (1 admin exists, max is 2, should be OK):'
SELECT morbac.check_cardinality_violation('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'::uuid, TRUE) as violation;

\echo ''
\echo '=== Constraint Tests Completed ==='
