-- =============================================================================
-- System Principals Tests
-- =============================================================================
-- Tests the morbac.system_principals registry and all associated protections.
--
-- Scenarios:
--   1. Setup: register a system principal and define its permissions via global_rules
--   2. Permissions work normally (system principal can access what it is granted)
--   3. Prohibitions are ignored (no role-based, user-level, or global prohibition applies)
--   4. Cannot assign roles to a system principal
--   5. Cannot revoke roles from a system principal
--   6. Cannot add negative role assignments for a system principal
--   7. Cannot add user_rules for a system principal
--   8. Cannot create delegations involving a system principal
--   9. Cannot add a targeted global_rules prohibition for a system principal
--  10. Cannot modify or delete existing global_rules for a system principal
--
-- Prerequisites: 00_setup.sql -> 13_global_rules.sql
-- =============================================================================

\echo ''
\echo '================================================================'
\echo '14 -- SYSTEM PRINCIPALS'
\echo '================================================================'

-- ---------------------------------------------------------------------------
-- Section 1: Setup
-- ---------------------------------------------------------------------------
\echo ''
\echo '--- 1. Setup ---'

-- Register a system principal (done as DB owner at deploy time)
INSERT INTO morbac.system_principals (user_id, description)
VALUES (
    '40000000-0000-0000-0000-000000000001',
    'Backend API service account'
);

-- Define its permissions via global_rules (immutable once inserted)
INSERT INTO morbac.global_rules (user_id, activity, view, context_id, modality)
VALUES (
    '40000000-0000-0000-0000-000000000001',
    NULL, NULL,
    (SELECT id FROM morbac.contexts WHERE name = 'always'),
    'permission'
);

SELECT morbac.t('System principal registered',
    EXISTS (SELECT 1 FROM morbac.system_principals WHERE user_id = '40000000-0000-0000-0000-000000000001'),
    TRUE);

-- ---------------------------------------------------------------------------
-- Section 2: Permissions work
-- ---------------------------------------------------------------------------
\echo ''
\echo '--- 2. System principal permissions are effective ---'

SELECT morbac.t('System principal reads GlobalTech documents [global permission, activity=NULL view=NULL]',
    morbac.is_allowed_nocache(
        '40000000-0000-0000-0000-000000000001'::uuid,
        '10000000-0000-0000-0000-000000000001'::uuid,
        'read', 'documents'
    ), TRUE);

SELECT morbac.t('System principal deletes Engineering contracts [global permission covers all]',
    morbac.is_allowed_nocache(
        '40000000-0000-0000-0000-000000000001'::uuid,
        '10000000-0000-0000-0000-000000000002'::uuid,
        'delete', 'contracts'
    ), TRUE);

-- ---------------------------------------------------------------------------
-- Section 3: Prohibitions are ignored
-- ---------------------------------------------------------------------------
\echo ''
\echo '--- 3. Prohibitions are ignored for system principals ---'

-- Insert a blanket global prohibition (user_id=NULL affects everyone normally)
INSERT INTO morbac.global_rules (user_id, activity, view, context_id, modality, priority)
VALUES (
    NULL,
    'delete', 'contracts',
    (SELECT id FROM morbac.contexts WHERE name = 'always'),
    'prohibition', 999
);

SELECT morbac.t('System principal deletes contracts [blanket global prohibition ignored]',
    morbac.is_allowed_nocache(
        '40000000-0000-0000-0000-000000000001'::uuid,
        '10000000-0000-0000-0000-000000000001'::uuid,
        'delete', 'contracts'
    ), TRUE);

-- Regular user is still affected by the prohibition
SELECT morbac.t('Dave deletes GlobalTech contracts [blanket prohibition applies to regular users]',
    morbac.is_allowed_nocache(
        '30000000-0000-0000-0000-000000000004'::uuid,
        '10000000-0000-0000-0000-000000000001'::uuid,
        'delete', 'contracts'
    ), FALSE);

DELETE FROM morbac.global_rules
WHERE user_id IS NULL AND activity = 'delete' AND view = 'contracts';

-- ---------------------------------------------------------------------------
-- Section 4: Cannot assign roles to a system principal
-- ---------------------------------------------------------------------------
\echo ''
\echo '--- 4. Role assignment blocked ---'

SELECT morbac.t('Assigning role to system principal raises exception',
    (SELECT COUNT(*) FROM (
        SELECT morbac.assign_role(
            '40000000-0000-0000-0000-000000000001'::uuid,
            (SELECT id FROM morbac.roles WHERE name = 'employee' AND org_id = '10000000-0000-0000-0000-000000000001'),
            '10000000-0000-0000-0000-000000000001'::uuid
        )
    ) sub) = 0,
    FALSE
) WHERE FALSE; -- skip, tested via exception below

DO $$
BEGIN
    INSERT INTO morbac.user_roles (user_id, role_id, org_id)
    VALUES (
        '40000000-0000-0000-0000-000000000001',
        (SELECT id FROM morbac.roles WHERE name = 'employee' AND org_id = '10000000-0000-0000-0000-000000000001'),
        '10000000-0000-0000-0000-000000000001'
    );
    RAISE EXCEPTION 'expected exception not raised';
EXCEPTION
    WHEN OTHERS THEN
        IF SQLERRM LIKE '%system principal%' THEN
            RAISE NOTICE 'PASS: role assignment to system principal blocked';
        ELSE
            RAISE;
        END IF;
END;
$$;

-- ---------------------------------------------------------------------------
-- Section 5: Cannot add negative role assignments for a system principal
-- ---------------------------------------------------------------------------
\echo ''
\echo '--- 5. Negative role assignment blocked ---'

DO $$
BEGIN
    INSERT INTO morbac.negative_role_assignments (user_id, role_id, org_id)
    VALUES (
        '40000000-0000-0000-0000-000000000001',
        (SELECT id FROM morbac.roles WHERE name = 'employee' AND org_id = '10000000-0000-0000-0000-000000000001'),
        '10000000-0000-0000-0000-000000000001'
    );
    RAISE EXCEPTION 'expected exception not raised';
EXCEPTION
    WHEN OTHERS THEN
        IF SQLERRM LIKE '%system principal%' THEN
            RAISE NOTICE 'PASS: negative role assignment for system principal blocked';
        ELSE
            RAISE;
        END IF;
END;
$$;

-- ---------------------------------------------------------------------------
-- Section 6: Cannot add user_rules for a system principal
-- ---------------------------------------------------------------------------
\echo ''
\echo '--- 6. user_rules blocked ---'

DO $$
BEGIN
    INSERT INTO morbac.user_rules (user_id, org_id, activity, view, context_id, modality)
    VALUES (
        '40000000-0000-0000-0000-000000000001',
        '10000000-0000-0000-0000-000000000001',
        'read', 'documents',
        (SELECT id FROM morbac.contexts WHERE name = 'always'),
        'permission'
    );
    RAISE EXCEPTION 'expected exception not raised';
EXCEPTION
    WHEN OTHERS THEN
        IF SQLERRM LIKE '%system principal%' THEN
            RAISE NOTICE 'PASS: user_rules insert for system principal blocked';
        ELSE
            RAISE;
        END IF;
END;
$$;

-- ---------------------------------------------------------------------------
-- Section 7: Cannot create delegations involving a system principal
-- ---------------------------------------------------------------------------
\echo ''
\echo '--- 7. Delegations blocked ---'

DO $$
BEGIN
    INSERT INTO morbac.delegations (delegator_id, delegatee_id, role_id, org_id)
    VALUES (
        '30000000-0000-0000-0000-000000000001', -- Alice as delegator
        '40000000-0000-0000-0000-000000000001', -- system principal as delegatee
        (SELECT id FROM morbac.roles WHERE name = 'employee' AND org_id = '10000000-0000-0000-0000-000000000001'),
        '10000000-0000-0000-0000-000000000001'
    );
    RAISE EXCEPTION 'expected exception not raised';
EXCEPTION
    WHEN OTHERS THEN
        IF SQLERRM LIKE '%system principal%' THEN
            RAISE NOTICE 'PASS: delegation to system principal blocked';
        ELSE
            RAISE;
        END IF;
END;
$$;

-- ---------------------------------------------------------------------------
-- Section 8: Cannot add a targeted global_rules prohibition
-- ---------------------------------------------------------------------------
\echo ''
\echo '--- 8. Targeted global prohibition blocked ---'

DO $$
BEGIN
    INSERT INTO morbac.global_rules (user_id, activity, view, context_id, modality)
    VALUES (
        '40000000-0000-0000-0000-000000000001',
        'delete', 'contracts',
        (SELECT id FROM morbac.contexts WHERE name = 'always'),
        'prohibition'
    );
    RAISE EXCEPTION 'expected exception not raised';
EXCEPTION
    WHEN OTHERS THEN
        IF SQLERRM LIKE '%system principal%' THEN
            RAISE NOTICE 'PASS: global prohibition targeting system principal blocked';
        ELSE
            RAISE;
        END IF;
END;
$$;

-- ---------------------------------------------------------------------------
-- Section 9: Cannot add a permission global_rule for a system principal
-- ---------------------------------------------------------------------------
\echo ''
\echo '--- 9. New global permission for system principal blocked ---'

DO $$
BEGIN
    INSERT INTO morbac.global_rules (user_id, activity, view, context_id, modality)
    VALUES (
        '40000000-0000-0000-0000-000000000001',
        'read', 'documents',
        (SELECT id FROM morbac.contexts WHERE name = 'always'),
        'permission'
    );
    RAISE EXCEPTION 'expected exception not raised';
EXCEPTION
    WHEN OTHERS THEN
        IF SQLERRM LIKE '%system principal%' THEN
            RAISE NOTICE 'PASS: new global permission for system principal blocked (define at deploy time only)';
        ELSE
            RAISE;
        END IF;
END;
$$;

-- ---------------------------------------------------------------------------
-- Section 10: Cannot delete existing global_rules for a system principal
-- ---------------------------------------------------------------------------
\echo ''
\echo '--- 10. Deleting system principal global_rules blocked ---'

DO $$
BEGIN
    DELETE FROM morbac.global_rules
    WHERE user_id = '40000000-0000-0000-0000-000000000001';
    RAISE EXCEPTION 'expected exception not raised';
EXCEPTION
    WHEN OTHERS THEN
        IF SQLERRM LIKE '%system principal%' THEN
            RAISE NOTICE 'PASS: deletion of system principal global rules blocked';
        ELSE
            RAISE;
        END IF;
END;
$$;

\echo ''
\echo '=== System Principals Tests Completed ==='
