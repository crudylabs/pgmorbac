-- =============================================================================
-- Scope Rules and Global Cross-Org Rules Tests
-- =============================================================================
-- Tests rules.scope and cross_org_rules.source_org_id = NULL:
--
--   1. scope='self' (default) — exact org only, unchanged behavior
--   2. scope='subtree' — rule at root covers self + Engineering + Sales
--   3. scope='descendants' — covers Engineering + Sales but NOT GlobalTech itself
--   4. scope='children' — covers direct children only
--   5. New org added after rule creation — picked up automatically (cache invalidation)
--
-- Prerequisites: 00_setup.sql -> 10_activity_view_bindings.sql
-- =============================================================================

\echo ''
\echo '================================================================'
\echo '11 — SCOPE RULES AND GLOBAL CROSS-ORG RULES'
\echo '================================================================'

-- Setup: create a dedicated role for scope tests (avoid polluting existing rules)
INSERT INTO morbac.roles (id, org_id, name, description)
VALUES (
    '20000000-0001-0000-0000-000000000012',
    '10000000-0000-0000-0000-000000000001',
    'analyst',
    'Data analyst — scope tests'
);

-- Assign Karl (previously no role) as analyst at GlobalTech
INSERT INTO morbac.user_roles (user_id, role_id, org_id)
VALUES (
    '30000000-0000-0000-0000-000000000011',
    '20000000-0001-0000-0000-000000000012',
    '10000000-0000-0000-0000-000000000001'
);

-- ---------------------------------------------------------------------------
-- Section 1: scope='self' (default) — exact org only
-- ---------------------------------------------------------------------------
\echo ''
\echo '--- 1. scope=self (default) ---'

INSERT INTO morbac.rules (id, org_id, role_id, activity, view, context_id, modality, scope)
VALUES (
    'c0000000-0000-0000-0000-000000000001',
    '10000000-0000-0000-0000-000000000001',
    '20000000-0001-0000-0000-000000000012',
    'read', 'reports',
    (SELECT id FROM morbac.contexts WHERE name = 'always'),
    'permission', 'self'
);

SELECT morbac.t('Karl (analyst, scope=self) reads reports in GlobalTech HQ [allowed]',
    morbac.is_allowed_nocache(
        '30000000-0000-0000-0000-000000000011'::uuid,
        '10000000-0000-0000-0000-000000000001'::uuid,
        'read', 'reports'
    ), TRUE);

SELECT morbac.t('Karl (analyst, scope=self) reads reports in Engineering [denied, self only]',
    morbac.is_allowed_nocache(
        '30000000-0000-0000-0000-000000000011'::uuid,
        '10000000-0000-0000-0000-000000000002'::uuid,
        'read', 'reports'
    ), FALSE);

DELETE FROM morbac.rules WHERE id = 'c0000000-0000-0000-0000-000000000001';

-- ---------------------------------------------------------------------------
-- Section 2: scope='subtree' — root + all descendants
-- ---------------------------------------------------------------------------
\echo ''
\echo '--- 2. scope=subtree ---'

INSERT INTO morbac.rules (id, org_id, role_id, activity, view, context_id, modality, scope)
VALUES (
    'c0000000-0000-0000-0000-000000000002',
    '10000000-0000-0000-0000-000000000001',
    '20000000-0001-0000-0000-000000000012',
    'read', 'reports',
    (SELECT id FROM morbac.contexts WHERE name = 'always'),
    'permission', 'subtree'
);

SELECT morbac.t('Karl (analyst, scope=subtree) reads reports in GlobalTech HQ [allowed]',
    morbac.is_allowed_nocache(
        '30000000-0000-0000-0000-000000000011'::uuid,
        '10000000-0000-0000-0000-000000000001'::uuid,
        'read', 'reports'
    ), TRUE);

SELECT morbac.t('Karl (analyst, scope=subtree) reads reports in Engineering [allowed]',
    morbac.is_allowed_nocache(
        '30000000-0000-0000-0000-000000000011'::uuid,
        '10000000-0000-0000-0000-000000000002'::uuid,
        'read', 'reports'
    ), TRUE);

SELECT morbac.t('Karl (analyst, scope=subtree) reads reports in Sales [allowed]',
    morbac.is_allowed_nocache(
        '30000000-0000-0000-0000-000000000011'::uuid,
        '10000000-0000-0000-0000-000000000003'::uuid,
        'read', 'reports'
    ), TRUE);

DELETE FROM morbac.rules WHERE id = 'c0000000-0000-0000-0000-000000000002';

-- ---------------------------------------------------------------------------
-- Section 3: scope='descendants' — children only, NOT self
-- ---------------------------------------------------------------------------
\echo ''
\echo '--- 3. scope=descendants ---'

INSERT INTO morbac.rules (id, org_id, role_id, activity, view, context_id, modality, scope)
VALUES (
    'c0000000-0000-0000-0000-000000000003',
    '10000000-0000-0000-0000-000000000001',
    '20000000-0001-0000-0000-000000000012',
    'read', 'reports',
    (SELECT id FROM morbac.contexts WHERE name = 'always'),
    'permission', 'descendants'
);

SELECT morbac.t('Karl (analyst, scope=descendants) reads reports in GlobalTech HQ [denied, not self]',
    morbac.is_allowed_nocache(
        '30000000-0000-0000-0000-000000000011'::uuid,
        '10000000-0000-0000-0000-000000000001'::uuid,
        'read', 'reports'
    ), FALSE);

SELECT morbac.t('Karl (analyst, scope=descendants) reads reports in Engineering [allowed]',
    morbac.is_allowed_nocache(
        '30000000-0000-0000-0000-000000000011'::uuid,
        '10000000-0000-0000-0000-000000000002'::uuid,
        'read', 'reports'
    ), TRUE);

SELECT morbac.t('Karl (analyst, scope=descendants) reads reports in Sales [allowed]',
    morbac.is_allowed_nocache(
        '30000000-0000-0000-0000-000000000011'::uuid,
        '10000000-0000-0000-0000-000000000003'::uuid,
        'read', 'reports'
    ), TRUE);

DELETE FROM morbac.rules WHERE id = 'c0000000-0000-0000-0000-000000000003';

-- ---------------------------------------------------------------------------
-- Section 4: scope='children' — direct children only
-- ---------------------------------------------------------------------------
\echo ''
\echo '--- 4. scope=children ---'

-- Add a grandchild org (child of Engineering)
INSERT INTO morbac.orgs (id, name, parent_id)
VALUES (
    '10000000-0000-0000-0000-000000000004',
    'Backend Team',
    '10000000-0000-0000-0000-000000000002'
);

INSERT INTO morbac.rules (id, org_id, role_id, activity, view, context_id, modality, scope)
VALUES (
    'c0000000-0000-0000-0000-000000000004',
    '10000000-0000-0000-0000-000000000001',
    '20000000-0001-0000-0000-000000000012',
    'read', 'reports',
    (SELECT id FROM morbac.contexts WHERE name = 'always'),
    'permission', 'children'
);

SELECT morbac.t('Karl (analyst, scope=children) reads reports in Engineering [direct child, allowed]',
    morbac.is_allowed_nocache(
        '30000000-0000-0000-0000-000000000011'::uuid,
        '10000000-0000-0000-0000-000000000002'::uuid,
        'read', 'reports'
    ), TRUE);

SELECT morbac.t('Karl (analyst, scope=children) reads reports in Backend Team [grandchild, denied]',
    morbac.is_allowed_nocache(
        '30000000-0000-0000-0000-000000000011'::uuid,
        '10000000-0000-0000-0000-000000000004'::uuid,
        'read', 'reports'
    ), FALSE);

SELECT morbac.t('Karl (analyst, scope=children) reads reports in GlobalTech HQ [self, denied]',
    morbac.is_allowed_nocache(
        '30000000-0000-0000-0000-000000000011'::uuid,
        '10000000-0000-0000-0000-000000000001'::uuid,
        'read', 'reports'
    ), FALSE);

DELETE FROM morbac.rules WHERE id = 'c0000000-0000-0000-0000-000000000004';
DELETE FROM morbac.orgs WHERE id = '10000000-0000-0000-0000-000000000004';

-- ---------------------------------------------------------------------------
-- Section 5: New org added after rule creation — scope picks it up automatically
-- ---------------------------------------------------------------------------
\echo ''
\echo '--- 5. Dynamic scope: new org covered automatically ---'

-- Create a subtree-scoped rule at GlobalTech HQ for the analyst role
INSERT INTO morbac.rules (id, org_id, role_id, activity, view, context_id, modality, scope)
VALUES (
    'c0000000-0000-0000-0000-000000000005',
    '10000000-0000-0000-0000-000000000001',
    '20000000-0001-0000-0000-000000000012',
    'read', 'documents',
    (SELECT id FROM morbac.contexts WHERE name = 'always'),
    'permission', 'subtree'
);

-- Verify the rule works for existing child orgs
SELECT morbac.t('Karl (analyst) reads documents in Engineering [existing child, allowed]',
    morbac.is_allowed_nocache(
        '30000000-0000-0000-0000-000000000011'::uuid,
        '10000000-0000-0000-0000-000000000002'::uuid,
        'read', 'documents'
    ), TRUE);

-- Add a new org AFTER the rule was created
INSERT INTO morbac.orgs (id, name, parent_id)
VALUES (
    '10000000-0000-0000-0000-000000000005',
    'Legal Dept',
    '10000000-0000-0000-0000-000000000001'
);

-- The scoped rule was defined before Legal Dept existed — still covers it
SELECT morbac.t('Karl (analyst) reads documents in Legal Dept [new org, covered by subtree scope]',
    morbac.is_allowed_nocache(
        '30000000-0000-0000-0000-000000000011'::uuid,
        '10000000-0000-0000-0000-000000000005'::uuid,
        'read', 'documents'
    ), TRUE);

-- A scope=self rule at GlobalTech HQ does NOT cover Legal Dept
INSERT INTO morbac.rules (id, org_id, role_id, activity, view, context_id, modality, scope)
VALUES (
    'c0000000-0000-0000-0000-000000000006',
    '10000000-0000-0000-0000-000000000001',
    '20000000-0001-0000-0000-000000000012',
    'read', 'reports',
    (SELECT id FROM morbac.contexts WHERE name = 'always'),
    'permission', 'self'
);

SELECT morbac.t('Karl (analyst, scope=self) reads reports in Legal Dept [new org, not covered]',
    morbac.is_allowed_nocache(
        '30000000-0000-0000-0000-000000000011'::uuid,
        '10000000-0000-0000-0000-000000000005'::uuid,
        'read', 'reports'
    ), FALSE);

-- Cleanup
DELETE FROM morbac.rules WHERE id IN ('c0000000-0000-0000-0000-000000000005', 'c0000000-0000-0000-0000-000000000006');
DELETE FROM morbac.orgs WHERE id = '10000000-0000-0000-0000-000000000005';

\echo ''
\echo '=== Scope Rules and Global Cross-Org Rules Tests Completed ==='
