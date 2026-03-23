-- =============================================================================
-- Authorization Decision Tests
-- =============================================================================
-- Tests the core is_allowed() function across a variety of scenarios.
-- No activity or view hierarchy is active yet (added in 02_hierarchies.sql).
--
-- Users and their roles at GlobalTech HQ:
--   Alice   — ceo           (permission: inherits all via hierarchy)
--   Bob     — director      (inherits manager -> employee -> intern)
--   Carol   — manager       (inherits employee -> intern)
--   Dave    — employee      (inherits intern)
--   Eve     — intern
--   Frank   — contractor    (has prohibition on financial/hr data)
--   Grace   — hr_manager
--   Heidi   — auditor
--   Ivan    — accountant
--   Judy    — engineer@Engineering + sales_rep@Sales (multi-org)
--   Karl    — no role
--   Leo     — employee
--
-- Prerequisites: 00_setup.sql
-- =============================================================================

\echo ''
\echo '================================================================'
\echo '01 — CORE AUTHORIZATION DECISIONS'
\echo '================================================================'

-- ---------------------------------------------------------------------------
-- Section 1: Basic permission grants
-- ---------------------------------------------------------------------------
\echo ''
\echo '--- 1. Basic permission grants ---'

-- Dave (employee) can read documents — has explicit permission
SELECT morbac.t('Dave (employee) reads documents',
    morbac.is_allowed_nocache(
        '30000000-0000-0000-0000-000000000004'::uuid,
        '10000000-0000-0000-0000-000000000001'::uuid,
        'read', 'documents'
    ), TRUE);

-- Dave (employee) can write documents — context is business_hours (evaluates TRUE)
SELECT morbac.t('Dave (employee) writes documents [business_hours context=true]',
    morbac.is_allowed_nocache(
        '30000000-0000-0000-0000-000000000004'::uuid,
        '10000000-0000-0000-0000-000000000001'::uuid,
        'write', 'documents'
    ), TRUE);

-- Dave (employee) can read reports
SELECT morbac.t('Dave (employee) reads reports',
    morbac.is_allowed_nocache(
        '30000000-0000-0000-0000-000000000004'::uuid,
        '10000000-0000-0000-0000-000000000001'::uuid,
        'read', 'reports'
    ), TRUE);

-- Eve (intern) can read public data only
SELECT morbac.t('Eve (intern) reads public_data',
    morbac.is_allowed_nocache(
        '30000000-0000-0000-0000-000000000005'::uuid,
        '10000000-0000-0000-0000-000000000001'::uuid,
        'read', 'public_data'
    ), TRUE);

-- Grace (hr_manager) can write hr_data
SELECT morbac.t('Grace (hr_manager) writes hr_data',
    morbac.is_allowed_nocache(
        '30000000-0000-0000-0000-000000000007'::uuid,
        '10000000-0000-0000-0000-000000000001'::uuid,
        'write', 'hr_data'
    ), TRUE);

-- Heidi (auditor) can read financial_data
SELECT morbac.t('Heidi (auditor) reads financial_data',
    morbac.is_allowed_nocache(
        '30000000-0000-0000-0000-000000000008'::uuid,
        '10000000-0000-0000-0000-000000000001'::uuid,
        'read', 'financial_data'
    ), TRUE);

-- Ivan (accountant) can write financial_data
SELECT morbac.t('Ivan (accountant) writes financial_data',
    morbac.is_allowed_nocache(
        '30000000-0000-0000-0000-000000000009'::uuid,
        '10000000-0000-0000-0000-000000000001'::uuid,
        'write', 'financial_data'
    ), TRUE);

-- ---------------------------------------------------------------------------
-- Section 2: Default deny — no rule exists for the combination
-- ---------------------------------------------------------------------------
\echo ''
\echo '--- 2. Default deny (no permission rule) ---'

-- Dave (employee) cannot delete documents — no delete permission for employee
SELECT morbac.t('Dave (employee) deletes documents [no permission]',
    morbac.is_allowed_nocache(
        '30000000-0000-0000-0000-000000000004'::uuid,
        '10000000-0000-0000-0000-000000000001'::uuid,
        'delete', 'documents'
    ), FALSE);

-- Eve (intern) cannot read documents — intern only has public_data permission
SELECT morbac.t('Eve (intern) reads documents [intern has no docs permission]',
    morbac.is_allowed_nocache(
        '30000000-0000-0000-0000-000000000005'::uuid,
        '10000000-0000-0000-0000-000000000001'::uuid,
        'read', 'documents'
    ), FALSE);

-- Dave (employee) cannot read financial_data — no rule for employee -> financial_data
SELECT morbac.t('Dave (employee) reads financial_data [no permission before view hierarchy]',
    morbac.is_allowed_nocache(
        '30000000-0000-0000-0000-000000000004'::uuid,
        '10000000-0000-0000-0000-000000000001'::uuid,
        'read', 'financial_data'
    ), FALSE);

-- Grace (hr_manager) cannot read audit_logs — no rule for hr_manager -> audit_logs
SELECT morbac.t('Grace (hr_manager) reads audit_logs [no permission]',
    morbac.is_allowed_nocache(
        '30000000-0000-0000-0000-000000000007'::uuid,
        '10000000-0000-0000-0000-000000000001'::uuid,
        'read', 'audit_logs'
    ), FALSE);

-- Dave (employee) cannot approve documents — no approve permission for employee
SELECT morbac.t('Dave (employee) approves documents [no permission]',
    morbac.is_allowed_nocache(
        '30000000-0000-0000-0000-000000000004'::uuid,
        '10000000-0000-0000-0000-000000000001'::uuid,
        'approve', 'documents'
    ), FALSE);

-- ---------------------------------------------------------------------------
-- Section 3: Default deny — user has no role at all
-- ---------------------------------------------------------------------------
\echo ''
\echo '--- 3. Default deny (user has no role) ---'

-- Karl has no role anywhere — all actions denied
SELECT morbac.t('Karl (no role) reads documents',
    morbac.is_allowed_nocache(
        '30000000-0000-0000-0000-000000000011'::uuid,
        '10000000-0000-0000-0000-000000000001'::uuid,
        'read', 'documents'
    ), FALSE);

-- Completely unknown user UUID — EXPECT FALSE
SELECT morbac.t('Unknown user reads documents',
    morbac.is_allowed_nocache(
        'ffffffff-ffff-ffff-ffff-ffffffffffff'::uuid,
        '10000000-0000-0000-0000-000000000001'::uuid,
        'read', 'documents'
    ), FALSE);

-- ---------------------------------------------------------------------------
-- Section 4: Prohibition overrides permission (prohibition precedence)
-- ---------------------------------------------------------------------------
\echo ''
\echo '--- 4. Prohibition overrides permission ---'

-- Frank (contractor) reads documents — permission granted, no prohibition
SELECT morbac.t('Frank (contractor) reads documents [has permission]',
    morbac.is_allowed_nocache(
        '30000000-0000-0000-0000-000000000006'::uuid,
        '10000000-0000-0000-0000-000000000001'::uuid,
        'read', 'documents'
    ), TRUE);

-- Frank (contractor) reads financial_data — PROHIBITED
SELECT morbac.t('Frank (contractor) reads financial_data [prohibited]',
    morbac.is_allowed_nocache(
        '30000000-0000-0000-0000-000000000006'::uuid,
        '10000000-0000-0000-0000-000000000001'::uuid,
        'read', 'financial_data'
    ), FALSE);

-- Frank (contractor) reads hr_data — prohibited
SELECT morbac.t('Frank (contractor) reads hr_data [prohibited]',
    morbac.is_allowed_nocache(
        '30000000-0000-0000-0000-000000000006'::uuid,
        '10000000-0000-0000-0000-000000000001'::uuid,
        'read', 'hr_data'
    ), FALSE);

-- Add a permission for contractor on financial_data, then confirm prohibition still wins
INSERT INTO morbac.rules (org_id, role_id, activity, view, context_id, modality)
VALUES (
    '10000000-0000-0000-0000-000000000001',
    '20000000-0001-0000-0000-000000000009', -- contractor
    'read', 'financial_data',
    (SELECT id FROM morbac.contexts WHERE name = 'always'),
    'permission'
);

-- Prohibition must always win over permission
SELECT morbac.t('Frank (contractor) reads financial_data after adding permission [prohibition wins]',
    morbac.is_allowed_nocache(
        '30000000-0000-0000-0000-000000000006'::uuid,
        '10000000-0000-0000-0000-000000000001'::uuid,
        'read', 'financial_data'
    ), FALSE);

-- Clean up the extra rule
DELETE FROM morbac.rules
WHERE org_id = '10000000-0000-0000-0000-000000000001'
  AND role_id = '20000000-0001-0000-0000-000000000009'
  AND activity = 'read' AND view = 'financial_data' AND modality = 'permission';

-- ---------------------------------------------------------------------------
-- Section 5: Context filtering — rule only applies when context is TRUE
-- ---------------------------------------------------------------------------
\echo ''
\echo '--- 5. Context filtering ---'

-- Add a rule that only applies after_hours (context evaluates FALSE)
INSERT INTO morbac.rules (org_id, role_id, activity, view, context_id, modality)
VALUES (
    '10000000-0000-0000-0000-000000000001',
    '20000000-0001-0000-0000-000000000004', -- employee
    'export', 'documents',
    (SELECT id FROM morbac.contexts WHERE name = 'after_hours'),
    'permission'
);

-- Context evaluates FALSE so the rule does not apply
SELECT morbac.t('Dave (employee) exports documents [after_hours context=false]',
    morbac.is_allowed_nocache(
        '30000000-0000-0000-0000-000000000004'::uuid,
        '10000000-0000-0000-0000-000000000001'::uuid,
        'export', 'documents'
    ), FALSE);

-- Replace with business_hours context (evaluates TRUE)
UPDATE morbac.rules
SET context_id = (SELECT id FROM morbac.contexts WHERE name = 'business_hours')
WHERE org_id = '10000000-0000-0000-0000-000000000001'
  AND role_id = '20000000-0001-0000-0000-000000000004'
  AND activity = 'export' AND view = 'documents';

-- Context evaluates TRUE
SELECT morbac.t('Dave (employee) exports documents [business_hours context=true]',
    morbac.is_allowed_nocache(
        '30000000-0000-0000-0000-000000000004'::uuid,
        '10000000-0000-0000-0000-000000000001'::uuid,
        'export', 'documents'
    ), TRUE);

-- Clean up the extra rule
DELETE FROM morbac.rules
WHERE org_id = '10000000-0000-0000-0000-000000000001'
  AND role_id = '20000000-0001-0000-0000-000000000004'
  AND activity = 'export' AND view = 'documents';

-- ---------------------------------------------------------------------------
-- Section 6: Wrong organization — user has no role in the target org
-- ---------------------------------------------------------------------------
\echo ''
\echo '--- 6. Wrong organization ---'

-- Dave (employee at GlobalTech) has no role in Engineering Dept
SELECT morbac.t('Dave (GlobalTech employee) reads Engineering documents [no role in Engineering]',
    morbac.is_allowed_nocache(
        '30000000-0000-0000-0000-000000000004'::uuid,
        '10000000-0000-0000-0000-000000000002'::uuid,
        'read', 'documents'
    ), FALSE);

-- Judy (engineer at Engineering) has no role in GlobalTech
SELECT morbac.t('Judy (Engineering engineer) reads GlobalTech financial_data [no role in GlobalTech]',
    morbac.is_allowed_nocache(
        '30000000-0000-0000-0000-000000000010'::uuid,
        '10000000-0000-0000-0000-000000000001'::uuid,
        'read', 'financial_data'
    ), FALSE);

-- ---------------------------------------------------------------------------
-- Section 7: Multi-organization user — access scoped to each org independently
-- ---------------------------------------------------------------------------
\echo ''
\echo '--- 7. Multi-org user (Judy) ---'

-- Judy is engineer at Engineering — can read documents there
SELECT morbac.t('Judy (engineer) reads Engineering documents',
    morbac.is_allowed_nocache(
        '30000000-0000-0000-0000-000000000010'::uuid,
        '10000000-0000-0000-0000-000000000002'::uuid,
        'read', 'documents'
    ), TRUE);

-- Judy is sales_rep at Sales — can write contracts there
SELECT morbac.t('Judy (sales_rep) writes Sales contracts',
    morbac.is_allowed_nocache(
        '30000000-0000-0000-0000-000000000010'::uuid,
        '10000000-0000-0000-0000-000000000003'::uuid,
        'write', 'contracts'
    ), TRUE);

-- Judy's engineering permissions do NOT carry to Sales
SELECT morbac.t('Judy writes documents at Sales [engineer perms dont carry over]',
    morbac.is_allowed_nocache(
        '30000000-0000-0000-0000-000000000010'::uuid,
        '10000000-0000-0000-0000-000000000003'::uuid,
        'write', 'documents'
    ), FALSE);

-- ---------------------------------------------------------------------------
-- Section 8: Role hierarchy inheritance
-- ---------------------------------------------------------------------------
\echo ''
\echo '--- 8. Role hierarchy inheritance ---'

-- Carol (manager) inherits employee permissions — can read documents (employee perm)
SELECT morbac.t('Carol (manager, inherits employee) reads documents',
    morbac.is_allowed_nocache(
        '30000000-0000-0000-0000-000000000003'::uuid,
        '10000000-0000-0000-0000-000000000001'::uuid,
        'read', 'documents'
    ), TRUE);

-- Carol (manager) has own permission — can approve documents
SELECT morbac.t('Carol (manager) approves documents [own permission]',
    morbac.is_allowed_nocache(
        '30000000-0000-0000-0000-000000000003'::uuid,
        '10000000-0000-0000-0000-000000000001'::uuid,
        'approve', 'documents'
    ), TRUE);

-- Bob (director) inherits manager -> employee chain — can read documents
SELECT morbac.t('Bob (director, inherits manager+employee) reads documents',
    morbac.is_allowed_nocache(
        '30000000-0000-0000-0000-000000000002'::uuid,
        '10000000-0000-0000-0000-000000000001'::uuid,
        'read', 'documents'
    ), TRUE);

-- Bob (director) inherits manager — can approve documents
SELECT morbac.t('Bob (director, inherits manager) approves documents',
    morbac.is_allowed_nocache(
        '30000000-0000-0000-0000-000000000002'::uuid,
        '10000000-0000-0000-0000-000000000001'::uuid,
        'approve', 'documents'
    ), TRUE);

-- Alice (CEO) inherits the entire hierarchy — can do everything below
SELECT morbac.t('Alice (CEO, inherits all) reads documents',
    morbac.is_allowed_nocache(
        '30000000-0000-0000-0000-000000000001'::uuid,
        '10000000-0000-0000-0000-000000000001'::uuid,
        'read', 'documents'
    ), TRUE);

SELECT morbac.t('Alice (CEO, inherits all) approves documents',
    morbac.is_allowed_nocache(
        '30000000-0000-0000-0000-000000000001'::uuid,
        '10000000-0000-0000-0000-000000000001'::uuid,
        'approve', 'documents'
    ), TRUE);

SELECT morbac.t('Alice (CEO, inherits all) deletes documents',
    morbac.is_allowed_nocache(
        '30000000-0000-0000-0000-000000000001'::uuid,
        '10000000-0000-0000-0000-000000000001'::uuid,
        'delete', 'documents'
    ), TRUE);

-- Eve (intern) cannot approve — intern has no approve permission
SELECT morbac.t('Eve (intern) approves documents [intern has no approve permission]',
    morbac.is_allowed_nocache(
        '30000000-0000-0000-0000-000000000005'::uuid,
        '10000000-0000-0000-0000-000000000001'::uuid,
        'approve', 'documents'
    ), FALSE);

-- ---------------------------------------------------------------------------
-- Section 9: is_allowed_nocache produces same result as is_allowed
-- ---------------------------------------------------------------------------
\echo ''
\echo '--- 9. is_allowed vs is_allowed_nocache consistency ---'

SELECT morbac.t('Dave reads documents: cached = nocache',
    morbac.is_allowed(
        '30000000-0000-0000-0000-000000000004'::uuid,
        '10000000-0000-0000-0000-000000000001'::uuid,
        'read', 'documents'
    ) IS NOT DISTINCT FROM morbac.is_allowed_nocache(
        '30000000-0000-0000-0000-000000000004'::uuid,
        '10000000-0000-0000-0000-000000000001'::uuid,
        'read', 'documents'
    ), TRUE);

SELECT morbac.t('Dave deletes documents: cached = nocache',
    morbac.is_allowed(
        '30000000-0000-0000-0000-000000000004'::uuid,
        '10000000-0000-0000-0000-000000000001'::uuid,
        'delete', 'documents'
    ) IS NOT DISTINCT FROM morbac.is_allowed_nocache(
        '30000000-0000-0000-0000-000000000004'::uuid,
        '10000000-0000-0000-0000-000000000001'::uuid,
        'delete', 'documents'
    ), TRUE);

SELECT morbac.t('Frank reads financial_data (prohibited): cached = nocache',
    morbac.is_allowed(
        '30000000-0000-0000-0000-000000000006'::uuid,
        '10000000-0000-0000-0000-000000000001'::uuid,
        'read', 'financial_data'
    ) IS NOT DISTINCT FROM morbac.is_allowed_nocache(
        '30000000-0000-0000-0000-000000000006'::uuid,
        '10000000-0000-0000-0000-000000000001'::uuid,
        'read', 'financial_data'
    ), TRUE);

-- ---------------------------------------------------------------------------
-- Section N: Priority-based conflict resolution
-- ---------------------------------------------------------------------------
\echo ''
\echo '--- Priority: permission overrides prohibition when strictly higher ---'

-- Dave (employee) already has permission to read documents.
-- Add a prohibition with priority=5 and a permission with priority=10 on 'read contracts'.
INSERT INTO morbac.rules (id, org_id, role_id, activity, view, context_id, modality, priority)
VALUES (
    'e0000000-0000-0000-0000-000000000001',
    '10000000-0000-0000-0000-000000000001',
    '20000000-0001-0000-0000-000000000004', -- employee
    'read', 'contracts',
    (SELECT id FROM morbac.contexts WHERE name = 'always'),
    'prohibition', 5
);

INSERT INTO morbac.rules (id, org_id, role_id, activity, view, context_id, modality, priority)
VALUES (
    'e0000000-0000-0000-0000-000000000002',
    '10000000-0000-0000-0000-000000000001',
    '20000000-0001-0000-0000-000000000004', -- employee
    'read', 'contracts',
    (SELECT id FROM morbac.contexts WHERE name = 'always'),
    'permission', 10
);

-- Permission (priority=10) beats prohibition (priority=5) -> ALLOW
SELECT morbac.t('Dave reads contracts: permission priority=10 overrides prohibition priority=5 [allowed]',
    morbac.is_allowed_nocache(
        '30000000-0000-0000-0000-000000000004'::uuid,
        '10000000-0000-0000-0000-000000000001'::uuid,
        'read', 'contracts'
    ), TRUE);

-- Flip priorities: prohibition=10, permission=5 -> prohibition wins
UPDATE morbac.rules SET priority = 10 WHERE id = 'e0000000-0000-0000-0000-000000000001';
UPDATE morbac.rules SET priority = 5  WHERE id = 'e0000000-0000-0000-0000-000000000002';

SELECT morbac.t('Dave reads contracts: prohibition priority=10 beats permission priority=5 [denied]',
    morbac.is_allowed_nocache(
        '30000000-0000-0000-0000-000000000004'::uuid,
        '10000000-0000-0000-0000-000000000001'::uuid,
        'read', 'contracts'
    ), FALSE);

-- Equal priorities: prohibition wins (modality tiebreaker)
UPDATE morbac.rules SET priority = 5 WHERE id = 'e0000000-0000-0000-0000-000000000001';

SELECT morbac.t('Dave reads contracts: equal priority — prohibition wins by modality precedence [denied]',
    morbac.is_allowed_nocache(
        '30000000-0000-0000-0000-000000000004'::uuid,
        '10000000-0000-0000-0000-000000000001'::uuid,
        'read', 'contracts'
    ), FALSE);

-- No priority on either (NULL = 0): prohibition still wins
UPDATE morbac.rules SET priority = NULL WHERE id IN (
    'e0000000-0000-0000-0000-000000000001',
    'e0000000-0000-0000-0000-000000000002'
);

SELECT morbac.t('Dave reads contracts: no priority set — prohibition wins by default [denied]',
    morbac.is_allowed_nocache(
        '30000000-0000-0000-0000-000000000004'::uuid,
        '10000000-0000-0000-0000-000000000001'::uuid,
        'read', 'contracts'
    ), FALSE);

-- Clean up
DELETE FROM morbac.rules WHERE id IN (
    'e0000000-0000-0000-0000-000000000001',
    'e0000000-0000-0000-0000-000000000002'
);

\echo ''
\echo '=== Authorization Decision Tests Completed ==='
