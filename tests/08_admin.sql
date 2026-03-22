-- =============================================================================
-- Administration Rules Tests
-- =============================================================================
-- Tests the admin meta-policy system: who can manage policies, roles, and users.
--
-- is_admin_allowed(user_id, org_id, admin_activity, admin_target) is the main API.
-- Helper functions: can_manage_roles(), can_manage_policies(), can_manage_user_role().
--
-- Scenarios:
--   1. Default deny: no admin rule = no admin access
--   2. Grant admin permission to a role, verify the role holder can manage
--   3. Admin prohibition blocks management even with permission
--   4. Role hierarchy applies: senior role inherits admin permissions
--   5. Admin helper functions
--   6. can_manage_user_role() per-role management permission
--   7. Admin rules are org-scoped
--
-- Company context:
--   Grace (hr_manager) can manage users (assign_role) for employee-level roles
--   Carol (manager) can create rules
--   Alice (CEO) inherits Carol's admin perms via hierarchy
--
-- Prerequisites: 00_setup.sql -> 07_audit.sql
-- =============================================================================

\echo ''
\echo '================================================================'
\echo '08 — ADMINISTRATION RULES'
\echo '================================================================'

-- ---------------------------------------------------------------------------
-- Section 1: Default deny — no admin rule means no admin access
-- ---------------------------------------------------------------------------
\echo ''
\echo '--- 1. Default deny: no admin rule ---'

-- Nobody has admin rules yet — all should be denied
SELECT morbac.t('Alice (CEO, no admin rule yet) creates rules [default deny]',
    morbac.is_admin_allowed(
        '30000000-0000-0000-0000-000000000001'::uuid,
        '10000000-0000-0000-0000-000000000001'::uuid,
        'create_rule', 'rules'
    ), FALSE);

SELECT morbac.t('Grace (hr_manager, no admin rule) assigns roles [default deny]',
    morbac.is_admin_allowed(
        '30000000-0000-0000-0000-000000000007'::uuid,
        '10000000-0000-0000-0000-000000000001'::uuid,
        'assign_role', 'employee'
    ), FALSE);

-- ---------------------------------------------------------------------------
-- Section 2: Grant admin permissions
-- ---------------------------------------------------------------------------
\echo ''
\echo '--- 2. Grant admin permissions ---'

-- Grant manager role: can create and delete rules
INSERT INTO morbac.admin_rules (org_id, role_id, admin_activity, admin_target, context_id, modality)
VALUES
    ('10000000-0000-0000-0000-000000000001',
     '20000000-0001-0000-0000-000000000003', -- manager
     'create_rule', 'rules',
     (SELECT id FROM morbac.contexts WHERE name = 'always'),
     'permission'),
    ('10000000-0000-0000-0000-000000000001',
     '20000000-0001-0000-0000-000000000003', -- manager
     'delete_rule', 'rules',
     (SELECT id FROM morbac.contexts WHERE name = 'always'),
     'permission');

-- Grant hr_manager role: can assign employee and intern roles
INSERT INTO morbac.admin_rules (org_id, role_id, admin_activity, admin_target, context_id, modality)
VALUES
    ('10000000-0000-0000-0000-000000000001',
     '20000000-0001-0000-0000-000000000008', -- hr_manager
     'assign_role', 'employee',
     (SELECT id FROM morbac.contexts WHERE name = 'always'),
     'permission'),
    ('10000000-0000-0000-0000-000000000001',
     '20000000-0001-0000-0000-000000000008', -- hr_manager
     'assign_role', 'intern',
     (SELECT id FROM morbac.contexts WHERE name = 'always'),
     'permission');

-- Grant director role: can manage roles and policies
INSERT INTO morbac.admin_rules (org_id, role_id, admin_activity, admin_target, context_id, modality)
VALUES
    ('10000000-0000-0000-0000-000000000001',
     '20000000-0001-0000-0000-000000000002', -- director
     'manage', 'roles',
     (SELECT id FROM morbac.contexts WHERE name = 'always'),
     'permission'),
    ('10000000-0000-0000-0000-000000000001',
     '20000000-0001-0000-0000-000000000002', -- director
     'manage', 'policies',
     (SELECT id FROM morbac.contexts WHERE name = 'always'),
     'permission');

-- ---------------------------------------------------------------------------
-- Section 3: Verify admin permissions
-- ---------------------------------------------------------------------------
\echo ''
\echo '--- 3. Verify admin permissions ---'

-- Carol (manager) can create rules
SELECT morbac.t('Carol (manager) creates rules',
    morbac.is_admin_allowed(
        '30000000-0000-0000-0000-000000000003'::uuid,
        '10000000-0000-0000-0000-000000000001'::uuid,
        'create_rule', 'rules'
    ), TRUE);

-- Carol (manager) can delete rules
SELECT morbac.t('Carol (manager) deletes rules',
    morbac.is_admin_allowed(
        '30000000-0000-0000-0000-000000000003'::uuid,
        '10000000-0000-0000-0000-000000000001'::uuid,
        'delete_rule', 'rules'
    ), TRUE);

-- Grace (hr_manager) can assign employee role
SELECT morbac.t('Grace (hr_manager) assigns employee role',
    morbac.is_admin_allowed(
        '30000000-0000-0000-0000-000000000007'::uuid,
        '10000000-0000-0000-0000-000000000001'::uuid,
        'assign_role', 'employee'
    ), TRUE);

-- Grace (hr_manager) can assign intern role
SELECT morbac.t('Grace (hr_manager) assigns intern role',
    morbac.is_admin_allowed(
        '30000000-0000-0000-0000-000000000007'::uuid,
        '10000000-0000-0000-0000-000000000001'::uuid,
        'assign_role', 'intern'
    ), TRUE);

-- Grace (hr_manager) cannot assign manager role (no rule for that)
SELECT morbac.t('Grace (hr_manager) assigns manager role [no admin rule for manager]',
    morbac.is_admin_allowed(
        '30000000-0000-0000-0000-000000000007'::uuid,
        '10000000-0000-0000-0000-000000000001'::uuid,
        'assign_role', 'manager'
    ), FALSE);

-- Dave (employee) has no admin permissions
SELECT morbac.t('Dave (employee) creates rules [no admin rule for employee]',
    morbac.is_admin_allowed(
        '30000000-0000-0000-0000-000000000004'::uuid,
        '10000000-0000-0000-0000-000000000001'::uuid,
        'create_rule', 'rules'
    ), FALSE);

-- ---------------------------------------------------------------------------
-- Section 4: Role hierarchy applies to admin permissions
-- ---------------------------------------------------------------------------
\echo ''
\echo '--- 4. Role hierarchy applies to admin permissions ---'

-- Bob (director) has own admin perm (manage roles/policies) and
-- inherits manager's admin perms (create_rule, delete_rule) via director->manager hierarchy

-- Bob (director) creates rules — inherited from manager via director->manager hierarchy
SELECT morbac.t('Bob (director, inherits manager admin) creates rules',
    morbac.is_admin_allowed(
        '30000000-0000-0000-0000-000000000002'::uuid,
        '10000000-0000-0000-0000-000000000001'::uuid,
        'create_rule', 'rules'
    ), TRUE);

-- Bob (director) manages roles — own admin perm
SELECT morbac.t('Bob (director) manages roles [own admin perm]',
    morbac.is_admin_allowed(
        '30000000-0000-0000-0000-000000000002'::uuid,
        '10000000-0000-0000-0000-000000000001'::uuid,
        'manage', 'roles'
    ), TRUE);

-- Alice (CEO) inherits everything through CEO->director->manager chain
SELECT morbac.t('Alice (CEO, inherits director+manager) manages roles',
    morbac.is_admin_allowed(
        '30000000-0000-0000-0000-000000000001'::uuid,
        '10000000-0000-0000-0000-000000000001'::uuid,
        'manage', 'roles'
    ), TRUE);

SELECT morbac.t('Alice (CEO) manages policies',
    morbac.is_admin_allowed(
        '30000000-0000-0000-0000-000000000001'::uuid,
        '10000000-0000-0000-0000-000000000001'::uuid,
        'manage', 'policies'
    ), TRUE);

-- Eve (intern) inherits nothing useful for admin
SELECT morbac.t('Eve (intern) creates rules [no admin permission in hierarchy]',
    morbac.is_admin_allowed(
        '30000000-0000-0000-0000-000000000005'::uuid,
        '10000000-0000-0000-0000-000000000001'::uuid,
        'create_rule', 'rules'
    ), FALSE);

-- ---------------------------------------------------------------------------
-- Section 5: Admin prohibition overrides permission
-- ---------------------------------------------------------------------------
\echo ''
\echo '--- 5. Admin prohibition overrides permission ---'

-- Carol (manager) currently can create rules. Add a prohibition.
INSERT INTO morbac.admin_rules (org_id, role_id, admin_activity, admin_target, context_id, modality)
VALUES (
    '10000000-0000-0000-0000-000000000001',
    '20000000-0001-0000-0000-000000000003', -- manager
    'create_rule', 'rules',
    (SELECT id FROM morbac.contexts WHERE name = 'always'),
    'prohibition'
);

-- Prohibition overrides permission
SELECT morbac.t('Carol (manager, now prohibited) creates rules [prohibition wins]',
    morbac.is_admin_allowed(
        '30000000-0000-0000-0000-000000000003'::uuid,
        '10000000-0000-0000-0000-000000000001'::uuid,
        'create_rule', 'rules'
    ), FALSE);

-- Carol can still delete rules (prohibition only applied to create_rule)
SELECT morbac.t('Carol (manager, prohibition only on create) deletes rules [still allowed]',
    morbac.is_admin_allowed(
        '30000000-0000-0000-0000-000000000003'::uuid,
        '10000000-0000-0000-0000-000000000001'::uuid,
        'delete_rule', 'rules'
    ), TRUE);

-- Remove the prohibition for subsequent tests
DELETE FROM morbac.admin_rules
WHERE org_id = '10000000-0000-0000-0000-000000000001'
  AND role_id = '20000000-0001-0000-0000-000000000003'
  AND admin_activity = 'create_rule' AND admin_target = 'rules'
  AND modality = 'prohibition';

-- Carol can again create rules after prohibition removed
SELECT morbac.t('Carol (manager) creates rules after prohibition removed',
    morbac.is_admin_allowed(
        '30000000-0000-0000-0000-000000000003'::uuid,
        '10000000-0000-0000-0000-000000000001'::uuid,
        'create_rule', 'rules'
    ), TRUE);

-- ---------------------------------------------------------------------------
-- Section 6: Admin helper functions
-- ---------------------------------------------------------------------------
\echo ''
\echo '--- 6. Admin helper functions ---'

-- can_manage_roles: wraps is_admin_allowed('manage', 'roles')
SELECT morbac.t('Bob (director) can_manage_roles',
    morbac.can_manage_roles(
        '30000000-0000-0000-0000-000000000002'::uuid,
        '10000000-0000-0000-0000-000000000001'::uuid
    ), TRUE);

SELECT morbac.t('Dave (employee) can_manage_roles [denied]',
    morbac.can_manage_roles(
        '30000000-0000-0000-0000-000000000004'::uuid,
        '10000000-0000-0000-0000-000000000001'::uuid
    ), FALSE);

-- can_manage_policies: wraps is_admin_allowed('manage', 'policies')
SELECT morbac.t('Bob (director) can_manage_policies',
    morbac.can_manage_policies(
        '30000000-0000-0000-0000-000000000002'::uuid,
        '10000000-0000-0000-0000-000000000001'::uuid
    ), TRUE);

SELECT morbac.t('Carol (manager) can_manage_policies [no manage policies rule for manager]',
    morbac.can_manage_policies(
        '30000000-0000-0000-0000-000000000003'::uuid,
        '10000000-0000-0000-0000-000000000001'::uuid
    ), FALSE);

-- ---------------------------------------------------------------------------
-- Section 7: can_manage_user_role — per-role management check
-- ---------------------------------------------------------------------------
\echo ''
\echo '--- 7. can_manage_user_role ---'

-- Grace (hr_manager) has assign_role perm for 'employee'
-- can_manage_user_role checks is_admin_allowed('assign_role', role_name)

SELECT morbac.t('Grace (hr_manager) can manage employee role assignments',
    morbac.can_manage_user_role(
        '30000000-0000-0000-0000-000000000007'::uuid,  -- Grace
        '10000000-0000-0000-0000-000000000001'::uuid,
        '20000000-0001-0000-0000-000000000004'::uuid   -- employee role
    ), TRUE);

SELECT morbac.t('Grace (hr_manager) can manage intern role assignments',
    morbac.can_manage_user_role(
        '30000000-0000-0000-0000-000000000007'::uuid,  -- Grace
        '10000000-0000-0000-0000-000000000001'::uuid,
        '20000000-0001-0000-0000-000000000005'::uuid   -- intern role
    ), TRUE);

SELECT morbac.t('Grace (hr_manager) cannot manage manager role assignments [no rule]',
    morbac.can_manage_user_role(
        '30000000-0000-0000-0000-000000000007'::uuid,  -- Grace
        '10000000-0000-0000-0000-000000000001'::uuid,
        '20000000-0001-0000-0000-000000000003'::uuid   -- manager role
    ), FALSE);

SELECT morbac.t('Dave (employee) cannot manage any role assignments',
    morbac.can_manage_user_role(
        '30000000-0000-0000-0000-000000000004'::uuid,  -- Dave
        '10000000-0000-0000-0000-000000000001'::uuid,
        '20000000-0001-0000-0000-000000000005'::uuid   -- intern role
    ), FALSE);

-- ---------------------------------------------------------------------------
-- Section 8: Admin rules are org-scoped
-- ---------------------------------------------------------------------------
\echo ''
\echo '--- 8. Admin rules are org-scoped ---'

-- Carol (manager at GlobalTech) cannot manage Engineering rules
-- (her admin rule is for GlobalTech org only)
SELECT morbac.t('Carol (GlobalTech manager) creates Engineering rules [wrong org]',
    morbac.is_admin_allowed(
        '30000000-0000-0000-0000-000000000003'::uuid,
        '10000000-0000-0000-0000-000000000002'::uuid, -- Engineering org
        'create_rule', 'rules'
    ), FALSE);

-- Alice (CEO at GlobalTech) cannot manage Engineering rules via admin (same org scoping)
SELECT morbac.t('Alice (GlobalTech CEO) creates Engineering rules [org-scoped]',
    morbac.is_admin_allowed(
        '30000000-0000-0000-0000-000000000001'::uuid,
        '10000000-0000-0000-0000-000000000002'::uuid, -- Engineering org
        'manage', 'roles'
    ), FALSE);

\echo ''
\echo '=== Administration Rules Tests Completed ==='
