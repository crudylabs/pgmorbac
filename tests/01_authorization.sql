-- ============================================================================
-- MORBAC PostgreSQL Extension - Authorization Decision Tests
-- ============================================================================
-- This test file covers authorization decision tests including:
-- - Basic authorization decisions (is_allowed function)
-- - Role hierarchy inheritance
-- - Organization hierarchy
-- - Prohibition precedence
-- - Multi-organization user access
--
-- Prerequisites: Assumes 00_setup.sql has been run to set up base data
-- ============================================================================

\echo ''
\echo '=== Authorization Decisions ==='

-- Test Alice (admin at Acme)
\echo 'Alice (admin at Acme Corp):'
SELECT
    'read documents' as action,
    morbac.is_allowed(
        'aaaaaaaa-0000-0000-0000-000000000001'::uuid,
        '11111111-1111-1111-1111-111111111111'::uuid,
        'read',
        'documents'
    ) as allowed;

SELECT
    'delete documents' as action,
    morbac.is_allowed(
        'aaaaaaaa-0000-0000-0000-000000000001'::uuid,
        '11111111-1111-1111-1111-111111111111'::uuid,
        'delete',
        'documents'
    ) as allowed;

-- Test Bob (employee at Acme)
\echo ''
\echo 'Bob (employee at Acme Corp):'
SELECT
    'read documents' as action,
    morbac.is_allowed(
        'bbbbbbbb-0000-0000-0000-000000000002'::uuid,
        '11111111-1111-1111-1111-111111111111'::uuid,
        'read',
        'documents'
    ) as allowed;

SELECT
    'delete documents' as action,
    morbac.is_allowed(
        'bbbbbbbb-0000-0000-0000-000000000002'::uuid,
        '11111111-1111-1111-1111-111111111111'::uuid,
        'delete',
        'documents'
    ) as allowed;

-- Test Charlie (contractor at Acme)
\echo ''
\echo 'Charlie (contractor at Acme Corp):'
SELECT
    'read documents' as action,
    morbac.is_allowed(
        'cccccccc-0000-0000-0000-000000000003'::uuid,
        '11111111-1111-1111-1111-111111111111'::uuid,
        'read',
        'documents'
    ) as allowed;

SELECT
    'write documents' as action,
    morbac.is_allowed(
        'cccccccc-0000-0000-0000-000000000003'::uuid,
        '11111111-1111-1111-1111-111111111111'::uuid,
        'write',
        'documents'
    ) as allowed;

-- Test PROHIBITION precedence
\echo ''
\echo 'Testing PROHIBITION PRECEDENCE:'
\echo 'Charlie (contractor) trying to read sensitive_data (should be DENIED by prohibition):'
SELECT
    'read sensitive_data' as action,
    morbac.is_allowed(
        'cccccccc-0000-0000-0000-000000000003'::uuid,
        '11111111-1111-1111-1111-111111111111'::uuid,
        'read',
        'sensitive_data'
    ) as allowed;

-- Test Charlie at Beta Inc (multi-org user)
\echo ''
\echo 'Charlie as staff at Beta Inc:'
SELECT
    'read documents' as action,
    morbac.is_allowed(
        'cccccccc-0000-0000-0000-000000000003'::uuid,
        '22222222-2222-2222-2222-222222222222'::uuid,
        'read',
        'documents'
    ) as allowed;

-- Test Diana (manager at Beta)
\echo ''
\echo 'Diana (manager at Beta Inc):'
SELECT
    'write documents' as action,
    morbac.is_allowed(
        'dddddddd-0000-0000-0000-000000000004'::uuid,
        '22222222-2222-2222-2222-222222222222'::uuid,
        'write',
        'documents'
    ) as allowed;

\echo ''
\echo '=== Role Hierarchy Inheritance ==='

-- Assign user Eve only viewer role
\echo 'Creating user Eve with only viewer role at Acme:'
INSERT INTO morbac.user_roles (user_id, role_id, org_id) VALUES
    ('eeeeeeee-0000-0000-0000-000000000005', 'ffffffff-ffff-ffff-ffff-ffffffffffff', '11111111-1111-1111-1111-111111111111');

-- Add permission for viewer role
INSERT INTO morbac.policy (org_name, role_name, activity, view, modality) VALUES
    ('Acme Corp', 'viewer', 'read', 'documents', 'permission');

SELECT * FROM morbac.compile_policy();

\echo ''
\echo 'Eve (has viewer role, which employee inherits from):'
SELECT
    'read documents' as action,
    morbac.is_allowed(
        'eeeeeeee-0000-0000-0000-000000000005'::uuid,
        '11111111-1111-1111-1111-111111111111'::uuid,
        'read',
        'documents'
    ) as allowed;

\echo ''
\echo 'Bob (employee) should inherit permissions from viewer role:'
\echo 'Effective roles for Bob (should include employee and viewer via hierarchy):'
SELECT r.name, er.depth
FROM morbac.get_effective_roles(
    'bbbbbbbb-0000-0000-0000-000000000002'::uuid,
    '11111111-1111-1111-1111-111111111111'::uuid
) er
JOIN morbac.roles r ON er.role_id = r.id
ORDER BY er.depth;

\echo ''
\echo 'Alice (admin) should inherit from both employee and viewer:'
SELECT r.name, er.depth
FROM morbac.get_effective_roles(
    'aaaaaaaa-0000-0000-0000-000000000001'::uuid,
    '11111111-1111-1111-1111-111111111111'::uuid
) er
JOIN morbac.roles r ON er.role_id = r.id
ORDER BY er.depth;

\echo ''
\echo '=== Organization Hierarchy ==='

\echo 'Ancestors of Acme Subsidiary:'
SELECT o.name, oa.depth
FROM morbac.get_org_ancestors('33333333-3333-3333-3333-333333333333'::uuid) oa
JOIN morbac.orgs o ON oa.org_id = o.id
ORDER BY oa.depth;

\echo ''
\echo 'Descendants of Acme Corp (should include subsidiary):'
SELECT o.name, od.depth
FROM morbac.get_org_descendants('11111111-1111-1111-1111-111111111111'::uuid) od
JOIN morbac.orgs o ON od.org_id = o.id
ORDER BY od.depth;

\echo ''
\echo '=== Authorization Decision Tests Completed ==='
