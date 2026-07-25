-- =============================================================================
-- Test Setup - GlobalTech Inc. Company Scenario
-- =============================================================================
-- This file establishes the full company structure used across all test files:
--
--   GlobalTech HQ (root)
--   +-- Engineering Dept (child)
--   \-- Sales Dept (child)
--
-- Role hierarchy in GlobalTech (senior -> junior, i.e. senior inherits junior perms):
--   ceo -> director -> manager -> employee -> intern
--   + specialized roles: auditor, accountant, hr_manager, contractor, compliance_officer
--
-- Role hierarchy in Engineering:
--   tech_lead -> engineer
--
-- Users:
--   Alice - CEO at GlobalTech
--   Bob - Director at GlobalTech
--   Carol - Manager at GlobalTech
--   Dave - Employee at GlobalTech
--   Eve - Intern at GlobalTech
--   Frank - Contractor at GlobalTech
--   Grace - HR Manager at GlobalTech
--   Heidi - Auditor at GlobalTech
--   Ivan - Accountant at GlobalTech
--   Judy - Engineer at Engineering + Sales Rep at Sales (multi-org)
--   Karl - No role (unauthorized user)
--   Leo - Employee at GlobalTech (used for delegation target)
-- =============================================================================

-- Clean slate
DROP EXTENSION IF EXISTS pgmorbac CASCADE;
DROP SCHEMA IF EXISTS morbac CASCADE;
CREATE EXTENSION pgmorbac;

\echo '=== Setup: Verify schema created ==='
SELECT tablename FROM pg_tables WHERE schemaname = 'morbac' ORDER BY tablename;

-- ---------------------------------------------------------------------------
-- ORGANIZATIONS
-- ---------------------------------------------------------------------------
\echo ''
\echo '=== Setup: Organizations ==='

INSERT INTO morbac.orgs (id, name) VALUES
    ('10000000-0000-0000-0000-000000000001', 'GlobalTech HQ'),
    ('10000000-0000-0000-0000-000000000002', 'Engineering Dept'),
    ('10000000-0000-0000-0000-000000000003', 'Sales Dept');

-- Engineering and Sales are children of GlobalTech
UPDATE morbac.orgs SET parent_id = '10000000-0000-0000-0000-000000000001'
WHERE id IN (
    '10000000-0000-0000-0000-000000000002',
    '10000000-0000-0000-0000-000000000003'
);

SELECT o.name, COALESCE(p.name, ' - ') AS parent
FROM morbac.orgs o LEFT JOIN morbac.orgs p ON o.parent_id = p.id
ORDER BY o.parent_id NULLS FIRST, o.name;

-- ---------------------------------------------------------------------------
-- ROLES
-- ---------------------------------------------------------------------------
\echo ''
\echo '=== Setup: Roles ==='

-- GlobalTech HQ roles
INSERT INTO morbac.roles (id, org_id, name, description) VALUES
    ('20000000-0001-0000-0000-000000000001', '10000000-0000-0000-0000-000000000001', 'ceo',                'Chief Executive Officer'),
    ('20000000-0001-0000-0000-000000000002', '10000000-0000-0000-0000-000000000001', 'director',           'Senior Director'),
    ('20000000-0001-0000-0000-000000000003', '10000000-0000-0000-0000-000000000001', 'manager',            'Department Manager'),
    ('20000000-0001-0000-0000-000000000004', '10000000-0000-0000-0000-000000000001', 'employee',           'Regular Employee'),
    ('20000000-0001-0000-0000-000000000005', '10000000-0000-0000-0000-000000000001', 'intern',             'Intern'),
    ('20000000-0001-0000-0000-000000000006', '10000000-0000-0000-0000-000000000001', 'auditor',            'Internal Auditor'),
    ('20000000-0001-0000-0000-000000000007', '10000000-0000-0000-0000-000000000001', 'accountant',         'Accountant'),
    ('20000000-0001-0000-0000-000000000008', '10000000-0000-0000-0000-000000000001', 'hr_manager',         'Human Resources Manager'),
    ('20000000-0001-0000-0000-000000000009', '10000000-0000-0000-0000-000000000001', 'contractor',         'External Contractor'),
    ('20000000-0001-0000-0000-000000000010', '10000000-0000-0000-0000-000000000001', 'compliance_officer', 'Compliance Officer');

-- Engineering Dept roles
INSERT INTO morbac.roles (id, org_id, name, description) VALUES
    ('20000000-0002-0000-0000-000000000001', '10000000-0000-0000-0000-000000000002', 'tech_lead', 'Technical Lead'),
    ('20000000-0002-0000-0000-000000000002', '10000000-0000-0000-0000-000000000002', 'engineer',  'Software Engineer');

-- Sales Dept roles
INSERT INTO morbac.roles (id, org_id, name, description) VALUES
    ('20000000-0003-0000-0000-000000000001', '10000000-0000-0000-0000-000000000003', 'sales_manager', 'Sales Manager'),
    ('20000000-0003-0000-0000-000000000002', '10000000-0000-0000-0000-000000000003', 'sales_rep',     'Sales Representative');

SELECT r.name AS role, o.name AS organization
FROM morbac.roles r JOIN morbac.orgs o ON r.org_id = o.id
ORDER BY o.name, r.name;

-- ---------------------------------------------------------------------------
-- ROLE HIERARCHY (GlobalTech)
-- Senior role inherits all permissions granted to junior role
-- ---------------------------------------------------------------------------
\echo ''
\echo '=== Setup: Role Hierarchy (GlobalTech HQ) ==='

INSERT INTO morbac.role_hierarchy (senior_role_id, junior_role_id) VALUES
    -- CEO inherits from Director
    ('20000000-0001-0000-0000-000000000001', '20000000-0001-0000-0000-000000000002'),
    -- Director inherits from Manager
    ('20000000-0001-0000-0000-000000000002', '20000000-0001-0000-0000-000000000003'),
    -- Manager inherits from Employee
    ('20000000-0001-0000-0000-000000000003', '20000000-0001-0000-0000-000000000004'),
    -- Employee inherits from Intern
    ('20000000-0001-0000-0000-000000000004', '20000000-0001-0000-0000-000000000005');

-- Engineering: tech_lead inherits from engineer
INSERT INTO morbac.role_hierarchy (senior_role_id, junior_role_id) VALUES
    ('20000000-0002-0000-0000-000000000001', '20000000-0002-0000-0000-000000000002');

SELECT
    sr.name AS senior_role,
    jr.name AS junior_role
FROM morbac.role_hierarchy rh
JOIN morbac.roles sr ON sr.id = rh.senior_role_id
JOIN morbac.roles jr ON jr.id = rh.junior_role_id
ORDER BY sr.name;

-- ---------------------------------------------------------------------------
-- USER - ROLE ASSIGNMENTS
-- ---------------------------------------------------------------------------
\echo ''
\echo '=== Setup: User-Role Assignments ==='

-- GlobalTech HQ users
INSERT INTO morbac.user_roles (user_id, role_id, org_id) VALUES
    -- Alice: CEO
    ('30000000-0000-0000-0000-000000000001', '20000000-0001-0000-0000-000000000001', '10000000-0000-0000-0000-000000000001'),
    -- Bob: Director
    ('30000000-0000-0000-0000-000000000002', '20000000-0001-0000-0000-000000000002', '10000000-0000-0000-0000-000000000001'),
    -- Carol: Manager
    ('30000000-0000-0000-0000-000000000003', '20000000-0001-0000-0000-000000000003', '10000000-0000-0000-0000-000000000001'),
    -- Dave: Employee
    ('30000000-0000-0000-0000-000000000004', '20000000-0001-0000-0000-000000000004', '10000000-0000-0000-0000-000000000001'),
    -- Eve: Intern
    ('30000000-0000-0000-0000-000000000005', '20000000-0001-0000-0000-000000000005', '10000000-0000-0000-0000-000000000001'),
    -- Frank: Contractor
    ('30000000-0000-0000-0000-000000000006', '20000000-0001-0000-0000-000000000009', '10000000-0000-0000-0000-000000000001'),
    -- Grace: HR Manager
    ('30000000-0000-0000-0000-000000000007', '20000000-0001-0000-0000-000000000008', '10000000-0000-0000-0000-000000000001'),
    -- Heidi: Auditor
    ('30000000-0000-0000-0000-000000000008', '20000000-0001-0000-0000-000000000006', '10000000-0000-0000-0000-000000000001'),
    -- Ivan: Accountant
    ('30000000-0000-0000-0000-000000000009', '20000000-0001-0000-0000-000000000007', '10000000-0000-0000-0000-000000000001'),
    -- Leo: Employee (delegation target)
    ('30000000-0000-0000-0000-000000000012', '20000000-0001-0000-0000-000000000004', '10000000-0000-0000-0000-000000000001');

-- Judy: Engineer at Engineering + Sales Rep at Sales (multi-org user)
INSERT INTO morbac.user_roles (user_id, role_id, org_id) VALUES
    ('30000000-0000-0000-0000-000000000010', '20000000-0002-0000-0000-000000000002', '10000000-0000-0000-0000-000000000002'),
    ('30000000-0000-0000-0000-000000000010', '20000000-0003-0000-0000-000000000002', '10000000-0000-0000-0000-000000000003');

-- Karl: no role (unauthorized user - intentionally not assigned any role)

SELECT ur.user_id, r.name AS role, o.name AS organization
FROM morbac.user_roles ur
JOIN morbac.roles r ON ur.role_id = r.id
JOIN morbac.orgs o ON ur.org_id = o.id
ORDER BY ur.user_id;

-- ---------------------------------------------------------------------------
-- ACTIVITIES AND VIEWS
-- ---------------------------------------------------------------------------
\echo ''
\echo '=== Setup: Activities and Views ==='

INSERT INTO morbac.activities (name, description) VALUES
    ('read',    'Read / view data'),
    ('write',   'Create or modify data'),
    ('delete',  'Delete data'),
    ('manage',  'Full management access'),
    ('approve', 'Approve requests or documents'),
    ('export',  'Export data to external format'),
    ('audit',   'Audit trail review')
ON CONFLICT (name) DO NOTHING;

INSERT INTO morbac.views (name, description) VALUES
    ('documents',     'General company documents'),
    ('reports',       'Business reports'),
    ('financial_data','Financial records'),
    ('hr_data',       'Human resources data'),
    ('contracts',     'Legal contracts'),
    ('audit_logs',    'System audit logs'),
    ('public_data',   'Publicly accessible data')
ON CONFLICT (name) DO NOTHING;

-- ---------------------------------------------------------------------------
-- CONTEXTS
-- ---------------------------------------------------------------------------
\echo ''
\echo '=== Setup: Contexts ==='

-- business_hours: always TRUE for tests (simulates daytime access)
CREATE OR REPLACE FUNCTION morbac.ctx_business_hours()
RETURNS BOOLEAN LANGUAGE plpgsql STABLE AS $$
BEGIN RETURN TRUE; END;
$$;

-- after_hours: always FALSE for tests (simulates outside-hours access)
CREATE OR REPLACE FUNCTION morbac.ctx_after_hours()
RETURNS BOOLEAN LANGUAGE plpgsql STABLE AS $$
BEGIN RETURN FALSE; END;
$$;

-- end_of_quarter: always TRUE for tests (simulates quarterly reporting period)
CREATE OR REPLACE FUNCTION morbac.ctx_end_of_quarter()
RETURNS BOOLEAN LANGUAGE plpgsql STABLE AS $$
BEGIN RETURN TRUE; END;
$$;

INSERT INTO morbac.contexts (name, description, evaluator) VALUES
    ('business_hours',   'During business hours (Mon-Fri 9-17)',  'morbac.ctx_business_hours'::regproc),
    ('after_hours',      'Outside business hours',                 'morbac.ctx_after_hours'::regproc),
    ('end_of_quarter',   'End-of-quarter reporting window',        'morbac.ctx_end_of_quarter'::regproc);

SELECT name, description FROM morbac.contexts ORDER BY name;

-- ---------------------------------------------------------------------------
-- RULES
-- ---------------------------------------------------------------------------
\echo ''
\echo '=== Setup: Rules ==='

INSERT INTO morbac.rules (org_id, role_id, activity, view, context_id, modality)
SELECT o.id, r.id, v.activity, v.view, c.id, v.modality::morbac.modality
FROM (VALUES
    ('GlobalTech HQ', 'intern',             'read',   'public_data',    'always',        'permission'),
    ('GlobalTech HQ', 'employee',           'read',   'documents',      'always',        'permission'),
    ('GlobalTech HQ', 'employee',           'write',  'documents',      'business_hours','permission'),
    ('GlobalTech HQ', 'employee',           'read',   'reports',        'always',        'permission'),
    ('GlobalTech HQ', 'employee',           'read',   'public_data',    'always',        'permission'),
    ('GlobalTech HQ', 'employee',           'read',   'reports',        'always',        'obligation'),
    ('GlobalTech HQ', 'employee',           'read',   'reports',        'end_of_quarter','recommendation'),
    ('GlobalTech HQ', 'employee',           'read',   'public_data',    'always',        'recommendation'),
    ('GlobalTech HQ', 'manager',            'approve','documents',      'always',        'permission'),
    ('GlobalTech HQ', 'manager',            'delete', 'documents',      'always',        'permission'),
    ('GlobalTech HQ', 'manager',            'read',   'financial_data', 'always',        'permission'),
    ('GlobalTech HQ', 'hr_manager',         'read',   'hr_data',        'always',        'permission'),
    ('GlobalTech HQ', 'hr_manager',         'write',  'hr_data',        'always',        'permission'),
    ('GlobalTech HQ', 'hr_manager',         'delete', 'hr_data',        'always',        'permission'),
    ('GlobalTech HQ', 'auditor',            'read',   'audit_logs',     'always',        'permission'),
    ('GlobalTech HQ', 'auditor',            'read',   'financial_data', 'always',        'permission'),
    ('GlobalTech HQ', 'auditor',            'read',   'documents',      'always',        'permission'),
    ('GlobalTech HQ', 'accountant',         'read',   'financial_data', 'always',        'permission'),
    ('GlobalTech HQ', 'accountant',         'write',  'financial_data', 'always',        'permission'),
    ('GlobalTech HQ', 'contractor',         'read',   'documents',      'always',        'permission'),
    ('GlobalTech HQ', 'contractor',         'read',   'financial_data', 'always',        'prohibition'),
    ('GlobalTech HQ', 'contractor',         'read',   'hr_data',        'always',        'prohibition'),
    ('GlobalTech HQ', 'compliance_officer', 'read',   'audit_logs',     'always',        'permission'),
    ('GlobalTech HQ', 'compliance_officer', 'read',   'financial_data', 'always',        'permission'),
    ('Engineering Dept', 'engineer',        'read',   'documents',      'always',        'permission'),
    ('Engineering Dept', 'engineer',        'write',  'documents',      'always',        'permission'),
    ('Engineering Dept', 'tech_lead',       'approve','documents',      'always',        'permission'),
    ('Sales Dept',       'sales_rep',       'read',   'documents',      'always',        'permission'),
    ('Sales Dept',       'sales_rep',       'write',  'contracts',      'always',        'permission'),
    ('Sales Dept',       'sales_manager',   'read',   'reports',        'always',        'permission'),
    ('Sales Dept',       'sales_manager',   'approve','contracts',      'always',        'permission')
) AS v(org_name, role_name, activity, view, context_name, modality)
JOIN morbac.orgs o ON o.name = v.org_name
JOIN morbac.roles r ON r.org_id = o.id AND r.name = v.role_name
JOIN morbac.contexts c ON c.name = v.context_name;

-- ---------------------------------------------------------------------------
-- Test infrastructure
-- ---------------------------------------------------------------------------
\echo ''
\echo '=== Setup: Test Infrastructure ==='

-- Disable auth cache so state changes between calls are always reflected
SELECT morbac.set_config('cache_ttl_seconds', '0');

-- morbac.t(label, actual, expected) - boolean assertion
CREATE OR REPLACE FUNCTION morbac.t(label TEXT, actual BOOLEAN, expect BOOLEAN)
RETURNS TEXT LANGUAGE sql STABLE AS $$
    SELECT CASE WHEN actual IS NOT DISTINCT FROM expect
                THEN 'CHECK PASS: ' || label
                ELSE 'CHECK FAIL: ' || label
                     || ' (expected ' || expect::text || ', got ' || COALESCE(actual::text, 'NULL') || ')'
           END;
$$;

-- morbac.t_null(label, actual) - assert value is NULL
CREATE OR REPLACE FUNCTION morbac.t_null(label TEXT, actual TEXT)
RETURNS TEXT LANGUAGE sql STABLE AS $$
    SELECT CASE WHEN actual IS NULL
                THEN 'CHECK PASS: ' || label
                ELSE 'CHECK FAIL: ' || label || ' (expected NULL, got: ' || actual || ')'
           END;
$$;

-- morbac.t_not_null(label, actual) - assert value is NOT NULL
CREATE OR REPLACE FUNCTION morbac.t_not_null(label TEXT, actual TEXT)
RETURNS TEXT LANGUAGE sql STABLE AS $$
    SELECT CASE WHEN actual IS NOT NULL
                THEN 'CHECK PASS: ' || label
                ELSE 'CHECK FAIL: ' || label || ' (expected a value, got NULL)'
           END;
$$;

-- morbac.t_eq(label, actual, expected) - assert two numeric values are equal
CREATE OR REPLACE FUNCTION morbac.t_eq(label TEXT, actual NUMERIC, expect NUMERIC)
RETURNS TEXT LANGUAGE sql STABLE AS $$
    SELECT CASE WHEN actual = expect
                THEN 'CHECK PASS: ' || label
                ELSE 'CHECK FAIL: ' || label
                     || ' (expected ' || expect || ', got ' || actual || ')'
           END;
$$;

\echo ''
\echo '=== Setup Complete ==='
\echo '    Organizations : GlobalTech HQ, Engineering Dept, Sales Dept'
\echo '    Roles         : 14 across 3 orgs'
\echo '    Users         : Alice, Bob, Carol, Dave, Eve, Frank, Grace, Heidi, Ivan, Judy, Karl, Leo'
\echo '    Activities    : read, write, delete, manage, approve, export, audit (+ built-ins: create, update)'
\echo '    Views         : documents, reports, financial_data, hr_data, contracts, audit_logs, public_data'
\echo '    Contexts      : always (true), business_hours (true), after_hours (false), end_of_quarter (true)'
