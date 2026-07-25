-- =============================================================================
-- Activity-View Binding Tests
-- =============================================================================
-- Tests opt-in activity-to-view restrictions:
--   1. No bindings defined - any view is allowed
--   2. Binding defined - listed view is allowed, unlisted view is blocked
--   3. Blocking applies to cross_org_rules as well
--   4. Removing all bindings lifts the restriction
--
-- Prerequisites: 00_setup.sql -> 09_utilities.sql
-- =============================================================================

\echo ''
\echo '================================================================'
\echo '10 - ACTIVITY-VIEW BINDINGS'
\echo '================================================================'

-- ---------------------------------------------------------------------------
-- Section 1: No bindings - unconstrained
-- ---------------------------------------------------------------------------
\echo ''
\echo '--- 1. No bindings: any view is allowed ---'

-- With no bindings, inserting a rule succeeds for any activity/view pair
INSERT INTO morbac.rules (id, org_id, role_id, activity, view, context_id, modality)
VALUES (
    'b0000000-0000-0000-0000-000000000001',
    '10000000-0000-0000-0000-000000000001',
    '20000000-0001-0000-0000-000000000004', -- employee
    'audit', 'documents',
    (SELECT id FROM morbac.contexts WHERE name = 'always'),
    'permission'
);

SELECT morbac.t('No bindings: audit/documents rule inserted successfully',
    EXISTS(SELECT 1 FROM morbac.rules WHERE id = 'b0000000-0000-0000-0000-000000000001'),
    TRUE);

DELETE FROM morbac.rules WHERE id = 'b0000000-0000-0000-0000-000000000001';

-- ---------------------------------------------------------------------------
-- Section 2: Binding defined - listed view allowed, unlisted view blocked
-- ---------------------------------------------------------------------------
\echo ''
\echo '--- 2. Binding defined: allowed view works, unlisted view blocked ---'

-- Restrict 'audit' activity to only 'audit_logs'
INSERT INTO morbac.activity_view_bindings (activity, view) VALUES ('audit', 'audit_logs');

SELECT morbac.t_eq('Binding for audit/audit_logs created',
    (SELECT COUNT(*) FROM morbac.activity_view_bindings WHERE activity = 'audit')::bigint,
    1);

-- Inserting a rule with the listed view succeeds
INSERT INTO morbac.rules (id, org_id, role_id, activity, view, context_id, modality)
VALUES (
    'b0000000-0000-0000-0000-000000000002',
    '10000000-0000-0000-0000-000000000001',
    '20000000-0001-0000-0000-000000000004', -- employee
    'audit', 'audit_logs',
    (SELECT id FROM morbac.contexts WHERE name = 'always'),
    'permission'
);

SELECT morbac.t('Binding allows audit/audit_logs rule',
    EXISTS(SELECT 1 FROM morbac.rules WHERE id = 'b0000000-0000-0000-0000-000000000002'),
    TRUE);

-- Inserting a rule with an unlisted view is blocked
DO $$
BEGIN
    INSERT INTO morbac.rules (org_id, role_id, activity, view, context_id, modality)
    VALUES (
        '10000000-0000-0000-0000-000000000001',
        '20000000-0001-0000-0000-000000000004',
        'audit', 'documents',
        (SELECT id FROM morbac.contexts WHERE name = 'always'),
        'permission'
    );
    RAISE NOTICE 'CHECK FAIL: Binding should have blocked audit/documents rule';
EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'CHECK PASS: Binding blocks audit/documents rule (unlisted view)';
END;
$$;

-- Other activities without bindings are unaffected
INSERT INTO morbac.rules (id, org_id, role_id, activity, view, context_id, modality)
VALUES (
    'b0000000-0000-0000-0000-000000000003',
    '10000000-0000-0000-0000-000000000001',
    '20000000-0001-0000-0000-000000000004',
    'manage', 'documents',
    (SELECT id FROM morbac.contexts WHERE name = 'always'),
    'permission'
);

SELECT morbac.t('Unbound activity (manage) still works with any view',
    EXISTS(SELECT 1 FROM morbac.rules WHERE id = 'b0000000-0000-0000-0000-000000000003'),
    TRUE);

-- ---------------------------------------------------------------------------
-- Section 3: Applies to cross_org_rules as well
-- ---------------------------------------------------------------------------
\echo ''
\echo '--- 3. Binding enforced on cross_org_rules ---'

DO $$
BEGIN
    INSERT INTO morbac.cross_org_rules (source_org_id, target_org_id, role_id, activity, view, context_id, modality)
    VALUES (
        '10000000-0000-0000-0000-000000000001',
        '10000000-0000-0000-0000-000000000002',
        '20000000-0001-0000-0000-000000000004',
        'audit', 'documents',
        (SELECT id FROM morbac.contexts WHERE name = 'always'),
        'permission'
    );
    RAISE NOTICE 'CHECK FAIL: Binding should have blocked cross_org_rule with unlisted view';
EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'CHECK PASS: Binding blocks cross_org_rule with unlisted view';
END;
$$;

-- Cross-org rule with the bound view succeeds
INSERT INTO morbac.cross_org_rules (id, source_org_id, target_org_id, role_id, activity, view, context_id, modality)
VALUES (
    'b0000000-0000-0000-0000-000000000004',
    '10000000-0000-0000-0000-000000000001',
    '10000000-0000-0000-0000-000000000002',
    '20000000-0001-0000-0000-000000000004',
    'audit', 'audit_logs',
    (SELECT id FROM morbac.contexts WHERE name = 'always'),
    'permission'
);

SELECT morbac.t('Binding allows cross_org_rule with listed view',
    EXISTS(SELECT 1 FROM morbac.cross_org_rules WHERE id = 'b0000000-0000-0000-0000-000000000004'),
    TRUE);

-- ---------------------------------------------------------------------------
-- Section 4: Removing all bindings lifts the restriction
-- ---------------------------------------------------------------------------
\echo ''
\echo '--- 4. Removing all bindings lifts the restriction ---'

DELETE FROM morbac.activity_view_bindings WHERE activity = 'audit';

SELECT morbac.t_eq('All audit bindings removed',
    (SELECT COUNT(*) FROM morbac.activity_view_bindings WHERE activity = 'audit')::bigint,
    0);

-- Now audit/documents should be insertable again
INSERT INTO morbac.rules (id, org_id, role_id, activity, view, context_id, modality)
VALUES (
    'b0000000-0000-0000-0000-000000000005',
    '10000000-0000-0000-0000-000000000001',
    '20000000-0001-0000-0000-000000000004',
    'audit', 'documents',
    (SELECT id FROM morbac.contexts WHERE name = 'always'),
    'permission'
);

SELECT morbac.t('Removing bindings: audit/documents rule now allowed',
    EXISTS(SELECT 1 FROM morbac.rules WHERE id = 'b0000000-0000-0000-0000-000000000005'),
    TRUE);

-- Clean up
DELETE FROM morbac.rules
WHERE id IN (
    'b0000000-0000-0000-0000-000000000002',
    'b0000000-0000-0000-0000-000000000003',
    'b0000000-0000-0000-0000-000000000005'
);

DELETE FROM morbac.cross_org_rules WHERE id = 'b0000000-0000-0000-0000-000000000004';

\echo ''
\echo '=== Activity-View Binding Tests Completed ==='
