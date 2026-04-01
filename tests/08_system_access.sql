-- =============================================================================
-- System Access Tests
-- =============================================================================
-- morbac system tables are protected by RLS.
-- is_allowed() and its internals are SECURITY DEFINER to avoid recursion.
-- System view names are config-driven (system_view.* keys, default: orgs/roles/rules/...).
--
-- Scenarios:
--   1. Default deny: no rule = no access to system views via is_allowed()
--   2. Grant permissions via regular rules, verify access
--   3. Prohibition overrides permission (standard engine behavior)
--   4. Role hierarchy applies: senior role inherits permissions
--   5. assign_role() / revoke_role() — SoD/cardinality enforcement, RLS guards the INSERT/DELETE
--   6. RLS on morbac tables: session user cannot read/write without rules
--   7. Rules are org-scoped
--
-- Prerequisites: 00_setup.sql -> 07_audit.sql
-- =============================================================================

\echo ''
\echo '================================================================'
\echo '08 — SYSTEM ACCESS'
\echo '================================================================'

-- ---------------------------------------------------------------------------
-- Section 1: Default deny
-- ---------------------------------------------------------------------------
\echo ''
\echo '--- 1. Default deny: no rule = no access to system views ---'

SELECT morbac.t('Carol (manager) create rules [default deny]',
    morbac.is_allowed(
        '30000000-0000-0000-0000-000000000003'::uuid,
        '10000000-0000-0000-0000-000000000001'::uuid,
        'create', 'rules'
    ), FALSE);

SELECT morbac.t('Grace (hr_manager) create user_roles [default deny]',
    morbac.is_allowed(
        '30000000-0000-0000-0000-000000000007'::uuid,
        '10000000-0000-0000-0000-000000000001'::uuid,
        'create', 'user_roles'
    ), FALSE);

-- ---------------------------------------------------------------------------
-- Section 2: Grant permissions via regular rules
-- ---------------------------------------------------------------------------
\echo ''
\echo '--- 2. Grant permissions ---'

INSERT INTO morbac.rules (org_id, role_id, activity, view, context_id, modality)
SELECT o.id, r.id, v.activity, v.view, c.id, v.modality::morbac.modality
FROM (VALUES
    ('GlobalTech HQ', 'manager',    'create', 'rules',      'always', 'permission'),
    ('GlobalTech HQ', 'manager',    'delete', 'rules',      'always', 'permission'),
    ('GlobalTech HQ', 'hr_manager', 'read',   'user_roles', 'always', 'permission'),
    ('GlobalTech HQ', 'hr_manager', 'create', 'user_roles', 'always', 'permission'),
    ('GlobalTech HQ', 'hr_manager', 'delete', 'user_roles', 'always', 'permission'),
    ('GlobalTech HQ', 'director',   'create', 'roles',      'always', 'permission'),
    ('GlobalTech HQ', 'director',   'read',   'roles',      'always', 'permission'),
    ('GlobalTech HQ', 'director',   'update', 'roles',      'always', 'permission'),
    ('GlobalTech HQ', 'director',   'delete', 'roles',      'always', 'permission')
) AS v(org_name, role_name, activity, view, context_name, modality)
JOIN morbac.orgs o ON o.name = v.org_name
JOIN morbac.roles r ON r.org_id = o.id AND r.name = v.role_name
JOIN morbac.contexts c ON c.name = v.context_name;

\echo ''
\echo '--- 3. Verify permissions ---'

SELECT morbac.t('Carol (manager) create rules',
    morbac.is_allowed(
        '30000000-0000-0000-0000-000000000003'::uuid,
        '10000000-0000-0000-0000-000000000001'::uuid,
        'create', 'rules'
    ), TRUE);

SELECT morbac.t('Carol (manager) delete rules',
    morbac.is_allowed(
        '30000000-0000-0000-0000-000000000003'::uuid,
        '10000000-0000-0000-0000-000000000001'::uuid,
        'delete', 'rules'
    ), TRUE);

SELECT morbac.t('Carol (manager) update rules [no rule]',
    morbac.is_allowed(
        '30000000-0000-0000-0000-000000000003'::uuid,
        '10000000-0000-0000-0000-000000000001'::uuid,
        'update', 'rules'
    ), FALSE);

SELECT morbac.t('Grace (hr_manager) create user_roles',
    morbac.is_allowed(
        '30000000-0000-0000-0000-000000000007'::uuid,
        '10000000-0000-0000-0000-000000000001'::uuid,
        'create', 'user_roles'
    ), TRUE);

SELECT morbac.t('Dave (employee) create rules [no rule]',
    morbac.is_allowed(
        '30000000-0000-0000-0000-000000000004'::uuid,
        '10000000-0000-0000-0000-000000000001'::uuid,
        'create', 'rules'
    ), FALSE);

-- ---------------------------------------------------------------------------
-- Section 4: Role hierarchy applies
-- ---------------------------------------------------------------------------
\echo ''
\echo '--- 4. Role hierarchy applies ---'

SELECT morbac.t('Bob (director, inherits manager) create rules',
    morbac.is_allowed(
        '30000000-0000-0000-0000-000000000002'::uuid,
        '10000000-0000-0000-0000-000000000001'::uuid,
        'create', 'rules'
    ), TRUE);

SELECT morbac.t('Bob (director) create roles [own rule]',
    morbac.is_allowed(
        '30000000-0000-0000-0000-000000000002'::uuid,
        '10000000-0000-0000-0000-000000000001'::uuid,
        'create', 'roles'
    ), TRUE);

SELECT morbac.t('Alice (CEO) create roles [inherits director]',
    morbac.is_allowed(
        '30000000-0000-0000-0000-000000000001'::uuid,
        '10000000-0000-0000-0000-000000000001'::uuid,
        'create', 'roles'
    ), TRUE);

SELECT morbac.t('Eve (intern) create rules [nothing in hierarchy]',
    morbac.is_allowed(
        '30000000-0000-0000-0000-000000000005'::uuid,
        '10000000-0000-0000-0000-000000000001'::uuid,
        'create', 'rules'
    ), FALSE);

-- ---------------------------------------------------------------------------
-- Section 5: Prohibition overrides permission
-- ---------------------------------------------------------------------------
\echo ''
\echo '--- 5. Prohibition overrides permission ---'

INSERT INTO morbac.rules (org_id, role_id, activity, view, context_id, modality)
SELECT o.id, r.id, 'create', 'rules', c.id, 'prohibition'
FROM morbac.orgs o
JOIN morbac.roles r ON r.org_id = o.id AND r.name = 'manager'
JOIN morbac.contexts c ON c.name = 'always'
WHERE o.name = 'GlobalTech HQ';

SELECT morbac.t('Carol (manager, prohibited) create rules [prohibition wins]',
    morbac.is_allowed(
        '30000000-0000-0000-0000-000000000003'::uuid,
        '10000000-0000-0000-0000-000000000001'::uuid,
        'create', 'rules'
    ), FALSE);

SELECT morbac.t('Carol (prohibition only on create) delete rules [still allowed]',
    morbac.is_allowed(
        '30000000-0000-0000-0000-000000000003'::uuid,
        '10000000-0000-0000-0000-000000000001'::uuid,
        'delete', 'rules'
    ), TRUE);

DELETE FROM morbac.rules
WHERE org_id = '10000000-0000-0000-0000-000000000001'
  AND role_id = '20000000-0001-0000-0000-000000000003'
  AND activity = 'create' AND view = 'rules'
  AND modality = 'prohibition';

-- ---------------------------------------------------------------------------
-- Section 6: assign_role / revoke_role
-- ---------------------------------------------------------------------------
\echo ''
\echo '--- 6. assign_role / revoke_role ---'

-- As DB owner (bypasses RLS), assign Karl as intern to verify constraint logic
SELECT morbac.assign_role(
    '30000000-0000-0000-0000-000000000011'::uuid,  -- Karl
    '20000000-0001-0000-0000-000000000005'::uuid,  -- intern
    '10000000-0000-0000-0000-000000000001'::uuid
);

SELECT morbac.t('Karl assigned intern role via assign_role()',
    EXISTS(
        SELECT 1 FROM morbac.user_roles
        WHERE user_id = '30000000-0000-0000-0000-000000000011'
          AND role_id = '20000000-0001-0000-0000-000000000005'
    ), TRUE);

SELECT morbac.revoke_role(
    '30000000-0000-0000-0000-000000000011'::uuid,
    '20000000-0001-0000-0000-000000000005'::uuid,
    '10000000-0000-0000-0000-000000000001'::uuid
);

SELECT morbac.t('Karl intern role revoked via revoke_role()',
    NOT EXISTS(
        SELECT 1 FROM morbac.user_roles
        WHERE user_id = '30000000-0000-0000-0000-000000000011'
          AND role_id = '20000000-0001-0000-0000-000000000005'
    ), TRUE);

-- ---------------------------------------------------------------------------
-- Section 7: RLS on morbac tables
-- ---------------------------------------------------------------------------
\echo ''
\echo '--- 7. RLS on morbac tables ---'

-- Create a non-superuser role so RLS policies are enforced (superusers bypass RLS by default)
DROP ROLE IF EXISTS morbac_rls_tester;
CREATE ROLE morbac_rls_tester;
GRANT USAGE ON SCHEMA morbac TO morbac_rls_tester;
GRANT SELECT, INSERT, DELETE ON morbac.user_roles TO morbac_rls_tester;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA morbac TO morbac_rls_tester;

SET SESSION AUTHORIZATION morbac_rls_tester;

-- Grace (hr_manager) has create/delete on user_roles — RLS should allow
SET morbac.user_id = '30000000-0000-0000-0000-000000000007';
SET morbac.org_id  = '10000000-0000-0000-0000-000000000001';

INSERT INTO morbac.user_roles (user_id, role_id, org_id)
VALUES (
    '30000000-0000-0000-0000-000000000011',
    '20000000-0001-0000-0000-000000000005',
    '10000000-0000-0000-0000-000000000001'
);

SELECT morbac.t('Grace (hr_manager) inserted user_role via RLS',
    EXISTS(
        SELECT 1 FROM morbac.user_roles
        WHERE user_id = '30000000-0000-0000-0000-000000000011'
          AND role_id = '20000000-0001-0000-0000-000000000005'
    ), TRUE);

DELETE FROM morbac.user_roles
WHERE user_id = '30000000-0000-0000-0000-000000000011'
  AND role_id = '20000000-0001-0000-0000-000000000005'
  AND org_id = '10000000-0000-0000-0000-000000000001';

-- Dave (employee) has no rules for user_roles — RLS should block
SET morbac.user_id = '30000000-0000-0000-0000-000000000004';
SET morbac.org_id  = '10000000-0000-0000-0000-000000000001';

DO $$
BEGIN
    INSERT INTO morbac.user_roles (user_id, role_id, org_id)
    VALUES (
        '30000000-0000-0000-0000-000000000011',
        '20000000-0001-0000-0000-000000000005',
        '10000000-0000-0000-0000-000000000001'
    );
    RAISE NOTICE 'CHECK FAIL: Dave (employee) inserted user_role [should have been blocked by RLS]';
EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'CHECK PASS: Dave (employee) blocked from inserting user_role by RLS';
END;
$$;

RESET SESSION AUTHORIZATION;
RESET morbac.user_id;
RESET morbac.org_id;

DROP OWNED BY morbac_rls_tester;
DROP ROLE IF EXISTS morbac_rls_tester;

-- ---------------------------------------------------------------------------
-- Section 8: Rules are org-scoped
-- ---------------------------------------------------------------------------
\echo ''
\echo '--- 8. Rules are org-scoped ---'

SELECT morbac.t('Carol (GlobalTech manager) create Engineering rules [wrong org]',
    morbac.is_allowed(
        '30000000-0000-0000-0000-000000000003'::uuid,
        '10000000-0000-0000-0000-000000000002'::uuid,
        'create', 'rules'
    ), FALSE);

SELECT morbac.t('Alice (GlobalTech CEO) create Engineering roles [org-scoped]',
    morbac.is_allowed(
        '30000000-0000-0000-0000-000000000001'::uuid,
        '10000000-0000-0000-0000-000000000002'::uuid,
        'create', 'roles'
    ), FALSE);

\echo ''
\echo '=== System Access Tests Completed ==='
