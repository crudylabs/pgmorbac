-- ============================================================================
-- MORBAC PostgreSQL Extension - Activity and View Hierarchies Tests
-- ============================================================================
-- This test file covers activity and view hierarchy tests including:
-- - Activity hierarchy (e.g., write implies read)
-- - View hierarchy (e.g., sensitive_data is a type of documents)
-- - Effective activities and views
-- - Permission inheritance through hierarchies
--
-- Prerequisites: Assumes 00_setup.sql has been run to set up base data
-- ============================================================================

\echo ''
\echo '=== Activity and View Hierarchies ==='

-- Define activity hierarchy: write implies read
INSERT INTO morbac.activity_hierarchy (senior_activity, junior_activity) VALUES
    ('write', 'read');

-- Define view hierarchy: sensitive_data is a type of documents
INSERT INTO morbac.view_hierarchy (senior_view, junior_view) VALUES
    ('sensitive_data', 'documents');

\echo 'Activities implied by write:'
SELECT * FROM morbac.get_effective_activities('write');

\echo 'Views for sensitive_data (should include documents):'
SELECT * FROM morbac.get_effective_views('sensitive_data');

\echo 'Bob has permission for read+documents, so write+documents should work (activity hierarchy):'
SELECT
    'write documents (via activity hierarchy)' as action,
    morbac.is_allowed(
        'bbbbbbbb-0000-0000-0000-000000000002'::uuid,
        '11111111-1111-1111-1111-111111111111'::uuid,
        'write',
        'documents'
    ) as allowed;

\echo ''
\echo '=== Activity and View Hierarchies Tests Completed ==='
