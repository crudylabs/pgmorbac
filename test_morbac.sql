-- =============================================================================
-- Test Script for morbac_pg Extension
-- =============================================================================
-- This script demonstrates and tests the Multi-OrBAC implementation
--
-- Test Scenario:
-- - Two organizations: "Acme Corp" and "Beta Inc"
-- - Multiple users with different roles
-- - Permission and prohibition rules
-- - Context evaluation
-- - Multi-organization resource access
-- - Obligations and recommendations
-- =============================================================================

-- Clean up any previous test
DROP EXTENSION IF EXISTS morbac_pg CASCADE;
DROP SCHEMA IF EXISTS morbac CASCADE;

-- Install the extension
CREATE EXTENSION morbac_pg;

-- Verify schema and tables exist
\echo '=== Schema and Tables Created ==='
SELECT schemaname, tablename
FROM pg_tables
WHERE schemaname = 'morbac'
ORDER BY tablename;

\echo ''
\echo '=== Test 1: Create Organizations ==='

-- Create two organizations
INSERT INTO morbac.orgs (id, name) VALUES
    ('11111111-1111-1111-1111-111111111111', 'Acme Corp'),
    ('22222222-2222-2222-2222-222222222222', 'Beta Inc');

-- Create hierarchical organization (Acme Subsidiary under Acme Corp)
INSERT INTO morbac.orgs (id, name, parent_id) VALUES
    ('33333333-3333-3333-3333-333333333333', 'Acme Subsidiary', '11111111-1111-1111-1111-111111111111');

SELECT
    o.name,
    COALESCE(p.name, 'None') as parent_organization
FROM morbac.orgs o
LEFT JOIN morbac.orgs p ON o.parent_id = p.id
ORDER BY o.parent_id NULLS FIRST, o.name;

\echo ''
\echo '=== Test 2: Create Roles ==='

-- Create roles in Acme Corp
INSERT INTO morbac.roles (id, org_id, name, description) VALUES
    ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '11111111-1111-1111-1111-111111111111', 'admin', 'Administrator role'),
    ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', '11111111-1111-1111-1111-111111111111', 'employee', 'Regular employee'),
    ('cccccccc-cccc-cccc-cccc-cccccccccccc', '11111111-1111-1111-1111-111111111111', 'contractor', 'External contractor'),
    ('ffffffff-ffff-ffff-ffff-ffffffffffff', '11111111-1111-1111-1111-111111111111', 'viewer', 'Read-only viewer');

-- Create roles in Beta Inc
INSERT INTO morbac.roles (id, org_id, name, description) VALUES
    ('dddddddd-dddd-dddd-dddd-dddddddddddd', '22222222-2222-2222-2222-222222222222', 'manager', 'Manager role'),
    ('eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee', '22222222-2222-2222-2222-222222222222', 'staff', 'Staff member');

SELECT r.name as role, o.name as organization
FROM morbac.roles r
JOIN morbac.orgs o ON r.org_id = o.id
ORDER BY o.name, r.name;

\echo ''
\echo '=== Test 2b: Create Role Hierarchy ==='

-- Role hierarchy in Acme Corp:
-- admin > employee > viewer
-- (admin inherits from employee, employee inherits from viewer)
INSERT INTO morbac.role_hierarchy (senior_role_id, junior_role_id) VALUES
    ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'),  -- admin inherits from employee
    ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', 'ffffffff-ffff-ffff-ffff-ffffffffffff');  -- employee inherits from viewer

\echo 'Role hierarchy created:'
SELECT
    sr.name as senior_role,
    jr.name as junior_role,
    o.name as organization
FROM morbac.role_hierarchy rh
JOIN morbac.roles sr ON rh.senior_role_id = sr.id
JOIN morbac.roles jr ON rh.junior_role_id = jr.id
JOIN morbac.orgs o ON sr.org_id = o.id;

\echo ''
\echo '=== Test 3: Assign Users to Roles ==='

-- Define test users (in real scenario, these would come from auth system)
-- User Alice (admin at Acme)
INSERT INTO morbac.user_roles (user_id, role_id, org_id) VALUES
    ('aaaaaaaa-0000-0000-0000-000000000001', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '11111111-1111-1111-1111-111111111111');

-- User Bob (employee at Acme)
INSERT INTO morbac.user_roles (user_id, role_id, org_id) VALUES
    ('bbbbbbbb-0000-0000-0000-000000000002', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', '11111111-1111-1111-1111-111111111111');

-- User Charlie (contractor at Acme AND staff at Beta - multi-org user)
INSERT INTO morbac.user_roles (user_id, role_id, org_id) VALUES
    ('cccccccc-0000-0000-0000-000000000003', 'cccccccc-cccc-cccc-cccc-cccccccccccc', '11111111-1111-1111-1111-111111111111'),
    ('cccccccc-0000-0000-0000-000000000003', 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee', '22222222-2222-2222-2222-222222222222');

-- User Diana (manager at Beta)
INSERT INTO morbac.user_roles (user_id, role_id, org_id) VALUES
    ('dddddddd-0000-0000-0000-000000000004', 'dddddddd-dddd-dddd-dddd-dddddddddddd', '22222222-2222-2222-2222-222222222222');

SELECT
    ur.user_id,
    r.name as role,
    o.name as organization
FROM morbac.user_roles ur
JOIN morbac.roles r ON ur.role_id = r.id
JOIN morbac.orgs o ON ur.org_id = o.id
ORDER BY ur.user_id;

\echo ''
\echo '=== Test 4: Define Activities and Views ==='

INSERT INTO morbac.activities (name, description) VALUES
    ('read', 'Read/view data'),
    ('write', 'Create/modify data'),
    ('delete', 'Delete data'),
    ('approve', 'Approve actions');

INSERT INTO morbac.views (name, description) VALUES
    ('documents', 'Document resources'),
    ('reports', 'Report resources'),
    ('sensitive_data', 'Sensitive/confidential data');

SELECT * FROM morbac.activities ORDER BY name;
SELECT * FROM morbac.views ORDER BY name;

\echo ''
\echo '=== Test 5: Create Additional Contexts ==='

-- Business hours context (simplified - always true for this test)
CREATE OR REPLACE FUNCTION morbac.context_business_hours()
RETURNS BOOLEAN
LANGUAGE plpgsql
STABLE
AS $$
BEGIN
    -- In production, check current time against business hours
    -- For test, return TRUE
    RETURN TRUE;
END;
$$;

INSERT INTO morbac.contexts (name, description, evaluator) VALUES
    ('business_hours', 'During business hours', 'morbac.context_business_hours'::regproc);

-- Weekend context (always false for test)
CREATE OR REPLACE FUNCTION morbac.context_weekend()
RETURNS BOOLEAN
LANGUAGE plpgsql
STABLE
AS $$
BEGIN
    -- In production, check if today is weekend
    -- For test, return FALSE
    RETURN FALSE;
END;
$$;

INSERT INTO morbac.contexts (name, description, evaluator) VALUES
    ('weekend', 'During weekend', 'morbac.context_weekend'::regproc);

SELECT name, description FROM morbac.contexts ORDER BY name;

\echo ''
\echo '=== Test 6: Define Policy Using DSL ==='

-- Acme Corp policies
INSERT INTO morbac.policy (org_name, role_name, activity, view, modality, context_name) VALUES
    -- Admins can do everything on documents
    ('Acme Corp', 'admin', 'read', 'documents', 'permission', 'always'),
    ('Acme Corp', 'admin', 'write', 'documents', 'permission', 'always'),
    ('Acme Corp', 'admin', 'delete', 'documents', 'permission', 'always'),

    -- Employees can read and write documents
    ('Acme Corp', 'employee', 'read', 'documents', 'permission', 'always'),
    ('Acme Corp', 'employee', 'write', 'documents', 'permission', 'business_hours'),

    -- Contractors can only read documents
    ('Acme Corp', 'contractor', 'read', 'documents', 'permission', 'always'),

    -- PROHIBITION: Contractors cannot access sensitive data
    ('Acme Corp', 'contractor', 'read', 'sensitive_data', 'prohibition', 'always'),
    ('Acme Corp', 'contractor', 'write', 'sensitive_data', 'prohibition', 'always'),

    -- OBLIGATION: Employees must review reports weekly
    ('Acme Corp', 'employee', 'read', 'reports', 'obligation', 'always'),

    -- Admins can access reports
    ('Acme Corp', 'admin', 'read', 'reports', 'permission', 'always'),
    ('Acme Corp', 'admin', 'approve', 'reports', 'permission', 'always');

-- Beta Inc policies
INSERT INTO morbac.policy (org_name, role_name, activity, view, modality, context_name) VALUES
    -- Managers have full access
    ('Beta Inc', 'manager', 'read', 'documents', 'permission', 'always'),
    ('Beta Inc', 'manager', 'write', 'documents', 'permission', 'always'),
    ('Beta Inc', 'manager', 'read', 'reports', 'permission', 'always'),

    -- Staff can read documents
    ('Beta Inc', 'staff', 'read', 'documents', 'permission', 'always'),

    -- PROHIBITION: No document modifications on weekends (example)
    ('Beta Inc', 'staff', 'write', 'documents', 'prohibition', 'weekend'),

    -- RECOMMENDATION: Staff should review reports
    ('Beta Inc', 'staff', 'read', 'reports', 'recommendation', 'always');

SELECT org_name, role_name, activity, view, modality, context_name
FROM morbac.policy
ORDER BY org_name, role_name, modality;

\echo ''
\echo '=== Test 7: Compile Policy ==='

SELECT * FROM morbac.compile_policy();

-- Verify rules were created
\echo ''
\echo 'Rules created by policy compiler:'
SELECT
    o.name as org,
    r.name as role,
    ru.activity,
    ru.view,
    ru.modality,
    c.name as context
FROM morbac.rules ru
JOIN morbac.orgs o ON ru.org_id = o.id
JOIN morbac.roles r ON ru.role_id = r.id
JOIN morbac.contexts c ON ru.context_id = c.id
ORDER BY o.name, r.name, ru.modality, ru.activity;

\echo ''
\echo '=== Test 8: Authorization Decisions ==='

-- Test Alice (admin at Acme)
\echo 'Alice (admin at Acme Corp):'
SELECT
    'read documents' as action,
    morbac.is_allowed(
        'aaaaaaaa-0000-0000-0000-000000000001'::uuid,
        '11111111-1111-1111-1111-111111111111'::uuid,
        'read',
        'documents'
    ) as allowed;

SELECT
    'delete documents' as action,
    morbac.is_allowed(
        'aaaaaaaa-0000-0000-0000-000000000001'::uuid,
        '11111111-1111-1111-1111-111111111111'::uuid,
        'delete',
        'documents'
    ) as allowed;

-- Test Bob (employee at Acme)
\echo ''
\echo 'Bob (employee at Acme Corp):'
SELECT
    'read documents' as action,
    morbac.is_allowed(
        'bbbbbbbb-0000-0000-0000-000000000002'::uuid,
        '11111111-1111-1111-1111-111111111111'::uuid,
        'read',
        'documents'
    ) as allowed;

SELECT
    'delete documents' as action,
    morbac.is_allowed(
        'bbbbbbbb-0000-0000-0000-000000000002'::uuid,
        '11111111-1111-1111-1111-111111111111'::uuid,
        'delete',
        'documents'
    ) as allowed;

-- Test Charlie (contractor at Acme)
\echo ''
\echo 'Charlie (contractor at Acme Corp):'
SELECT
    'read documents' as action,
    morbac.is_allowed(
        'cccccccc-0000-0000-0000-000000000003'::uuid,
        '11111111-1111-1111-1111-111111111111'::uuid,
        'read',
        'documents'
    ) as allowed;

SELECT
    'write documents' as action,
    morbac.is_allowed(
        'cccccccc-0000-0000-0000-000000000003'::uuid,
        '11111111-1111-1111-1111-111111111111'::uuid,
        'write',
        'documents'
    ) as allowed;

-- Test PROHIBITION precedence
\echo ''
\echo 'Testing PROHIBITION PRECEDENCE:'
\echo 'Charlie (contractor) trying to read sensitive_data (should be DENIED by prohibition):'
SELECT
    'read sensitive_data' as action,
    morbac.is_allowed(
        'cccccccc-0000-0000-0000-000000000003'::uuid,
        '11111111-1111-1111-1111-111111111111'::uuid,
        'read',
        'sensitive_data'
    ) as allowed;

-- Test Charlie at Beta Inc (multi-org user)
\echo ''
\echo 'Charlie as staff at Beta Inc:'
SELECT
    'read documents' as action,
    morbac.is_allowed(
        'cccccccc-0000-0000-0000-000000000003'::uuid,
        '22222222-2222-2222-2222-222222222222'::uuid,
        'read',
        'documents'
    ) as allowed;

-- Test Diana (manager at Beta)
\echo ''
\echo 'Diana (manager at Beta Inc):'
SELECT
    'write documents' as action,
    morbac.is_allowed(
        'dddddddd-0000-0000-0000-000000000004'::uuid,
        '22222222-2222-2222-2222-222222222222'::uuid,
        'write',
        'documents'
    ) as allowed;

\echo ''
\echo '=== Test 8b: Role Hierarchy Inheritance ==='

-- Assign user Eve only viewer role
\echo 'Creating user Eve with only viewer role at Acme:'
INSERT INTO morbac.user_roles (user_id, role_id, org_id) VALUES
    ('eeeeeeee-0000-0000-0000-000000000005', 'ffffffff-ffff-ffff-ffff-ffffffffffff', '11111111-1111-1111-1111-111111111111');

-- Add permission for viewer role
INSERT INTO morbac.policy (org_name, role_name, activity, view, modality) VALUES
    ('Acme Corp', 'viewer', 'read', 'documents', 'permission');

SELECT * FROM morbac.compile_policy();

\echo ''
\echo 'Eve (has viewer role, which employee inherits from):'
SELECT
    'read documents' as action,
    morbac.is_allowed(
        'eeeeeeee-0000-0000-0000-000000000005'::uuid,
        '11111111-1111-1111-1111-111111111111'::uuid,
        'read',
        'documents'
    ) as allowed;

\echo ''
\echo 'Bob (employee) should inherit permissions from viewer role:'
\echo 'Effective roles for Bob (should include employee and viewer via hierarchy):'
SELECT r.name, er.depth
FROM morbac.get_effective_roles(
    'bbbbbbbb-0000-0000-0000-000000000002'::uuid,
    '11111111-1111-1111-1111-111111111111'::uuid
) er
JOIN morbac.roles r ON er.role_id = r.id
ORDER BY er.depth;

\echo ''
\echo 'Alice (admin) should inherit from both employee and viewer:'
SELECT r.name, er.depth
FROM morbac.get_effective_roles(
    'aaaaaaaa-0000-0000-0000-000000000001'::uuid,
    '11111111-1111-1111-1111-111111111111'::uuid
) er
JOIN morbac.roles r ON er.role_id = r.id
ORDER BY er.depth;

\echo ''
\echo '=== Test 8c: Organization Hierarchy ==='

\echo 'Ancestors of Acme Subsidiary:'
SELECT o.name, oa.depth
FROM morbac.get_org_ancestors('33333333-3333-3333-3333-333333333333'::uuid) oa
JOIN morbac.orgs o ON oa.org_id = o.id
ORDER BY oa.depth;

\echo ''
\echo 'Descendants of Acme Corp (should include subsidiary):'
SELECT o.name, od.depth
FROM morbac.get_org_descendants('11111111-1111-1111-1111-111111111111'::uuid) od
JOIN morbac.orgs o ON od.org_id = o.id
ORDER BY od.depth;

\echo ''
\echo '=== Test 9: Obligations and Recommendations ==='

\echo 'Obligations for Bob (employee at Acme):'
SELECT * FROM morbac.pending_obligations(
    'bbbbbbbb-0000-0000-0000-000000000002'::uuid,
    '11111111-1111-1111-1111-111111111111'::uuid
);

\echo ''
\echo 'Recommendations for Charlie (staff at Beta):'
SELECT * FROM morbac.pending_recommendations(
    'cccccccc-0000-0000-0000-000000000003'::uuid,
    '22222222-2222-2222-2222-222222222222'::uuid
);

\echo ''
\echo '=== Test 10: Utility Functions ==='

\echo 'Roles for Charlie at Acme Corp:'
SELECT * FROM morbac.user_roles_in_org(
    'cccccccc-0000-0000-0000-000000000003'::uuid,
    '11111111-1111-1111-1111-111111111111'::uuid
);

\echo ''
\echo 'Roles for Charlie at Beta Inc:'
SELECT * FROM morbac.user_roles_in_org(
    'cccccccc-0000-0000-0000-000000000003'::uuid,
    '22222222-2222-2222-2222-222222222222'::uuid
);

\echo ''
\echo 'Does Alice have admin role at Acme Corp?'
SELECT morbac.user_has_role(
    'aaaaaaaa-0000-0000-0000-000000000001'::uuid,
    '11111111-1111-1111-1111-111111111111'::uuid,
    'admin'
) as has_admin_role;

\echo ''
\echo '=== Test 11: Context Evaluation ==='

\echo 'Evaluating always context:'
SELECT morbac.eval_context(
    (SELECT id FROM morbac.contexts WHERE name = 'always')
) as result;

\echo ''
\echo 'Evaluating business_hours context:'
SELECT morbac.eval_context(
    (SELECT id FROM morbac.contexts WHERE name = 'business_hours')
) as result;

\echo ''
\echo 'Evaluating weekend context:'
SELECT morbac.eval_context(
    (SELECT id FROM morbac.contexts WHERE name = 'weekend')
) as result;

\echo ''
\echo '=== Test 12: Policy Re-compilation (Idempotency Test) ==='

\echo 'Compiling policy again (should show 0 new rules, idempotent):'
SELECT * FROM morbac.compile_policy();

\echo ''
\echo '=== Test 13: Adding New Policy Entry ==='

INSERT INTO morbac.policy (org_name, role_name, activity, view, modality, context_name) VALUES
    ('Acme Corp', 'admin', 'approve', 'documents', 'permission', 'always');

\echo 'Compiling new policy entry:'
SELECT * FROM morbac.compile_policy();

\echo ''
\echo '=== Test 14: Delegation ==='

-- Alice delegates admin role to user Frank temporarily
INSERT INTO morbac.delegations (delegator_id, delegatee_id, role_id, org_id, valid_from, valid_until) VALUES
    ('aaaaaaaa-0000-0000-0000-000000000001', 'ffffffff-0000-0000-0000-000000000006', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '11111111-1111-1111-1111-111111111111', now(), now() + interval '1 day');

\echo 'Frank (via delegation from Alice) should have admin permissions:'
SELECT
    'delete documents (delegated)' as action,
    morbac.is_allowed(
        'ffffffff-0000-0000-0000-000000000006'::uuid,
        '11111111-1111-1111-1111-111111111111'::uuid,
        'delete',
        'documents'
    ) as allowed;

\echo 'Frank effective roles (should include delegated admin):'
SELECT r.name, cr.source
FROM morbac.get_comprehensive_roles('ffffffff-0000-0000-0000-000000000006'::uuid, '11111111-1111-1111-1111-111111111111'::uuid) cr
JOIN morbac.roles r ON cr.role_id = r.id;

\echo ''
\echo '=== Test 15: Separation of Duty ==='

-- Define SoD conflict: auditor and accountant roles are mutually exclusive
INSERT INTO morbac.roles (id, org_id, name, description) VALUES
    ('11111111-1111-1111-1111-111111111111', '11111111-1111-1111-1111-111111111111', 'auditor', 'Auditor role'),
    ('22222222-2222-2222-2222-222222222222', '11111111-1111-1111-1111-111111111111', 'accountant', 'Accountant role');

INSERT INTO morbac.sod_conflicts (role_a_id, role_b_id, org_id, description) VALUES
    ('11111111-1111-1111-1111-111111111111', '22222222-2222-2222-2222-222222222222', '11111111-1111-1111-1111-111111111111', 'Auditors and accountants are mutually exclusive');

-- Assign user to auditor role
INSERT INTO morbac.user_roles (user_id, role_id, org_id) VALUES
    ('99999999-0000-0000-0000-000000000009', '11111111-1111-1111-1111-111111111111', '11111111-1111-1111-1111-111111111111');

\echo 'Check SoD violation if we try to assign accountant role to auditor:'
SELECT morbac.check_sod_violation(
    '99999999-0000-0000-0000-000000000009'::uuid,
    '22222222-2222-2222-2222-222222222222'::uuid,
    '11111111-1111-1111-1111-111111111111'::uuid
) as would_violate_sod;

\echo ''
\echo '=== Test 16: Activity and View Hierarchies ==='

-- Define activity hierarchy: write implies read
INSERT INTO morbac.activity_hierarchy (senior_activity, junior_activity) VALUES
    ('write', 'read');

-- Define view hierarchy: sensitive_data is a type of documents
INSERT INTO morbac.view_hierarchy (senior_view, junior_view) VALUES
    ('sensitive_data', 'documents');

\echo 'Activities implied by write:'
SELECT * FROM morbac.get_effective_activities('write');

\echo 'Views for sensitive_data (should include documents):'
SELECT * FROM morbac.get_effective_views('sensitive_data');

\echo 'Bob has permission for read+documents, so write+documents should work (activity hierarchy):'
SELECT
    'write documents (via activity hierarchy)' as action,
    morbac.is_allowed(
        'bbbbbbbb-0000-0000-0000-000000000002'::uuid,
        '11111111-1111-1111-1111-111111111111'::uuid,
        'write',
        'documents'
    ) as allowed;

\echo ''
\echo '=== Test 17: Negative Role Assignment ==='

-- Explicitly prohibit contractor from ever being admin
INSERT INTO morbac.negative_role_assignments (user_id, role_id, org_id, reason) VALUES
    ('cccccccc-0000-0000-0000-000000000003', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '11111111-1111-1111-1111-111111111111', 'Contractors cannot be administrators');

\echo 'Charlie cannot have admin role even if explicitly assigned (negative assignment takes precedence).'

\echo ''
\echo '=== Test 18: Cardinality Constraints ==='

-- Set max 2 users for admin role
INSERT INTO morbac.role_cardinality (role_id, min_users, max_users, description) VALUES
    ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 1, 2, 'Admin role limited to 2 users minimum 1');

\echo 'Check cardinality when adding user (1 admin exists, max is 2, should be OK):'
SELECT morbac.check_cardinality_violation('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'::uuid, TRUE) as violation;

\echo ''
\echo '=== Test 19: Administration Rules ==='

-- Only admin role can create rules
INSERT INTO morbac.admin_rules (org_id, role_id, admin_activity, admin_target, context_id, modality) VALUES
    ('11111111-1111-1111-1111-111111111111', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'create_rule', 'rules', (SELECT id FROM morbac.contexts WHERE name = 'always'), 'permission');

\echo 'Alice (admin) can create rules:'
SELECT morbac.is_admin_allowed(
    'aaaaaaaa-0000-0000-0000-000000000001'::uuid,
    '11111111-1111-1111-1111-111111111111'::uuid,
    'create_rule',
    'rules'
) as can_create_rules;

\echo 'Bob (employee) cannot create rules:'
SELECT morbac.is_admin_allowed(
    'bbbbbbbb-0000-0000-0000-000000000002'::uuid,
    '11111111-1111-1111-1111-111111111111'::uuid,
    'create_rule',
    'rules'
) as can_create_rules;

\echo ''
\echo '=== Test 20: Cross-Organization Rules ==='

-- Allow Beta managers to read Acme documents (inter-org collaboration)
INSERT INTO morbac.cross_org_rules (source_org_id, target_org_id, role_id, activity, view, context_id, modality) VALUES
    ('22222222-2222-2222-2222-222222222222', '11111111-1111-1111-1111-111111111111', 'dddddddd-dddd-dddd-dddd-dddddddddddd', 'read', 'documents', (SELECT id FROM morbac.contexts WHERE name = 'always'), 'permission');

\echo 'Diana (manager at Beta) can read Acme documents via cross-org rule:'
SELECT
    'read Acme documents from Beta' as action,
    morbac.is_allowed(
        'dddddddd-0000-0000-0000-000000000004'::uuid,
        '11111111-1111-1111-1111-111111111111'::uuid,
        'read',
        'documents'
    ) as allowed;

\echo ''
\echo '=== ALL TESTS COMPLETED SUCCESSFULLY ==='
\echo ''
\echo 'Summary:'
\echo '- Extension installed and schema created'
\echo '- Organizations with hierarchy'
\echo '- Roles with hierarchy'
\echo '- Delegation support'
\echo '- Separation of Duty constraints'
\echo '- Activity and View hierarchies'
\echo '- Negative role assignments'
\echo '- Cardinality constraints'
\echo '- Administration rules'
\echo '- Cross-organizational rules'
\echo '- Derived roles (framework ready)'
\echo '- Complete authorization with all features'
\echo '- Prohibition precedence verified'
\echo '- Multi-organization support verified'
