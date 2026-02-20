-- ============================================================================
-- MORBAC PostgreSQL Extension - Audit Logging Tests
-- ============================================================================
-- This test file covers audit logging functionality including:
-- - Enabling audit on tables
-- - Auditing INSERT operations
-- - Auditing UPDATE operations
-- - Auditing DELETE operations
-- - Audit log queries and reporting
-- - Disabling audit
--
-- Prerequisites: Assumes 00_setup.sql has been run to set up base data
-- ============================================================================

\echo ''
\echo '=== Audit Logging ==='

-- Enable audit on user_roles table
SELECT morbac.enable_audit('user_roles');

\echo 'Audit trigger created for user_roles table'

-- Perform some auditable operations
INSERT INTO morbac.user_roles (user_id, role_id, org_id)
VALUES (
    'ffffffff-0000-0000-0000-000000000001'::uuid,
    'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',  -- employee role
    '11111111-1111-1111-1111-111111111111'
);

-- Update an existing user_role
UPDATE morbac.user_roles
SET active = false
WHERE user_id = 'aaaaaaaa-0000-0000-0000-000000000001'::uuid
  AND role_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';

-- Delete a user role
DELETE FROM morbac.user_roles
WHERE user_id = 'ffffffff-0000-0000-0000-000000000001'::uuid
  AND role_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';

\echo 'Audit log entries for user_roles operations:'
SELECT
    operation,
    record_id,
    CASE
        WHEN old_data IS NOT NULL THEN old_data->>'active'
        ELSE 'N/A'
    END as old_active,
    CASE
        WHEN new_data IS NOT NULL THEN new_data->>'active'
        ELSE 'N/A'
    END as new_active,
    session_user,
    timestamp
FROM morbac.audit_log
WHERE table_name = 'user_roles'
ORDER BY timestamp;

\echo 'Disable audit on user_roles:'
SELECT morbac.disable_audit('user_roles');

\echo ''
\echo '=== Audit Logging Tests Completed ==='
