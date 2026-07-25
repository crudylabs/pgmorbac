-- =============================================================================
-- Delegation Tests
-- =============================================================================
-- Tests the role delegation feature:
--   - Active delegation grants the delegate the delegator's role permissions
--   - Expired delegations are inactive
--   - Future delegations are not yet active
--   - Revoked delegations are inactive
--   - Delegator must hold the role (delegation from source is validated)
--   - Negative role assignments override delegations
--   - Delegated roles participate in role hierarchy
--   - get_comprehensive_roles reports delegation source
--
-- Scenario:
--   Carol (manager) delegates her manager role to Leo (employee) for 1 day
--   -> Leo should temporarily have manager-level access
--
-- Prerequisites: 00_setup.sql -> 02_hierarchies.sql
-- =============================================================================

\echo ''
\echo '================================================================'
\echo '03 - DELEGATION'
\echo '================================================================'

-- ---------------------------------------------------------------------------
-- Section 1: Baseline - Leo (employee) before any delegation
-- ---------------------------------------------------------------------------
\echo ''
\echo '--- 1. Baseline: Leo before delegation ---'

-- Leo has only employee permissions
SELECT morbac.t('Leo (employee) reads documents before delegation',
    morbac.is_allowed_nocache(
        '30000000-0000-0000-0000-000000000012'::uuid,
        '10000000-0000-0000-0000-000000000001'::uuid,
        'read', 'documents'
    ), TRUE);

-- Leo cannot approve documents - that requires manager role
SELECT morbac.t('Leo (employee) approves documents before delegation [no manager perm]',
    morbac.is_allowed_nocache(
        '30000000-0000-0000-0000-000000000012'::uuid,
        '10000000-0000-0000-0000-000000000001'::uuid,
        'approve', 'documents'
    ), FALSE);

-- Leo cannot delete documents (no employee delete perm, activity hierarchy grants delete via read rule,
-- but 'delete' implies only that if there's a delete->write->read chain; in 02 we set write->read but
-- the chain delete->write was also set. So Leo gets delete via documents perm. Let's check:
-- Actually with activity hierarchy (delete->write->read), the 'read documents' rule covers delete.
SELECT morbac.t('Leo (employee) deletes documents before delegation [via activity hierarchy]',
    morbac.is_allowed_nocache(
        '30000000-0000-0000-0000-000000000012'::uuid,
        '10000000-0000-0000-0000-000000000001'::uuid,
        'delete', 'documents'
    ), TRUE);

-- Leo cannot approve documents (approve is not in activity hierarchy for documents)
-- This is the key baseline check: approve requires manager-level permission
SELECT morbac.t('Leo (employee) does not have approve permission before delegation',
    morbac.is_allowed_nocache(
        '30000000-0000-0000-0000-000000000012'::uuid,
        '10000000-0000-0000-0000-000000000001'::uuid,
        'approve', 'documents'
    ), FALSE);

-- ---------------------------------------------------------------------------
-- Section 2: Active delegation - Carol delegates manager role to Leo
-- ---------------------------------------------------------------------------
\echo ''
\echo '--- 2. Active delegation: Carol -> Leo (manager role, 1 day) ---'

INSERT INTO morbac.delegations
    (id, delegator_id, delegatee_id, role_id, org_id, valid_from, valid_until)
VALUES (
    'de000001-0000-0000-0000-000000000001',
    '30000000-0000-0000-0000-000000000003', -- Carol (delegator, holds manager)
    '30000000-0000-0000-0000-000000000012', -- Leo (delegatee)
    '20000000-0001-0000-0000-000000000003', -- manager role
    '10000000-0000-0000-0000-000000000001',
    now() - interval '1 hour',
    now() + interval '1 day'
);

-- Leo now has delegated manager role - can approve documents
SELECT morbac.t('Leo (delegated manager) approves documents',
    morbac.is_allowed_nocache(
        '30000000-0000-0000-0000-000000000012'::uuid,
        '10000000-0000-0000-0000-000000000001'::uuid,
        'approve', 'documents'
    ), TRUE);

-- Leo can delete documents (manager permission)
SELECT morbac.t('Leo (delegated manager) deletes documents',
    morbac.is_allowed_nocache(
        '30000000-0000-0000-0000-000000000012'::uuid,
        '10000000-0000-0000-0000-000000000001'::uuid,
        'delete', 'documents'
    ), TRUE);

-- Leo (delegated manager) inherits manager's inherited permissions:
-- manager->employee->intern chain; employee has read documents -> view hierarchy covers financial_data
SELECT morbac.t('Leo (delegated manager) reads financial_data via manager+view hierarchy',
    morbac.is_allowed_nocache(
        '30000000-0000-0000-0000-000000000012'::uuid,
        '10000000-0000-0000-0000-000000000001'::uuid,
        'read', 'financial_data'
    ), TRUE);

-- get_comprehensive_roles should show manager role with delegation source
SELECT morbac.t('Leo has delegated manager role in comprehensive roles',
    EXISTS(
        SELECT 1 FROM morbac.get_comprehensive_roles(
            '30000000-0000-0000-0000-000000000012'::uuid,
            '10000000-0000-0000-0000-000000000001'::uuid
        )
        WHERE role_id = '20000000-0001-0000-0000-000000000003'
          AND source LIKE 'delegation%'
    ), TRUE);

-- Employee role appears as direct in comprehensive roles
SELECT morbac.t('Leo has employee role as direct in comprehensive roles',
    EXISTS(
        SELECT 1 FROM morbac.get_comprehensive_roles(
            '30000000-0000-0000-0000-000000000012'::uuid,
            '10000000-0000-0000-0000-000000000001'::uuid
        )
        WHERE role_id = '20000000-0001-0000-0000-000000000004'
          AND source = 'direct'
    ), TRUE);

-- ---------------------------------------------------------------------------
-- Section 3: Expired delegation
-- ---------------------------------------------------------------------------
\echo ''
\echo '--- 3. Expired delegation ---'

INSERT INTO morbac.delegations
    (id, delegator_id, delegatee_id, role_id, org_id, valid_from, valid_until)
VALUES (
    'de000001-0000-0000-0000-000000000002',
    '30000000-0000-0000-0000-000000000008', -- Heidi (auditor)
    '30000000-0000-0000-0000-000000000004', -- Dave
    '20000000-0001-0000-0000-000000000006', -- auditor role
    '10000000-0000-0000-0000-000000000001',
    now() - interval '7 days',
    now() - interval '1 second'  -- expired 1 second ago
);

-- Dave should NOT get auditor permissions from expired delegation
SELECT morbac.t('Dave via expired auditor delegation reads audit_logs [delegation expired]',
    morbac.is_allowed_nocache(
        '30000000-0000-0000-0000-000000000004'::uuid,
        '10000000-0000-0000-0000-000000000001'::uuid,
        'read', 'audit_logs'
    ), FALSE);

-- The expired delegation should NOT appear in comprehensive roles
SELECT morbac.t('Expired auditor delegation not in Dave comprehensive roles',
    NOT EXISTS(
        SELECT 1 FROM morbac.get_comprehensive_roles(
            '30000000-0000-0000-0000-000000000004'::uuid,
            '10000000-0000-0000-0000-000000000001'::uuid
        )
        WHERE role_id = '20000000-0001-0000-0000-000000000006'
          AND source LIKE 'delegation%'
    ), TRUE);

-- ---------------------------------------------------------------------------
-- Section 4: Future delegation (not yet active)
-- ---------------------------------------------------------------------------
\echo ''
\echo '--- 4. Future delegation (not yet active) ---'

INSERT INTO morbac.delegations
    (id, delegator_id, delegatee_id, role_id, org_id, valid_from, valid_until)
VALUES (
    'de000001-0000-0000-0000-000000000003',
    '30000000-0000-0000-0000-000000000007', -- Grace (hr_manager)
    '30000000-0000-0000-0000-000000000004', -- Dave
    '20000000-0001-0000-0000-000000000008', -- hr_manager role
    '10000000-0000-0000-0000-000000000001',
    now() + interval '1 day',       -- starts tomorrow
    now() + interval '8 days'
);

-- Dave should NOT have hr_manager in his comprehensive roles (delegation not yet active)
-- Note: employee already has write hr_data via view hierarchy (hr_data->documents);
-- so we test comprehensive roles rather than is_allowed to verify the delegation is inactive.
SELECT morbac.t('Future hr_manager delegation not yet in Dave comprehensive roles',
    NOT EXISTS(
        SELECT 1 FROM morbac.get_comprehensive_roles(
            '30000000-0000-0000-0000-000000000004'::uuid,
            '10000000-0000-0000-0000-000000000001'::uuid
        )
        WHERE role_id = '20000000-0001-0000-0000-000000000008' -- hr_manager
          AND source LIKE 'delegation%'
    ), TRUE);

-- ---------------------------------------------------------------------------
-- Section 5: Revoked delegation
-- ---------------------------------------------------------------------------
\echo ''
\echo '--- 5. Revoked delegation ---'

INSERT INTO morbac.delegations
    (id, delegator_id, delegatee_id, role_id, org_id, valid_from, valid_until, revoked)
VALUES (
    'de000001-0000-0000-0000-000000000004',
    '30000000-0000-0000-0000-000000000009', -- Ivan (accountant)
    '30000000-0000-0000-0000-000000000004', -- Dave
    '20000000-0001-0000-0000-000000000007', -- accountant role
    '10000000-0000-0000-0000-000000000001',
    now() - interval '1 hour',
    now() + interval '1 day',
    TRUE  -- revoked
);

-- Dave should NOT get accountant from revoked delegation - verify revoked flag is set
-- Note: employee already has write financial_data via view hierarchy;
-- so we verify the delegation is actually revoked in the DB.
SELECT morbac.t('Revoked accountant delegation has revoked=TRUE in DB',
    (SELECT revoked FROM morbac.delegations
     WHERE id = 'de000001-0000-0000-0000-000000000004'),
    TRUE);

-- The revoked delegation should NOT appear in comprehensive roles
SELECT morbac.t('Revoked accountant delegation not in Dave comprehensive roles',
    NOT EXISTS(
        SELECT 1 FROM morbac.get_comprehensive_roles(
            '30000000-0000-0000-0000-000000000004'::uuid,
            '10000000-0000-0000-0000-000000000001'::uuid
        )
        WHERE role_id = '20000000-0001-0000-0000-000000000007'
          AND source LIKE 'delegation%'
    ), TRUE);

-- ---------------------------------------------------------------------------
-- Section 6: Delegation blocked by negative role assignment
-- ---------------------------------------------------------------------------
\echo ''
\echo '--- 6. Negative role assignment overrides delegation ---'

-- Leo has an active delegation for manager role (from section 2)
-- Now add a negative assignment to block that same role
INSERT INTO morbac.negative_role_assignments (user_id, role_id, org_id, reason)
VALUES (
    '30000000-0000-0000-0000-000000000012', -- Leo
    '20000000-0001-0000-0000-000000000003', -- manager role
    '10000000-0000-0000-0000-000000000001',
    'Temporarily suspended from manager responsibilities'
);

-- negative assignment blocks the delegated manager role
SELECT morbac.t('Leo (delegated manager, but negatively assigned) approves documents [blocked]',
    morbac.is_allowed_nocache(
        '30000000-0000-0000-0000-000000000012'::uuid,
        '10000000-0000-0000-0000-000000000001'::uuid,
        'approve', 'documents'
    ), FALSE);

-- Leo's own employee permissions still work (negative is only for manager)
SELECT morbac.t('Leo (employee, manager negated) reads documents [employee perm unaffected]',
    morbac.is_allowed_nocache(
        '30000000-0000-0000-0000-000000000012'::uuid,
        '10000000-0000-0000-0000-000000000001'::uuid,
        'read', 'documents'
    ), TRUE);

-- Manager delegation no longer appears in comprehensive roles (blocked by negative)
SELECT morbac.t('Negated manager delegation not in Leo comprehensive roles',
    NOT EXISTS(
        SELECT 1 FROM morbac.get_comprehensive_roles(
            '30000000-0000-0000-0000-000000000012'::uuid,
            '10000000-0000-0000-0000-000000000001'::uuid
        )
        WHERE role_id = '20000000-0001-0000-0000-000000000003'
    ), TRUE);

-- Clean up negative assignment so subsequent tests aren't affected
DELETE FROM morbac.negative_role_assignments
WHERE user_id = '30000000-0000-0000-0000-000000000012'
  AND role_id = '20000000-0001-0000-0000-000000000003'
  AND org_id  = '10000000-0000-0000-0000-000000000001';

-- ---------------------------------------------------------------------------
-- Section 7: Delegator must hold the role (validation check)
-- ---------------------------------------------------------------------------
\echo ''
\echo '--- 7. Delegator-role validation ---'

-- Create a delegation where the delegator does NOT hold the role
-- Dave (employee) tries to delegate the manager role (which he does not have)
INSERT INTO morbac.delegations
    (id, delegator_id, delegatee_id, role_id, org_id, valid_from, valid_until)
VALUES (
    'de000001-0000-0000-0000-000000000005',
    '30000000-0000-0000-0000-000000000004', -- Dave (employee - does NOT hold manager)
    '30000000-0000-0000-0000-000000000005', -- Eve
    '20000000-0001-0000-0000-000000000003', -- manager role
    '10000000-0000-0000-0000-000000000001',
    now() - interval '1 hour',
    now() + interval '1 day'
);

-- get_comprehensive_roles requires delegator to hold the role
-- Eve does NOT get manager access from invalid delegation
SELECT morbac.t('Eve via invalid delegation (Dave does not hold manager) denied approve',
    morbac.is_allowed_nocache(
        '30000000-0000-0000-0000-000000000005'::uuid,
        '10000000-0000-0000-0000-000000000001'::uuid,
        'approve', 'documents'
    ), FALSE);

-- The invalid delegation should NOT appear in Eve's comprehensive roles
SELECT morbac.t('Invalid delegation not in Eve comprehensive roles',
    NOT EXISTS(
        SELECT 1 FROM morbac.get_comprehensive_roles(
            '30000000-0000-0000-0000-000000000005'::uuid,
            '10000000-0000-0000-0000-000000000001'::uuid
        )
        WHERE role_id = '20000000-0001-0000-0000-000000000003'
          AND source LIKE 'delegation%'
    ), TRUE);

-- ---------------------------------------------------------------------------
-- Section 8: Comprehensive roles source reporting
-- ---------------------------------------------------------------------------
\echo ''
\echo '--- 8. get_comprehensive_roles source reporting ---'

-- Alice (CEO, direct) - source should be 'direct'
SELECT morbac.t('Alice CEO role has source=direct in comprehensive roles',
    EXISTS(
        SELECT 1 FROM morbac.get_comprehensive_roles(
            '30000000-0000-0000-0000-000000000001'::uuid,
            '10000000-0000-0000-0000-000000000001'::uuid
        )
        WHERE role_id = '20000000-0001-0000-0000-000000000001'
          AND source = 'direct'
    ), TRUE);

-- Alice has no delegation-sourced roles
SELECT morbac.t('Alice has no delegation-sourced roles',
    NOT EXISTS(
        SELECT 1 FROM morbac.get_comprehensive_roles(
            '30000000-0000-0000-0000-000000000001'::uuid,
            '10000000-0000-0000-0000-000000000001'::uuid
        )
        WHERE source LIKE 'delegation%'
    ), TRUE);

\echo ''
\echo '=== Delegation Tests Completed ==='
