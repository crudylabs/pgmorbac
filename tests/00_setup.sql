-- =============================================================================
-- Test Setup - Creates test data for all tests
-- =============================================================================
-- This file creates organizations, roles, users, activities, views, and contexts
-- that are used across multiple test files.
-- =============================================================================

-- Clean up any previous test
DROP EXTENSION IF EXISTS pgmorbac CASCADE;
DROP SCHEMA IF EXISTS morbac CASCADE;

-- Install the extension
CREATE EXTENSION pgmorbac;

-- Verify schema and tables exist
\echo '=== Schema and Tables Created ==='
SELECT schemaname, tablename
FROM pg_tables
WHERE schemaname = 'morbac'
ORDER BY tablename;

\echo ''
\echo '=== Setup: Organizations ==='

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
\echo '=== Setup: Roles ==='

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
\echo '=== Setup: User Role Assignments ==='

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
\echo '=== Setup: Activities and Views ==='

INSERT INTO morbac.activities (name, description) VALUES
    ('read', 'Read/view data'),
    ('write', 'Create/modify data'),
    ('delete', 'Delete data'),
    ('approve', 'Approve actions');

INSERT INTO morbac.views (name, description) VALUES
    ('documents', 'Document resources'),
    ('reports', 'Report resources'),
    ('sensitive_data', 'Sensitive/confidential data'),
    ('temp_documents', 'Temporary documents'),
    ('future_documents', 'Future documents'),
    ('active_documents', 'Active documents');

\echo ''
\echo '=== Setup: Additional Contexts ==='

-- Business hours context (simplified - always true for this test)
CREATE OR REPLACE FUNCTION morbac.context_business_hours()
RETURNS BOOLEAN
LANGUAGE plpgsql
STABLE
AS $$
BEGIN
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
    RETURN FALSE;
END;
$$;

INSERT INTO morbac.contexts (name, description, evaluator) VALUES
    ('weekend', 'During weekend', 'morbac.context_weekend'::regproc);

\echo ''
\echo '=== Setup: Policy DSL ==='

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

-- Compile policy
SELECT * FROM morbac.compile_policy();

\echo ''
\echo '=== Setup Complete ==='
