-- ============================================================================
-- MORBAC PostgreSQL Extension - Utility Functions and Context Tests
-- ============================================================================
-- This test file covers utility functions and context evaluation including:
-- - Obligations (pending_obligations)
-- - Recommendations (pending_recommendations)
-- - Context evaluation (eval_context)
-- - User role queries (user_roles_in_org, user_has_role)
-- - Policy compilation and idempotency
-- - Adding new policy entries
--
-- Prerequisites: Assumes 00_setup.sql has been run to set up base data
-- ============================================================================

\echo ''
\echo '=== Obligations and Recommendations ==='

\echo 'Obligations for Bob (employee at Acme):'
SELECT * FROM morbac.pending_obligations(
    'bbbbbbbb-0000-0000-0000-000000000002'::uuid,
    '11111111-1111-1111-1111-111111111111'::uuid
);

\echo ''
\echo 'Recommendations for Charlie (staff at Beta):'
SELECT * FROM morbac.pending_recommendations(
    'cccccccc-0000-0000-0000-000000000003'::uuid,
    '22222222-2222-2222-2222-222222222222'::uuid
);

\echo ''
\echo '=== Utility Functions ==='

\echo 'Roles for Charlie at Acme Corp:'
SELECT * FROM morbac.user_roles_in_org(
    'cccccccc-0000-0000-0000-000000000003'::uuid,
    '11111111-1111-1111-1111-111111111111'::uuid
);

\echo ''
\echo 'Roles for Charlie at Beta Inc:'
SELECT * FROM morbac.user_roles_in_org(
    'cccccccc-0000-0000-0000-000000000003'::uuid,
    '22222222-2222-2222-2222-222222222222'::uuid
);

\echo ''
\echo 'Does Alice have admin role at Acme Corp?'
SELECT morbac.user_has_role(
    'aaaaaaaa-0000-0000-0000-000000000001'::uuid,
    '11111111-1111-1111-1111-111111111111'::uuid,
    'admin'
) as has_admin_role;

\echo ''
\echo '=== Context Evaluation ==='

\echo 'Evaluating always context:'
SELECT morbac.eval_context(
    (SELECT id FROM morbac.contexts WHERE name = 'always')
) as result;

\echo ''
\echo 'Evaluating business_hours context:'
SELECT morbac.eval_context(
    (SELECT id FROM morbac.contexts WHERE name = 'business_hours')
) as result;

\echo ''
\echo 'Evaluating weekend context:'
SELECT morbac.eval_context(
    (SELECT id FROM morbac.contexts WHERE name = 'weekend')
) as result;

\echo ''
\echo '=== Policy Re-compilation (Idempotency Test) ==='

\echo 'Compiling policy again (should show 0 new rules, idempotent):'
SELECT * FROM morbac.compile_policy();

\echo ''
\echo '=== Adding New Policy Entry ==='

INSERT INTO morbac.policy (org_name, role_name, activity, view, modality, context_name) VALUES
    ('Acme Corp', 'admin', 'approve', 'documents', 'permission', 'always');

\echo 'Compiling new policy entry:'
SELECT * FROM morbac.compile_policy();

\echo ''
\echo '=== Utility Functions and Context Tests Completed ==='
