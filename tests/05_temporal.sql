-- ============================================================================
-- MORBAC PostgreSQL Extension - Temporal Constraint Tests
-- ============================================================================
-- This test file covers temporal constraints including:
-- - Rules with valid_from timestamps (future activation)
-- - Rules with valid_until timestamps (expiration)
-- - Rules with both valid_from and valid_until (time windows)
-- - Authorization decisions respecting temporal bounds
--
-- Prerequisites: Assumes 00_setup.sql has been run to set up base data
-- ============================================================================

\echo ''
\echo '=== Temporal Constraints on Rules ==='

-- Create a time-limited rule (expires in the past)
INSERT INTO morbac.rules (org_id, role_id, activity, view, context_id, modality, valid_until)
VALUES (
    '11111111-1111-1111-1111-111111111111',
    'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', -- employee role
    'write',
    'temp_documents',
    (SELECT id FROM morbac.contexts WHERE name = 'always'),
    'permission',
    '2020-01-01 00:00:00+00'  -- Expired rule
);

-- Create a future rule (not yet active)
INSERT INTO morbac.rules (org_id, role_id, activity, view, context_id, modality, valid_from)
VALUES (
    '11111111-1111-1111-1111-111111111111',
    'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
    'write',
    'future_documents',
    (SELECT id FROM morbac.contexts WHERE name = 'always'),
    'permission',
    '2030-01-01 00:00:00+00'  -- Future rule
);

-- Create an active time-bounded rule
INSERT INTO morbac.rules (org_id, role_id, activity, view, context_id, modality, valid_from, valid_until)
VALUES (
    '11111111-1111-1111-1111-111111111111',
    'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
    'write',
    'active_documents',
    (SELECT id FROM morbac.contexts WHERE name = 'always'),
    'permission',
    '2020-01-01 00:00:00+00',  -- Started in the past
    '2030-12-31 23:59:59+00'   -- Ends in the future
);

\echo 'Alice (employee) access to temporal-constrained documents:'
SELECT
    'write to temp_documents (expired rule)' as action,
    morbac.is_allowed(
        'aaaaaaaa-0000-0000-0000-000000000001'::uuid,
        '11111111-1111-1111-1111-111111111111'::uuid,
        'write',
        'temp_documents'
    ) as allowed
UNION ALL
SELECT
    'write to future_documents (not yet active)' as action,
    morbac.is_allowed(
        'aaaaaaaa-0000-0000-0000-000000000001'::uuid,
        '11111111-1111-1111-1111-111111111111'::uuid,
        'write',
        'future_documents'
    ) as allowed
UNION ALL
SELECT
    'write to active_documents (currently valid)' as action,
    morbac.is_allowed(
        'aaaaaaaa-0000-0000-0000-000000000001'::uuid,
        '11111111-1111-1111-1111-111111111111'::uuid,
        'write',
        'active_documents'
    ) as allowed;

\echo ''
\echo '=== Temporal Constraint Tests Completed ==='
