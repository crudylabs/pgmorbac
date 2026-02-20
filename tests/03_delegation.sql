-- ============================================================================
-- MORBAC PostgreSQL Extension - Delegation Tests
-- ============================================================================
-- This test file covers delegation functionality including:
-- - Temporary role delegation
-- - Delegated permission inheritance
-- - Comprehensive role reporting (direct + delegated)
-- - Time-limited delegation (valid_from/valid_until)
--
-- Prerequisites: Assumes 00_setup.sql has been run to set up base data
-- ============================================================================

\echo ''
\echo '=== Delegation ==='

-- Alice delegates admin role to user Frank temporarily
INSERT INTO morbac.delegations (delegator_id, delegatee_id, role_id, org_id, valid_from, valid_until) VALUES
    ('aaaaaaaa-0000-0000-0000-000000000001', 'ffffffff-0000-0000-0000-000000000006', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '11111111-1111-1111-1111-111111111111', now(), now() + interval '1 day');

\echo 'Frank (via delegation from Alice) should have admin permissions:'
SELECT
    'delete documents (delegated)' as action,
    morbac.is_allowed(
        'ffffffff-0000-0000-0000-000000000006'::uuid,
        '11111111-1111-1111-1111-111111111111'::uuid,
        'delete',
        'documents'
    ) as allowed;

\echo 'Frank effective roles (should include delegated admin):'
SELECT r.name, cr.source
FROM morbac.get_comprehensive_roles('ffffffff-0000-0000-0000-000000000006'::uuid, '11111111-1111-1111-1111-111111111111'::uuid) cr
JOIN morbac.roles r ON cr.role_id = r.id;

\echo ''
\echo '=== Delegation Tests Completed ==='
