# Security Policy

## Supported Versions

| Version | Supported          |
| ------- | ------------------ |
| 1.0.x   | :white_check_mark: |

## Security Model

pgmorbac implements the Multi-OrBAC access control model with the following security principles:

### Default Deny
- No permission = access denied
- Explicit permissions must be granted

### Prohibition Precedence
- Prohibitions and permissions are both evaluated; the higher-priority rule wins
- At equal or unset priority, prohibition overrides permission
- A permission with strictly higher priority than a prohibition will override it

### Organization Isolation
- All policies are scoped to organizations
- Cross-organization access requires explicit `cross_org_rules`
- Users cannot access resources outside their authorized organizations

### Context Evaluation
- All rules can have contextual conditions
- Contexts are evaluated at authorization time
- Failed context evaluation = rule does not apply

### SQL Injection Protection
- All functions use parameterized queries
- No dynamic SQL construction from user input
- Type-safe PostgreSQL functions

## Reporting a Vulnerability

If you discover a security vulnerability in pgmorbac, please report it responsibly:

### DO NOT
- Open a public GitHub issue for security vulnerabilities
- Disclose the vulnerability publicly before it's fixed

### DO
1. **Email the maintainer** with details:
   - Description of the vulnerability
   - Steps to reproduce
   - Potential impact
   - Suggested fix (if any)

2. **Wait for acknowledgment** (within 48 hours)

3. **Coordinate disclosure** after a fix is available

### What to Expect

- **Acknowledgment**: Within 48 hours
- **Initial assessment**: Within 1 week
- **Fix timeline**: Depends on severity
  - Critical: 1-7 days
  - High: 1-2 weeks
  - Medium: 2-4 weeks
  - Low: Next release
- **Disclosure**: Coordinated after fix is released
- **Credit**: You will be credited (unless you prefer anonymity)

## Security Best Practices

When using pgmorbac:

### 1. Protect Authorization Headers
```sql
-- In PostgREST, ensure X-User-Id and X-Org-Id come from authenticated sessions
-- Never trust client-provided values directly
```

### 2. Use RLS Policies
```sql
-- Always enable RLS on application tables
ALTER TABLE app.documents ENABLE ROW LEVEL SECURITY;

-- Use pgmorbac for authorization
CREATE POLICY doc_access ON app.documents
FOR ALL USING (morbac.rls_check('read', 'documents'));
```

### 3. Validate Context Functions
```sql
-- Context functions should be STABLE or IMMUTABLE
-- Avoid VOLATILE contexts that could leak information
CREATE OR REPLACE FUNCTION morbac.my_context()
RETURNS BOOLEAN
LANGUAGE plpgsql
STABLE  -- Important!
AS $$ ... $$;
```

### 4. Audit Critical Operations
```sql
-- Enable audit logging on security-critical tables
SELECT morbac.enable_audit('user_roles');
SELECT morbac.enable_audit('rules');
SELECT morbac.enable_audit('delegations');

-- Query audit log for security review
SELECT
    timestamp,
    operation,
    table_name,
    session_user,
    client_addr,
    old_data,
    new_data
FROM morbac.audit_log
WHERE table_name = 'user_roles'
ORDER BY timestamp DESC
LIMIT 100;
```

### 5. Regular Updates
- Keep PostgreSQL updated
- Monitor for pgmorbac security advisories
- Review and test policies regularly

### 6. Principle of Least Privilege
- Grant only necessary permissions
- Use prohibitions to explicitly deny sensitive operations
- Implement Separation of Duty for critical roles

## Known Limitations

1. **Context Function Security**: Context functions run with database privileges. Ensure they are written securely and don't expose sensitive information.

2. **Delegation Trust**: Delegations are trusted. Ensure delegator has authority to delegate their role.

3. **Performance**: Complex authorization queries on large datasets may impact performance. Use indexes and consider caching.

## Acknowledgments

We appreciate responsible disclosure and will acknowledge security researchers who help improve pgmorbac security.
