-- ============================================================================
-- MORBAC PostgreSQL Extension - Administration Rules Tests
-- ============================================================================
-- This test file covers administration rules including:
-- - Administrative activities (create_rule, etc.)
-- - Administrative permission checks (is_admin_allowed)
-- - Role-based administrative access control
-- - Administrative authorization decisions
--
-- Prerequisites: Assumes 00_setup.sql has been run to set up base data
-- ============================================================================

\echo ''
\echo '=== Administration Rules ==='

-- Only admin role can create rules
INSERT INTO morbac.admin_rules (org_id, role_id, admin_activity, admin_target, context_id, modality) VALUES
    ('11111111-1111-1111-1111-111111111111', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'create_rule', 'rules', (SELECT id FROM morbac.contexts WHERE name = 'always'), 'permission');

\echo 'Alice (admin) can create rules:'
SELECT morbac.is_admin_allowed(
    'aaaaaaaa-0000-0000-0000-000000000001'::uuid,
    '11111111-1111-1111-1111-111111111111'::uuid,
    'create_rule',
    'rules'
) as can_create_rules;

\echo 'Bob (employee) cannot create rules:'
SELECT morbac.is_admin_allowed(
    'bbbbbbbb-0000-0000-0000-000000000002'::uuid,
    '11111111-1111-1111-1111-111111111111'::uuid,
    'create_rule',
    'rules'
) as can_create_rules;

\echo ''
\echo '=== Administration Rules Tests Completed ==='
