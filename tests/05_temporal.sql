-- =============================================================================
-- Temporal Constraint Tests
-- =============================================================================
-- Tests time-bounded rules using valid_from and valid_until on the rules table.
--
-- Cases:
--   1. is_rule_valid() helper function tested directly
--   2. is_active flag set by trigger on insert/update
--   3. Expired rule (valid_until in the past) -> denied
--   4. Future rule (valid_from in the future) -> denied
--   5. Active time window (valid_from past, valid_until future) -> allowed
--   6. Multiple rules for same combination — only active ones count
--   7. Expired prohibition: no longer blocks access after it expires
--   8. Temporal rules interact correctly with role hierarchy
--
-- Note: Direct rule inserts are used (bypassing Policy DSL) to control timestamps.
-- Uses a dedicated view 'temp_view' for isolation so existing rules aren't disturbed.
--
-- Prerequisites: 00_setup.sql -> 04_constraints.sql
-- =============================================================================

\echo ''
\echo '================================================================'
\echo '05 — TEMPORAL CONSTRAINTS'
\echo '================================================================'

-- ---------------------------------------------------------------------------
-- Setup: dedicated view for temporal tests
-- ---------------------------------------------------------------------------
INSERT INTO morbac.views (name, description) VALUES
    ('temp_view', 'Scratch view for temporal tests');

-- ---------------------------------------------------------------------------
-- Section 1: is_rule_valid() helper function
-- ---------------------------------------------------------------------------
\echo ''
\echo '--- 1. is_rule_valid() helper ---'

-- No bounds: always valid
SELECT morbac.t('is_rule_valid(NULL, NULL) — always valid',
    morbac.is_rule_valid(NULL::timestamptz, NULL::timestamptz), TRUE);

-- Past valid_from, no valid_until: currently active
SELECT morbac.t('is_rule_valid(past, NULL) — started in past, no end',
    morbac.is_rule_valid('2000-01-01'::timestamptz, NULL), TRUE);

-- Future valid_from: not yet active
SELECT morbac.t('is_rule_valid(future, NULL) — not yet started',
    morbac.is_rule_valid('2099-01-01'::timestamptz, NULL), FALSE);

-- Past valid_until: expired
SELECT morbac.t('is_rule_valid(NULL, past) — already expired',
    morbac.is_rule_valid(NULL, '2000-01-01'::timestamptz), FALSE);

-- Future valid_until, no valid_from: currently active
SELECT morbac.t('is_rule_valid(NULL, future) — no start, future end',
    morbac.is_rule_valid(NULL, '2099-01-01'::timestamptz), TRUE);

-- Active window: past start, future end
SELECT morbac.t('is_rule_valid(past, future) — within active window',
    morbac.is_rule_valid('2000-01-01'::timestamptz, '2099-01-01'::timestamptz), TRUE);

-- Fully past window (both start and end in the past)
SELECT morbac.t('is_rule_valid(past_start, past_end) — entirely expired',
    morbac.is_rule_valid('2000-01-01'::timestamptz, '2001-01-01'::timestamptz), FALSE);

-- Fully future window (both start and end in the future)
SELECT morbac.t('is_rule_valid(future_start, future_end) — entirely in the future',
    morbac.is_rule_valid('2090-01-01'::timestamptz, '2099-01-01'::timestamptz), FALSE);

-- ---------------------------------------------------------------------------
-- Section 2: is_active flag set by trigger on insert
-- ---------------------------------------------------------------------------
\echo ''
\echo '--- 2. is_active trigger on insert ---'

-- Insert a currently active rule
INSERT INTO morbac.rules (org_id, role_id, activity, view, context_id, modality, valid_from, valid_until)
VALUES (
    '10000000-0000-0000-0000-000000000001',
    '20000000-0001-0000-0000-000000000004', -- employee
    'audit', 'temp_view',
    (SELECT id FROM morbac.contexts WHERE name = 'always'),
    'permission',
    now() - interval '1 day',
    now() + interval '1 day'
);

-- is_active should be TRUE for the active rule
SELECT morbac.t('is_active = TRUE for rule with active time window',
    (SELECT is_active FROM morbac.rules WHERE activity = 'audit' AND view = 'temp_view'),
    TRUE);

-- Update to expired window, trigger should recalculate is_active
UPDATE morbac.rules
SET valid_until = now() - interval '1 second'
WHERE activity = 'audit' AND view = 'temp_view';

-- is_active should be FALSE after expiry update
SELECT morbac.t('is_active = FALSE after valid_until set to past',
    (SELECT is_active FROM morbac.rules WHERE activity = 'audit' AND view = 'temp_view'),
    FALSE);

-- Clean up
DELETE FROM morbac.rules WHERE activity = 'audit' AND view = 'temp_view';

-- ---------------------------------------------------------------------------
-- Section 3: Expired rule — valid_until in the past
-- ---------------------------------------------------------------------------
\echo ''
\echo '--- 3. Expired rule (valid_until in the past) ---'

INSERT INTO morbac.rules (org_id, role_id, activity, view, context_id, modality, valid_until)
VALUES (
    '10000000-0000-0000-0000-000000000001',
    '20000000-0001-0000-0000-000000000004', -- employee
    'export', 'temp_view',
    (SELECT id FROM morbac.contexts WHERE name = 'always'),
    'permission',
    '2020-01-01 00:00:00+00'  -- expired years ago
);

-- Rule expired, no valid permission
SELECT morbac.t('Dave (employee) exports temp_view via expired rule [denied]',
    morbac.is_allowed_nocache(
        '30000000-0000-0000-0000-000000000004'::uuid,
        '10000000-0000-0000-0000-000000000001'::uuid,
        'export', 'temp_view'
    ), FALSE);

-- ---------------------------------------------------------------------------
-- Section 4: Future rule — valid_from in the future
-- ---------------------------------------------------------------------------
\echo ''
\echo '--- 4. Future rule (valid_from in the future) ---'

INSERT INTO morbac.rules (org_id, role_id, activity, view, context_id, modality, valid_from)
VALUES (
    '10000000-0000-0000-0000-000000000001',
    '20000000-0001-0000-0000-000000000004', -- employee
    'manage', 'temp_view',
    (SELECT id FROM morbac.contexts WHERE name = 'always'),
    'permission',
    '2099-01-01 00:00:00+00'  -- won't start for decades
);

-- Rule not yet active
SELECT morbac.t('Dave (employee) manages temp_view via future rule [not yet active]',
    morbac.is_allowed_nocache(
        '30000000-0000-0000-0000-000000000004'::uuid,
        '10000000-0000-0000-0000-000000000001'::uuid,
        'manage', 'temp_view'
    ), FALSE);

-- ---------------------------------------------------------------------------
-- Section 5: Active time window (valid_from past, valid_until future)
-- ---------------------------------------------------------------------------
\echo ''
\echo '--- 5. Active time window ---'

INSERT INTO morbac.rules (org_id, role_id, activity, view, context_id, modality, valid_from, valid_until)
VALUES (
    '10000000-0000-0000-0000-000000000001',
    '20000000-0001-0000-0000-000000000004', -- employee
    'read', 'temp_view',
    (SELECT id FROM morbac.contexts WHERE name = 'always'),
    'permission',
    '2020-01-01 00:00:00+00',
    '2099-12-31 23:59:59+00'
);

-- Rule is within its validity window
SELECT morbac.t('Dave (employee) reads temp_view via active window rule',
    morbac.is_allowed_nocache(
        '30000000-0000-0000-0000-000000000004'::uuid,
        '10000000-0000-0000-0000-000000000001'::uuid,
        'read', 'temp_view'
    ), TRUE);

-- ---------------------------------------------------------------------------
-- Section 6: Multiple rules for same combination, only active ones count
-- ---------------------------------------------------------------------------
\echo ''
\echo '--- 6. Multiple rules for same combination, only active ones count ---'

-- At this point, employee has expired export rule (section 3) and active read rule (section 5).
-- Since export->read in activity hierarchy, the active read rule grants export access.
SELECT morbac.t('Dave exports temp_view (expired export + active read via export->read hierarchy)',
    morbac.is_allowed_nocache(
        '30000000-0000-0000-0000-000000000004'::uuid,
        '10000000-0000-0000-0000-000000000001'::uuid,
        'export', 'temp_view'
    ), TRUE);

-- Activate the expired export rule (unique constraint prevents a second rule with same modality)
UPDATE morbac.rules
SET valid_from = now() - interval '1 hour',
    valid_until = now() + interval '1 hour'
WHERE org_id = '10000000-0000-0000-0000-000000000001'
  AND role_id = '20000000-0001-0000-0000-000000000004'
  AND activity = 'export' AND view = 'temp_view' AND modality = 'permission';

-- Now export rule is active directly (not just via read hierarchy)
SELECT morbac.t('Dave exports temp_view (export rule now active)',
    morbac.is_allowed_nocache(
        '30000000-0000-0000-0000-000000000004'::uuid,
        '10000000-0000-0000-0000-000000000001'::uuid,
        'export', 'temp_view'
    ), TRUE);

-- ---------------------------------------------------------------------------
-- Section 7: Temporal prohibition — expired prohibition no longer blocks
-- ---------------------------------------------------------------------------
\echo ''
\echo '--- 7. Expired prohibition no longer blocks ---'

-- Add an active permission for intern -> read temp_view
INSERT INTO morbac.rules (org_id, role_id, activity, view, context_id, modality)
VALUES (
    '10000000-0000-0000-0000-000000000001',
    '20000000-0001-0000-0000-000000000005', -- intern
    'read', 'temp_view',
    (SELECT id FROM morbac.contexts WHERE name = 'always'),
    'permission'
);

-- Add an EXPIRED prohibition for intern -> read temp_view
INSERT INTO morbac.rules (org_id, role_id, activity, view, context_id, modality, valid_until)
VALUES (
    '10000000-0000-0000-0000-000000000001',
    '20000000-0001-0000-0000-000000000005', -- intern
    'read', 'temp_view',
    (SELECT id FROM morbac.contexts WHERE name = 'always'),
    'prohibition',
    '2020-01-01 00:00:00+00'  -- prohibition expired years ago
);

-- Prohibition expired, permission stands
SELECT morbac.t('Eve (intern) reads temp_view [active permission, expired prohibition]',
    morbac.is_allowed_nocache(
        '30000000-0000-0000-0000-000000000005'::uuid,
        '10000000-0000-0000-0000-000000000001'::uuid,
        'read', 'temp_view'
    ), TRUE);

-- Now replace the prohibition with an active one
UPDATE morbac.rules
SET valid_until = now() + interval '1 day'
WHERE org_id = '10000000-0000-0000-0000-000000000001'
  AND role_id = '20000000-0001-0000-0000-000000000005'
  AND activity = 'read' AND view = 'temp_view' AND modality = 'prohibition';

-- Active prohibition now blocks
SELECT morbac.t('Eve (intern) reads temp_view [active prohibition blocks]',
    morbac.is_allowed_nocache(
        '30000000-0000-0000-0000-000000000005'::uuid,
        '10000000-0000-0000-0000-000000000001'::uuid,
        'read', 'temp_view'
    ), FALSE);

-- ---------------------------------------------------------------------------
-- Section 8: Temporal rule with role hierarchy
-- ---------------------------------------------------------------------------
\echo ''
\echo '--- 8. Temporal rule with role hierarchy ---'

-- Expire the intern read temp_view prohibition (activated in section 7) so it does not
-- block Carol (manager) and Alice (CEO) who inherit from intern via role hierarchy.
UPDATE morbac.rules
SET valid_until = now() - interval '1 second'
WHERE org_id = '10000000-0000-0000-0000-000000000001'
  AND role_id = '20000000-0001-0000-0000-000000000005'
  AND activity = 'read' AND view = 'temp_view' AND modality = 'prohibition';

-- Add an active 'approve temp_view' permission for manager.
-- 'approve' is NOT in the activity hierarchy (manage->delete->write->read, export->read),
-- so employee's 'read temp_view' rule does NOT cover 'approve temp_view'.
-- This ensures the temporal test cleanly verifies expiry without hierarchy interference.
INSERT INTO morbac.rules (org_id, role_id, activity, view, context_id, modality, valid_from, valid_until)
VALUES (
    '10000000-0000-0000-0000-000000000001',
    '20000000-0001-0000-0000-000000000003', -- manager
    'approve', 'temp_view',
    (SELECT id FROM morbac.contexts WHERE name = 'always'),
    'permission',
    now() - interval '1 hour',
    now() + interval '1 hour'
);

-- Carol (manager) can approve temp_view directly
SELECT morbac.t('Carol (manager) approves temp_view [temporal rule, active]',
    morbac.is_allowed_nocache(
        '30000000-0000-0000-0000-000000000003'::uuid,
        '10000000-0000-0000-0000-000000000001'::uuid,
        'approve', 'temp_view'
    ), TRUE);

-- Alice (CEO) inherits from manager — should also get the temporal permission
SELECT morbac.t('Alice (CEO, inherits manager) approves temp_view [temporal rule, active]',
    morbac.is_allowed_nocache(
        '30000000-0000-0000-0000-000000000001'::uuid,
        '10000000-0000-0000-0000-000000000001'::uuid,
        'approve', 'temp_view'
    ), TRUE);

-- Expire the manager approve rule
UPDATE morbac.rules
SET valid_until = now() - interval '1 second'
WHERE org_id = '10000000-0000-0000-0000-000000000001'
  AND role_id = '20000000-0001-0000-0000-000000000003'
  AND activity = 'approve' AND view = 'temp_view';

-- Rule expired for both manager and CEO
SELECT morbac.t('Carol (manager) approves temp_view after rule expiry [denied]',
    morbac.is_allowed_nocache(
        '30000000-0000-0000-0000-000000000003'::uuid,
        '10000000-0000-0000-0000-000000000001'::uuid,
        'approve', 'temp_view'
    ), FALSE);

SELECT morbac.t('Alice (CEO, inherits manager) approves temp_view after rule expiry [denied]',
    morbac.is_allowed_nocache(
        '30000000-0000-0000-0000-000000000001'::uuid,
        '10000000-0000-0000-0000-000000000001'::uuid,
        'approve', 'temp_view'
    ), FALSE);

\echo ''
\echo '=== Temporal Constraint Tests Completed ==='
