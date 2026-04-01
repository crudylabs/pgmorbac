-- =============================================================================
-- User Rules Tests
-- =============================================================================
-- Tests direct user-level rules via morbac.user_rules.
--
-- Scenarios:
--   1. No user rule: Karl (no role) is denied by default
--   2. Direct user permission: Karl gets access without any role assignment
--   3. User rule covers activity/view hierarchy
--   4. User-level prohibition overrides a role-based permission
--   5. Priority: user permission with higher priority overrides user prohibition
--   6. Temporal user rules (valid_from / valid_until)
--   7. rls_check user filter: morbac.target_user_id scopes rows to a specific user
--
-- Prerequisites: 00_setup.sql -> 11_scope_rules.sql
-- =============================================================================

\echo ''
\echo '================================================================'
\echo '12 — USER RULES'
\echo '================================================================'

-- ---------------------------------------------------------------------------
-- Section 1: No user rule — Karl (no role) is denied
-- ---------------------------------------------------------------------------
\echo ''
\echo '--- 1. No user rule: access denied ---'

SELECT morbac.t('Karl (no role) reads GlobalTech documents [no user rule]',
    morbac.is_allowed_nocache(
        '30000000-0000-0000-0000-000000000011'::uuid,
        '10000000-0000-0000-0000-000000000001'::uuid,
        'read', 'documents'
    ), FALSE);

SELECT morbac.t('Karl (no role) reads GlobalTech financial_data [no user rule]',
    morbac.is_allowed_nocache(
        '30000000-0000-0000-0000-000000000011'::uuid,
        '10000000-0000-0000-0000-000000000001'::uuid,
        'read', 'financial_data'
    ), FALSE);

-- ---------------------------------------------------------------------------
-- Section 2: Direct user permission — Karl gets access without a role
-- ---------------------------------------------------------------------------
\echo ''
\echo '--- 2. Direct user permission ---'

INSERT INTO morbac.user_rules (user_id, org_id, activity, view, context_id, modality)
VALUES (
    '30000000-0000-0000-0000-000000000011', -- Karl
    '10000000-0000-0000-0000-000000000001', -- GlobalTech HQ
    'read', 'documents',
    (SELECT id FROM morbac.contexts WHERE name = 'always'),
    'permission'
);

SELECT morbac.t('Karl (no role) reads GlobalTech documents [user rule grants access]',
    morbac.is_allowed_nocache(
        '30000000-0000-0000-0000-000000000011'::uuid,
        '10000000-0000-0000-0000-000000000001'::uuid,
        'read', 'documents'
    ), TRUE);

-- Rule only covers GlobalTech, not Engineering
SELECT morbac.t('Karl reads Engineering documents [no user rule for Engineering]',
    morbac.is_allowed_nocache(
        '30000000-0000-0000-0000-000000000011'::uuid,
        '10000000-0000-0000-0000-000000000002'::uuid,
        'read', 'documents'
    ), FALSE);

-- financial_data is a subtype of documents (view hierarchy), so the documents rule covers it
SELECT morbac.t('Karl reads GlobalTech financial_data [documents rule covers it via view hierarchy]',
    morbac.is_allowed_nocache(
        '30000000-0000-0000-0000-000000000011'::uuid,
        '10000000-0000-0000-0000-000000000001'::uuid,
        'read', 'financial_data'
    ), TRUE);

-- contracts has no hierarchy relationship — documents rule does not cover it
SELECT morbac.t('Karl reads GlobalTech contracts [no user rule, no hierarchy coverage]',
    morbac.is_allowed_nocache(
        '30000000-0000-0000-0000-000000000011'::uuid,
        '10000000-0000-0000-0000-000000000001'::uuid,
        'read', 'contracts'
    ), FALSE);

-- ---------------------------------------------------------------------------
-- Section 3: User rule + activity/view hierarchy
-- ---------------------------------------------------------------------------
\echo ''
\echo '--- 3. User rule with activity/view hierarchy ---'

-- Add a user rule for 'read reports' (parent of financial_data via view hierarchy)
INSERT INTO morbac.user_rules (user_id, org_id, activity, view, context_id, modality)
VALUES (
    '30000000-0000-0000-0000-000000000011', -- Karl
    '10000000-0000-0000-0000-000000000001', -- GlobalTech HQ
    'read', 'reports',
    (SELECT id FROM morbac.contexts WHERE name = 'always'),
    'permission'
);

-- get_effective_activities('write') includes 'read', so read permission covers write requests
SELECT morbac.t('Karl writes GlobalTech documents [user rule read covers write via activity hierarchy]',
    morbac.is_allowed_nocache(
        '30000000-0000-0000-0000-000000000011'::uuid,
        '10000000-0000-0000-0000-000000000001'::uuid,
        'write', 'documents'
    ), TRUE);

-- ---------------------------------------------------------------------------
-- Section 4: User-level prohibition overrides role-based permission
-- ---------------------------------------------------------------------------
\echo ''
\echo '--- 4. User prohibition overrides role permission ---'

-- Eve (intern) can read public_data via role
SELECT morbac.t('Eve (intern) reads GlobalTech public_data [role permission]',
    morbac.is_allowed_nocache(
        '30000000-0000-0000-0000-000000000005'::uuid,
        '10000000-0000-0000-0000-000000000001'::uuid,
        'read', 'public_data'
    ), TRUE);

-- Add a user prohibition for Eve on public_data
INSERT INTO morbac.user_rules (user_id, org_id, activity, view, context_id, modality)
VALUES (
    '30000000-0000-0000-0000-000000000005', -- Eve
    '10000000-0000-0000-0000-000000000001', -- GlobalTech HQ
    'read', 'public_data',
    (SELECT id FROM morbac.contexts WHERE name = 'always'),
    'prohibition'
);

SELECT morbac.t('Eve (intern) reads GlobalTech public_data [user prohibition blocks role permission]',
    morbac.is_allowed_nocache(
        '30000000-0000-0000-0000-000000000005'::uuid,
        '10000000-0000-0000-0000-000000000001'::uuid,
        'read', 'public_data'
    ), FALSE);

-- Dave (employee) is unaffected — only Eve has the prohibition
SELECT morbac.t('Dave (employee) reads GlobalTech public_data [no user prohibition]',
    morbac.is_allowed_nocache(
        '30000000-0000-0000-0000-000000000004'::uuid,
        '10000000-0000-0000-0000-000000000001'::uuid,
        'read', 'public_data'
    ), TRUE);

-- ---------------------------------------------------------------------------
-- Section 5: Priority — higher-priority user permission overrides prohibition
-- ---------------------------------------------------------------------------
\echo ''
\echo '--- 5. Priority: user permission overrides user prohibition ---'

-- Eve has a prohibition (priority 0) on public_data; add a higher-priority permission
INSERT INTO morbac.user_rules (user_id, org_id, activity, view, context_id, modality, priority)
VALUES (
    '30000000-0000-0000-0000-000000000005', -- Eve
    '10000000-0000-0000-0000-000000000001', -- GlobalTech HQ
    'read', 'public_data',
    (SELECT id FROM morbac.contexts WHERE name = 'always'),
    'permission',
    10
);

SELECT morbac.t('Eve reads GlobalTech public_data [priority-10 user permission beats priority-0 prohibition]',
    morbac.is_allowed_nocache(
        '30000000-0000-0000-0000-000000000005'::uuid,
        '10000000-0000-0000-0000-000000000001'::uuid,
        'read', 'public_data'
    ), TRUE);

-- Clean up the priority override for the temporal test
DELETE FROM morbac.user_rules
WHERE user_id = '30000000-0000-0000-0000-000000000005'
  AND modality = 'permission'
  AND priority = 10;

-- ---------------------------------------------------------------------------
-- Section 6: Temporal user rules
-- ---------------------------------------------------------------------------
\echo ''
\echo '--- 6. Temporal user rules ---'

-- Use contracts: Karl has no other rules covering it, so expiry is conclusive
INSERT INTO morbac.user_rules (user_id, org_id, activity, view, context_id, modality, valid_from, valid_until)
VALUES (
    '30000000-0000-0000-0000-000000000011', -- Karl
    '10000000-0000-0000-0000-000000000001', -- GlobalTech HQ
    'read', 'contracts',
    (SELECT id FROM morbac.contexts WHERE name = 'always'),
    'permission',
    now() - interval '1 hour',
    now() + interval '1 day'
);

SELECT morbac.t('Karl reads GlobalTech contracts [temporal user rule, active]',
    morbac.is_allowed_nocache(
        '30000000-0000-0000-0000-000000000011'::uuid,
        '10000000-0000-0000-0000-000000000001'::uuid,
        'read', 'contracts'
    ), TRUE);

-- Expire the rule
UPDATE morbac.user_rules
SET valid_until = now() - interval '1 second'
WHERE user_id = '30000000-0000-0000-0000-000000000011'
  AND org_id = '10000000-0000-0000-0000-000000000001'
  AND activity = 'read' AND view = 'contracts'
  AND modality = 'permission';

SELECT morbac.t('Karl reads GlobalTech contracts [temporal user rule, expired]',
    morbac.is_allowed_nocache(
        '30000000-0000-0000-0000-000000000011'::uuid,
        '10000000-0000-0000-0000-000000000001'::uuid,
        'read', 'contracts'
    ), FALSE);

-- ---------------------------------------------------------------------------
-- Section 7: rls_check user filter via morbac.target_user_id
-- ---------------------------------------------------------------------------
\echo ''
\echo '--- 7. rls_check user filter ---'

SET morbac.user_id = '30000000-0000-0000-0000-000000000004'; -- Dave (employee)
SET morbac.org_id  = '10000000-0000-0000-0000-000000000001'; -- GlobalTech HQ

-- No target_user_id set: row with any user_id passes the user filter
SELECT morbac.t('rls_check passes without target_user_id filter',
    morbac.rls_check(
        'read', 'documents',
        '10000000-0000-0000-0000-000000000001'::uuid,
        '30000000-0000-0000-0000-000000000004'::uuid
    ), TRUE);

-- Set target_user_id to Dave — rows belonging to Dave pass
SET morbac.target_user_id = '30000000-0000-0000-0000-000000000004';

SELECT morbac.t('rls_check passes when row user_id matches target_user_id',
    morbac.rls_check(
        'read', 'documents',
        '10000000-0000-0000-0000-000000000001'::uuid,
        '30000000-0000-0000-0000-000000000004'::uuid
    ), TRUE);

-- Row belonging to Alice is filtered out
SELECT morbac.t('rls_check blocked when row user_id differs from target_user_id',
    morbac.rls_check(
        'read', 'documents',
        '10000000-0000-0000-0000-000000000001'::uuid,
        '30000000-0000-0000-0000-000000000001'::uuid
    ), FALSE);

-- No p_row_user_id passed — user filter does not apply
SELECT morbac.t('rls_check passes when no row user_id passed (filter skipped)',
    morbac.rls_check(
        'read', 'documents',
        '10000000-0000-0000-0000-000000000001'::uuid
    ), TRUE);

RESET morbac.target_user_id;
RESET morbac.user_id;
RESET morbac.org_id;

\echo ''
\echo '=== User Rules Tests Completed ==='
