-- =============================================================================
-- Audit Logging Tests
-- =============================================================================
-- Tests the audit system: enable_audit / disable_audit and the resulting
-- audit_log entries for INSERT, UPDATE, and DELETE operations.
--
-- Cases:
--   1. Enable audit creates trigger on specified table
--   2. INSERT to audited table creates an audit log entry
--   3. DELETE from audited table creates an audit log entry
--   4. UPDATE to audited table creates an audit log entry with changed_fields
--   5. All operations for a record_id are queryable
--   6. Multiple tables can be audited independently
--   7. Disable audit removes the trigger
--   8. After disabling, changes are no longer logged
--
-- Prerequisites: 00_setup.sql -> 06_cross_org.sql
-- =============================================================================

\echo ''
\echo '================================================================'
\echo '07 — AUDIT LOGGING'
\echo '================================================================'

-- Clear any existing audit log entries to start fresh
TRUNCATE morbac.audit_log;

-- ---------------------------------------------------------------------------
-- Section 1: Enable audit on user_roles
-- ---------------------------------------------------------------------------
\echo ''
\echo '--- 1. Enable audit on user_roles ---'

SELECT morbac.enable_audit('user_roles');

-- Trigger must exist on user_roles after enable
SELECT morbac.t('Trigger exists on user_roles after enable_audit',
    (SELECT COUNT(*) > 0 FROM information_schema.triggers
     WHERE event_object_schema = 'morbac'
       AND event_object_table = 'user_roles'),
    TRUE);

-- No entries before any change
SELECT morbac.t_eq('Audit log count before operations = 0',
    (SELECT COUNT(*) FROM morbac.audit_log WHERE table_name = 'user_roles')::bigint,
    0);

-- ---------------------------------------------------------------------------
-- Section 2: INSERT is logged
-- ---------------------------------------------------------------------------
\echo ''
\echo '--- 2. INSERT is logged ---'

-- Assign a new role to Karl (user who has no role)
INSERT INTO morbac.user_roles (user_id, role_id, org_id)
VALUES (
    '30000000-0000-0000-0000-000000000011', -- Karl
    '20000000-0001-0000-0000-000000000005', -- intern role
    '10000000-0000-0000-0000-000000000001'
);

-- Exactly 1 INSERT entry for user_roles
SELECT morbac.t_eq('Audit log has 1 INSERT entry after INSERT into user_roles',
    (SELECT COUNT(*) FROM morbac.audit_log
     WHERE table_name = 'user_roles' AND operation = 'INSERT')::bigint,
    1);

-- new_data must contain the inserted record
SELECT morbac.t('INSERT audit entry contains user_id in new_data',
    (SELECT new_data->>'user_id' FROM morbac.audit_log
     WHERE table_name = 'user_roles' AND operation = 'INSERT'
     LIMIT 1) = '30000000-0000-0000-0000-000000000011',
    TRUE);

-- ---------------------------------------------------------------------------
-- Section 3: DELETE is logged
-- ---------------------------------------------------------------------------
\echo ''
\echo '--- 3. DELETE is logged ---'

DELETE FROM morbac.user_roles
WHERE user_id = '30000000-0000-0000-0000-000000000011'
  AND role_id = '20000000-0001-0000-0000-000000000005'
  AND org_id  = '10000000-0000-0000-0000-000000000001';

-- Now 2 entries: INSERT + DELETE
SELECT morbac.t_eq('Audit log has 2 entries after DELETE (INSERT + DELETE)',
    (SELECT COUNT(*) FROM morbac.audit_log WHERE table_name = 'user_roles')::bigint,
    2);

-- DELETE entry must have old_data populated
SELECT morbac.t('DELETE audit entry has old_data populated',
    (SELECT old_data IS NOT NULL FROM morbac.audit_log
     WHERE table_name = 'user_roles' AND operation = 'DELETE'
     LIMIT 1),
    TRUE);

-- ---------------------------------------------------------------------------
-- Section 4: Enable audit on rules and test UPDATE logging
-- ---------------------------------------------------------------------------
\echo ''
\echo '--- 4. UPDATE on rules table is logged (with changed_fields) ---'

SELECT morbac.enable_audit('rules');

-- Insert a rule to audit (using explicit id for record_id tracking)
INSERT INTO morbac.rules (id, org_id, role_id, activity, view, context_id, modality)
VALUES (
    'a0000000-0000-0000-0000-000000000001',
    '10000000-0000-0000-0000-000000000001',
    '20000000-0001-0000-0000-000000000009', -- contractor
    'read', 'public_data',
    (SELECT id FROM morbac.contexts WHERE name = 'always'),
    'permission'
);

-- 1 INSERT entry for rules
SELECT morbac.t_eq('Audit log has 1 INSERT entry for rules',
    (SELECT COUNT(*) FROM morbac.audit_log
     WHERE table_name = 'rules' AND operation = 'INSERT')::bigint,
    1);

-- Update the modality (simulate a policy change)
UPDATE morbac.rules
SET modality = 'prohibition'
WHERE id = 'a0000000-0000-0000-0000-000000000001';

-- 1 UPDATE entry with changed_fields
SELECT morbac.t_eq('Audit log has 1 UPDATE entry for rules',
    (SELECT COUNT(*) FROM morbac.audit_log
     WHERE table_name = 'rules' AND operation = 'UPDATE')::bigint,
    1);

-- changed_fields must be non-null for UPDATE
SELECT morbac.t('UPDATE audit entry has changed_fields populated',
    (SELECT changed_fields IS NOT NULL FROM morbac.audit_log
     WHERE table_name = 'rules' AND operation = 'UPDATE'
     LIMIT 1),
    TRUE);

-- old_data and new_data both populated for UPDATE
SELECT morbac.t('UPDATE audit entry: old modality = permission',
    (SELECT old_data->>'modality' FROM morbac.audit_log
     WHERE table_name = 'rules' AND operation = 'UPDATE'
     LIMIT 1) = 'permission',
    TRUE);

SELECT morbac.t('UPDATE audit entry: new modality = prohibition',
    (SELECT new_data->>'modality' FROM morbac.audit_log
     WHERE table_name = 'rules' AND operation = 'UPDATE'
     LIMIT 1) = 'prohibition',
    TRUE);

-- Clean up the audited rule
DELETE FROM morbac.rules WHERE id = 'a0000000-0000-0000-0000-000000000001';

-- ---------------------------------------------------------------------------
-- Section 5: All operations queryable by record_id
-- ---------------------------------------------------------------------------
\echo ''
\echo '--- 5. Query audit log by record_id ---'

-- The test rule had INSERT, UPDATE, DELETE — should be 3 entries
SELECT morbac.t_eq('Audit log has 3 entries for test rule record (INSERT + UPDATE + DELETE)',
    (SELECT COUNT(*) FROM morbac.audit_log
     WHERE table_name = 'rules'
       AND record_id = 'a0000000-0000-0000-0000-000000000001')::bigint,
    3);

-- All three operations present
SELECT morbac.t('INSERT, UPDATE, DELETE all present for test rule record',
    (SELECT COUNT(DISTINCT operation) FROM morbac.audit_log
     WHERE table_name = 'rules'
       AND record_id = 'a0000000-0000-0000-0000-000000000001')::bigint = 3,
    TRUE);

-- ---------------------------------------------------------------------------
-- Section 6: Multiple tables audited independently
-- ---------------------------------------------------------------------------
\echo ''
\echo '--- 6. Multiple tables audited independently ---'

SELECT morbac.enable_audit('delegations');

-- Insert a delegation to trigger audit on the delegations table
INSERT INTO morbac.delegations
    (id, delegator_id, delegatee_id, role_id, org_id, valid_from, valid_until)
VALUES (
    'de000099-0000-0000-0000-000000000099',
    '30000000-0000-0000-0000-000000000001', -- Alice (CEO)
    '30000000-0000-0000-0000-000000000011', -- Karl
    '20000000-0001-0000-0000-000000000001', -- ceo role
    '10000000-0000-0000-0000-000000000001',
    now(),
    now() + interval '1 hour'
);

-- delegations table now has audit entries
SELECT morbac.t('Audit log has at least 1 entry for delegations table',
    (SELECT COUNT(*) FROM morbac.audit_log WHERE table_name = 'delegations') >= 1,
    TRUE);

-- All three tables have audit entries
SELECT morbac.t('user_roles, rules, and delegations all have audit entries',
    (SELECT COUNT(DISTINCT table_name) FROM morbac.audit_log
     WHERE table_name IN ('user_roles', 'rules', 'delegations'))::bigint = 3,
    TRUE);

-- Clean up the test delegation
DELETE FROM morbac.delegations WHERE id = 'de000099-0000-0000-0000-000000000099';

-- ---------------------------------------------------------------------------
-- Section 7: Disable audit removes trigger
-- ---------------------------------------------------------------------------
\echo ''
\echo '--- 7. Disable audit removes trigger ---'

SELECT morbac.disable_audit('user_roles');

-- Audit trigger must be removed from user_roles (other system triggers may remain)
SELECT morbac.t('No audit trigger on user_roles after disable_audit',
    (SELECT COUNT(*) = 0 FROM information_schema.triggers
     WHERE event_object_schema = 'morbac'
       AND event_object_table = 'user_roles'
       AND trigger_name LIKE '%audit%'),
    TRUE);

-- ---------------------------------------------------------------------------
-- Section 8: After disabling, changes are no longer logged
-- ---------------------------------------------------------------------------
\echo ''
\echo '--- 8. Disable audit stops logging ---'

-- Record current count for user_roles before post-disable operations
-- (2 entries from sections 2+3)
DO $$
DECLARE
    count_before BIGINT;
BEGIN
    SELECT COUNT(*) INTO count_before FROM morbac.audit_log WHERE table_name = 'user_roles';
    -- Store in a temp table for later assertion
    CREATE TEMP TABLE IF NOT EXISTS audit_count_check (cnt BIGINT);
    DELETE FROM audit_count_check;
    INSERT INTO audit_count_check VALUES (count_before);
END;
$$;

-- Perform another user_roles change — should NOT be logged
INSERT INTO morbac.user_roles (user_id, role_id, org_id)
VALUES (
    '30000000-0000-0000-0000-000000000011',
    '20000000-0001-0000-0000-000000000005', -- intern
    '10000000-0000-0000-0000-000000000001'
);

DELETE FROM morbac.user_roles
WHERE user_id = '30000000-0000-0000-0000-000000000011'
  AND role_id = '20000000-0001-0000-0000-000000000005';

-- Count after operations must equal count before (no new entries)
SELECT morbac.t('user_roles audit count unchanged after post-disable operations',
    (SELECT COUNT(*) FROM morbac.audit_log WHERE table_name = 'user_roles')::bigint
        = (SELECT cnt FROM audit_count_check),
    TRUE);

DROP TABLE IF EXISTS audit_count_check;

-- Disable the remaining audit triggers
SELECT morbac.disable_audit('rules');
SELECT morbac.disable_audit('delegations');

-- All audit triggers removed
SELECT morbac.t('No audit triggers remain after all disable_audit calls',
    (SELECT COUNT(*) = 0 FROM information_schema.triggers
     WHERE event_object_schema = 'morbac'
       AND trigger_name LIKE '%audit%'),
    TRUE);

\echo ''
\echo '=== Audit Logging Tests Completed ==='
