-- =============================================================================
-- rls_check Tests
-- =============================================================================
-- Tests morbac.rls_check() with all session-org combinations, focusing on
-- the two cases fixed to support global rows (p_row_org_id IS NULL):
--
--   1. No user_id set: always FALSE
--   2. Single org context
--      a. org-scoped row, matching org
--      b. org-scoped row, different org (blocked)
--      c. global row (NULL org_id): uses session org
--   3. org_ids filter
--      a. org-scoped row in list
--      b. org-scoped row not in list (blocked)
--      c. global row + global permission  [was FALSE, now TRUE]
--      d. global row + global prohibition [was FALSE, now correctly FALSE]
--      e. global row + no rule            [was FALSE, still FALSE]
--   4. No org context
--      a. org-scoped row: uses row's org
--      b. global row + global permission  [was FALSE, now TRUE]
--      c. global row + global prohibition [was FALSE, now correctly FALSE]
--      d. global row + no rule            [was FALSE, still FALSE]
--
-- User state carried from previous tests:
--   Karl (30000000-0000-0000-0000-000000000011):
--     - user_rules: read documents, read reports in GlobalTech HQ (no expiry)
--     - no role assignments, no org memberships
--
-- Prerequisites: 00_setup.sql -> 14_system_principals.sql
-- =============================================================================

\echo ''
\echo '================================================================'
\echo '15 -- RLS_CHECK'
\echo '================================================================'

-- ---------------------------------------------------------------------------
-- Section 1: No user_id set — always FALSE
-- ---------------------------------------------------------------------------
\echo ''
\echo '--- 1. No user_id: always FALSE ---'

RESET morbac.user_id;
RESET morbac.org_id;
RESET morbac.org_ids;

SELECT morbac.t('rls_check without user_id, org row',
    morbac.rls_check('read', 'documents',
        '10000000-0000-0000-0000-000000000001'::uuid),
    FALSE);

SELECT morbac.t('rls_check without user_id, global row',
    morbac.rls_check('read', 'contracts', NULL),
    FALSE);

-- ---------------------------------------------------------------------------
-- Section 2: Single org context
-- ---------------------------------------------------------------------------
\echo ''
\echo '--- 2. Single org context ---'

SET morbac.user_id = '30000000-0000-0000-0000-000000000011'; -- Karl
SET morbac.org_id  = '10000000-0000-0000-0000-000000000001'; -- GlobalTech HQ

-- 2a: org-scoped row, matching org — Karl has user_rule for read documents
SELECT morbac.t('rls_check single org, org row matches session org (Karl/documents)',
    morbac.rls_check('read', 'documents',
        '10000000-0000-0000-0000-000000000001'::uuid),
    TRUE);

-- 2b: org-scoped row, different org — blocked before is_allowed
SELECT morbac.t('rls_check single org, org row from different org (blocked)',
    morbac.rls_check('read', 'documents',
        '10000000-0000-0000-0000-000000000002'::uuid),
    FALSE);

-- 2c: global row — uses session org, so Karl's user_rule on GlobalTech applies
SELECT morbac.t('rls_check single org, global row (NULL org_id): uses session org',
    morbac.rls_check('read', 'documents', NULL),
    TRUE);

-- 2c (no permission): Karl has no rule for contracts in GlobalTech
SELECT morbac.t('rls_check single org, global row (NULL org_id): no permission for contracts',
    morbac.rls_check('read', 'contracts', NULL),
    FALSE);

RESET morbac.user_id;
RESET morbac.org_id;

-- ---------------------------------------------------------------------------
-- Section 3: org_ids filter
-- ---------------------------------------------------------------------------
\echo ''
\echo '--- 3. org_ids filter ---'

SET morbac.user_id = '30000000-0000-0000-0000-000000000011'; -- Karl
SET morbac.org_ids = '["10000000-0000-0000-0000-000000000001"]'; -- [GlobalTech HQ]

-- 3a: org-scoped row in the list — Karl has user_rule for read documents in GlobalTech
SELECT morbac.t('rls_check org_ids, org row in list (Karl/documents/GlobalTech)',
    morbac.rls_check('read', 'documents',
        '10000000-0000-0000-0000-000000000001'::uuid),
    TRUE);

-- 3b: org-scoped row not in the list — blocked
SELECT morbac.t('rls_check org_ids, org row not in list (blocked)',
    morbac.rls_check('read', 'documents',
        '10000000-0000-0000-0000-000000000002'::uuid),
    FALSE);

-- 3c: global row + global permission — now goes to is_allowed(Karl, NULL, ...) → global_rules only
INSERT INTO morbac.global_rules (user_id, activity, view, context_id, modality)
VALUES (
    '30000000-0000-0000-0000-000000000011', -- Karl
    'read', 'contracts',
    (SELECT id FROM morbac.contexts WHERE name = 'always'),
    'permission'
);

SELECT morbac.t('rls_check org_ids, global row + global permission [new: was FALSE]',
    morbac.rls_check('read', 'contracts', NULL),
    TRUE);

DELETE FROM morbac.global_rules
WHERE user_id = '30000000-0000-0000-0000-000000000011'
  AND activity = 'read' AND view = 'contracts';

-- 3d: global row + global prohibition
INSERT INTO morbac.global_rules (user_id, activity, view, context_id, modality)
VALUES (
    '30000000-0000-0000-0000-000000000011', -- Karl
    'read', 'contracts',
    (SELECT id FROM morbac.contexts WHERE name = 'always'),
    'prohibition'
);

SELECT morbac.t('rls_check org_ids, global row + global prohibition',
    morbac.rls_check('read', 'contracts', NULL),
    FALSE);

DELETE FROM morbac.global_rules
WHERE user_id = '30000000-0000-0000-0000-000000000011'
  AND activity = 'read' AND view = 'contracts';

-- 3e: global row + no rule
SELECT morbac.t('rls_check org_ids, global row + no rule',
    morbac.rls_check('read', 'contracts', NULL),
    FALSE);

RESET morbac.user_id;
RESET morbac.org_ids;

-- ---------------------------------------------------------------------------
-- Section 4: No org context
-- ---------------------------------------------------------------------------
\echo ''
\echo '--- 4. No org context ---'

SET morbac.user_id = '30000000-0000-0000-0000-000000000011'; -- Karl

-- 4a: org-scoped row — uses row's org_id (Karl has user_rule in GlobalTech)
SELECT morbac.t('rls_check no org context, org row: uses row org (Karl/documents/GlobalTech)',
    morbac.rls_check('read', 'documents',
        '10000000-0000-0000-0000-000000000001'::uuid),
    TRUE);

-- 4a (no permission): Karl has no rule in Engineering
SELECT morbac.t('rls_check no org context, org row: no permission in row org (Engineering)',
    morbac.rls_check('read', 'documents',
        '10000000-0000-0000-0000-000000000002'::uuid),
    FALSE);

-- 4b: global row + global permission — now goes to is_allowed(Karl, NULL, ...) → global_rules only
INSERT INTO morbac.global_rules (user_id, activity, view, context_id, modality)
VALUES (
    '30000000-0000-0000-0000-000000000011', -- Karl
    'read', 'contracts',
    (SELECT id FROM morbac.contexts WHERE name = 'always'),
    'permission'
);

SELECT morbac.t('rls_check no org context, global row + global permission [new: was FALSE]',
    morbac.rls_check('read', 'contracts', NULL),
    TRUE);

DELETE FROM morbac.global_rules
WHERE user_id = '30000000-0000-0000-0000-000000000011'
  AND activity = 'read' AND view = 'contracts';

-- 4c: global row + global prohibition
INSERT INTO morbac.global_rules (user_id, activity, view, context_id, modality)
VALUES (
    '30000000-0000-0000-0000-000000000011', -- Karl
    'read', 'contracts',
    (SELECT id FROM morbac.contexts WHERE name = 'always'),
    'prohibition'
);

SELECT morbac.t('rls_check no org context, global row + global prohibition',
    morbac.rls_check('read', 'contracts', NULL),
    FALSE);

DELETE FROM morbac.global_rules
WHERE user_id = '30000000-0000-0000-0000-000000000011'
  AND activity = 'read' AND view = 'contracts';

-- 4d: global row + no rule
SELECT morbac.t('rls_check no org context, global row + no rule',
    morbac.rls_check('read', 'contracts', NULL),
    FALSE);

RESET morbac.user_id;

\echo ''
\echo '=== rls_check Tests Completed ==='
