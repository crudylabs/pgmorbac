-- =============================================================================
-- Utilities, Derived Roles, RLS, and Policy DSL Tests
-- =============================================================================
-- Tests miscellaneous utility functions and advanced features:
--
--   1. pending_obligations — returns obligation rules for a user
--   2. pending_recommendations — returns recommendation rules for a user
--   3. Obligations/recommendations do NOT affect is_allowed()
--   3b. Conflict resolution: prohibition voids obligation; prohibition/obligation voids recommendation
--   4. user_has_role — checks if user holds a named role
--   5. user_roles_in_org — lists all roles for user in org
--   6. eval_context — evaluates context predicates directly
--   7. Policy DSL idempotency — compile_policy() is safe to run multiple times
--   8. Policy DSL error handling — reports errors for missing org/role
--   9. Derived roles — computed via evaluator function
--  10. RLS helpers: get_user_orgs, current_org_ids, rls_check() org scoping
--
-- Prerequisites: 00_setup.sql -> 08_admin.sql
-- =============================================================================

\echo ''
\echo '================================================================'
\echo '09 — UTILITIES, DERIVED ROLES, RLS, POLICY DSL'
\echo '================================================================'

-- ---------------------------------------------------------------------------
-- Section 1: pending_obligations
-- ---------------------------------------------------------------------------
\echo ''
\echo '--- 1. pending_obligations ---'

-- Dave (employee) has obligation: 'read reports' (set up in 00_setup via Policy DSL)
-- The context is 'always' so it evaluates TRUE
SELECT morbac.t('Dave (employee) has at least 1 pending obligation',
    (SELECT COUNT(*) FROM morbac.pending_obligations(
        '30000000-0000-0000-0000-000000000004'::uuid,
        '10000000-0000-0000-0000-000000000001'::uuid
    )) >= 1,
    TRUE);

-- Dave's obligation is for 'read reports'
SELECT morbac.t('Dave has pending obligation: read reports',
    EXISTS(
        SELECT 1 FROM morbac.pending_obligations(
            '30000000-0000-0000-0000-000000000004'::uuid,
            '10000000-0000-0000-0000-000000000001'::uuid
        )
        WHERE activity = 'read' AND view = 'reports'
    ), TRUE);

-- Karl (no role) has no obligations
SELECT morbac.t_eq('Karl (no role) has 0 pending obligations',
    (SELECT COUNT(*) FROM morbac.pending_obligations(
        '30000000-0000-0000-0000-000000000011'::uuid,
        '10000000-0000-0000-0000-000000000001'::uuid
    ))::bigint,
    0);

-- ---------------------------------------------------------------------------
-- Section 2: pending_recommendations
-- ---------------------------------------------------------------------------
\echo ''
\echo '--- 2. pending_recommendations ---'

-- Dave (employee) has recommendation for 'read public_data' (no conflicting obligation/prohibition)
SELECT morbac.t('Dave (employee) has at least 1 pending recommendation',
    (SELECT COUNT(*) FROM morbac.pending_recommendations(
        '30000000-0000-0000-0000-000000000004'::uuid,
        '10000000-0000-0000-0000-000000000001'::uuid
    )) >= 1,
    TRUE);

-- 'read public_data' recommendation appears (no obligation or prohibition conflicts)
SELECT morbac.t('Dave has pending recommendation: read public_data',
    EXISTS(
        SELECT 1 FROM morbac.pending_recommendations(
            '30000000-0000-0000-0000-000000000004'::uuid,
            '10000000-0000-0000-0000-000000000001'::uuid
        )
        WHERE activity = 'read' AND view = 'public_data'
    ), TRUE);

-- 'read reports' recommendation is voided by the existing obligation (conflict resolution)
SELECT morbac.t('Dave: read reports recommendation is voided by obligation',
    NOT EXISTS(
        SELECT 1 FROM morbac.pending_recommendations(
            '30000000-0000-0000-0000-000000000004'::uuid,
            '10000000-0000-0000-0000-000000000001'::uuid
        )
        WHERE activity = 'read' AND view = 'reports'
    ), TRUE);

-- Eve (intern) has no recommendations
SELECT morbac.t_eq('Eve (intern) has 0 pending recommendations',
    (SELECT COUNT(*) FROM morbac.pending_recommendations(
        '30000000-0000-0000-0000-000000000005'::uuid,
        '10000000-0000-0000-0000-000000000001'::uuid
    ))::bigint,
    0);

-- ---------------------------------------------------------------------------
-- Section 3: Obligations / Recommendations do NOT affect is_allowed
-- ---------------------------------------------------------------------------
\echo ''
\echo '--- 3. Obligations do not affect authorization ---'

-- Add a pure obligation for a view Dave has no permission rule for
INSERT INTO morbac.rules (org_id, role_id, activity, view, context_id, modality)
VALUES (
    '10000000-0000-0000-0000-000000000001',
    '20000000-0001-0000-0000-000000000004', -- employee
    'read', 'contracts',
    (SELECT id FROM morbac.contexts WHERE name = 'always'),
    'obligation'
);

-- Obligation alone doesn't grant access
SELECT morbac.t('Dave has obligation for read contracts but no permission [denied]',
    morbac.is_allowed_nocache(
        '30000000-0000-0000-0000-000000000004'::uuid,
        '10000000-0000-0000-0000-000000000001'::uuid,
        'read', 'contracts'
    ), FALSE);

-- Recommendations similarly do not grant access
INSERT INTO morbac.rules (org_id, role_id, activity, view, context_id, modality)
VALUES (
    '10000000-0000-0000-0000-000000000001',
    '20000000-0001-0000-0000-000000000004', -- employee
    'read', 'audit_logs',
    (SELECT id FROM morbac.contexts WHERE name = 'always'),
    'recommendation'
);

-- Recommendation alone doesn't grant access
SELECT morbac.t('Dave has recommendation for read audit_logs but no permission [denied]',
    morbac.is_allowed_nocache(
        '30000000-0000-0000-0000-000000000004'::uuid,
        '10000000-0000-0000-0000-000000000001'::uuid,
        'read', 'audit_logs'
    ), FALSE);

-- ---------------------------------------------------------------------------
-- Section 3b: Conflict resolution — prohibition voids obligation/recommendation
-- ---------------------------------------------------------------------------
\echo ''
\echo '--- 3b. Conflict resolution: prohibition voids obligation and recommendation ---'

-- Add a prohibition for employee on read contracts (Dave already has an obligation for this)
INSERT INTO morbac.rules (org_id, role_id, activity, view, context_id, modality)
VALUES (
    '10000000-0000-0000-0000-000000000001',
    '20000000-0001-0000-0000-000000000004', -- employee
    'read', 'contracts',
    (SELECT id FROM morbac.contexts WHERE name = 'always'),
    'prohibition'
);

-- Prohibition voids the obligation: read contracts obligation no longer pending
SELECT morbac.t('Dave: read contracts obligation is voided by prohibition',
    NOT EXISTS(
        SELECT 1 FROM morbac.pending_obligations(
            '30000000-0000-0000-0000-000000000004'::uuid,
            '10000000-0000-0000-0000-000000000001'::uuid
        )
        WHERE activity = 'read' AND view = 'contracts'
    ), TRUE);

-- Prohibition also voids the recommendation for read audit_logs
INSERT INTO morbac.rules (org_id, role_id, activity, view, context_id, modality)
VALUES (
    '10000000-0000-0000-0000-000000000001',
    '20000000-0001-0000-0000-000000000004', -- employee
    'read', 'audit_logs',
    (SELECT id FROM morbac.contexts WHERE name = 'always'),
    'prohibition'
);

SELECT morbac.t('Dave: read audit_logs recommendation is voided by prohibition',
    NOT EXISTS(
        SELECT 1 FROM morbac.pending_recommendations(
            '30000000-0000-0000-0000-000000000004'::uuid,
            '10000000-0000-0000-0000-000000000001'::uuid
        )
        WHERE activity = 'read' AND view = 'audit_logs'
    ), TRUE);

-- Clean up: remove the temporary prohibitions added for this test
DELETE FROM morbac.rules
WHERE org_id = '10000000-0000-0000-0000-000000000001'
  AND role_id = '20000000-0001-0000-0000-000000000004'
  AND modality = 'prohibition'
  AND view IN ('contracts', 'audit_logs');

-- ---------------------------------------------------------------------------
-- Section 4: user_has_role
-- ---------------------------------------------------------------------------
\echo ''
\echo '--- 4. user_has_role ---'

-- Alice has the CEO role at GlobalTech
SELECT morbac.t('Alice has ceo role at GlobalTech',
    morbac.user_has_role(
        '30000000-0000-0000-0000-000000000001'::uuid,
        '10000000-0000-0000-0000-000000000001'::uuid,
        'ceo'
    ), TRUE);

-- Alice does NOT have employee role (user_has_role checks direct assignment, not hierarchy)
SELECT morbac.t('Alice does NOT have employee role directly at GlobalTech',
    morbac.user_has_role(
        '30000000-0000-0000-0000-000000000001'::uuid,
        '10000000-0000-0000-0000-000000000001'::uuid,
        'employee'
    ), FALSE);

-- Dave has employee role
SELECT morbac.t('Dave has employee role at GlobalTech',
    morbac.user_has_role(
        '30000000-0000-0000-0000-000000000004'::uuid,
        '10000000-0000-0000-0000-000000000001'::uuid,
        'employee'
    ), TRUE);

-- Dave does not have auditor role
SELECT morbac.t('Dave does not have auditor role at GlobalTech',
    morbac.user_has_role(
        '30000000-0000-0000-0000-000000000004'::uuid,
        '10000000-0000-0000-0000-000000000001'::uuid,
        'auditor'
    ), FALSE);

-- Karl has no role
SELECT morbac.t('Karl does not have employee role at GlobalTech [no role]',
    morbac.user_has_role(
        '30000000-0000-0000-0000-000000000011'::uuid,
        '10000000-0000-0000-0000-000000000001'::uuid,
        'employee'
    ), FALSE);

-- Judy has engineer at Engineering but not at GlobalTech
SELECT morbac.t('Judy does not have engineer role at GlobalTech [wrong org]',
    morbac.user_has_role(
        '30000000-0000-0000-0000-000000000010'::uuid,
        '10000000-0000-0000-0000-000000000001'::uuid,
        'engineer'
    ), FALSE);

SELECT morbac.t('Judy has engineer role at Engineering [correct org]',
    morbac.user_has_role(
        '30000000-0000-0000-0000-000000000010'::uuid,
        '10000000-0000-0000-0000-000000000002'::uuid,
        'engineer'
    ), TRUE);

-- ---------------------------------------------------------------------------
-- Section 5: user_roles_in_org
-- ---------------------------------------------------------------------------
\echo ''
\echo '--- 5. user_roles_in_org ---'

-- Alice has exactly 1 role at GlobalTech (ceo)
SELECT morbac.t_eq('Alice has exactly 1 role at GlobalTech (ceo)',
    (SELECT COUNT(*) FROM morbac.user_roles_in_org(
        '30000000-0000-0000-0000-000000000001'::uuid,
        '10000000-0000-0000-0000-000000000001'::uuid
    ))::bigint,
    1);

SELECT morbac.t('Alice role at GlobalTech is ceo',
    EXISTS(
        SELECT 1 FROM morbac.user_roles_in_org(
            '30000000-0000-0000-0000-000000000001'::uuid,
            '10000000-0000-0000-0000-000000000001'::uuid
        )
        WHERE role_name = 'ceo'
    ), TRUE);

-- Judy has 1 role at Engineering (engineer)
SELECT morbac.t_eq('Judy has 1 role at Engineering',
    (SELECT COUNT(*) FROM morbac.user_roles_in_org(
        '30000000-0000-0000-0000-000000000010'::uuid,
        '10000000-0000-0000-0000-000000000002'::uuid
    ))::bigint,
    1);

-- Judy has 1 role at Sales (sales_rep)
SELECT morbac.t_eq('Judy has 1 role at Sales',
    (SELECT COUNT(*) FROM morbac.user_roles_in_org(
        '30000000-0000-0000-0000-000000000010'::uuid,
        '10000000-0000-0000-0000-000000000003'::uuid
    ))::bigint,
    1);

-- Karl has no roles at GlobalTech
SELECT morbac.t_eq('Karl has 0 roles at GlobalTech',
    (SELECT COUNT(*) FROM morbac.user_roles_in_org(
        '30000000-0000-0000-0000-000000000011'::uuid,
        '10000000-0000-0000-0000-000000000001'::uuid
    ))::bigint,
    0);

-- ---------------------------------------------------------------------------
-- Section 6: eval_context
-- ---------------------------------------------------------------------------
\echo ''
\echo '--- 6. eval_context ---'

-- 'always' context always returns TRUE
SELECT morbac.t('eval_context(always) = TRUE',
    morbac.eval_context((SELECT id FROM morbac.contexts WHERE name = 'always')),
    TRUE);

-- 'business_hours' context returns TRUE (our test implementation)
SELECT morbac.t('eval_context(business_hours) = TRUE',
    morbac.eval_context((SELECT id FROM morbac.contexts WHERE name = 'business_hours')),
    TRUE);

-- 'after_hours' context returns FALSE (our test implementation)
SELECT morbac.t('eval_context(after_hours) = FALSE',
    morbac.eval_context((SELECT id FROM morbac.contexts WHERE name = 'after_hours')),
    FALSE);

-- 'end_of_quarter' context returns TRUE (our test implementation)
SELECT morbac.t('eval_context(end_of_quarter) = TRUE',
    morbac.eval_context((SELECT id FROM morbac.contexts WHERE name = 'end_of_quarter')),
    TRUE);

-- ---------------------------------------------------------------------------
-- Section 7: Policy DSL — idempotency
-- ---------------------------------------------------------------------------
\echo ''
\echo '--- 7. Policy DSL idempotency ---'

-- All existing policies are already compiled (compiled=TRUE)
-- Running compile_policy() again should compile 0 new entries
SELECT morbac.t_eq('Re-running compile_policy() gives compiled_count=0 (all already compiled)',
    (SELECT compiled_count FROM morbac.compile_policy()),
    0);

SELECT morbac.t_eq('Re-running compile_policy() gives error_count=0',
    (SELECT error_count FROM morbac.compile_policy()),
    0);

-- Adding a new policy and verifying it compiles once but not twice
INSERT INTO morbac.policy (org_name, role_name, activity, view, modality, context_name)
VALUES ('GlobalTech HQ', 'employee', 'read', 'contracts', 'permission', 'always');

SELECT morbac.t_eq('compile_policy() compiles 1 new policy entry',
    (SELECT compiled_count FROM morbac.compile_policy()),
    1);

SELECT morbac.t_eq('compile_policy() is idempotent: compiled_count=0 on second run',
    (SELECT compiled_count FROM morbac.compile_policy()),
    0);

-- Verify the rule was actually created
SELECT morbac.t_eq('Rule for employee read contracts was created',
    (SELECT COUNT(*) FROM morbac.rules r
     JOIN morbac.roles ro ON ro.id = r.role_id
     WHERE ro.name = 'employee'
       AND r.activity = 'read' AND r.view = 'contracts' AND r.modality = 'permission')::bigint,
    1);

-- ---------------------------------------------------------------------------
-- Section 8: Policy DSL — error handling
-- ---------------------------------------------------------------------------
\echo ''
\echo '--- 8. Policy DSL error handling ---'

-- Insert a policy for a non-existent organization
INSERT INTO morbac.policy (org_name, role_name, activity, view, modality, context_name)
VALUES ('Nonexistent Corp', 'employee', 'read', 'documents', 'permission', 'always');

-- Should produce errors (org not found)
SELECT morbac.t('compile_policy: nonexistent org produces errors',
    (SELECT error_count > 0 FROM morbac.compile_policy()),
    TRUE);

-- Insert a policy with a valid org but nonexistent role
INSERT INTO morbac.policy (org_name, role_name, activity, view, modality, context_name)
VALUES ('GlobalTech HQ', 'ghost_role', 'read', 'documents', 'permission', 'always');

-- Should produce errors (role not found)
SELECT morbac.t('compile_policy: nonexistent role produces errors',
    (SELECT error_count > 0 FROM morbac.compile_policy()),
    TRUE);

-- ---------------------------------------------------------------------------
-- Section 9: Derived roles
-- ---------------------------------------------------------------------------
\echo ''
\echo '--- 9. Derived roles ---'

-- Create a derived role: 'senior_employee' — dynamically granted to Dave (only)
INSERT INTO morbac.roles (id, org_id, name, description)
VALUES (
    '20000000-0001-0000-0000-000000000011',
    '10000000-0000-0000-0000-000000000001',
    'senior_employee',
    'Senior employee — granted dynamically based on tenure'
);

-- Evaluator function: returns TRUE only for Dave at GlobalTech
CREATE OR REPLACE FUNCTION morbac.eval_senior_employee(p_user_id UUID, p_org_id UUID)
RETURNS BOOLEAN LANGUAGE plpgsql STABLE AS $$
BEGIN
    -- In a real system, this would query app.employees for tenure >= 2 years.
    -- For testing, we hardcode Dave's UUID.
    RETURN p_user_id = '30000000-0000-0000-0000-000000000004'::UUID
       AND p_org_id  = '10000000-0000-0000-0000-000000000001'::UUID;
END;
$$;

INSERT INTO morbac.derived_roles (role_id, condition_evaluator, description)
VALUES (
    '20000000-0001-0000-0000-000000000011',
    'morbac.eval_senior_employee'::regproc,
    'Senior employee role: granted to employees with 2+ years tenure'
);

-- Grant senior_employee permission to read financial_data directly
-- (separate from the view hierarchy path, to test derived role specifically)
INSERT INTO morbac.rules (org_id, role_id, activity, view, context_id, modality)
VALUES (
    '10000000-0000-0000-0000-000000000001',
    '20000000-0001-0000-0000-000000000011', -- senior_employee role
    'read', 'financial_data',
    (SELECT id FROM morbac.contexts WHERE name = 'always'),
    'permission'
);

-- Dave should have senior_employee via derived role in get_comprehensive_roles
SELECT morbac.t('Dave has senior_employee derived role in comprehensive roles',
    EXISTS(
        SELECT 1 FROM morbac.get_comprehensive_roles(
            '30000000-0000-0000-0000-000000000004'::uuid,
            '10000000-0000-0000-0000-000000000001'::uuid
        )
        WHERE role_id = '20000000-0001-0000-0000-000000000011'
          AND source = 'derived'
    ), TRUE);

-- Eve (intern) does NOT satisfy the evaluator — no derived role
SELECT morbac.t('Eve has no derived roles in comprehensive roles',
    NOT EXISTS(
        SELECT 1 FROM morbac.get_comprehensive_roles(
            '30000000-0000-0000-0000-000000000005'::uuid,
            '10000000-0000-0000-0000-000000000001'::uuid
        )
        WHERE source = 'derived'
    ), TRUE);

-- Karl (no role) does not get the derived role
SELECT morbac.t('Karl has no derived roles in comprehensive roles',
    NOT EXISTS(
        SELECT 1 FROM morbac.get_comprehensive_roles(
            '30000000-0000-0000-0000-000000000011'::uuid,
            '10000000-0000-0000-0000-000000000001'::uuid
        )
        WHERE source = 'derived'
    ), TRUE);

-- Negative assignment overrides derived role
INSERT INTO morbac.negative_role_assignments (user_id, role_id, org_id, reason)
VALUES (
    '30000000-0000-0000-0000-000000000004', -- Dave
    '20000000-0001-0000-0000-000000000011', -- senior_employee
    '10000000-0000-0000-0000-000000000001',
    'Derived role explicitly blocked for testing'
);

-- Derived role is blocked by negative assignment
SELECT morbac.t('Dave: senior_employee derived role absent after negative assignment',
    NOT EXISTS(
        SELECT 1 FROM morbac.get_comprehensive_roles(
            '30000000-0000-0000-0000-000000000004'::uuid,
            '10000000-0000-0000-0000-000000000001'::uuid
        )
        WHERE role_id = '20000000-0001-0000-0000-000000000011'
    ), TRUE);

-- Dave's direct employee role is still present (negative only blocks senior_employee)
SELECT morbac.t('Dave: employee role still present after senior_employee negated',
    EXISTS(
        SELECT 1 FROM morbac.get_comprehensive_roles(
            '30000000-0000-0000-0000-000000000004'::uuid,
            '10000000-0000-0000-0000-000000000001'::uuid
        )
        WHERE role_id = '20000000-0001-0000-0000-000000000004'
          AND source = 'direct'
    ), TRUE);

-- Clean up negative assignment
DELETE FROM morbac.negative_role_assignments
WHERE user_id = '30000000-0000-0000-0000-000000000004'
  AND role_id = '20000000-0001-0000-0000-000000000011';

-- ---------------------------------------------------------------------------
-- Section 10: RLS helper functions
-- ---------------------------------------------------------------------------
\echo ''
\echo '--- 10. RLS helpers: get_user_orgs, current_org_ids, rls_check ---'

-- Without session variables set, current_user_id / current_org_id / current_org_ids return NULL
SELECT morbac.t_null('current_user_id() returns NULL without session var',
    morbac.current_user_id()::text);

SELECT morbac.t_null('current_org_id() returns NULL without session var',
    morbac.current_org_id()::text);

SELECT morbac.t_null('current_org_ids() returns NULL without session var',
    morbac.current_org_ids()::text);

-- rls_check without any session context returns FALSE
SELECT morbac.t('rls_check without session context returns FALSE',
    morbac.rls_check('read', 'documents'),
    FALSE);

-- get_user_orgs: Judy has roles in Engineering and Sales (2 orgs)
SELECT morbac.t_eq('get_user_orgs(Judy) returns 2 orgs',
    (SELECT COUNT(*) FROM morbac.get_user_orgs('30000000-0000-0000-0000-000000000010'::uuid))::bigint,
    2);

SELECT morbac.t('get_user_orgs(Judy) includes Engineering',
    EXISTS(SELECT 1 FROM morbac.get_user_orgs('30000000-0000-0000-0000-000000000010'::uuid)
           WHERE org_id = '10000000-0000-0000-0000-000000000002'),
    TRUE);

SELECT morbac.t('get_user_orgs(Judy) includes Sales',
    EXISTS(SELECT 1 FROM morbac.get_user_orgs('30000000-0000-0000-0000-000000000010'::uuid)
           WHERE org_id = '10000000-0000-0000-0000-000000000003'),
    TRUE);

-- get_user_orgs: Karl has no roles anywhere
SELECT morbac.t_eq('get_user_orgs(Karl) returns 0 orgs',
    (SELECT COUNT(*) FROM morbac.get_user_orgs('30000000-0000-0000-0000-000000000011'::uuid))::bigint,
    0);

-- Single-org mode: morbac.org_id set
SET morbac.user_id = '30000000-0000-0000-0000-000000000004';
SET morbac.org_id  = '10000000-0000-0000-0000-000000000001';

SELECT morbac.t('rls_check(read, documents) as Dave at GlobalTech',
    morbac.rls_check('read', 'documents'),
    TRUE);

SELECT morbac.t('rls_check(approve, documents) as Dave at GlobalTech [no permission]',
    morbac.rls_check('approve', 'documents'),
    FALSE);

-- Row org matches session org -> allowed
SELECT morbac.t('rls_check with matching row org_id allows access',
    morbac.rls_check('read', 'documents', '10000000-0000-0000-0000-000000000001'),
    TRUE);

-- Row org does not match session org -> denied regardless of permissions
SELECT morbac.t('rls_check with non-matching row org_id denies access',
    morbac.rls_check('read', 'documents', '10000000-0000-0000-0000-000000000002'),
    FALSE);

RESET morbac.org_id;

-- Org-list mode: morbac.org_ids set (Judy in Engineering + Sales)
SET morbac.user_id = '30000000-0000-0000-0000-000000000010';
SET morbac.org_ids = '["10000000-0000-0000-0000-000000000002","10000000-0000-0000-0000-000000000003"]';

-- Row in Engineering: Judy is engineer there -> can read documents
SELECT morbac.t('rls_check org_ids mode: Judy reads documents in Engineering [allowed]',
    morbac.rls_check('read', 'documents', '10000000-0000-0000-0000-000000000002'),
    TRUE);

-- Row in Sales: Judy is sales_rep -> can read documents there too
SELECT morbac.t('rls_check org_ids mode: Judy reads documents in Sales [allowed]',
    morbac.rls_check('read', 'documents', '10000000-0000-0000-0000-000000000003'),
    TRUE);

-- Row in GlobalTech: not in org_ids list -> denied
SELECT morbac.t('rls_check org_ids mode: row org not in list [denied]',
    morbac.rls_check('read', 'documents', '10000000-0000-0000-0000-000000000001'),
    FALSE);

-- No row org provided with org_ids set -> denied
SELECT morbac.t('rls_check org_ids mode: no row org_id [denied]',
    morbac.rls_check('read', 'documents'),
    FALSE);

RESET morbac.org_ids;

-- All-orgs mode: no org_id / org_ids set, row org_id provided
-- Judy can read documents in Engineering
SELECT morbac.t('rls_check all-orgs mode: Judy reads documents in Engineering [allowed]',
    morbac.rls_check('read', 'documents', '10000000-0000-0000-0000-000000000002'),
    TRUE);

-- Judy has no role at GlobalTech -> denied even in all-orgs mode
SELECT morbac.t('rls_check all-orgs mode: Judy reads documents in GlobalTech [no role, denied]',
    morbac.rls_check('read', 'documents', '10000000-0000-0000-0000-000000000001'),
    FALSE);

-- No row org and no session org -> denied
SELECT morbac.t('rls_check all-orgs mode: no row org_id [denied]',
    morbac.rls_check('read', 'documents'),
    FALSE);

-- Karl has no role anywhere -> denied in all modes
SET morbac.user_id = '30000000-0000-0000-0000-000000000011';

SELECT morbac.t('rls_check(read, documents) as Karl (no role) [denied]',
    morbac.rls_check('read', 'documents', '10000000-0000-0000-0000-000000000001'),
    FALSE);

RESET morbac.user_id;

\echo ''
\echo '=== Utilities, Derived Roles, RLS, and Policy DSL Tests Completed ==='
