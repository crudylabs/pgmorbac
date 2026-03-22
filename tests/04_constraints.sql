-- =============================================================================
-- Constraint Tests
-- =============================================================================
-- Tests business constraints:
--   1. Separation of Duty (SoD) — mutually exclusive roles
--   2. Negative role assignments — explicit blocking of a role
--   3. Role cardinality constraints — min/max users per role
--   4. Rule conflict detection — modality conflicts on same tuple
--
-- Scenario:
--   - auditor and accountant are mutually exclusive (no one can hold both)
--   - Heidi (auditor) cannot be assigned accountant role
--   - Ivan (accountant) cannot be assigned auditor role
--   - Frank (contractor) is explicitly blocked from the employee role
--   - compliance_officer role has a min 1, max 2 cardinality constraint
--
-- Prerequisites: 00_setup.sql -> 03_delegation.sql
-- =============================================================================

\echo ''
\echo '================================================================'
\echo '04 — CONSTRAINTS'
\echo '================================================================'

-- ---------------------------------------------------------------------------
-- Section 1: Separation of Duty — define conflict
-- ---------------------------------------------------------------------------
\echo ''
\echo '--- 1. Separation of Duty setup ---'

INSERT INTO morbac.sod_conflicts (role_a_id, role_b_id, org_id, description)
VALUES (
    '20000000-0001-0000-0000-000000000006', -- auditor
    '20000000-0001-0000-0000-000000000007', -- accountant
    '10000000-0000-0000-0000-000000000001',
    'Auditors and accountants are mutually exclusive to ensure financial independence'
);

-- Verify the conflict was created
SELECT morbac.t_eq('SoD conflict between auditor and accountant created',
    (SELECT COUNT(*) FROM morbac.sod_conflicts
     WHERE role_a_id = '20000000-0001-0000-0000-000000000006'
       AND role_b_id = '20000000-0001-0000-0000-000000000007')::bigint,
    1);

-- ---------------------------------------------------------------------------
-- Section 2: SoD violation detection
-- ---------------------------------------------------------------------------
\echo ''
\echo '--- 2. SoD violation detection ---'

-- Heidi (auditor) — check if assigning accountant role would violate SoD
SELECT morbac.t('Assigning accountant to Heidi (auditor) violates SoD',
    morbac.check_sod_violation(
        '30000000-0000-0000-0000-000000000008'::uuid,  -- Heidi
        '20000000-0001-0000-0000-000000000007'::uuid,  -- accountant role
        '10000000-0000-0000-0000-000000000001'::uuid
    ), TRUE);

-- Ivan (accountant) — check if assigning auditor role would violate SoD
SELECT morbac.t('Assigning auditor to Ivan (accountant) violates SoD [symmetric]',
    morbac.check_sod_violation(
        '30000000-0000-0000-0000-000000000009'::uuid,  -- Ivan
        '20000000-0001-0000-0000-000000000006'::uuid,  -- auditor role
        '10000000-0000-0000-0000-000000000001'::uuid
    ), TRUE);

-- Dave (employee) — check if assigning accountant would violate SoD
-- Dave is not an auditor — no conflict
SELECT morbac.t('Assigning accountant to Dave (not an auditor) does not violate SoD',
    morbac.check_sod_violation(
        '30000000-0000-0000-0000-000000000004'::uuid,  -- Dave
        '20000000-0001-0000-0000-000000000007'::uuid,  -- accountant role
        '10000000-0000-0000-0000-000000000001'::uuid
    ), FALSE);

-- Heidi (auditor) — assigning a non-conflicting role (manager) is fine
SELECT morbac.t('Assigning manager to Heidi (auditor) does not violate SoD',
    morbac.check_sod_violation(
        '30000000-0000-0000-0000-000000000008'::uuid,  -- Heidi
        '20000000-0001-0000-0000-000000000003'::uuid,  -- manager role
        '10000000-0000-0000-0000-000000000001'::uuid
    ), FALSE);

-- User in a different org has no SoD conflict with GlobalTech roles
-- Judy is in Engineering/Sales, not GlobalTech
SELECT morbac.t('Assigning accountant to Judy (no GlobalTech roles) does not violate SoD',
    morbac.check_sod_violation(
        '30000000-0000-0000-0000-000000000010'::uuid,  -- Judy
        '20000000-0001-0000-0000-000000000007'::uuid,  -- accountant role
        '10000000-0000-0000-0000-000000000001'::uuid
    ), FALSE);

-- ---------------------------------------------------------------------------
-- Section 3: Negative role assignments
-- ---------------------------------------------------------------------------
\echo ''
\echo '--- 3. Negative role assignments ---'

-- Baseline: Frank (contractor) has read documents permission
SELECT morbac.t('Frank (contractor) reads documents [baseline before negative assignment]',
    morbac.is_allowed_nocache(
        '30000000-0000-0000-0000-000000000006'::uuid,
        '10000000-0000-0000-0000-000000000001'::uuid,
        'read', 'documents'
    ), TRUE);

-- Add employee role directly to Frank (unusual but valid)
INSERT INTO morbac.user_roles (user_id, role_id, org_id) VALUES
    ('30000000-0000-0000-0000-000000000006', '20000000-0001-0000-0000-000000000004', '10000000-0000-0000-0000-000000000001');

-- Frank now has both contractor and employee roles; employee grants write documents
SELECT morbac.t('Frank (now also employee) writes documents [employee permission]',
    morbac.is_allowed_nocache(
        '30000000-0000-0000-0000-000000000006'::uuid,
        '10000000-0000-0000-0000-000000000001'::uuid,
        'write', 'documents'
    ), TRUE);

-- Add negative assignment blocking Frank from the employee role
INSERT INTO morbac.negative_role_assignments (user_id, role_id, org_id, reason)
VALUES (
    '30000000-0000-0000-0000-000000000006', -- Frank
    '20000000-0001-0000-0000-000000000004', -- employee role
    '10000000-0000-0000-0000-000000000001',
    'Frank is a contractor and must not gain employee-level access'
);

-- Frank's employee role is negated — verify via get_comprehensive_roles
-- employee role must not appear (negated by negative assignment)
SELECT morbac.t('Frank: employee role excluded by negative assignment',
    NOT EXISTS(
        SELECT 1 FROM morbac.get_comprehensive_roles(
            '30000000-0000-0000-0000-000000000006'::uuid,
            '10000000-0000-0000-0000-000000000001'::uuid
        )
        WHERE role_id = '20000000-0001-0000-0000-000000000004'
    ), TRUE);

-- Frank's contractor role still appears (only employee is negated)
SELECT morbac.t('Frank: contractor role still present after employee negated',
    EXISTS(
        SELECT 1 FROM morbac.get_comprehensive_roles(
            '30000000-0000-0000-0000-000000000006'::uuid,
            '10000000-0000-0000-0000-000000000001'::uuid
        )
        WHERE role_id = '20000000-0001-0000-0000-000000000009'
    ), TRUE);

-- Negative assignment on a role the user never had is harmless
-- Karl has no role — adding negative assignment for manager is a no-op
INSERT INTO morbac.negative_role_assignments (user_id, role_id, org_id, reason)
VALUES (
    '30000000-0000-0000-0000-000000000011', -- Karl
    '20000000-0001-0000-0000-000000000003', -- manager role (Karl never had this)
    '10000000-0000-0000-0000-000000000001',
    'Preemptive block'
);

-- Karl still has no access (negative assignment on non-held role is harmless)
SELECT morbac.t('Karl (no role, preemptive negative assignment) reads documents [still no access]',
    morbac.is_allowed_nocache(
        '30000000-0000-0000-0000-000000000011'::uuid,
        '10000000-0000-0000-0000-000000000001'::uuid,
        'read', 'documents'
    ), FALSE);

-- Clean up Frank's extra employee assignment and negative assignment for later tests
DELETE FROM morbac.user_roles
WHERE user_id = '30000000-0000-0000-0000-000000000006'
  AND role_id = '20000000-0001-0000-0000-000000000004'
  AND org_id  = '10000000-0000-0000-0000-000000000001';

DELETE FROM morbac.negative_role_assignments
WHERE user_id = '30000000-0000-0000-0000-000000000006'
  AND role_id = '20000000-0001-0000-0000-000000000004';

-- ---------------------------------------------------------------------------
-- Section 4: Role cardinality constraints
-- ---------------------------------------------------------------------------
\echo ''
\echo '--- 4. Role cardinality constraints ---'

-- Set a cardinality constraint: compliance_officer role — min 1, max 2
INSERT INTO morbac.role_cardinality (role_id, min_users, max_users, description)
VALUES (
    '20000000-0001-0000-0000-000000000010', -- compliance_officer
    1, 2,
    'Compliance officer role: at least 1, at most 2'
);

-- Currently 0 users have compliance_officer — adding one should be fine (0 < max=2)
SELECT morbac.t_null('Adding first compliance_officer (0 users, max=2) — no violation',
    morbac.check_cardinality_violation(
        '20000000-0001-0000-0000-000000000010'::uuid,
        TRUE  -- adding
    ));

-- Assign two users as compliance officer
INSERT INTO morbac.user_roles (user_id, role_id, org_id) VALUES
    ('30000000-0000-0000-0000-000000000004', '20000000-0001-0000-0000-000000000010', '10000000-0000-0000-0000-000000000001'),
    ('30000000-0000-0000-0000-000000000005', '20000000-0001-0000-0000-000000000010', '10000000-0000-0000-0000-000000000001');

-- Now 2 users — at max. Trying to add a 3rd should violate
SELECT morbac.t_not_null('Adding 3rd compliance_officer (2 users, max=2) — violation returned',
    morbac.check_cardinality_violation(
        '20000000-0001-0000-0000-000000000010'::uuid,
        TRUE  -- adding
    ));

-- Removing one — 2 users, min=1 — removing leaves 1 which is ≥ min=1, should be fine
SELECT morbac.t_null('Removing from 2 compliance_officers (min=1) — no violation (still above min)',
    morbac.check_cardinality_violation(
        '20000000-0001-0000-0000-000000000010'::uuid,
        FALSE  -- removing
    ));

-- Remove one user
DELETE FROM morbac.user_roles
WHERE user_id = '30000000-0000-0000-0000-000000000005'
  AND role_id = '20000000-0001-0000-0000-000000000010';

-- 1 user remaining = min. Removing the last one would violate min=1
SELECT morbac.t_not_null('Removing last compliance_officer (1 user, min=1) — violation returned',
    morbac.check_cardinality_violation(
        '20000000-0001-0000-0000-000000000010'::uuid,
        FALSE  -- removing
    ));

-- Adding again after being at 1 — 1 user, max=2 — ok
SELECT morbac.t_null('Adding when at 1 compliance_officer (max=2) — no violation',
    morbac.check_cardinality_violation(
        '20000000-0001-0000-0000-000000000010'::uuid,
        TRUE  -- adding
    ));

-- Role with no cardinality constraint — no violation for any operation
SELECT morbac.t_null('Checking cardinality for employee role (no constraint) — no violation',
    morbac.check_cardinality_violation(
        '20000000-0001-0000-0000-000000000004'::uuid, -- employee
        TRUE
    ));

-- Clean up extra compliance_officer assignments
DELETE FROM morbac.user_roles
WHERE role_id = '20000000-0001-0000-0000-000000000010'
  AND user_id = '30000000-0000-0000-0000-000000000004';

-- ---------------------------------------------------------------------------
-- Section 4: Rule conflict detection
-- ---------------------------------------------------------------------------
\echo ''
\echo '--- 4. Rule conflict detection ---'

-- Insert a permission rule for employee on read/contracts (no existing conflict)
INSERT INTO morbac.rules (id, org_id, role_id, activity, view, context_id, modality)
VALUES (
    'f0000000-0000-0000-0000-000000000001',
    '10000000-0000-0000-0000-000000000001',
    '20000000-0001-0000-0000-000000000004', -- employee
    'read', 'contracts',
    (SELECT id FROM morbac.contexts WHERE name = 'always'),
    'permission'
);

-- No conflict yet — only a permission exists
SELECT morbac.t_eq('detect_rule_conflicts: permission alone — no conflicts',
    (SELECT COUNT(*) FROM morbac.detect_rule_conflicts(
        '10000000-0000-0000-0000-000000000001',
        '20000000-0001-0000-0000-000000000004',
        'read', 'contracts',
        (SELECT id FROM morbac.contexts WHERE name = 'always'),
        'permission'
    ))::bigint,
    0);

-- Insert a prohibition for the same tuple (conflicts with the permission)
INSERT INTO morbac.rules (id, org_id, role_id, activity, view, context_id, modality)
VALUES (
    'f0000000-0000-0000-0000-000000000002',
    '10000000-0000-0000-0000-000000000001',
    '20000000-0001-0000-0000-000000000004',
    'read', 'contracts',
    (SELECT id FROM morbac.contexts WHERE name = 'always'),
    'prohibition'
);

-- Prohibition conflicts with the existing permission
SELECT morbac.t_eq('detect_rule_conflicts: prohibition conflicts with existing permission',
    (SELECT COUNT(*) FROM morbac.detect_rule_conflicts(
        '10000000-0000-0000-0000-000000000001',
        '20000000-0001-0000-0000-000000000004',
        'read', 'contracts',
        (SELECT id FROM morbac.contexts WHERE name = 'always'),
        'prohibition'
    ))::bigint,
    1);

-- The conflicting rule is the permission
SELECT morbac.t('detect_rule_conflicts: conflicting rule is the permission',
    EXISTS(
        SELECT 1 FROM morbac.detect_rule_conflicts(
            '10000000-0000-0000-0000-000000000001',
            '20000000-0001-0000-0000-000000000004',
            'read', 'contracts',
            (SELECT id FROM morbac.contexts WHERE name = 'always'),
            'prohibition'
        )
        WHERE conflicting_modality = 'permission'
    ), TRUE);

-- Insert an obligation for the same tuple — conflicts with the prohibition
INSERT INTO morbac.rules (id, org_id, role_id, activity, view, context_id, modality)
VALUES (
    'f0000000-0000-0000-0000-000000000003',
    '10000000-0000-0000-0000-000000000001',
    '20000000-0001-0000-0000-000000000004',
    'read', 'contracts',
    (SELECT id FROM morbac.contexts WHERE name = 'always'),
    'obligation'
);

-- Obligation conflicts with existing prohibition
SELECT morbac.t_eq('detect_rule_conflicts: obligation conflicts with existing prohibition',
    (SELECT COUNT(*) FROM morbac.detect_rule_conflicts(
        '10000000-0000-0000-0000-000000000001',
        '20000000-0001-0000-0000-000000000004',
        'read', 'contracts',
        (SELECT id FROM morbac.contexts WHERE name = 'always'),
        'obligation'
    ))::bigint,
    1);

-- Insert a recommendation — conflicts with both obligation and prohibition
INSERT INTO morbac.rules (id, org_id, role_id, activity, view, context_id, modality)
VALUES (
    'f0000000-0000-0000-0000-000000000004',
    '10000000-0000-0000-0000-000000000001',
    '20000000-0001-0000-0000-000000000004',
    'read', 'contracts',
    (SELECT id FROM morbac.contexts WHERE name = 'always'),
    'recommendation'
);

-- Recommendation conflicts with both prohibition and obligation
SELECT morbac.t_eq('detect_rule_conflicts: recommendation conflicts with prohibition and obligation',
    (SELECT COUNT(*) FROM morbac.detect_rule_conflicts(
        '10000000-0000-0000-0000-000000000001',
        '20000000-0001-0000-0000-000000000004',
        'read', 'contracts',
        (SELECT id FROM morbac.contexts WHERE name = 'always'),
        'recommendation'
    ))::bigint,
    2);

-- No conflict between permission and recommendation (they coexist meaningfully)
SELECT morbac.t_eq('detect_rule_conflicts: permission vs recommendation — no conflict',
    (SELECT COUNT(*) FROM morbac.detect_rule_conflicts(
        '10000000-0000-0000-0000-000000000001',
        '20000000-0001-0000-0000-000000000004',
        'read', 'contracts',
        (SELECT id FROM morbac.contexts WHERE name = 'always'),
        'permission',
        'f0000000-0000-0000-0000-000000000001'  -- exclude self
    )
    WHERE conflicting_modality = 'recommendation')::bigint,
    0);

-- Clean up
DELETE FROM morbac.rules
WHERE id IN (
    'f0000000-0000-0000-0000-000000000001',
    'f0000000-0000-0000-0000-000000000002',
    'f0000000-0000-0000-0000-000000000003',
    'f0000000-0000-0000-0000-000000000004'
);

\echo ''
\echo '=== Constraint Tests Completed ==='
