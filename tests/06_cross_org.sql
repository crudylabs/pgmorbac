-- ============================================================================
-- MORBAC PostgreSQL Extension - Cross-Organizational Rules Tests
-- ============================================================================
-- This test file covers cross-organizational authorization including:
-- - Cross-organization rules (access between different orgs)
-- - Inter-organizational collaboration scenarios
-- - Cross-org permission validation
--
-- Prerequisites: Assumes 00_setup.sql has been run to set up base data
-- ============================================================================

\echo ''
\echo '=== Cross-Organization Rules ==='

-- Allow Beta managers to read Acme documents (inter-org collaboration)
INSERT INTO morbac.cross_org_rules (source_org_id, target_org_id, role_id, activity, view, context_id, modality) VALUES
    ('22222222-2222-2222-2222-222222222222', '11111111-1111-1111-1111-111111111111', 'dddddddd-dddd-dddd-dddd-dddddddddddd', 'read', 'documents', (SELECT id FROM morbac.contexts WHERE name = 'always'), 'permission');

\echo 'Diana (manager at Beta) can read Acme documents via cross-org rule:'
SELECT
    'read Acme documents from Beta' as action,
    morbac.is_allowed(
        'dddddddd-0000-0000-0000-000000000004'::uuid,
        '11111111-1111-1111-1111-111111111111'::uuid,
        'read',
        'documents'
    ) as allowed;

\echo ''
\echo '=== Cross-Organization Rules Tests Completed ==='
