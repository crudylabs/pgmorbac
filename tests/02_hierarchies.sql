-- =============================================================================
-- Hierarchy Tests
-- =============================================================================
-- Tests all four hierarchy types:
--   1. Role hierarchy — senior roles inherit permissions of junior roles (transitive)
--   2. Activity hierarchy — requesting a senior activity also matches junior-activity rules
--   3. View hierarchy — requesting a senior view also matches junior-view rules
--   4. Org hierarchy — get_org_ancestors / get_org_descendants traversal
--
-- Hierarchy semantics in this system:
--   Activity: (senior='write', junior='read') means get_effective_activities('write')
--             returns {write, read}, so a rule for 'read' ALSO covers 'write' requests.
--   View:     (senior='financial_data', junior='documents') means
--             get_effective_views('financial_data') returns {financial_data, documents},
--             so a rule for 'documents' ALSO covers 'financial_data' requests.
--
-- Prerequisites: 00_setup.sql, 01_authorization.sql
-- =============================================================================

\echo ''
\echo '================================================================'
\echo '02 — HIERARCHIES'
\echo '================================================================'

-- ---------------------------------------------------------------------------
-- Section 1: Role hierarchy — get_effective_roles and get_inherited_roles
-- ---------------------------------------------------------------------------
\echo ''
\echo '--- 1. Role hierarchy introspection ---'

-- Eve (intern) direct assignment only — 1 effective role
SELECT morbac.t_eq('Eve has 1 effective role (intern only)',
    (SELECT COUNT(*) FROM morbac.get_effective_roles(
        '30000000-0000-0000-0000-000000000005'::uuid,
        '10000000-0000-0000-0000-000000000001'::uuid
    ))::bigint, 1);

-- Dave (employee) has employee + intern via hierarchy — 2 effective roles
SELECT morbac.t_eq('Dave has 2 effective roles (employee, intern)',
    (SELECT COUNT(*) FROM morbac.get_effective_roles(
        '30000000-0000-0000-0000-000000000004'::uuid,
        '10000000-0000-0000-0000-000000000001'::uuid
    ))::bigint, 2);

-- Carol (manager) has manager + employee + intern via hierarchy — 3 effective roles
SELECT morbac.t_eq('Carol has 3 effective roles (manager, employee, intern)',
    (SELECT COUNT(*) FROM morbac.get_effective_roles(
        '30000000-0000-0000-0000-000000000003'::uuid,
        '10000000-0000-0000-0000-000000000001'::uuid
    ))::bigint, 3);

-- Alice (CEO) has ceo, director, manager, employee, intern — 5 effective roles
SELECT morbac.t_eq('Alice has 5 effective roles (ceo through intern)',
    (SELECT COUNT(*) FROM morbac.get_effective_roles(
        '30000000-0000-0000-0000-000000000001'::uuid,
        '10000000-0000-0000-0000-000000000001'::uuid
    ))::bigint, 5);

-- get_inherited_roles for manager — manager itself + employee + intern = 3
SELECT morbac.t_eq('get_inherited_roles(manager) returns 3 roles (manager, employee, intern)',
    (SELECT COUNT(*) FROM morbac.get_inherited_roles(
        '20000000-0001-0000-0000-000000000003'::uuid
    ))::bigint, 3);

-- get_inherited_roles for ceo — entire chain = 5
SELECT morbac.t_eq('get_inherited_roles(ceo) returns 5 roles (ceo through intern)',
    (SELECT COUNT(*) FROM morbac.get_inherited_roles(
        '20000000-0001-0000-0000-000000000001'::uuid
    ))::bigint, 5);

-- Manager is included in its own inherited roles (at depth 0)
SELECT morbac.t('manager role is in its own inherited roles at depth 0',
    EXISTS(
        SELECT 1 FROM morbac.get_inherited_roles('20000000-0001-0000-0000-000000000003'::uuid)
        WHERE role_id = '20000000-0001-0000-0000-000000000003' AND depth = 0
    ), TRUE);

-- Intern is included in manager's inherited roles (at depth 2)
SELECT morbac.t('intern role appears in manager inherited roles',
    EXISTS(
        SELECT 1 FROM morbac.get_inherited_roles('20000000-0001-0000-0000-000000000003'::uuid)
        WHERE role_id = '20000000-0001-0000-0000-000000000005'
    ), TRUE);

-- ---------------------------------------------------------------------------
-- Section 2: Role hierarchy — authorization via inheritance (transitive)
-- ---------------------------------------------------------------------------
\echo ''
\echo '--- 2. Role hierarchy — authorization via inheritance ---'

-- Carol (manager) has employee permission (read documents) via 1-level inheritance
SELECT morbac.t('Carol (manager, 1-level inherit) reads documents',
    morbac.is_allowed_nocache(
        '30000000-0000-0000-0000-000000000003'::uuid,
        '10000000-0000-0000-0000-000000000001'::uuid,
        'read', 'documents'
    ), TRUE);

-- Bob (director) has employee permission (read documents) via 2-level inheritance
SELECT morbac.t('Bob (director, 2-level inherit) reads documents',
    morbac.is_allowed_nocache(
        '30000000-0000-0000-0000-000000000002'::uuid,
        '10000000-0000-0000-0000-000000000001'::uuid,
        'read', 'documents'
    ), TRUE);

-- Alice (CEO) has employee permission (read documents) via 3-level inheritance
SELECT morbac.t('Alice (CEO, 3-level inherit) reads documents',
    morbac.is_allowed_nocache(
        '30000000-0000-0000-0000-000000000001'::uuid,
        '10000000-0000-0000-0000-000000000001'::uuid,
        'read', 'documents'
    ), TRUE);

-- Alice (CEO) has intern permission (read public_data) via 4-level inheritance
SELECT morbac.t('Alice (CEO, 4-level inherit) reads public_data',
    morbac.is_allowed_nocache(
        '30000000-0000-0000-0000-000000000001'::uuid,
        '10000000-0000-0000-0000-000000000001'::uuid,
        'read', 'public_data'
    ), TRUE);

-- Carol (manager) has manager's own perm (approve documents)
SELECT morbac.t('Carol (manager) approves documents (own perm)',
    morbac.is_allowed_nocache(
        '30000000-0000-0000-0000-000000000003'::uuid,
        '10000000-0000-0000-0000-000000000001'::uuid,
        'approve', 'documents'
    ), TRUE);

-- Eve (intern) cannot approve — no role above intern has approve perm
SELECT morbac.t('Eve (intern) approves documents [inheritance only goes up in seniority]',
    morbac.is_allowed_nocache(
        '30000000-0000-0000-0000-000000000005'::uuid,
        '10000000-0000-0000-0000-000000000001'::uuid,
        'approve', 'documents'
    ), FALSE);

-- tech_lead in Engineering inherits engineer permissions
INSERT INTO morbac.user_roles (user_id, role_id, org_id) VALUES
    ('30000000-0000-0000-0000-000000000013', '20000000-0002-0000-0000-000000000001', '10000000-0000-0000-0000-000000000002');

-- tech_lead inherits engineer's read permission
SELECT morbac.t('Tech lead (inherits engineer) reads Engineering documents',
    morbac.is_allowed_nocache(
        '30000000-0000-0000-0000-000000000013'::uuid,
        '10000000-0000-0000-0000-000000000002'::uuid,
        'read', 'documents'
    ), TRUE);

-- tech_lead has own approve permission
SELECT morbac.t('Tech lead approves Engineering documents (own perm)',
    morbac.is_allowed_nocache(
        '30000000-0000-0000-0000-000000000013'::uuid,
        '10000000-0000-0000-0000-000000000002'::uuid,
        'approve', 'documents'
    ), TRUE);

-- ---------------------------------------------------------------------------
-- Section 3: Activity hierarchy
-- ---------------------------------------------------------------------------
\echo ''
\echo '--- 3. Activity hierarchy setup ---'

-- Build activity chain: manage -> delete -> write -> read
-- (Senior activity requesting also covers rules for its junior activities)
INSERT INTO morbac.activity_hierarchy (senior_activity, junior_activity) VALUES
    ('manage', 'delete'),
    ('delete', 'write'),
    ('write',  'read'),
    ('export', 'read');

-- get_effective_activities introspection
SELECT morbac.t_eq('get_effective_activities(read) returns 1 (read only)',
    (SELECT COUNT(*) FROM morbac.get_effective_activities('read'))::bigint, 1);

SELECT morbac.t_eq('get_effective_activities(write) returns 2 (write, read)',
    (SELECT COUNT(*) FROM morbac.get_effective_activities('write'))::bigint, 2);

SELECT morbac.t_eq('get_effective_activities(delete) returns 3 (delete, write, read)',
    (SELECT COUNT(*) FROM morbac.get_effective_activities('delete'))::bigint, 3);

SELECT morbac.t_eq('get_effective_activities(manage) returns 4 (manage, delete, write, read)',
    (SELECT COUNT(*) FROM morbac.get_effective_activities('manage'))::bigint, 4);

SELECT morbac.t_eq('get_effective_activities(export) returns 2 (export, read)',
    (SELECT COUNT(*) FROM morbac.get_effective_activities('export'))::bigint, 2);

-- Activity hierarchy authorization tests
-- Rule: employee has 'read documents' permission.
-- With hierarchy (write->read), requesting 'write' also matches the 'read' rule.

-- Dave (employee) requests 'write' — matches 'read' rule via write->read hierarchy
SELECT morbac.t('Dave (employee, has read perm) writes docs via activity hierarchy',
    morbac.is_allowed_nocache(
        '30000000-0000-0000-0000-000000000004'::uuid,
        '10000000-0000-0000-0000-000000000001'::uuid,
        'write', 'documents'
    ), TRUE);

-- Dave (employee) requests 'delete' — delete->write->read chain, 'read' rule matches
SELECT morbac.t('Dave (employee, has read perm) deletes docs via delete->write->read hierarchy',
    morbac.is_allowed_nocache(
        '30000000-0000-0000-0000-000000000004'::uuid,
        '10000000-0000-0000-0000-000000000001'::uuid,
        'delete', 'documents'
    ), TRUE);

-- Dave (employee) requests 'export' — export->read, 'read' rule matches
SELECT morbac.t('Dave (employee, has read perm) exports docs via export->read hierarchy',
    morbac.is_allowed_nocache(
        '30000000-0000-0000-0000-000000000004'::uuid,
        '10000000-0000-0000-0000-000000000001'::uuid,
        'export', 'documents'
    ), TRUE);

-- Eve (intern) has only 'read public_data' — requesting 'write public_data' also matches
SELECT morbac.t('Eve (intern, has read perm) writes public_data via activity hierarchy',
    morbac.is_allowed_nocache(
        '30000000-0000-0000-0000-000000000005'::uuid,
        '10000000-0000-0000-0000-000000000001'::uuid,
        'write', 'public_data'
    ), TRUE);

-- 'audit' is not in the hierarchy — no junior, no senior — no match for employee
SELECT morbac.t('Dave (employee) audits documents [audit not in hierarchy, no permission]',
    morbac.is_allowed_nocache(
        '30000000-0000-0000-0000-000000000004'::uuid,
        '10000000-0000-0000-0000-000000000001'::uuid,
        'audit', 'documents'
    ), FALSE);

-- ---------------------------------------------------------------------------
-- Section 4: View hierarchy
-- ---------------------------------------------------------------------------
\echo ''
\echo '--- 4. View hierarchy setup ---'

-- financial_data and hr_data are specific sub-types of documents
INSERT INTO morbac.view_hierarchy (senior_view, junior_view) VALUES
    ('financial_data', 'documents'),
    ('hr_data',        'documents');

-- get_effective_views introspection
SELECT morbac.t_eq('get_effective_views(documents) returns 1 (documents only)',
    (SELECT COUNT(*) FROM morbac.get_effective_views('documents'))::bigint, 1);

SELECT morbac.t_eq('get_effective_views(financial_data) returns 2 (financial_data, documents)',
    (SELECT COUNT(*) FROM morbac.get_effective_views('financial_data'))::bigint, 2);

SELECT morbac.t_eq('get_effective_views(hr_data) returns 2 (hr_data, documents)',
    (SELECT COUNT(*) FROM morbac.get_effective_views('hr_data'))::bigint, 2);

-- financial_data is included in get_effective_views('financial_data')
SELECT morbac.t('financial_data is in effective views of itself',
    EXISTS(
        SELECT 1 FROM morbac.get_effective_views('financial_data')
        WHERE view = 'financial_data'
    ), TRUE);

-- documents is also included (as junior)
SELECT morbac.t('documents is in effective views of financial_data',
    EXISTS(
        SELECT 1 FROM morbac.get_effective_views('financial_data')
        WHERE view = 'documents'
    ), TRUE);

-- employee has 'read documents' permission
-- requesting 'financial_data' -> get_effective_views('financial_data') = {financial_data, documents}
-- the 'documents' rule matches -> access granted

-- Dave (employee) reads financial_data — matches employee's 'read documents' rule via view hierarchy
SELECT morbac.t('Dave (employee, has read documents) reads financial_data via view hierarchy',
    morbac.is_allowed_nocache(
        '30000000-0000-0000-0000-000000000004'::uuid,
        '10000000-0000-0000-0000-000000000001'::uuid,
        'read', 'financial_data'
    ), TRUE);

-- Dave (employee) reads hr_data — matches 'read documents' via view hierarchy
SELECT morbac.t('Dave (employee, has read documents) reads hr_data via view hierarchy',
    morbac.is_allowed_nocache(
        '30000000-0000-0000-0000-000000000004'::uuid,
        '10000000-0000-0000-0000-000000000001'::uuid,
        'read', 'hr_data'
    ), TRUE);

-- Frank (contractor) reads documents — permitted
SELECT morbac.t('Frank (contractor) reads documents [has permission]',
    morbac.is_allowed_nocache(
        '30000000-0000-0000-0000-000000000006'::uuid,
        '10000000-0000-0000-0000-000000000001'::uuid,
        'read', 'documents'
    ), TRUE);

-- Frank (contractor) reads financial_data — matches contractor's 'read documents' rule via view hierarchy
-- BUT contractor has a PROHIBITION on financial_data — prohibition wins
SELECT morbac.t('Frank (contractor) reads financial_data [prohibition overrides view-hierarchy match]',
    morbac.is_allowed_nocache(
        '30000000-0000-0000-0000-000000000006'::uuid,
        '10000000-0000-0000-0000-000000000001'::uuid,
        'read', 'financial_data'
    ), FALSE);

-- ---------------------------------------------------------------------------
-- Section 5: Org hierarchy navigation
-- ---------------------------------------------------------------------------
\echo ''
\echo '--- 5. Org hierarchy navigation ---'

-- Engineering Dept has 2 ancestors: itself (depth=0) and GlobalTech HQ (depth=1)
SELECT morbac.t_eq('Engineering Dept has 2 ancestors (self + GlobalTech HQ)',
    (SELECT COUNT(*) FROM morbac.get_org_ancestors(
        '10000000-0000-0000-0000-000000000002'::uuid
    ))::bigint, 2);

-- Sales Dept also has 2 ancestors
SELECT morbac.t_eq('Sales Dept has 2 ancestors (self + GlobalTech HQ)',
    (SELECT COUNT(*) FROM morbac.get_org_ancestors(
        '10000000-0000-0000-0000-000000000003'::uuid
    ))::bigint, 2);

-- GlobalTech HQ is the root — only 1 ancestor (itself)
SELECT morbac.t_eq('GlobalTech HQ (root) has 1 ancestor (itself only)',
    (SELECT COUNT(*) FROM morbac.get_org_ancestors(
        '10000000-0000-0000-0000-000000000001'::uuid
    ))::bigint, 1);

-- GlobalTech HQ has 3 descendants: itself + Engineering + Sales
SELECT morbac.t_eq('GlobalTech HQ has 3 descendants (self + Engineering + Sales)',
    (SELECT COUNT(*) FROM morbac.get_org_descendants(
        '10000000-0000-0000-0000-000000000001'::uuid
    ))::bigint, 3);

-- Engineering (leaf node) has only 1 descendant: itself
SELECT morbac.t_eq('Engineering (leaf) has 1 descendant (itself only)',
    (SELECT COUNT(*) FROM morbac.get_org_descendants(
        '10000000-0000-0000-0000-000000000002'::uuid
    ))::bigint, 1);

-- GlobalTech HQ is its own ancestor at depth 0
SELECT morbac.t('GlobalTech HQ is its own ancestor at depth 0',
    EXISTS(
        SELECT 1 FROM morbac.get_org_ancestors('10000000-0000-0000-0000-000000000001'::uuid)
        WHERE org_id = '10000000-0000-0000-0000-000000000001' AND depth = 0
    ), TRUE);

-- Engineering's parent (GlobalTech HQ) appears at depth 1
SELECT morbac.t('GlobalTech HQ appears at depth 1 in Engineering ancestors',
    EXISTS(
        SELECT 1 FROM morbac.get_org_ancestors('10000000-0000-0000-0000-000000000002'::uuid)
        WHERE org_id = '10000000-0000-0000-0000-000000000001' AND depth = 1
    ), TRUE);

-- Verify org hierarchy does NOT automatically propagate permissions
-- (permissions are org-scoped; cross-org access requires explicit cross_org_rules)
SELECT morbac.t('Dave (GlobalTech employee) reads Engineering docs [no cross-org rule]',
    morbac.is_allowed_nocache(
        '30000000-0000-0000-0000-000000000004'::uuid,
        '10000000-0000-0000-0000-000000000002'::uuid,
        'read', 'documents'
    ), FALSE);

\echo ''
\echo '=== Hierarchy Tests Completed ==='
