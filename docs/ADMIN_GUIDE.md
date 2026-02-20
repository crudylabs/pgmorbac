# Administration Guide

This guide explains how to set up organization-scoped administrators without relying on database superadmins.

## Concept

Multi-OrBAC allows you to delegate administrative capabilities to specific roles within each organization. This means:

- Organization administrators can manage users, roles, and policies within their own organization
- No need for database-level superadmin access for day-to-day administration
- Fine-grained control over what each admin role can do
- Admins cannot affect other organizations

## Administration Rules

The `morbac.admin_rules` table defines administrative capabilities for specific roles:

**Key columns:**
- `org_id`, `role_id`: Role receiving capabilities
- `admin_activity`: Action type (e.g., 'manage', 'assign_role')
- `admin_target`: Target type (e.g., 'policies', 'roles', specific role name, '*' for wildcard)
- `modality`: Permission or prohibition
- `context_id`: Optional conditional evaluation

## Common Admin Patterns

### 1. Organization Administrator

Full admin within their organization:

```sql
-- Create admin role
INSERT INTO morbac.roles (org_id, name, description)
SELECT id, 'org_admin', 'Organization administrator'
FROM morbac.orgs WHERE name = 'Acme Corp';

-- Grant ability to manage policies
INSERT INTO morbac.admin_rules (org_id, role_id, admin_activity, admin_target, modality, context_id)
SELECT
    o.id,
    r.id,
    'manage',
    'policies',
    'permission',
    (SELECT id FROM morbac.contexts WHERE name = 'always')
FROM morbac.orgs o
JOIN morbac.roles r ON r.org_id = o.id
WHERE o.name = 'Acme Corp' AND r.name = 'org_admin';

-- Grant ability to manage roles
INSERT INTO morbac.admin_rules (org_id, role_id, admin_activity, admin_target, modality, context_id)
SELECT
    o.id,
    r.id,
    'manage',
    'roles',
    'permission',
    (SELECT id FROM morbac.contexts WHERE name = 'always')
FROM morbac.orgs o
JOIN morbac.roles r ON r.org_id = o.id
WHERE o.name = 'Acme Corp' AND r.name = 'org_admin';

-- Grant ability to assign ALL roles (wildcard)
INSERT INTO morbac.admin_rules (org_id, role_id, admin_activity, admin_target, modality, context_id)
SELECT
    o.id,
    r.id,
    'assign_role',
    '*',
    'permission',
    (SELECT id FROM morbac.contexts WHERE name = 'always')
FROM morbac.orgs o
JOIN morbac.roles r ON r.org_id = o.id
WHERE o.name = 'Acme Corp' AND r.name = 'org_admin';

-- Assign someone as org admin
INSERT INTO morbac.user_roles (user_id, role_id, org_id)
SELECT
    'alice-uuid'::uuid,
    r.id,
    o.id
FROM morbac.orgs o
JOIN morbac.roles r ON r.org_id = o.id
WHERE o.name = 'Acme Corp' AND r.name = 'org_admin';
```

### 2. HR Manager (User/Role Assignment Only)

Can assign users to roles but cannot modify policies:

```sql
-- Create HR manager role
INSERT INTO morbac.roles (org_id, name, description)
SELECT id, 'hr_manager', 'HR manager - can assign users to roles'
FROM morbac.orgs WHERE name = 'Acme Corp';

-- Grant ability to assign specific roles
INSERT INTO morbac.admin_rules (org_id, role_id, admin_activity, admin_target, modality, context_id)
SELECT
    o.id,
    r.id,
    'assign_role',
    target_role,
    'permission',
    (SELECT id FROM morbac.contexts WHERE name = 'always')
FROM morbac.orgs o
CROSS JOIN (VALUES ('employee'), ('manager'), ('contractor')) AS roles(target_role)
JOIN morbac.roles r ON r.org_id = o.id
WHERE o.name = 'Acme Corp' AND r.name = 'hr_manager';

-- Prohibit assigning admin roles
INSERT INTO morbac.admin_rules (org_id, role_id, admin_activity, admin_target, modality, context_id)
SELECT
    o.id,
    r.id,
    'assign_role',
    'org_admin',
    'prohibition',
    (SELECT id FROM morbac.contexts WHERE name = 'always')
FROM morbac.orgs o
JOIN morbac.roles r ON r.org_id = o.id
WHERE o.name = 'Acme Corp' AND r.name = 'hr_manager';
```

### 3. Security Manager (Policy Management Only)

Can define policies but cannot assign users:

```sql
-- Create security manager role
INSERT INTO morbac.roles (org_id, name, description)
SELECT id, 'security_manager', 'Security manager - can manage policies'
FROM morbac.orgs WHERE name = 'Acme Corp';

-- Grant policy management
INSERT INTO morbac.admin_rules (org_id, role_id, admin_activity, admin_target, modality, context_id)
SELECT
    o.id,
    r.id,
    'manage',
    'policies',
    'permission',
    (SELECT id FROM morbac.contexts WHERE name = 'always')
FROM morbac.orgs o
JOIN morbac.roles r ON r.org_id = o.id
WHERE o.name = 'Acme Corp' AND r.name = 'security_manager';
```

## Using Admin Functions

### Check Permissions

```sql
-- Check if Alice can manage policies
SELECT morbac.can_manage_policies('alice-uuid'::uuid, org_id);

-- Check if Alice can manage roles
SELECT morbac.can_manage_roles('alice-uuid'::uuid, org_id);

-- Check if Alice can assign a specific role
SELECT morbac.can_manage_user_role('alice-uuid'::uuid, org_id, employee_role_id);

-- General admin check
SELECT morbac.is_admin_allowed('alice-uuid'::uuid, org_id, 'assign_role', 'manager');
```

### Assign/Revoke Roles Safely

```sql
-- Alice (HR manager) assigns Bob to employee role
SELECT morbac.admin_assign_role(
    'alice-uuid'::uuid,      -- Admin user
    'bob-uuid'::uuid,        -- Target user
    employee_role_id,        -- Role to assign
    org_id                   -- Organization
);

-- Alice revokes Bob's employee role
SELECT morbac.admin_revoke_role(
    'alice-uuid'::uuid,
    'bob-uuid'::uuid,
    employee_role_id,
    org_id
);
```

These functions automatically:
- Check if Alice has permission to manage the role
- Validate SoD constraints
- Validate cardinality constraints
- Raise exceptions if constraints are violated

## Application Integration

### REST API Example

Your application can expose admin endpoints that use these functions:

```sql
-- Endpoint: POST /api/orgs/:orgId/users/:userId/roles/:roleId
-- Handler checks:
CREATE OR REPLACE FUNCTION app.assign_role_endpoint(
    p_requesting_user_id UUID,
    p_org_id UUID,
    p_target_user_id UUID,
    p_role_id UUID
)
RETURNS JSON
LANGUAGE plpgsql
AS $$
DECLARE
    v_result JSON;
BEGIN
    BEGIN
        PERFORM morbac.admin_assign_role(
            p_requesting_user_id,
            p_target_user_id,
            p_role_id,
            p_org_id
        );

        v_result := json_build_object(
            'success', true,
            'message', 'Role assigned successfully'
        );
    EXCEPTION WHEN OTHERS THEN
        v_result := json_build_object(
            'success', false,
            'error', SQLERRM
        );
    END;

    RETURN v_result;
END;
$$;
```

### Row-Level Security for Admin Tables

Protect admin configuration with RLS:

```sql
-- Only org admins can see admin rules
ALTER TABLE morbac.admin_rules ENABLE ROW LEVEL SECURITY;

CREATE POLICY admin_rules_access ON morbac.admin_rules
FOR SELECT
USING (
    org_id = morbac.current_org_id()
    AND (
        -- User is org admin
        morbac.can_manage_policies(morbac.current_user_id(), org_id)
        OR morbac.can_manage_roles(morbac.current_user_id(), org_id)
    )
);

-- Only org admins can modify admin rules
CREATE POLICY admin_rules_modify ON morbac.admin_rules
FOR ALL
USING (
    org_id = morbac.current_org_id()
    AND morbac.can_manage_policies(morbac.current_user_id(), org_id)
);
```

## Context-Based Admin Rules

You can limit admin actions to specific contexts (e.g., business hours):

```sql
-- Create context for business hours
CREATE OR REPLACE FUNCTION morbac.context_business_hours()
RETURNS BOOLEAN
LANGUAGE plpgsql
STABLE
AS $$
BEGIN
    RETURN EXTRACT(DOW FROM CURRENT_DATE) BETWEEN 1 AND 5
       AND EXTRACT(HOUR FROM CURRENT_TIME) BETWEEN 9 AND 17;
END;
$$;

INSERT INTO morbac.contexts (name, description, evaluator) VALUES
    ('business_hours', 'Monday-Friday 9am-5pm', 'morbac.context_business_hours');

-- HR can only assign roles during business hours
INSERT INTO morbac.admin_rules (org_id, role_id, admin_activity, admin_target, modality, context_id)
SELECT
    o.id,
    r.id,
    'assign_role',
    '*',
    'permission',
    (SELECT id FROM morbac.contexts WHERE name = 'business_hours')
FROM morbac.orgs o
JOIN morbac.roles r ON r.org_id = o.id
WHERE o.name = 'Acme Corp' AND r.name = 'hr_manager';
```

## Best Practices

1. **Principle of Least Privilege**: Grant only necessary admin capabilities to each role
2. **Separation of Duties**: Separate policy management from user assignment
3. **Audit Trail**: Log all admin actions (consider triggers on user_roles, rules tables)
4. **Context-Based**: Use contexts to limit when admin actions can occur
5. **Multiple Admins**: Use role cardinality to ensure multiple admins exist
6. **Prohibitions**: Use prohibition admin rules to explicitly deny certain actions

## Example: Complete Setup

```sql
-- 1. Create organization
INSERT INTO morbac.orgs (name) VALUES ('Acme Corp');

-- 2. Create roles
INSERT INTO morbac.roles (org_id, name)
SELECT id, name FROM morbac.orgs,
    (VALUES ('org_admin'), ('hr_manager'), ('employee'), ('manager')) AS roles(name)
WHERE morbac.orgs.name = 'Acme Corp';

-- 3. Set up org_admin with full permissions
INSERT INTO morbac.admin_rules (org_id, role_id, admin_activity, admin_target, modality, context_id)
SELECT o.id, r.id, activity, target, 'permission', c.id
FROM morbac.orgs o
JOIN morbac.roles r ON r.org_id = o.id
CROSS JOIN (VALUES
    ('manage', 'policies'),
    ('manage', 'roles'),
    ('assign_role', '*')
) AS perms(activity, target)
CROSS JOIN morbac.contexts c
WHERE o.name = 'Acme Corp' AND r.name = 'org_admin' AND c.name = 'always';

-- 4. Set up hr_manager with limited permissions
INSERT INTO morbac.admin_rules (org_id, role_id, admin_activity, admin_target, modality, context_id)
SELECT o.id, r.id, 'assign_role', role_name, 'permission', c.id
FROM morbac.orgs o
JOIN morbac.roles r ON r.org_id = o.id
CROSS JOIN (VALUES ('employee'), ('manager')) AS assignable(role_name)
CROSS JOIN morbac.contexts c
WHERE o.name = 'Acme Corp' AND r.name = 'hr_manager' AND c.name = 'always';

-- 5. Assign Alice as org_admin
INSERT INTO morbac.user_roles (user_id, role_id, org_id)
SELECT 'alice-uuid'::uuid, r.id, o.id
FROM morbac.orgs o
JOIN morbac.roles r ON r.org_id = o.id
WHERE o.name = 'Acme Corp' AND r.name = 'org_admin';

-- 6. Now Alice can assign Bob as hr_manager
SELECT morbac.admin_assign_role(
    'alice-uuid'::uuid,
    'bob-uuid'::uuid,
    (SELECT id FROM morbac.roles WHERE name = 'hr_manager' AND org_id =
        (SELECT id FROM morbac.orgs WHERE name = 'Acme Corp')),
    (SELECT id FROM morbac.orgs WHERE name = 'Acme Corp')
);

-- 7. Now Bob can assign users to employee/manager roles
SELECT morbac.admin_assign_role(
    'bob-uuid'::uuid,
    'charlie-uuid'::uuid,
    (SELECT id FROM morbac.roles WHERE name = 'employee' AND org_id =
        (SELECT id FROM morbac.orgs WHERE name = 'Acme Corp')),
    (SELECT id FROM morbac.orgs WHERE name = 'Acme Corp')
);
```

## Summary

Multi-OrBAC provides complete delegation of administrative capabilities:

- **No superadmins needed**: for day-to-day operations
- **Organization-scoped**: admins only affect their own org
- **Fine-grained**: control exactly what each admin role can do
- **Safe**: automatic constraint validation (SoD, cardinality)
- **Auditable**: all actions go through tracked functions
- **Context-aware**: limit when admin actions can occur
