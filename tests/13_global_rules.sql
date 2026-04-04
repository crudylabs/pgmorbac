-- =============================================================================
-- Global Rules Tests
-- =============================================================================
-- Tests system-wide rules via morbac.global_rules.
--
-- Scenarios:
--   1. No global rule: Karl (no role) is denied by default
--   2. Global permission (user_id=NULL): all users gain access
--   3. Global permission (user_id=uuid): only that user gains access
--   4. Global prohibition (user_id=NULL): all users are denied regardless of role
--   5. Global prohibition (user_id=uuid): only that user is denied
--   6. Priority: global permission with higher priority overrides global prohibition
--   7. Priority: high-priority global prohibition overrides role-based permission
--   8. NULL activity/view wildcards (no hierarchy needed)
--   9. Activity/view hierarchy applies when activity/view are set
--  10. Temporal global rules (valid_from / valid_until)
--
-- Prerequisites: 00_setup.sql -> 12_user_rules.sql
-- =============================================================================

\echo ''
\echo '================================================================'
\echo '13 -- GLOBAL RULES'
\echo '================================================================'

-- ---------------------------------------------------------------------------
-- Section 1: No global rule -- Karl (no role) is denied
-- ---------------------------------------------------------------------------
\echo ''
\echo '--- 1. No global rule: access denied ---'

SELECT morbac.t('Karl (no role) reads GlobalTech contracts [no global rule]',
    morbac.is_allowed_nocache(
        '30000000-0000-0000-0000-000000000011'::uuid,
        '10000000-0000-0000-0000-000000000001'::uuid,
        'read', 'contracts'
    ), FALSE);

SELECT morbac.t('Karl (no role) reads Engineering contracts [no global rule]',
    morbac.is_allowed_nocache(
        '30000000-0000-0000-0000-000000000011'::uuid,
        '10000000-0000-0000-0000-000000000002'::uuid,
        'read', 'contracts'
    ), FALSE);

-- ---------------------------------------------------------------------------
-- Section 2: Global permission (user_id=NULL) -- all users gain access
-- ---------------------------------------------------------------------------
\echo ''
\echo '--- 2. Global permission, user_id=NULL: all users ---'

INSERT INTO morbac.global_rules (user_id, activity, view, context_id, modality)
VALUES (
    NULL,
    'read', 'contracts',
    (SELECT id FROM morbac.contexts WHERE name = 'always'),
    'permission'
);

-- Karl (no role) can now read contracts in any org
SELECT morbac.t('Karl reads GlobalTech contracts [global permission, any user]',
    morbac.is_allowed_nocache(
        '30000000-0000-0000-0000-000000000011'::uuid,
        '10000000-0000-0000-0000-000000000001'::uuid,
        'read', 'contracts'
    ), TRUE);

SELECT morbac.t('Karl reads Engineering contracts [global permission covers all orgs]',
    morbac.is_allowed_nocache(
        '30000000-0000-0000-0000-000000000011'::uuid,
        '10000000-0000-0000-0000-000000000002'::uuid,
        'read', 'contracts'
    ), TRUE);

-- Dave (employee) also benefits
SELECT morbac.t('Dave reads GlobalTech contracts [global permission, any user]',
    morbac.is_allowed_nocache(
        '30000000-0000-0000-0000-000000000004'::uuid,
        '10000000-0000-0000-0000-000000000001'::uuid,
        'read', 'contracts'
    ), TRUE);

DELETE FROM morbac.global_rules WHERE user_id IS NULL AND activity = 'read' AND view = 'contracts';

-- ---------------------------------------------------------------------------
-- Section 3: Global permission (user_id=uuid) -- specific user only
-- ---------------------------------------------------------------------------
\echo ''
\echo '--- 3. Global permission, user_id=Karl only ---'

INSERT INTO morbac.global_rules (user_id, activity, view, context_id, modality)
VALUES (
    '30000000-0000-0000-0000-000000000011', -- Karl
    'read', 'contracts',
    (SELECT id FROM morbac.contexts WHERE name = 'always'),
    'permission'
);

SELECT morbac.t('Karl reads GlobalTech contracts [user_id-specific global permission]',
    morbac.is_allowed_nocache(
        '30000000-0000-0000-0000-000000000011'::uuid,
        '10000000-0000-0000-0000-000000000001'::uuid,
        'read', 'contracts'
    ), TRUE);

-- Dave has no role permission on contracts and no global rule for him
SELECT morbac.t('Dave reads GlobalTech contracts [user_id-specific rule does not cover Dave]',
    morbac.is_allowed_nocache(
        '30000000-0000-0000-0000-000000000004'::uuid,
        '10000000-0000-0000-0000-000000000001'::uuid,
        'read', 'contracts'
    ), FALSE);

DELETE FROM morbac.global_rules
WHERE user_id = '30000000-0000-0000-0000-000000000011'
  AND activity = 'read' AND view = 'contracts';

-- ---------------------------------------------------------------------------
-- Section 4: Global prohibition (user_id=NULL) -- all users denied regardless of role
-- ---------------------------------------------------------------------------
\echo ''
\echo '--- 4. Global prohibition, user_id=NULL: all users denied ---'

-- Dave (employee) has a role-based permission on public_data from setup
SELECT morbac.t('Dave reads GlobalTech public_data [role permission before global prohibition]',
    morbac.is_allowed_nocache(
        '30000000-0000-0000-0000-000000000004'::uuid,
        '10000000-0000-0000-0000-000000000001'::uuid,
        'read', 'public_data'
    ), TRUE);

INSERT INTO morbac.global_rules (user_id, activity, view, context_id, modality)
VALUES (
    NULL,
    'read', 'public_data',
    (SELECT id FROM morbac.contexts WHERE name = 'always'),
    'prohibition'
);

SELECT morbac.t('Dave reads GlobalTech public_data [global prohibition blocks role permission]',
    morbac.is_allowed_nocache(
        '30000000-0000-0000-0000-000000000004'::uuid,
        '10000000-0000-0000-0000-000000000001'::uuid,
        'read', 'public_data'
    ), FALSE);

-- Karl (no role) is also denied
SELECT morbac.t('Karl reads GlobalTech public_data [global prohibition, no role]',
    morbac.is_allowed_nocache(
        '30000000-0000-0000-0000-000000000011'::uuid,
        '10000000-0000-0000-0000-000000000001'::uuid,
        'read', 'public_data'
    ), FALSE);

-- Alice (CEO, highest role) is also denied
SELECT morbac.t('Alice reads GlobalTech public_data [global prohibition overrides CEO role]',
    morbac.is_allowed_nocache(
        '30000000-0000-0000-0000-000000000001'::uuid,
        '10000000-0000-0000-0000-000000000001'::uuid,
        'read', 'public_data'
    ), FALSE);

DELETE FROM morbac.global_rules WHERE user_id IS NULL AND activity = 'read' AND view = 'public_data';

-- ---------------------------------------------------------------------------
-- Section 5: Global prohibition (user_id=uuid) -- specific user denied only
-- ---------------------------------------------------------------------------
\echo ''
\echo '--- 5. Global prohibition, user_id=Dave only ---'

INSERT INTO morbac.global_rules (user_id, activity, view, context_id, modality)
VALUES (
    '30000000-0000-0000-0000-000000000004', -- Dave
    'read', 'public_data',
    (SELECT id FROM morbac.contexts WHERE name = 'always'),
    'prohibition'
);

SELECT morbac.t('Dave reads GlobalTech public_data [user_id-specific global prohibition]',
    morbac.is_allowed_nocache(
        '30000000-0000-0000-0000-000000000004'::uuid,
        '10000000-0000-0000-0000-000000000001'::uuid,
        'read', 'public_data'
    ), FALSE);

-- Carol (manager) is unaffected
SELECT morbac.t('Carol reads GlobalTech public_data [global prohibition does not affect Carol]',
    morbac.is_allowed_nocache(
        '30000000-0000-0000-0000-000000000003'::uuid,
        '10000000-0000-0000-0000-000000000001'::uuid,
        'read', 'public_data'
    ), TRUE);

DELETE FROM morbac.global_rules
WHERE user_id = '30000000-0000-0000-0000-000000000004'
  AND activity = 'read' AND view = 'public_data';

-- ---------------------------------------------------------------------------
-- Section 6: Priority -- global permission overrides global prohibition
-- ---------------------------------------------------------------------------
\echo ''
\echo '--- 6. Priority: global permission > global prohibition ---'

INSERT INTO morbac.global_rules (user_id, activity, view, context_id, modality, priority)
VALUES (
    NULL,
    'read', 'public_data',
    (SELECT id FROM morbac.contexts WHERE name = 'always'),
    'prohibition', 5
);

INSERT INTO morbac.global_rules (user_id, activity, view, context_id, modality, priority)
VALUES (
    '30000000-0000-0000-0000-000000000004', -- Dave
    'read', 'public_data',
    (SELECT id FROM morbac.contexts WHERE name = 'always'),
    'permission', 10
);

SELECT morbac.t('Dave reads GlobalTech public_data [priority-10 global permission beats priority-5 global prohibition]',
    morbac.is_allowed_nocache(
        '30000000-0000-0000-0000-000000000004'::uuid,
        '10000000-0000-0000-0000-000000000001'::uuid,
        'read', 'public_data'
    ), TRUE);

-- Karl has no user_id-specific permission -- global prohibition still blocks him
SELECT morbac.t('Karl reads GlobalTech public_data [global prohibition still blocks non-exempted user]',
    morbac.is_allowed_nocache(
        '30000000-0000-0000-0000-000000000011'::uuid,
        '10000000-0000-0000-0000-000000000001'::uuid,
        'read', 'public_data'
    ), FALSE);

DELETE FROM morbac.global_rules WHERE activity = 'read' AND view = 'public_data';

-- ---------------------------------------------------------------------------
-- Section 7: Priority -- high-priority global prohibition overrides role permission
-- ---------------------------------------------------------------------------
\echo ''
\echo '--- 7. Priority: global prohibition > role permission ---'

-- Dave has role-based read on public_data (priority 0 by default)
SELECT morbac.t('Dave reads GlobalTech public_data [role permission, no global rule]',
    morbac.is_allowed_nocache(
        '30000000-0000-0000-0000-000000000004'::uuid,
        '10000000-0000-0000-0000-000000000001'::uuid,
        'read', 'public_data'
    ), TRUE);

INSERT INTO morbac.global_rules (user_id, activity, view, context_id, modality, priority)
VALUES (
    NULL,
    'read', 'public_data',
    (SELECT id FROM morbac.contexts WHERE name = 'always'),
    'prohibition', 100
);

SELECT morbac.t('Dave reads GlobalTech public_data [priority-100 global prohibition beats role permission]',
    morbac.is_allowed_nocache(
        '30000000-0000-0000-0000-000000000004'::uuid,
        '10000000-0000-0000-0000-000000000001'::uuid,
        'read', 'public_data'
    ), FALSE);

DELETE FROM morbac.global_rules WHERE activity = 'read' AND view = 'public_data';

-- ---------------------------------------------------------------------------
-- Section 8: NULL activity/view wildcards
-- ---------------------------------------------------------------------------
\echo ''
\echo '--- 8. NULL wildcards: activity=NULL and view=NULL ---'

-- view=NULL grants read on every view for Karl (no role)
INSERT INTO morbac.global_rules (user_id, activity, view, context_id, modality)
VALUES (
    '30000000-0000-0000-0000-000000000011', -- Karl
    'read', NULL,
    (SELECT id FROM morbac.contexts WHERE name = 'always'),
    'permission'
);

SELECT morbac.t('Karl reads GlobalTech contracts [view=NULL global permission]',
    morbac.is_allowed_nocache(
        '30000000-0000-0000-0000-000000000011'::uuid,
        '10000000-0000-0000-0000-000000000001'::uuid,
        'read', 'contracts'
    ), TRUE);

SELECT morbac.t('Karl reads GlobalTech financial_data [view=NULL global permission]',
    morbac.is_allowed_nocache(
        '30000000-0000-0000-0000-000000000011'::uuid,
        '10000000-0000-0000-0000-000000000001'::uuid,
        'read', 'financial_data'
    ), TRUE);

DELETE FROM morbac.global_rules
WHERE user_id = '30000000-0000-0000-0000-000000000011'
  AND activity = 'read' AND view IS NULL;

-- activity=NULL and view=NULL grants everything
INSERT INTO morbac.global_rules (user_id, activity, view, context_id, modality)
VALUES (
    '30000000-0000-0000-0000-000000000011', -- Karl
    NULL, NULL,
    (SELECT id FROM morbac.contexts WHERE name = 'always'),
    'permission'
);

SELECT morbac.t('Karl deletes GlobalTech contracts [activity=NULL, view=NULL global permission]',
    morbac.is_allowed_nocache(
        '30000000-0000-0000-0000-000000000011'::uuid,
        '10000000-0000-0000-0000-000000000001'::uuid,
        'delete', 'contracts'
    ), TRUE);

DELETE FROM morbac.global_rules
WHERE user_id = '30000000-0000-0000-0000-000000000011'
  AND activity IS NULL AND view IS NULL;

-- ---------------------------------------------------------------------------
-- Section 9: Activity/view hierarchy applies when activity/view are set
-- ---------------------------------------------------------------------------
\echo ''
\echo '--- 9. Activity/view hierarchy ---'

-- financial_data is a child of documents (view hierarchy from setup)
-- A global permission on 'documents' should cover 'financial_data'
INSERT INTO morbac.global_rules (user_id, activity, view, context_id, modality)
VALUES (
    '30000000-0000-0000-0000-000000000011', -- Karl
    'read', 'documents',
    (SELECT id FROM morbac.contexts WHERE name = 'always'),
    'permission'
);

SELECT morbac.t('Karl reads GlobalTech financial_data [global permission on documents covers child view]',
    morbac.is_allowed_nocache(
        '30000000-0000-0000-0000-000000000011'::uuid,
        '10000000-0000-0000-0000-000000000001'::uuid,
        'read', 'financial_data'
    ), TRUE);

DELETE FROM morbac.global_rules
WHERE user_id = '30000000-0000-0000-0000-000000000011'
  AND activity = 'read' AND view = 'documents';

-- ---------------------------------------------------------------------------
-- Section 10: Temporal global rules
-- ---------------------------------------------------------------------------
\echo ''
\echo '--- 10. Temporal global rules ---'

INSERT INTO morbac.global_rules (user_id, activity, view, context_id, modality, valid_from, valid_until)
VALUES (
    '30000000-0000-0000-0000-000000000011', -- Karl
    'read', 'contracts',
    (SELECT id FROM morbac.contexts WHERE name = 'always'),
    'permission',
    now() - interval '1 hour',
    now() + interval '1 day'
);

SELECT morbac.t('Karl reads GlobalTech contracts [temporal global rule, active]',
    morbac.is_allowed_nocache(
        '30000000-0000-0000-0000-000000000011'::uuid,
        '10000000-0000-0000-0000-000000000001'::uuid,
        'read', 'contracts'
    ), TRUE);

UPDATE morbac.global_rules
SET valid_until = now() - interval '1 second'
WHERE user_id = '30000000-0000-0000-0000-000000000011'
  AND activity = 'read' AND view = 'contracts';

SELECT morbac.t('Karl reads GlobalTech contracts [temporal global rule, expired]',
    morbac.is_allowed_nocache(
        '30000000-0000-0000-0000-000000000011'::uuid,
        '10000000-0000-0000-0000-000000000001'::uuid,
        'read', 'contracts'
    ), FALSE);

\echo ''
\echo '=== Global Rules Tests Completed ==='
