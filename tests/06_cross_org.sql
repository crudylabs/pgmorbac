-- =============================================================================
-- Cross-Organization Rules Tests
-- =============================================================================
-- Tests inter-organizational access via the cross_org_rules table.
--
-- Scenarios:
--   1. No cross-org rule: users in org A cannot access org B resources
--   2. Cross-org permission: specific role in source org can access target org
--   3. User must hold role in source org (not just any role)
--   4. Cross-org prohibition: blocks access even if there's a regular permission
--   5. Cross-org rules combine with activity hierarchy
--   6. Cross-org rules combine with view hierarchy
--   7. Temporal cross-org rules (valid_from / valid_until)
--
-- Company context:
--   Judy (sales_rep at Sales) is allowed to read GlobalTech reports via cross-org rule
--   Nina (eng_auditor at Engineering) has a temporal cross-org rule to read GlobalTech audit_logs
--   Diana (sales_manager at Sales) has a cross-org prohibition on writing Engineering docs
--
-- Prerequisites: 00_setup.sql -> 05_temporal.sql
-- =============================================================================

\echo ''
\echo '================================================================'
\echo '06 - CROSS-ORGANIZATIONAL RULES'
\echo '================================================================'

-- ---------------------------------------------------------------------------
-- Setup: additional roles and users for cross-org scenarios
-- ---------------------------------------------------------------------------

-- Nina: eng_auditor role in Engineering Dept
INSERT INTO morbac.roles (id, org_id, name, description) VALUES
    ('20000000-0002-0000-0000-000000000003', '10000000-0000-0000-0000-000000000002', 'eng_auditor', 'Engineering Auditor');

INSERT INTO morbac.user_roles (user_id, role_id, org_id) VALUES
    ('30000000-0000-0000-0000-000000000014', '20000000-0002-0000-0000-000000000003', '10000000-0000-0000-0000-000000000002');

-- Rules for eng_auditor in Engineering
INSERT INTO morbac.rules (org_id, role_id, activity, view, context_id, modality)
SELECT o.id, r.id, 'read', 'audit_logs', c.id, 'permission'
FROM morbac.orgs o
JOIN morbac.roles r ON r.org_id = o.id AND r.name = 'eng_auditor'
JOIN morbac.contexts c ON c.name = 'always'
WHERE o.name = 'Engineering Dept';

-- Verify nina's role was set up correctly
SELECT morbac.t('Nina has eng_auditor role at Engineering',
    morbac.user_has_role(
        '30000000-0000-0000-0000-000000000014'::uuid,
        '10000000-0000-0000-0000-000000000002'::uuid,
        'eng_auditor'
    ), TRUE);

-- ---------------------------------------------------------------------------
-- Section 1: No cross-org rule - access between orgs is denied by default
-- ---------------------------------------------------------------------------
\echo ''
\echo '--- 1. No cross-org rule: access denied by default ---'

-- Dave (employee at GlobalTech) has no role in Engineering and no cross-org rule
SELECT morbac.t('Dave (GlobalTech employee) reads Engineering documents [no cross-org rule]',
    morbac.is_allowed_nocache(
        '30000000-0000-0000-0000-000000000004'::uuid,
        '10000000-0000-0000-0000-000000000002'::uuid,
        'read', 'documents'
    ), FALSE);

-- Judy (Engineering engineer) accesses GlobalTech financial_data (no cross-org rule yet)
SELECT morbac.t('Judy (Engineering engineer) reads GlobalTech financial_data [no cross-org rule]',
    morbac.is_allowed_nocache(
        '30000000-0000-0000-0000-000000000010'::uuid,
        '10000000-0000-0000-0000-000000000001'::uuid,
        'read', 'financial_data'
    ), FALSE);

-- ---------------------------------------------------------------------------
-- Section 2: Cross-org permission - Sales sales_rep reads GlobalTech reports
-- ---------------------------------------------------------------------------
\echo ''
\echo '--- 2. Cross-org permission ---'

-- Judy is sales_rep at Sales. Add a cross-org rule:
-- Sales sales_rep can read GlobalTech reports
INSERT INTO morbac.cross_org_rules
    (source_org_id, target_org_id, role_id, activity, view, context_id, modality)
VALUES (
    '10000000-0000-0000-0000-000000000003', -- source: Sales Dept
    '10000000-0000-0000-0000-000000000001', -- target: GlobalTech HQ
    '20000000-0003-0000-0000-000000000002', -- sales_rep role
    'read', 'reports',
    (SELECT id FROM morbac.contexts WHERE name = 'always'),
    'permission'
);

-- Cross-org rule grants access
SELECT morbac.t('Judy (Sales sales_rep) reads GlobalTech reports via cross-org rule',
    morbac.is_allowed_nocache(
        '30000000-0000-0000-0000-000000000010'::uuid,
        '10000000-0000-0000-0000-000000000001'::uuid,
        'read', 'reports'
    ), TRUE);

-- Judy at Sales can still read Sales docs normally (local rule, no cross-org needed)
SELECT morbac.t('Judy (Sales sales_rep) reads Sales documents [local rule]',
    morbac.is_allowed_nocache(
        '30000000-0000-0000-0000-000000000010'::uuid,
        '10000000-0000-0000-0000-000000000003'::uuid,
        'read', 'documents'
    ), TRUE);

-- Judy does NOT have permission to read GlobalTech documents (cross-org rule only covers reports)
SELECT morbac.t('Judy (Sales sales_rep) reads GlobalTech documents [no rule for documents]',
    morbac.is_allowed_nocache(
        '30000000-0000-0000-0000-000000000010'::uuid,
        '10000000-0000-0000-0000-000000000001'::uuid,
        'read', 'documents'
    ), FALSE);

-- ---------------------------------------------------------------------------
-- Section 3: User must hold role in source org
-- ---------------------------------------------------------------------------
\echo ''
\echo '--- 3. Role must be held in source org ---'

-- Karl has no role anywhere - cannot use the Sales->GlobalTech cross-org rule
SELECT morbac.t('Karl (no role) reads GlobalTech reports via cross-org rule [no role in source]',
    morbac.is_allowed_nocache(
        '30000000-0000-0000-0000-000000000011'::uuid,
        '10000000-0000-0000-0000-000000000001'::uuid,
        'read', 'reports'
    ), FALSE);

-- Karl also has no access to GlobalTech documents
SELECT morbac.t('Karl (no role) reads GlobalTech documents [no access anywhere]',
    morbac.is_allowed_nocache(
        '30000000-0000-0000-0000-000000000011'::uuid,
        '10000000-0000-0000-0000-000000000001'::uuid,
        'read', 'documents'
    ), FALSE);

-- ---------------------------------------------------------------------------
-- Section 4: Cross-org prohibition - blocks access even with regular permission
-- ---------------------------------------------------------------------------
\echo ''
\echo '--- 4. Cross-org prohibition ---'

-- Engineering engineer can normally read Engineering documents (local perm)
SELECT morbac.t('Judy (Engineering engineer) reads Engineering documents [local perm]',
    morbac.is_allowed_nocache(
        '30000000-0000-0000-0000-000000000010'::uuid,
        '10000000-0000-0000-0000-000000000002'::uuid,
        'read', 'documents'
    ), TRUE);

-- Add Diana (sales_manager at Sales) for cross-org prohibition test
INSERT INTO morbac.user_roles (user_id, role_id, org_id) VALUES
    ('30000000-0000-0000-0000-000000000015', '20000000-0003-0000-0000-000000000001', '10000000-0000-0000-0000-000000000003');

-- Add cross-org prohibition: Sales sales_manager prohibited from writing Engineering documents
INSERT INTO morbac.cross_org_rules
    (source_org_id, target_org_id, role_id, activity, view, context_id, modality)
VALUES (
    '10000000-0000-0000-0000-000000000003', -- source: Sales Dept
    '10000000-0000-0000-0000-000000000002', -- target: Engineering Dept
    '20000000-0003-0000-0000-000000000001', -- sales_manager role
    'write', 'documents',
    (SELECT id FROM morbac.contexts WHERE name = 'always'),
    'prohibition'
);

-- Also give a cross-org permission that would otherwise allow the write
INSERT INTO morbac.cross_org_rules
    (source_org_id, target_org_id, role_id, activity, view, context_id, modality)
VALUES (
    '10000000-0000-0000-0000-000000000003', -- source: Sales Dept
    '10000000-0000-0000-0000-000000000002', -- target: Engineering Dept
    '20000000-0003-0000-0000-000000000001', -- sales_manager role
    'write', 'documents',
    (SELECT id FROM morbac.contexts WHERE name = 'always'),
    'permission'
);

-- Cross-org prohibition takes precedence over permission
SELECT morbac.t('Diana (Sales sales_manager) writes Engineering documents [cross-org prohibition wins]',
    morbac.is_allowed_nocache(
        '30000000-0000-0000-0000-000000000015'::uuid,
        '10000000-0000-0000-0000-000000000002'::uuid,
        'write', 'documents'
    ), FALSE);

-- Diana can read Engineering documents (no prohibition for read)
INSERT INTO morbac.cross_org_rules
    (source_org_id, target_org_id, role_id, activity, view, context_id, modality)
VALUES (
    '10000000-0000-0000-0000-000000000003', -- source: Sales Dept
    '10000000-0000-0000-0000-000000000002', -- target: Engineering Dept
    '20000000-0003-0000-0000-000000000001', -- sales_manager role
    'read', 'documents',
    (SELECT id FROM morbac.contexts WHERE name = 'always'),
    'permission'
);

-- No prohibition for read, permission applies
SELECT morbac.t('Diana (Sales sales_manager) reads Engineering documents [cross-org permission]',
    morbac.is_allowed_nocache(
        '30000000-0000-0000-0000-000000000015'::uuid,
        '10000000-0000-0000-0000-000000000002'::uuid,
        'read', 'documents'
    ), TRUE);

-- ---------------------------------------------------------------------------
-- Section 5: Cross-org + activity hierarchy
-- ---------------------------------------------------------------------------
\echo ''
\echo '--- 5. Cross-org with activity hierarchy ---'

-- The sales_rep cross-org rule grants 'read reports' in GlobalTech.
-- With activity hierarchy (write->read), requesting 'write reports' also matches
-- the 'read' rule (get_effective_activities('write') = {write, read}).
SELECT morbac.t('Judy (Sales sales_rep) writes GlobalTech reports via cross-org + activity hierarchy',
    morbac.is_allowed_nocache(
        '30000000-0000-0000-0000-000000000010'::uuid,
        '10000000-0000-0000-0000-000000000001'::uuid,
        'write', 'reports'
    ), TRUE);

-- ---------------------------------------------------------------------------
-- Section 6: Cross-org + view hierarchy
-- ---------------------------------------------------------------------------
\echo ''
\echo '--- 6. Cross-org with view hierarchy ---'

-- Add a cross-org rule for 'read documents' (not financial_data directly)
-- With view hierarchy (financial_data->documents), 'read documents' cross-org rule
-- also covers 'read financial_data' requests
INSERT INTO morbac.cross_org_rules
    (source_org_id, target_org_id, role_id, activity, view, context_id, modality)
VALUES (
    '10000000-0000-0000-0000-000000000003', -- source: Sales Dept
    '10000000-0000-0000-0000-000000000001', -- target: GlobalTech HQ
    '20000000-0003-0000-0000-000000000002', -- sales_rep role
    'read', 'documents',
    (SELECT id FROM morbac.contexts WHERE name = 'always'),
    'permission'
);

-- get_effective_views('financial_data') = {financial_data, documents}
-- so 'read documents' cross-org rule covers 'read financial_data' request
SELECT morbac.t('Judy (Sales sales_rep) reads GlobalTech financial_data via cross-org + view hierarchy',
    morbac.is_allowed_nocache(
        '30000000-0000-0000-0000-000000000010'::uuid,
        '10000000-0000-0000-0000-000000000001'::uuid,
        'read', 'financial_data'
    ), TRUE);

-- ---------------------------------------------------------------------------
-- Section 7: Temporal cross-org rule
-- ---------------------------------------------------------------------------
\echo ''
\echo '--- 7. Temporal cross-org rule ---'

-- Add a time-limited cross-org rule for eng_auditor to read GlobalTech audit_logs
INSERT INTO morbac.cross_org_rules
    (source_org_id, target_org_id, role_id, activity, view, context_id, modality, valid_from, valid_until)
VALUES (
    '10000000-0000-0000-0000-000000000002', -- source: Engineering
    '10000000-0000-0000-0000-000000000001', -- target: GlobalTech HQ
    '20000000-0002-0000-0000-000000000003', -- eng_auditor role
    'read', 'audit_logs',
    (SELECT id FROM morbac.contexts WHERE name = 'always'),
    'permission',
    now() - interval '1 hour',
    now() + interval '1 day'
);

-- Nina (Engineering eng_auditor) reads GlobalTech audit_logs within window
SELECT morbac.t('Nina (Engineering eng_auditor) reads GlobalTech audit_logs [temporal cross-org, active]',
    morbac.is_allowed_nocache(
        '30000000-0000-0000-0000-000000000014'::uuid,
        '10000000-0000-0000-0000-000000000001'::uuid,
        'read', 'audit_logs'
    ), TRUE);

-- Expire the cross-org rule
UPDATE morbac.cross_org_rules
SET valid_until = now() - interval '1 second'
WHERE source_org_id = '10000000-0000-0000-0000-000000000002'
  AND target_org_id = '10000000-0000-0000-0000-000000000001'
  AND role_id = '20000000-0002-0000-0000-000000000003'
  AND activity = 'read' AND view = 'audit_logs';

-- Temporal rule expired
SELECT morbac.t('Nina (Engineering eng_auditor) reads GlobalTech audit_logs [temporal cross-org, expired]',
    morbac.is_allowed_nocache(
        '30000000-0000-0000-0000-000000000014'::uuid,
        '10000000-0000-0000-0000-000000000001'::uuid,
        'read', 'audit_logs'
    ), FALSE);

\echo ''
\echo '=== Cross-Organization Rules Tests Completed ==='
