-- =============================================================================
-- morbac_pg Extension
-- =============================================================================
-- Multi-OrBAC: Organization-Based Access Control with Multi-Organization Support
-- Based on the CNRS research paper on Multi-OrBAC model
--
-- This extension implements:
-- - Organization-Based Access Control (OrBAC)
-- - Multi-organization support
-- - Deontic modalities: permissions, prohibitions, obligations, recommendations
-- - Context-based rule evaluation
-- - Prohibition precedence over permissions
-- - Policy DSL for simplified rule declaration
-- - RLS helper functions for PostgREST compatibility
-- =============================================================================

-- Require pgcrypto for UUID generation
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- Create the morbac schema
CREATE SCHEMA IF NOT EXISTS morbac;

COMMENT ON SCHEMA morbac IS 'Multi-OrBAC access control framework - all objects live in this schema';

-- =============================================================================
-- CONFIGURATION
-- =============================================================================
-- Centralized configuration for morbac_pg extension
-- Edit these values to customize behavior

CREATE TABLE morbac.config (
    key TEXT PRIMARY KEY,
    value TEXT NOT NULL,
    description TEXT,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

COMMENT ON TABLE morbac.config IS 'Extension configuration - edit values to customize behavior';

-- Insert default configuration values
INSERT INTO morbac.config (key, value, description) VALUES
    ('cache_ttl_seconds', '300', 'Authorization cache time-to-live in seconds (default: 5 minutes)'),
    ('hierarchy_max_depth', '10', 'Maximum depth for hierarchy traversal to prevent infinite loops'),
    ('enable_audit_by_default', 'false', 'Whether to enable audit logging by default on installation');

-- Helper function to get configuration values
CREATE OR REPLACE FUNCTION morbac.get_config(p_key TEXT)
RETURNS TEXT
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    v_value TEXT;
BEGIN
    SELECT value INTO v_value FROM morbac.config WHERE key = p_key;
    RETURN v_value;
EXCEPTION
    WHEN OTHERS THEN
        RETURN NULL;
END;
$$;

COMMENT ON FUNCTION morbac.get_config(TEXT) IS
'Get configuration value by key';

-- Helper function to set configuration values
CREATE OR REPLACE FUNCTION morbac.set_config(p_key TEXT, p_value TEXT)
RETURNS VOID
LANGUAGE plpgsql
AS $$
BEGIN
    UPDATE morbac.config
    SET value = p_value, updated_at = CURRENT_TIMESTAMP
    WHERE key = p_key;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Configuration key % does not exist', p_key;
    END IF;
END;
$$;

COMMENT ON FUNCTION morbac.set_config(TEXT, TEXT) IS
'Set configuration value by key';

-- =============================================================================
-- DEONTIC MODALITY TYPE
-- =============================================================================
-- Represents the four deontic modalities of OrBAC model

CREATE TYPE morbac.modality AS ENUM (
    'permission',
    'prohibition',
    'obligation',
    'recommendation'
);

COMMENT ON TYPE morbac.modality IS 'Deontic modalities: permission, prohibition, obligation, recommendation';

-- =============================================================================
-- ORGANIZATIONS
-- =============================================================================
-- Organizations are first-class entities in Multi-OrBAC
-- Each organization has its own policy space

CREATE TABLE morbac.orgs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL UNIQUE,
    parent_id UUID REFERENCES morbac.orgs(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    metadata JSONB DEFAULT '{}'::jsonb
);

CREATE INDEX idx_orgs_name ON morbac.orgs(name);
CREATE INDEX idx_orgs_parent ON morbac.orgs(parent_id);

COMMENT ON TABLE morbac.orgs IS 'Organizations - first-class entities in Multi-OrBAC with hierarchy support';
COMMENT ON COLUMN morbac.orgs.id IS 'Unique organization identifier';
COMMENT ON COLUMN morbac.orgs.name IS 'Organization name (unique)';
COMMENT ON COLUMN morbac.orgs.parent_id IS 'Parent organization for hierarchical organizations';
COMMENT ON COLUMN morbac.orgs.metadata IS 'Optional metadata for organization';

-- =============================================================================
-- ROLES
-- =============================================================================
-- Roles are scoped to organizations
-- A role abstracts a set of subjects within an organization

CREATE TABLE morbac.roles (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    org_id UUID NOT NULL REFERENCES morbac.orgs(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    description TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE(org_id, name)
);

CREATE INDEX idx_roles_org_id ON morbac.roles(org_id);
CREATE INDEX idx_roles_org_name ON morbac.roles(org_id, name);

COMMENT ON TABLE morbac.roles IS 'Roles scoped to organizations - abstract sets of subjects';
COMMENT ON COLUMN morbac.roles.org_id IS 'Organization this role belongs to';
COMMENT ON COLUMN morbac.roles.name IS 'Role name (unique within organization)';

-- =============================================================================
-- ROLE HIERARCHY
-- =============================================================================
-- Roles can inherit from other roles (role hierarchy)
-- Senior roles inherit permissions from junior roles

CREATE TABLE morbac.role_hierarchy (
    senior_role_id UUID NOT NULL REFERENCES morbac.roles(id) ON DELETE CASCADE,
    junior_role_id UUID NOT NULL REFERENCES morbac.roles(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (senior_role_id, junior_role_id),
    CHECK (senior_role_id != junior_role_id)
);

CREATE INDEX idx_role_hierarchy_senior ON morbac.role_hierarchy(senior_role_id);
CREATE INDEX idx_role_hierarchy_junior ON morbac.role_hierarchy(junior_role_id);

COMMENT ON TABLE morbac.role_hierarchy IS 'Role hierarchy - senior roles inherit from junior roles';
COMMENT ON COLUMN morbac.role_hierarchy.senior_role_id IS 'Senior role (inherits permissions)';
COMMENT ON COLUMN morbac.role_hierarchy.junior_role_id IS 'Junior role (provides permissions)';

-- =============================================================================
-- USER-ROLE ASSIGNMENTS
-- =============================================================================
-- Maps users to roles within organizations
-- user_id is external (e.g., from authentication system)

CREATE TABLE morbac.user_roles (
    user_id UUID NOT NULL,
    role_id UUID NOT NULL REFERENCES morbac.roles(id) ON DELETE CASCADE,
    org_id UUID NOT NULL REFERENCES morbac.orgs(id) ON DELETE CASCADE,
    assigned_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (user_id, role_id, org_id)
);

CREATE INDEX idx_user_roles_user_org ON morbac.user_roles(user_id, org_id);
CREATE INDEX idx_user_roles_role ON morbac.user_roles(role_id);
-- Performance: Fast role lookup with included role_id
CREATE INDEX idx_user_roles_fast ON morbac.user_roles(user_id, org_id) INCLUDE (role_id);

COMMENT ON TABLE morbac.user_roles IS 'Maps users to roles within organizations';
COMMENT ON COLUMN morbac.user_roles.user_id IS 'External user identifier';
COMMENT ON COLUMN morbac.user_roles.role_id IS 'Role assigned to the user';
COMMENT ON COLUMN morbac.user_roles.org_id IS 'Organization context for this assignment';

-- =============================================================================
-- DELEGATION
-- =============================================================================
-- Users can delegate their permissions to other users temporarily
-- Delegation is time-bounded and role-scoped

CREATE TABLE morbac.delegations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    delegator_id UUID NOT NULL,
    delegatee_id UUID NOT NULL,
    role_id UUID NOT NULL REFERENCES morbac.roles(id) ON DELETE CASCADE,
    org_id UUID NOT NULL REFERENCES morbac.orgs(id) ON DELETE CASCADE,
    valid_from TIMESTAMPTZ NOT NULL DEFAULT now(),
    valid_until TIMESTAMPTZ NOT NULL,
    revoked BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CHECK (delegator_id != delegatee_id),
    CHECK (valid_until > valid_from)
);

CREATE INDEX idx_delegations_delegatee ON morbac.delegations(delegatee_id, org_id);
CREATE INDEX idx_delegations_validity ON morbac.delegations(valid_from, valid_until) WHERE NOT revoked;

COMMENT ON TABLE morbac.delegations IS 'Temporary delegation of roles from one user to another';
COMMENT ON COLUMN morbac.delegations.delegator_id IS 'User delegating the role';
COMMENT ON COLUMN morbac.delegations.delegatee_id IS 'User receiving the delegated role';
COMMENT ON COLUMN morbac.delegations.role_id IS 'Role being delegated';
COMMENT ON COLUMN morbac.delegations.valid_from IS 'Delegation start time';
COMMENT ON COLUMN morbac.delegations.valid_until IS 'Delegation end time';
COMMENT ON COLUMN morbac.delegations.revoked IS 'Whether delegation has been revoked';

-- =============================================================================
-- NEGATIVE ROLE ASSIGNMENTS
-- =============================================================================
-- Explicitly prevent users from ever getting certain roles
-- Takes precedence over positive assignments

CREATE TABLE morbac.negative_role_assignments (
    user_id UUID NOT NULL,
    role_id UUID NOT NULL REFERENCES morbac.roles(id) ON DELETE CASCADE,
    org_id UUID NOT NULL REFERENCES morbac.orgs(id) ON DELETE CASCADE,
    reason TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (user_id, role_id, org_id)
);

CREATE INDEX idx_negative_assignments ON morbac.negative_role_assignments(user_id, org_id);

COMMENT ON TABLE morbac.negative_role_assignments IS 'Explicit prohibition of role assignments';
COMMENT ON COLUMN morbac.negative_role_assignments.user_id IS 'User prohibited from having role';
COMMENT ON COLUMN morbac.negative_role_assignments.role_id IS 'Role that is prohibited';
COMMENT ON COLUMN morbac.negative_role_assignments.reason IS 'Reason for prohibition';

-- =============================================================================
-- SEPARATION OF DUTY (SoD)
-- =============================================================================
-- Define mutually exclusive roles that cannot be held simultaneously

CREATE TABLE morbac.sod_conflicts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    role_a_id UUID NOT NULL REFERENCES morbac.roles(id) ON DELETE CASCADE,
    role_b_id UUID NOT NULL REFERENCES morbac.roles(id) ON DELETE CASCADE,
    org_id UUID NOT NULL REFERENCES morbac.orgs(id) ON DELETE CASCADE,
    description TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CHECK (role_a_id != role_b_id),
    UNIQUE (role_a_id, role_b_id, org_id)
);

CREATE INDEX idx_sod_conflicts_org ON morbac.sod_conflicts(org_id);
CREATE INDEX idx_sod_conflicts_roles ON morbac.sod_conflicts(role_a_id, role_b_id);

COMMENT ON TABLE morbac.sod_conflicts IS 'Separation of Duty: mutually exclusive roles';
COMMENT ON COLUMN morbac.sod_conflicts.role_a_id IS 'First conflicting role';
COMMENT ON COLUMN morbac.sod_conflicts.role_b_id IS 'Second conflicting role';
COMMENT ON COLUMN morbac.sod_conflicts.description IS 'Description of the conflict';

-- =============================================================================
-- CARDINALITY CONSTRAINTS
-- =============================================================================
-- Limit the number of users that can have a specific role

CREATE TABLE morbac.role_cardinality (
    role_id UUID PRIMARY KEY REFERENCES morbac.roles(id) ON DELETE CASCADE,
    min_users INTEGER,
    max_users INTEGER,
    description TEXT,
    CHECK (min_users IS NULL OR min_users >= 0),
    CHECK (max_users IS NULL OR max_users >= 1),
    CHECK (min_users IS NULL OR max_users IS NULL OR max_users >= min_users)
);

COMMENT ON TABLE morbac.role_cardinality IS 'Cardinality constraints for roles (min/max number of users)';
COMMENT ON COLUMN morbac.role_cardinality.min_users IS 'Minimum number of users required for this role';
COMMENT ON COLUMN morbac.role_cardinality.max_users IS 'Maximum number of users allowed for this role';

-- =============================================================================
-- DERIVED ROLES
-- =============================================================================
-- Roles computed dynamically based on conditions rather than explicit assignment

CREATE TABLE morbac.derived_roles (
    role_id UUID PRIMARY KEY REFERENCES morbac.roles(id) ON DELETE CASCADE,
    condition_evaluator REGPROC NOT NULL,
    description TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

COMMENT ON TABLE morbac.derived_roles IS 'Roles computed dynamically based on conditions';
COMMENT ON COLUMN morbac.derived_roles.role_id IS 'Role that is derived';
COMMENT ON COLUMN morbac.derived_roles.condition_evaluator IS 'Function(user_id, org_id) returning boolean';

-- =============================================================================
-- ACTIVITIES
-- =============================================================================
-- Activities represent abstract actions in OrBAC
-- These are global abstractions (not org-scoped)

CREATE TABLE morbac.activities (
    name TEXT PRIMARY KEY,
    description TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

COMMENT ON TABLE morbac.activities IS 'Activities - abstract actions in OrBAC model (global)';
COMMENT ON COLUMN morbac.activities.name IS 'Activity name (unique, global)';

-- =============================================================================
-- ACTIVITY HIERARCHY
-- =============================================================================
-- Activities can inherit from other activities
-- e.g., "write" implies "read", "admin_delete" implies "delete"

CREATE TABLE morbac.activity_hierarchy (
    senior_activity TEXT NOT NULL REFERENCES morbac.activities(name) ON DELETE CASCADE,
    junior_activity TEXT NOT NULL REFERENCES morbac.activities(name) ON DELETE CASCADE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (senior_activity, junior_activity),
    CHECK (senior_activity != junior_activity)
);

CREATE INDEX idx_activity_hierarchy_senior ON morbac.activity_hierarchy(senior_activity);
CREATE INDEX idx_activity_hierarchy_junior ON morbac.activity_hierarchy(junior_activity);

COMMENT ON TABLE morbac.activity_hierarchy IS 'Activity hierarchy - senior activities imply junior activities';
COMMENT ON COLUMN morbac.activity_hierarchy.senior_activity IS 'Senior activity (implies junior)';
COMMENT ON COLUMN morbac.activity_hierarchy.junior_activity IS 'Junior activity (implied by senior)';

-- =============================================================================
-- VIEWS
-- =============================================================================
-- Views represent abstract object categories in OrBAC
-- These are global abstractions (not org-scoped)

CREATE TABLE morbac.views (
    name TEXT PRIMARY KEY,
    description TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

COMMENT ON TABLE morbac.views IS 'Views - abstract object categories in OrBAC model (global)';
COMMENT ON COLUMN morbac.views.name IS 'View name (unique, global)';

-- =============================================================================
-- VIEW HIERARCHY
-- =============================================================================
-- Views can inherit from other views
-- e.g., "confidential_documents" is a "documents", "admin_reports" is a "reports"

CREATE TABLE morbac.view_hierarchy (
    senior_view TEXT NOT NULL REFERENCES morbac.views(name) ON DELETE CASCADE,
    junior_view TEXT NOT NULL REFERENCES morbac.views(name) ON DELETE CASCADE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (senior_view, junior_view),
    CHECK (senior_view != junior_view)
);

CREATE INDEX idx_view_hierarchy_senior ON morbac.view_hierarchy(senior_view);
CREATE INDEX idx_view_hierarchy_junior ON morbac.view_hierarchy(junior_view);

COMMENT ON TABLE morbac.view_hierarchy IS 'View hierarchy - senior views inherit from junior views';
COMMENT ON COLUMN morbac.view_hierarchy.senior_view IS 'Senior view (more specific)';
COMMENT ON COLUMN morbac.view_hierarchy.junior_view IS 'Junior view (more general)';

-- =============================================================================
-- CONTEXTS
-- =============================================================================
-- Contexts represent conditions under which rules apply
-- Implemented as callable predicates (functions)

CREATE TABLE morbac.contexts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL UNIQUE,
    description TEXT,
    evaluator REGPROC NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_contexts_name ON morbac.contexts(name);

COMMENT ON TABLE morbac.contexts IS 'Contexts - conditions under which rules apply (callable predicates)';
COMMENT ON COLUMN morbac.contexts.name IS 'Context name (unique)';
COMMENT ON COLUMN morbac.contexts.evaluator IS 'Function that evaluates this context (returns boolean)';

-- =============================================================================
-- DEFAULT CONTEXT: ALWAYS
-- =============================================================================
-- Create a default context that always evaluates to true

CREATE OR REPLACE FUNCTION morbac.context_always()
RETURNS BOOLEAN
LANGUAGE plpgsql
STABLE
AS $$
BEGIN
    RETURN TRUE;
END;
$$;

COMMENT ON FUNCTION morbac.context_always() IS 'Default context evaluator - always returns true';

-- Insert the default 'always' context
INSERT INTO morbac.contexts (name, description, evaluator)
VALUES (
    'always',
    'Default context - always evaluates to true',
    'morbac.context_always'::regproc
);

-- =============================================================================
-- RULES (Core OrBAC Policy)
-- =============================================================================
-- Implements the OrBAC rule relation:
-- Rule(org, role, activity, view, context, modality)
--
-- Represents: Permission, Prohibition, Obligation, or Recommendation

CREATE TABLE morbac.rules (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    org_id UUID NOT NULL REFERENCES morbac.orgs(id) ON DELETE CASCADE,
    role_id UUID NOT NULL REFERENCES morbac.roles(id) ON DELETE CASCADE,
    activity TEXT NOT NULL REFERENCES morbac.activities(name) ON DELETE CASCADE,
    view TEXT NOT NULL REFERENCES morbac.views(name) ON DELETE CASCADE,
    context_id UUID NOT NULL REFERENCES morbac.contexts(id) ON DELETE CASCADE,
    modality morbac.modality NOT NULL,
    valid_from TIMESTAMPTZ,
    valid_until TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    metadata JSONB DEFAULT '{}'::jsonb,
    UNIQUE(org_id, role_id, activity, view, context_id, modality),
    CHECK (valid_until IS NULL OR valid_from IS NULL OR valid_until > valid_from)
);

CREATE INDEX idx_rules_org_role ON morbac.rules(org_id, role_id);
CREATE INDEX idx_rules_activity_view ON morbac.rules(activity, view);
CREATE INDEX idx_rules_modality ON morbac.rules(modality);
CREATE INDEX idx_rules_lookup ON morbac.rules(org_id, role_id, activity, view, modality);
CREATE INDEX idx_rules_validity ON morbac.rules(valid_from, valid_until);
-- Performance: Fast lookup for active rules during authorization
CREATE INDEX idx_rules_fast_lookup ON morbac.rules(org_id, modality, activity, view)
INCLUDE (role_id, context_id)
WHERE (valid_from IS NULL OR valid_from <= CURRENT_TIMESTAMP)
  AND (valid_until IS NULL OR valid_until > CURRENT_TIMESTAMP);

COMMENT ON TABLE morbac.rules IS 'Core OrBAC rules - Permission, Prohibition, Obligation, Recommendation';
COMMENT ON COLUMN morbac.rules.org_id IS 'Organization scope';
COMMENT ON COLUMN morbac.rules.role_id IS 'Role this rule applies to';
COMMENT ON COLUMN morbac.rules.activity IS 'Activity (abstract action)';
COMMENT ON COLUMN morbac.rules.view IS 'View (abstract object category)';
COMMENT ON COLUMN morbac.rules.context_id IS 'Context condition';
COMMENT ON COLUMN morbac.rules.modality IS 'Deontic modality: permission, prohibition, obligation, recommendation';
COMMENT ON COLUMN morbac.rules.valid_from IS 'Optional: Rule valid from this timestamp';
COMMENT ON COLUMN morbac.rules.valid_until IS 'Optional: Rule valid until this timestamp';

-- Helper function to check if a rule is currently valid
CREATE OR REPLACE FUNCTION morbac.is_rule_valid(
    p_valid_from TIMESTAMPTZ,
    p_valid_until TIMESTAMPTZ
)
RETURNS BOOLEAN
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    v_now TIMESTAMPTZ := CURRENT_TIMESTAMP;
BEGIN
    -- If no temporal constraints, rule is valid
    IF p_valid_from IS NULL AND p_valid_until IS NULL THEN
        RETURN TRUE;
    END IF;

    -- Check valid_from
    IF p_valid_from IS NOT NULL AND v_now < p_valid_from THEN
        RETURN FALSE;
    END IF;

    -- Check valid_until
    IF p_valid_until IS NOT NULL AND v_now >= p_valid_until THEN
        RETURN FALSE;
    END IF;

    RETURN TRUE;
END;
$$;

COMMENT ON FUNCTION morbac.is_rule_valid(TIMESTAMPTZ, TIMESTAMPTZ) IS
'Check if a rule is currently valid based on temporal constraints';

-- =============================================================================
-- INTER-ORGANIZATIONAL RULES
-- =============================================================================
-- Rules that apply across organizations (cross-org access)
-- Allows users from one org to access resources in another org

CREATE TABLE morbac.cross_org_rules (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    source_org_id UUID NOT NULL REFERENCES morbac.orgs(id) ON DELETE CASCADE,
    target_org_id UUID NOT NULL REFERENCES morbac.orgs(id) ON DELETE CASCADE,
    role_id UUID NOT NULL REFERENCES morbac.roles(id) ON DELETE CASCADE,
    activity TEXT NOT NULL REFERENCES morbac.activities(name) ON DELETE CASCADE,
    view TEXT NOT NULL REFERENCES morbac.views(name) ON DELETE CASCADE,
    context_id UUID NOT NULL REFERENCES morbac.contexts(id) ON DELETE CASCADE,
    modality morbac.modality NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    valid_from TIMESTAMPTZ,
    valid_until TIMESTAMPTZ,
    metadata JSONB DEFAULT '{}'::jsonb,
    CHECK (source_org_id != target_org_id),
    CHECK (valid_until IS NULL OR valid_from IS NULL OR valid_until > valid_from),
    UNIQUE(source_org_id, target_org_id, role_id, activity, view, context_id, modality)
);

CREATE INDEX idx_cross_org_rules_source ON morbac.cross_org_rules(source_org_id, role_id);
CREATE INDEX idx_cross_org_rules_target ON morbac.cross_org_rules(target_org_id);
CREATE INDEX idx_cross_org_rules_temporal ON morbac.cross_org_rules(valid_from, valid_until);

COMMENT ON TABLE morbac.cross_org_rules IS 'Inter-organizational rules for cross-org access';
COMMENT ON COLUMN morbac.cross_org_rules.source_org_id IS 'Organization where user has role';
COMMENT ON COLUMN morbac.cross_org_rules.target_org_id IS 'Organization where resource resides';
COMMENT ON COLUMN morbac.cross_org_rules.valid_from IS 'Optional start time for rule validity';
COMMENT ON COLUMN morbac.cross_org_rules.valid_until IS 'Optional end time for rule validity';

-- =============================================================================
-- ADMINISTRATION RULES
-- =============================================================================
-- Meta-policies defining who can create/modify policies (AdministrationPermission)

CREATE TABLE morbac.admin_rules (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    org_id UUID NOT NULL REFERENCES morbac.orgs(id) ON DELETE CASCADE,
    role_id UUID NOT NULL REFERENCES morbac.roles(id) ON DELETE CASCADE,
    admin_activity TEXT NOT NULL,
    admin_target TEXT NOT NULL,
    context_id UUID NOT NULL REFERENCES morbac.contexts(id) ON DELETE CASCADE,
    modality morbac.modality NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    metadata JSONB DEFAULT '{}'::jsonb,
    UNIQUE(org_id, role_id, admin_activity, admin_target, context_id, modality)
);

CREATE INDEX idx_admin_rules_org_role ON morbac.admin_rules(org_id, role_id);

COMMENT ON TABLE morbac.admin_rules IS 'Administration rules - meta-policies for policy management';
COMMENT ON COLUMN morbac.admin_rules.admin_activity IS 'Admin action: create_rule, modify_rule, delete_rule, assign_role, etc.';
COMMENT ON COLUMN morbac.admin_rules.admin_target IS 'What can be administered: rules, roles, users, orgs, etc.';

-- =============================================================================
-- AUDIT LOG
-- =============================================================================
-- Optional audit logging for tracking changes to security-critical tables
-- Enable/disable per table with triggers

CREATE TABLE morbac.audit_log (
    id BIGSERIAL PRIMARY KEY,
    timestamp TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    user_id UUID,
    org_id UUID,
    table_name TEXT NOT NULL,
    operation TEXT NOT NULL,
    record_id UUID,
    old_data JSONB,
    new_data JSONB,
    changed_fields TEXT[],
    session_user TEXT DEFAULT SESSION_USER,
    client_addr INET DEFAULT INET_CLIENT_ADDR(),
    application_name TEXT DEFAULT CURRENT_SETTING('application_name', true),
    metadata JSONB DEFAULT '{}'::jsonb
);

CREATE INDEX idx_audit_log_timestamp ON morbac.audit_log(timestamp DESC);
CREATE INDEX idx_audit_log_user_id ON morbac.audit_log(user_id);
CREATE INDEX idx_audit_log_org_id ON morbac.audit_log(org_id);
CREATE INDEX idx_audit_log_table_operation ON morbac.audit_log(table_name, operation);
CREATE INDEX idx_audit_log_record_id ON morbac.audit_log(record_id);

COMMENT ON TABLE morbac.audit_log IS 'Audit trail for security-critical operations';
COMMENT ON COLUMN morbac.audit_log.user_id IS 'Application user (from morbac.current_user_id() if available)';
COMMENT ON COLUMN morbac.audit_log.org_id IS 'Organization context (from morbac.current_org_id() if available)';
COMMENT ON COLUMN morbac.audit_log.operation IS 'INSERT, UPDATE, DELETE, or custom operation name';
COMMENT ON COLUMN morbac.audit_log.changed_fields IS 'Array of field names that changed (for UPDATE operations)';
COMMENT ON COLUMN morbac.audit_log.session_user IS 'Database session user';
COMMENT ON COLUMN morbac.audit_log.client_addr IS 'Client IP address';

-- Generic audit trigger function
CREATE OR REPLACE FUNCTION morbac.audit_trigger()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_old_data JSONB;
    v_new_data JSONB;
    v_changed_fields TEXT[];
    v_user_id UUID;
    v_org_id UUID;
    v_record_id UUID;
BEGIN
    -- Try to get current user/org context
    BEGIN
        v_user_id := morbac.current_user_id();
    EXCEPTION WHEN OTHERS THEN
        v_user_id := NULL;
    END;

    BEGIN
        v_org_id := morbac.current_org_id();
    EXCEPTION WHEN OTHERS THEN
        v_org_id := NULL;
    END;

    -- Handle different operations
    IF TG_OP = 'DELETE' THEN
        v_old_data := row_to_json(OLD)::jsonb;
        v_new_data := NULL;
        v_record_id := (v_old_data->>'id')::uuid;
    ELSIF TG_OP = 'INSERT' THEN
        v_old_data := NULL;
        v_new_data := row_to_json(NEW)::jsonb;
        v_record_id := (v_new_data->>'id')::uuid;
    ELSIF TG_OP = 'UPDATE' THEN
        v_old_data := row_to_json(OLD)::jsonb;
        v_new_data := row_to_json(NEW)::jsonb;
        v_record_id := (v_new_data->>'id')::uuid;

        -- Identify changed fields
        SELECT array_agg(key)
        INTO v_changed_fields
        FROM jsonb_each(v_old_data)
        WHERE v_old_data->key IS DISTINCT FROM v_new_data->key;
    END IF;

    -- Override org_id from record if available
    IF v_org_id IS NULL THEN
        IF v_new_data ? 'org_id' THEN
            v_org_id := (v_new_data->>'org_id')::uuid;
        ELSIF v_old_data ? 'org_id' THEN
            v_org_id := (v_old_data->>'org_id')::uuid;
        END IF;
    END IF;

    -- Insert audit record
    INSERT INTO morbac.audit_log (
        user_id,
        org_id,
        table_name,
        operation,
        record_id,
        old_data,
        new_data,
        changed_fields
    ) VALUES (
        v_user_id,
        v_org_id,
        TG_TABLE_NAME,
        TG_OP,
        v_record_id,
        v_old_data,
        v_new_data,
        v_changed_fields
    );

    -- Return appropriate value
    IF TG_OP = 'DELETE' THEN
        RETURN OLD;
    ELSE
        RETURN NEW;
    END IF;
END;
$$;

COMMENT ON FUNCTION morbac.audit_trigger() IS
'Generic audit trigger function - captures INSERT/UPDATE/DELETE operations';

-- Helper function to enable audit logging on a table
CREATE OR REPLACE FUNCTION morbac.enable_audit(p_table_name TEXT)
RETURNS VOID
LANGUAGE plpgsql
AS $$
DECLARE
    v_trigger_name TEXT;
BEGIN
    v_trigger_name := 'audit_' || p_table_name;

    EXECUTE format(
        'CREATE TRIGGER %I AFTER INSERT OR UPDATE OR DELETE ON morbac.%I ' ||
        'FOR EACH ROW EXECUTE FUNCTION morbac.audit_trigger()',
        v_trigger_name,
        p_table_name
    );

    RAISE NOTICE 'Audit logging enabled for morbac.%', p_table_name;
END;
$$;

COMMENT ON FUNCTION morbac.enable_audit(TEXT) IS
'Enable audit logging on a morbac table - creates audit trigger';

-- Helper function to disable audit logging on a table
CREATE OR REPLACE FUNCTION morbac.disable_audit(p_table_name TEXT)
RETURNS VOID
LANGUAGE plpgsql
AS $$
DECLARE
    v_trigger_name TEXT;
BEGIN
    v_trigger_name := 'audit_' || p_table_name;

    EXECUTE format(
        'DROP TRIGGER IF EXISTS %I ON morbac.%I',
        v_trigger_name,
        p_table_name
    );

    RAISE NOTICE 'Audit logging disabled for morbac.%', p_table_name;
END;
$$;

COMMENT ON FUNCTION morbac.disable_audit(TEXT) IS
'Disable audit logging on a morbac table - removes audit trigger';

-- =============================================================================
-- HIERARCHY FUNCTIONS
-- =============================================================================
-- Functions to compute transitive closures for organization and role hierarchies

-- Get all ancestor organizations (including self)
CREATE OR REPLACE FUNCTION morbac.get_org_ancestors(p_org_id UUID)
RETURNS TABLE(org_id UUID, depth INTEGER)
LANGUAGE plpgsql
STABLE
AS $$
BEGIN
    RETURN QUERY
    WITH RECURSIVE org_ancestors AS (
        -- Base case: the organization itself
        SELECT p_org_id AS org_id, 0 AS depth
        UNION
        -- Recursive case: parent organizations
        SELECT o.parent_id, oa.depth + 1
        FROM org_ancestors oa
        INNER JOIN morbac.orgs o ON o.id = oa.org_id
        WHERE o.parent_id IS NOT NULL
    )
    SELECT * FROM org_ancestors;
END;
$$;

COMMENT ON FUNCTION morbac.get_org_ancestors(UUID) IS
'Returns all ancestor organizations (including self) with depth in hierarchy';

-- Get all descendant organizations (including self)
CREATE OR REPLACE FUNCTION morbac.get_org_descendants(p_org_id UUID)
RETURNS TABLE(org_id UUID, depth INTEGER)
LANGUAGE plpgsql
STABLE
AS $$
BEGIN
    RETURN QUERY
    WITH RECURSIVE org_descendants AS (
        -- Base case: the organization itself
        SELECT p_org_id AS org_id, 0 AS depth
        UNION
        -- Recursive case: child organizations
        SELECT o.id, od.depth + 1
        FROM org_descendants od
        INNER JOIN morbac.orgs o ON o.parent_id = od.org_id
    )
    SELECT * FROM org_descendants;
END;
$$;

COMMENT ON FUNCTION morbac.get_org_descendants(UUID) IS
'Returns all descendant organizations (including self) with depth in hierarchy';

-- Get all roles a user effectively has (direct + inherited via role hierarchy)
CREATE OR REPLACE FUNCTION morbac.get_effective_roles(p_user_id UUID, p_org_id UUID)
RETURNS TABLE(role_id UUID, depth INTEGER)
LANGUAGE plpgsql
STABLE
AS $$
BEGIN
    RETURN QUERY
    WITH RECURSIVE effective_roles AS (
        -- Base case: directly assigned roles
        SELECT ur.role_id, 0 AS depth
        FROM morbac.user_roles ur
        WHERE ur.user_id = p_user_id
          AND ur.org_id = p_org_id
        UNION
        -- Recursive case: senior roles (roles that inherit from assigned roles)
        SELECT rh.senior_role_id, er.depth + 1
        FROM effective_roles er
        INNER JOIN morbac.role_hierarchy rh ON rh.junior_role_id = er.role_id
    )
    SELECT DISTINCT ON (role_id) role_id, depth
    FROM effective_roles
    ORDER BY role_id, depth;
END;
$$;

COMMENT ON FUNCTION morbac.get_effective_roles(UUID, UUID) IS
'Returns all effective roles for a user in an organization (direct + inherited via role hierarchy)';

-- Get all roles inherited by a role (transitive closure)
CREATE OR REPLACE FUNCTION morbac.get_inherited_roles(p_role_id UUID)
RETURNS TABLE(role_id UUID, depth INTEGER)
LANGUAGE plpgsql
STABLE
AS $$
BEGIN
    RETURN QUERY
    WITH RECURSIVE inherited_roles AS (
        -- Base case: the role itself
        SELECT p_role_id AS role_id, 0 AS depth
        UNION
        -- Recursive case: junior roles
        SELECT rh.junior_role_id, ir.depth + 1
        FROM inherited_roles ir
        INNER JOIN morbac.role_hierarchy rh ON rh.senior_role_id = ir.role_id
    )
    SELECT DISTINCT ON (role_id) role_id, depth
    FROM inherited_roles
    ORDER BY role_id, depth;
END;
$$;

COMMENT ON FUNCTION morbac.get_inherited_roles(UUID) IS
'Returns all roles inherited by a role (transitive closure via role hierarchy)';

-- Get all effective activities (including inherited via activity hierarchy)
CREATE OR REPLACE FUNCTION morbac.get_effective_activities(p_activity TEXT)
RETURNS TABLE(activity TEXT, depth INTEGER)
LANGUAGE plpgsql
STABLE
AS $$
BEGIN
    RETURN QUERY
    WITH RECURSIVE effective_activities AS (
        -- Base case: the activity itself
        SELECT p_activity AS activity, 0 AS depth
        UNION
        -- Recursive case: junior activities (implied activities)
        SELECT ah.junior_activity, ea.depth + 1
        FROM effective_activities ea
        INNER JOIN morbac.activity_hierarchy ah ON ah.senior_activity = ea.activity
    )
    SELECT DISTINCT ON (activity) activity, depth
    FROM effective_activities
    ORDER BY activity, depth;
END;
$$;

COMMENT ON FUNCTION morbac.get_effective_activities(TEXT) IS
'Returns all activities including those implied via activity hierarchy (e.g., write implies read)';

-- Get all effective views (including inherited via view hierarchy)
CREATE OR REPLACE FUNCTION morbac.get_effective_views(p_view TEXT)
RETURNS TABLE(view TEXT, depth INTEGER)
LANGUAGE plpgsql
STABLE
AS $$
BEGIN
    RETURN QUERY
    WITH RECURSIVE effective_views AS (
        -- Base case: the view itself
        SELECT p_view AS view, 0 AS depth
        UNION
        -- Recursive case: junior views (more general categories)
        SELECT vh.junior_view, ev.depth + 1
        FROM effective_views ev
        INNER JOIN morbac.view_hierarchy vh ON vh.senior_view = ev.view
    )
    SELECT DISTINCT ON (view) view, depth
    FROM effective_views
    ORDER BY view, depth;
END;
$$;

COMMENT ON FUNCTION morbac.get_effective_views(TEXT) IS
'Returns all views including parent categories via view hierarchy';

-- Get comprehensive effective roles including delegation and derived roles
CREATE OR REPLACE FUNCTION morbac.get_comprehensive_roles(p_user_id UUID, p_org_id UUID)
RETURNS TABLE(role_id UUID, source TEXT, depth INTEGER)
LANGUAGE plpgsql
STABLE
AS $$
BEGIN
    RETURN QUERY
    WITH RECURSIVE effective_roles AS (
        -- Direct role assignments
        SELECT ur.role_id, 'direct'::TEXT as source, 0 AS depth
        FROM morbac.user_roles ur
        WHERE ur.user_id = p_user_id
          AND ur.org_id = p_org_id
          -- Check not negatively assigned
          AND NOT EXISTS (
              SELECT 1 FROM morbac.negative_role_assignments nra
              WHERE nra.user_id = p_user_id
                AND nra.role_id = ur.role_id
                AND nra.org_id = p_org_id
          )

        UNION

        -- Delegated roles (active and not revoked)
        SELECT d.role_id, 'delegation'::TEXT, 0 AS depth
        FROM morbac.delegations d
        WHERE d.delegatee_id = p_user_id
          AND d.org_id = p_org_id
          AND NOT d.revoked
          AND now() BETWEEN d.valid_from AND d.valid_until
          -- Check delegator has the role
          AND EXISTS (
              SELECT 1 FROM morbac.user_roles ur
              WHERE ur.user_id = d.delegator_id
                AND ur.role_id = d.role_id
                AND ur.org_id = d.org_id
          )
          -- Check not negatively assigned to delegatee
          AND NOT EXISTS (
              SELECT 1 FROM morbac.negative_role_assignments nra
              WHERE nra.user_id = p_user_id
                AND nra.role_id = d.role_id
                AND nra.org_id = p_org_id
          )

        UNION

        -- Derived roles (computed dynamically)
        -- Note: derived roles are evaluated separately due to EXECUTE limitations
        -- Use morbac.check_derived_role() helper

        UNION

        -- Role hierarchy (senior roles)
        SELECT rh.senior_role_id, er.source || '_inherited', er.depth + 1
        FROM effective_roles er
        INNER JOIN morbac.role_hierarchy rh ON rh.junior_role_id = er.role_id
    )
    SELECT DISTINCT ON (role_id) role_id, source, depth
    FROM effective_roles
    WHERE role_id IS NOT NULL
    ORDER BY role_id, depth;

    -- Add derived roles separately
    RETURN QUERY
    SELECT dr.role_id, 'derived'::TEXT, 0
    FROM morbac.derived_roles dr
    INNER JOIN morbac.roles r ON r.id = dr.role_id
    WHERE r.org_id = p_org_id
      AND morbac.eval_derived_role(dr.condition_evaluator, p_user_id, p_org_id)
      AND NOT EXISTS (
          SELECT 1 FROM morbac.negative_role_assignments nra
          WHERE nra.user_id = p_user_id
            AND nra.role_id = dr.role_id
            AND nra.org_id = p_org_id
      );
END;
$$;

COMMENT ON FUNCTION morbac.get_comprehensive_roles(UUID, UUID) IS
'Returns all effective roles including direct, delegated, derived, and inherited via hierarchy';

-- Helper to evaluate derived role conditions
CREATE OR REPLACE FUNCTION morbac.eval_derived_role(
    p_evaluator REGPROC,
    p_user_id UUID,
    p_org_id UUID
)
RETURNS BOOLEAN
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    v_result BOOLEAN;
BEGIN
    EXECUTE format('SELECT %s(%L, %L)', p_evaluator::text, p_user_id, p_org_id) INTO v_result;
    RETURN COALESCE(v_result, FALSE);
EXCEPTION
    WHEN OTHERS THEN
        RETURN FALSE;
END;
$$;

COMMENT ON FUNCTION morbac.eval_derived_role(REGPROC, UUID, UUID) IS
'Evaluates a derived role condition function';

-- Get all roles inherited by a role (transitive closure)
CREATE OR REPLACE FUNCTION morbac.get_inherited_roles(p_role_id UUID)
RETURNS TABLE(role_id UUID, depth INTEGER)
LANGUAGE plpgsql
STABLE
AS $$
BEGIN
    RETURN QUERY
    WITH RECURSIVE inherited_roles AS (
        -- Base case: the role itself
        SELECT p_role_id AS role_id, 0 AS depth
        UNION
        -- Recursive case: junior roles
        SELECT rh.junior_role_id, ir.depth + 1
        FROM inherited_roles ir
        INNER JOIN morbac.role_hierarchy rh ON rh.senior_role_id = ir.role_id
    )
    SELECT DISTINCT ON (role_id) role_id, depth
    FROM inherited_roles
    ORDER BY role_id, depth;
END;
$$;

COMMENT ON FUNCTION morbac.get_inherited_roles(UUID) IS
'Returns all roles inherited by a role (transitive closure via role hierarchy)';

-- =============================================================================
-- PERFORMANCE: MATERIALIZED HIERARCHY VIEWS
-- =============================================================================
-- Precomputed transitive closures for hierarchies to avoid recursive CTEs on every request

-- Precomputed role hierarchy transitive closure
CREATE MATERIALIZED VIEW morbac.mv_role_closure AS
WITH RECURSIVE role_closure AS (
    SELECT id as senior_role_id, id as junior_role_id, 0 as depth
    FROM morbac.roles
    UNION
    SELECT rh.senior_role_id, rh.junior_role_id, 1 as depth
    FROM morbac.role_hierarchy rh
    UNION
    SELECT rc.senior_role_id, rh.junior_role_id, rc.depth + 1
    FROM role_closure rc
    INNER JOIN morbac.role_hierarchy rh ON rh.senior_role_id = rc.junior_role_id
    WHERE rc.depth < (SELECT value::integer FROM morbac.config WHERE key = 'hierarchy_max_depth')
)
SELECT DISTINCT senior_role_id, junior_role_id, MIN(depth) as depth
FROM role_closure
GROUP BY senior_role_id, junior_role_id;

CREATE UNIQUE INDEX idx_mv_role_closure ON morbac.mv_role_closure(senior_role_id, junior_role_id);
CREATE INDEX idx_mv_role_closure_junior ON morbac.mv_role_closure(junior_role_id);

COMMENT ON MATERIALIZED VIEW morbac.mv_role_closure IS
'Precomputed role hierarchy transitive closure - refresh after role hierarchy changes';

-- Precomputed org hierarchy transitive closure
CREATE MATERIALIZED VIEW morbac.mv_org_closure AS
WITH RECURSIVE org_closure AS (
    SELECT id as descendant_id, id as ancestor_id, 0 as depth
    FROM morbac.orgs
    UNION
    SELECT o.id, oc.ancestor_id, oc.depth + 1
    FROM morbac.orgs o
    INNER JOIN org_closure oc ON o.parent_id = oc.descendant_id
    WHERE oc.depth < (SELECT value::integer FROM morbac.config WHERE key = 'hierarchy_max_depth')
)
SELECT DISTINCT descendant_id, ancestor_id, MIN(depth) as depth
FROM org_closure
GROUP BY descendant_id, ancestor_id;

CREATE UNIQUE INDEX idx_mv_org_closure ON morbac.mv_org_closure(descendant_id, ancestor_id);
CREATE INDEX idx_mv_org_closure_ancestor ON morbac.mv_org_closure(ancestor_id);

COMMENT ON MATERIALIZED VIEW morbac.mv_org_closure IS
'Precomputed organization hierarchy transitive closure - refresh after org hierarchy changes';

-- Precomputed activity hierarchy
CREATE MATERIALIZED VIEW morbac.mv_activity_closure AS
WITH RECURSIVE activity_closure AS (
    SELECT name as senior_activity, name as junior_activity, 0 as depth
    FROM morbac.activities
    UNION
    SELECT ah.senior_activity, ah.junior_activity, 1 as depth
    FROM morbac.activity_hierarchy ah
    UNION
    SELECT ac.senior_activity, ah.junior_activity, ac.depth + 1
    FROM activity_closure ac
    INNER JOIN morbac.activity_hierarchy ah ON ah.senior_activity = ac.junior_activity
    WHERE ac.depth < (SELECT value::integer FROM morbac.config WHERE key = 'hierarchy_max_depth')
)
SELECT DISTINCT senior_activity, junior_activity, MIN(depth) as depth
FROM activity_closure
GROUP BY senior_activity, junior_activity;

CREATE UNIQUE INDEX idx_mv_activity_closure ON morbac.mv_activity_closure(senior_activity, junior_activity);
CREATE INDEX idx_mv_activity_closure_junior ON morbac.mv_activity_closure(junior_activity);

COMMENT ON MATERIALIZED VIEW morbac.mv_activity_closure IS
'Precomputed activity hierarchy transitive closure - refresh after activity hierarchy changes';

-- Precomputed view hierarchy
CREATE MATERIALIZED VIEW morbac.mv_view_closure AS
WITH RECURSIVE view_closure AS (
    SELECT name as senior_view, name as junior_view, 0 as depth
    FROM morbac.views
    UNION
    SELECT vh.senior_view, vh.junior_view, 1 as depth
    FROM morbac.view_hierarchy vh
    UNION
    SELECT vc.senior_view, vh.junior_view, vc.depth + 1
    FROM view_closure vc
    INNER JOIN morbac.view_hierarchy vh ON vh.senior_view = vc.junior_view
    WHERE vc.depth < (SELECT value::integer FROM morbac.config WHERE key = 'hierarchy_max_depth')
)
SELECT DISTINCT senior_view, junior_view, MIN(depth) as depth
FROM view_closure
GROUP BY senior_view, junior_view;

CREATE UNIQUE INDEX idx_mv_view_closure ON morbac.mv_view_closure(senior_view, junior_view);
CREATE INDEX idx_mv_view_closure_junior ON morbac.mv_view_closure(junior_view);

COMMENT ON MATERIALIZED VIEW morbac.mv_view_closure IS
'Precomputed view hierarchy transitive closure - refresh after view hierarchy changes';

-- Helper function to refresh all materialized views
CREATE OR REPLACE FUNCTION morbac.refresh_hierarchy_cache()
RETURNS VOID
LANGUAGE plpgsql
AS $$
BEGIN
    REFRESH MATERIALIZED VIEW CONCURRENTLY morbac.mv_role_closure;
    REFRESH MATERIALIZED VIEW CONCURRENTLY morbac.mv_org_closure;
    REFRESH MATERIALIZED VIEW CONCURRENTLY morbac.mv_activity_closure;
    REFRESH MATERIALIZED VIEW CONCURRENTLY morbac.mv_view_closure;
END;
$$;

COMMENT ON FUNCTION morbac.refresh_hierarchy_cache() IS
'Refresh all materialized hierarchy views - call after modifying hierarchies';

-- =============================================================================
-- VALIDATION FUNCTIONS
-- =============================================================================

-- Check if role assignment would violate Separation of Duty
CREATE OR REPLACE FUNCTION morbac.check_sod_violation(
    p_user_id UUID,
    p_role_id UUID,
    p_org_id UUID
)
RETURNS BOOLEAN
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    v_conflict_exists BOOLEAN;
BEGIN
    -- Check if user already has a conflicting role
    SELECT EXISTS (
        SELECT 1
        FROM morbac.user_roles ur
        INNER JOIN morbac.sod_conflicts sod ON (
            (sod.role_a_id = ur.role_id AND sod.role_b_id = p_role_id)
            OR (sod.role_b_id = ur.role_id AND sod.role_a_id = p_role_id)
        )
        WHERE ur.user_id = p_user_id
          AND ur.org_id = p_org_id
          AND sod.org_id = p_org_id
    ) INTO v_conflict_exists;

    RETURN v_conflict_exists;
END;
$$;

COMMENT ON FUNCTION morbac.check_sod_violation(UUID, UUID, UUID) IS
'Returns true if assigning role would violate Separation of Duty constraints';

-- Check if role assignment would violate cardinality constraints
CREATE OR REPLACE FUNCTION morbac.check_cardinality_violation(
    p_role_id UUID,
    p_adding BOOLEAN DEFAULT TRUE
)
RETURNS TEXT
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    v_current_count INTEGER;
    v_min_users INTEGER;
    v_max_users INTEGER;
BEGIN
    -- Get current user count and constraints
    SELECT
        COUNT(DISTINCT ur.user_id),
        rc.min_users,
        rc.max_users
    INTO v_current_count, v_min_users, v_max_users
    FROM morbac.user_roles ur
    LEFT JOIN morbac.role_cardinality rc ON rc.role_id = ur.role_id
    WHERE ur.role_id = p_role_id
    GROUP BY rc.min_users, rc.max_users;

    -- Check max constraint when adding
    IF p_adding AND v_max_users IS NOT NULL THEN
        IF v_current_count >= v_max_users THEN
            RETURN format('Maximum users (%s) reached for role', v_max_users);
        END IF;
    END IF;

    -- Check min constraint when removing
    IF NOT p_adding AND v_min_users IS NOT NULL THEN
        IF v_current_count <= v_min_users THEN
            RETURN format('Minimum users (%s) required for role', v_min_users);
        END IF;
    END IF;

    RETURN NULL; -- No violation
END;
$$;

COMMENT ON FUNCTION morbac.check_cardinality_violation(UUID, BOOLEAN) IS
'Returns error message if cardinality constraint would be violated, NULL otherwise';

-- =============================================================================
-- CONTEXT EVALUATION HELPER
-- =============================================================================
-- Evaluates a context by calling its evaluator function

CREATE OR REPLACE FUNCTION morbac.eval_context(p_context_id UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    v_evaluator REGPROC;
    v_result BOOLEAN;
BEGIN
    -- Get the evaluator function for this context
    SELECT evaluator INTO v_evaluator
    FROM morbac.contexts
    WHERE id = p_context_id;

    IF v_evaluator IS NULL THEN
        RAISE EXCEPTION 'Context % not found', p_context_id;
    END IF;

    -- Execute the evaluator function
    EXECUTE format('SELECT %s()', v_evaluator::text) INTO v_result;

    RETURN COALESCE(v_result, FALSE);
END;
$$;

COMMENT ON FUNCTION morbac.eval_context(UUID) IS 'Evaluates a context by calling its evaluator function';

-- =============================================================================
-- PERFORMANCE: AUTHORIZATION CACHE
-- =============================================================================
-- Cache authorization decisions to avoid repeated expensive computations
-- Cache TTL is configurable via morbac.config table (key: cache_ttl_seconds)

CREATE TABLE morbac.auth_cache (
    user_id UUID NOT NULL,
    org_id UUID NOT NULL,
    activity TEXT NOT NULL,
    view TEXT NOT NULL,
    allowed BOOLEAN NOT NULL,
    computed_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    expires_at TIMESTAMPTZ NOT NULL DEFAULT (CURRENT_TIMESTAMP + INTERVAL '5 minutes'),
    PRIMARY KEY (user_id, org_id, activity, view)
);

CREATE INDEX idx_auth_cache_expires ON morbac.auth_cache(expires_at);
CREATE INDEX idx_auth_cache_user_org ON morbac.auth_cache(user_id, org_id);

COMMENT ON TABLE morbac.auth_cache IS
'Authorization decision cache - expires after 5 minutes or when policies change';

-- Invalidate cache for user/org
CREATE OR REPLACE FUNCTION morbac.invalidate_cache(p_user_id UUID DEFAULT NULL, p_org_id UUID DEFAULT NULL)
RETURNS VOID
LANGUAGE plpgsql
AS $$
BEGIN
    IF p_user_id IS NOT NULL AND p_org_id IS NOT NULL THEN
        DELETE FROM morbac.auth_cache WHERE user_id = p_user_id AND org_id = p_org_id;
    ELSIF p_org_id IS NOT NULL THEN
        DELETE FROM morbac.auth_cache WHERE org_id = p_org_id;
    ELSIF p_user_id IS NOT NULL THEN
        DELETE FROM morbac.auth_cache WHERE user_id = p_user_id;
    ELSE
        DELETE FROM morbac.auth_cache;
    END IF;
END;
$$;

COMMENT ON FUNCTION morbac.invalidate_cache(UUID, UUID) IS
'Invalidate auth cache for specific user/org or all entries';

-- Auto cleanup expired cache entries
CREATE OR REPLACE FUNCTION morbac.cleanup_auth_cache()
RETURNS INTEGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_deleted INTEGER;
BEGIN
    DELETE FROM morbac.auth_cache WHERE expires_at < CURRENT_TIMESTAMP;
    GET DIAGNOSTICS v_deleted = ROW_COUNT;
    RETURN v_deleted;
END;
$$;

COMMENT ON FUNCTION morbac.cleanup_auth_cache() IS
'Remove expired cache entries - call periodically via cron';

-- Trigger to invalidate cache on rule changes
CREATE OR REPLACE FUNCTION morbac.invalidate_cache_on_change()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    -- Clear cache for affected org
    DELETE FROM morbac.auth_cache WHERE org_id = COALESCE(NEW.org_id, OLD.org_id);
    RETURN COALESCE(NEW, OLD);
END;
$$;

-- Attach cache invalidation triggers
CREATE TRIGGER trg_invalidate_cache_rules
AFTER INSERT OR UPDATE OR DELETE ON morbac.rules
FOR EACH ROW EXECUTE FUNCTION morbac.invalidate_cache_on_change();

CREATE TRIGGER trg_invalidate_cache_user_roles
AFTER INSERT OR UPDATE OR DELETE ON morbac.user_roles
FOR EACH ROW EXECUTE FUNCTION morbac.invalidate_cache_on_change();

CREATE TRIGGER trg_invalidate_cache_delegations
AFTER INSERT OR UPDATE OR DELETE ON morbac.delegations
FOR EACH ROW EXECUTE FUNCTION morbac.invalidate_cache_on_change();

CREATE TRIGGER trg_invalidate_cache_cross_org
AFTER INSERT OR UPDATE OR DELETE ON morbac.cross_org_rules
FOR EACH ROW EXECUTE FUNCTION morbac.invalidate_cache_on_change();

-- Trigger to refresh hierarchies when they change
CREATE OR REPLACE FUNCTION morbac.refresh_on_hierarchy_change()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    -- Refresh in background (this will block briefly but necessary)
    PERFORM morbac.refresh_hierarchy_cache();
    -- Also invalidate auth cache since hierarchies affect authorization
    DELETE FROM morbac.auth_cache;
    RETURN COALESCE(NEW, OLD);
END;
$$;

CREATE TRIGGER trg_refresh_role_hierarchy
AFTER INSERT OR UPDATE OR DELETE ON morbac.role_hierarchy
FOR EACH STATEMENT EXECUTE FUNCTION morbac.refresh_on_hierarchy_change();

CREATE TRIGGER trg_refresh_activity_hierarchy
AFTER INSERT OR UPDATE OR DELETE ON morbac.activity_hierarchy
FOR EACH STATEMENT EXECUTE FUNCTION morbac.refresh_on_hierarchy_change();

CREATE TRIGGER trg_refresh_view_hierarchy
AFTER INSERT OR UPDATE OR DELETE ON morbac.view_hierarchy
FOR EACH STATEMENT EXECUTE FUNCTION morbac.refresh_on_hierarchy_change();

-- =============================================================================
-- AUTHORIZATION DECISION FUNCTION (CRITICAL)
-- =============================================================================
-- Implements the canonical OrBAC authorization decision
--
-- Semantics (from Multi-OrBAC paper):
-- - Access is allowed if and only if:
--   1. At least one applicable permission exists
--   2. AND no applicable prohibition exists
-- - Prohibitions have precedence over permissions
-- - Contexts must be evaluated
-- - Default deny (no permission = deny)
-- - Obligations and recommendations do NOT affect authorization

CREATE OR REPLACE FUNCTION morbac.is_allowed_nocache(
    p_user_id UUID,
    p_org_id UUID,
    p_activity TEXT,
    p_view TEXT
)
RETURNS BOOLEAN
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    v_rule RECORD;
BEGIN
    -- STEP 1: Check for prohibitions first (prohibition precedence)
    -- If any applicable prohibition exists, deny immediately
    -- Checks:
    -- - Direct rules for (activity, view) combinations
    -- - Activity hierarchy (senior activities imply junior)
    -- - View hierarchy (senior views imply junior)
    -- - Comprehensive roles (direct, delegated, derived, inherited)
    -- - Temporal validity (if rule has time constraints)

    FOR v_rule IN
        SELECT r.context_id
        FROM morbac.rules r
        WHERE r.org_id = p_org_id
          AND r.modality = 'prohibition'
          -- Match activity or any senior activity in hierarchy
          AND r.activity IN (
              SELECT activity FROM morbac.get_effective_activities(p_activity)
          )
          -- Match view or any senior view in hierarchy
          AND r.view IN (
              SELECT view FROM morbac.get_effective_views(p_view)
          )
          -- Match comprehensive roles (direct, delegated, derived, inherited)
          AND r.role_id IN (
              SELECT role_id FROM morbac.get_comprehensive_roles(p_user_id, p_org_id)
          )
          -- Check temporal validity
          AND morbac.is_rule_valid(r.valid_from, r.valid_until)
    LOOP
        -- Evaluate context
        IF morbac.eval_context(v_rule.context_id) THEN
            -- Prohibition found - immediate deny (prohibition precedence)
            RETURN FALSE;
        END IF;
    END LOOP;

    -- STEP 2: Check cross-organizational prohibitions
    FOR v_rule IN
        SELECT cr.context_id
        FROM morbac.cross_org_rules cr
        WHERE cr.target_org_id = p_org_id
          AND cr.modality = 'prohibition'
          AND cr.activity IN (SELECT activity FROM morbac.get_effective_activities(p_activity))
          AND cr.view IN (SELECT view FROM morbac.get_effective_views(p_view))
          -- User has role in source org
          AND cr.role_id IN (
              SELECT role_id FROM morbac.get_comprehensive_roles(p_user_id, cr.source_org_id)
          )
          -- Check temporal validity
          AND morbac.is_rule_valid(cr.valid_from, cr.valid_until)
    LOOP
        IF morbac.eval_context(v_rule.context_id) THEN
            RETURN FALSE;
        END IF;
    END LOOP;

    -- STEP 3: No prohibitions found, check for permissions
    FOR v_rule IN
        SELECT r.context_id
        FROM morbac.rules r
        WHERE r.org_id = p_org_id
          AND r.modality = 'permission'
          -- Match activity or any senior activity in hierarchy
          AND r.activity IN (
              SELECT activity FROM morbac.get_effective_activities(p_activity)
          )
          -- Match view or any senior view in hierarchy
          AND r.view IN (
              SELECT view FROM morbac.get_effective_views(p_view)
          )
          -- Match comprehensive roles
          AND r.role_id IN (
              SELECT role_id FROM morbac.get_comprehensive_roles(p_user_id, p_org_id)
          )
          -- Check temporal validity
          AND morbac.is_rule_valid(r.valid_from, r.valid_until)
    LOOP
        -- Evaluate context
        IF morbac.eval_context(v_rule.context_id) THEN
            -- Permission found and no prohibition - allow
            RETURN TRUE;
        END IF;
    END LOOP;

    -- STEP 4: Check cross-organizational permissions
    FOR v_rule IN
        SELECT cr.context_id
        FROM morbac.cross_org_rules cr
        WHERE cr.target_org_id = p_org_id
          AND cr.modality = 'permission'
          AND cr.activity IN (SELECT activity FROM morbac.get_effective_activities(p_activity))
          AND cr.view IN (SELECT view FROM morbac.get_effective_views(p_view))
          AND cr.role_id IN (
              SELECT role_id FROM morbac.get_comprehensive_roles(p_user_id, cr.source_org_id)
          )
          -- Check temporal validity
          AND morbac.is_rule_valid(cr.valid_from, cr.valid_until)
    LOOP
        IF morbac.eval_context(v_rule.context_id) THEN
            RETURN TRUE;
        END IF;
    END LOOP;

    -- No permission found - deny (default deny)
    RETURN FALSE;
END;
$$;

COMMENT ON FUNCTION morbac.is_allowed_nocache(UUID, UUID, TEXT, TEXT) IS
'Authorization without cache - use for debugging or when cache must be bypassed';

-- Cached authorization check (default, recommended for production use)
CREATE OR REPLACE FUNCTION morbac.is_allowed(
    p_user_id UUID,
    p_org_id UUID,
    p_activity TEXT,
    p_view TEXT
)
RETURNS BOOLEAN
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    v_cached_result BOOLEAN;
    v_computed_result BOOLEAN;
    v_expires_at TIMESTAMPTZ;
BEGIN
    -- Try cache first
    SELECT allowed, expires_at INTO v_cached_result, v_expires_at
    FROM morbac.auth_cache
    WHERE user_id = p_user_id
      AND org_id = p_org_id
      AND activity = p_activity
      AND view = p_view
      AND expires_at > CURRENT_TIMESTAMP;

    IF FOUND THEN
        RETURN v_cached_result;
    END IF;

    -- Cache miss - compute authorization
    v_computed_result := morbac.is_allowed_nocache(p_user_id, p_org_id, p_activity, p_view);

    -- Store in cache (TTL from config)
    INSERT INTO morbac.auth_cache (user_id, org_id, activity, view, allowed, expires_at)
    VALUES (
        p_user_id,
        p_org_id,
        p_activity,
        p_view,
        v_computed_result,
        CURRENT_TIMESTAMP + make_interval(secs => morbac.get_config('cache_ttl_seconds')::integer)
    )
    ON CONFLICT (user_id, org_id, activity, view) DO UPDATE
    SET allowed = v_computed_result,
        computed_at = CURRENT_TIMESTAMP,
        expires_at = CURRENT_TIMESTAMP + make_interval(secs => morbac.get_config('cache_ttl_seconds')::integer);

    RETURN v_computed_result;
END;
$$;

COMMENT ON FUNCTION morbac.is_allowed(UUID, UUID, TEXT, TEXT) IS
'Complete OrBAC authorization with caching (default) - use is_allowed_nocache() for debugging';

-- =============================================================================
-- POLICY DSL TABLE
-- =============================================================================
-- Simplified table for developers to declare policy
-- Uses friendly names instead of UUIDs

CREATE TABLE morbac.policy (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    org_name TEXT NOT NULL,
    role_name TEXT NOT NULL,
    activity TEXT NOT NULL,
    view TEXT NOT NULL,
    modality morbac.modality NOT NULL,
    context_name TEXT NOT NULL DEFAULT 'always',
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    compiled BOOLEAN NOT NULL DEFAULT FALSE,
    UNIQUE(org_name, role_name, activity, view, modality, context_name)
);

CREATE INDEX idx_policy_not_compiled ON morbac.policy(compiled) WHERE NOT compiled;

COMMENT ON TABLE morbac.policy IS 'Policy DSL - simplified policy declaration using names';
COMMENT ON COLUMN morbac.policy.org_name IS 'Organization name (resolved during compilation)';
COMMENT ON COLUMN morbac.policy.role_name IS 'Role name (resolved during compilation)';
COMMENT ON COLUMN morbac.policy.activity IS 'Activity name';
COMMENT ON COLUMN morbac.policy.view IS 'View name';
COMMENT ON COLUMN morbac.policy.modality IS 'Deontic modality';
COMMENT ON COLUMN morbac.policy.context_name IS 'Context name (default: always)';
COMMENT ON COLUMN morbac.policy.compiled IS 'Whether this policy entry has been compiled into rules';

-- Helper function to check administration permissions
CREATE OR REPLACE FUNCTION morbac.is_admin_allowed(
    p_user_id UUID,
    p_org_id UUID,
    p_admin_activity TEXT,
    p_admin_target TEXT
)
RETURNS BOOLEAN
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    v_rule RECORD;
BEGIN
    -- Check for admin prohibitions first
    FOR v_rule IN
        SELECT ar.context_id
        FROM morbac.admin_rules ar
        WHERE ar.org_id = p_org_id
          AND ar.admin_activity = p_admin_activity
          AND ar.admin_target = p_admin_target
          AND ar.modality = 'prohibition'
          AND ar.role_id IN (
              SELECT role_id FROM morbac.get_comprehensive_roles(p_user_id, p_org_id)
          )
    LOOP
        IF morbac.eval_context(v_rule.context_id) THEN
            RETURN FALSE;
        END IF;
    END LOOP;

    -- Check for admin permissions
    FOR v_rule IN
        SELECT ar.context_id
        FROM morbac.admin_rules ar
        WHERE ar.org_id = p_org_id
          AND ar.admin_activity = p_admin_activity
          AND ar.admin_target = p_admin_target
          AND ar.modality = 'permission'
          AND ar.role_id IN (
              SELECT role_id FROM morbac.get_comprehensive_roles(p_user_id, p_org_id)
          )
    LOOP
        IF morbac.eval_context(v_rule.context_id) THEN
            RETURN TRUE;
        END IF;
    END LOOP;

    RETURN FALSE; -- Default deny
END;
$$;

COMMENT ON FUNCTION morbac.is_admin_allowed(UUID, UUID, TEXT, TEXT) IS
'Checks administration permissions for policy management operations';

-- =============================================================================
-- POLICY COMPILER
-- =============================================================================
-- Translates policy DSL entries into concrete rules
-- Resolves names to IDs
-- Idempotent - safe to run multiple times

CREATE OR REPLACE FUNCTION morbac.compile_policy()
RETURNS TABLE(
    compiled_count INTEGER,
    error_count INTEGER,
    errors TEXT[]
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_policy RECORD;
    v_org_id UUID;
    v_role_id UUID;
    v_context_id UUID;
    v_compiled INTEGER := 0;
    v_errors TEXT[] := ARRAY[]::TEXT[];
    v_error_count INTEGER := 0;
BEGIN
    -- Process all uncompiled policy entries
    FOR v_policy IN
        SELECT * FROM morbac.policy WHERE NOT compiled
    LOOP
        BEGIN
            -- Resolve organization
            SELECT id INTO STRICT v_org_id
            FROM morbac.orgs
            WHERE name = v_policy.org_name;

            -- Resolve role within organization
            SELECT id INTO STRICT v_role_id
            FROM morbac.roles
            WHERE org_id = v_org_id AND name = v_policy.role_name;

            -- Resolve context
            SELECT id INTO STRICT v_context_id
            FROM morbac.contexts
            WHERE name = v_policy.context_name;

            -- Ensure activity exists
            INSERT INTO morbac.activities (name)
            VALUES (v_policy.activity)
            ON CONFLICT (name) DO NOTHING;

            -- Ensure view exists
            INSERT INTO morbac.views (name)
            VALUES (v_policy.view)
            ON CONFLICT (name) DO NOTHING;

            -- Insert rule (ignore if already exists)
            INSERT INTO morbac.rules (org_id, role_id, activity, view, context_id, modality)
            VALUES (v_org_id, v_role_id, v_policy.activity, v_policy.view, v_context_id, v_policy.modality)
            ON CONFLICT (org_id, role_id, activity, view, context_id, modality) DO NOTHING;

            -- Mark as compiled
            UPDATE morbac.policy SET compiled = TRUE WHERE id = v_policy.id;

            v_compiled := v_compiled + 1;

        EXCEPTION WHEN OTHERS THEN
            v_error_count := v_error_count + 1;
            v_errors := array_append(v_errors,
                format('Policy %s: %s', v_policy.id, SQLERRM));
        END;
    END LOOP;

    RETURN QUERY SELECT v_compiled, v_error_count, v_errors;
END;
$$;

COMMENT ON FUNCTION morbac.compile_policy() IS
'Compiles policy DSL entries into concrete rules - idempotent and safe to run multiple times';

-- =============================================================================
-- RLS HELPER FUNCTIONS
-- =============================================================================
-- Helper functions for Row-Level Security policies
-- Compatible with PostgREST

-- Get current user ID from request header
CREATE OR REPLACE FUNCTION morbac.current_user_id()
RETURNS UUID
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    v_user_id TEXT;
BEGIN
    -- Read from PostgREST request.header.x-user-id setting
    v_user_id := current_setting('request.header.x-user-id', TRUE);

    IF v_user_id IS NULL OR v_user_id = '' THEN
        RETURN NULL;
    END IF;

    RETURN v_user_id::UUID;
EXCEPTION
    WHEN OTHERS THEN
        RETURN NULL;
END;
$$;

COMMENT ON FUNCTION morbac.current_user_id() IS
'Returns current user ID from request.header.x-user-id (PostgREST compatible)';

-- Get current organization ID from request header
CREATE OR REPLACE FUNCTION morbac.current_org_id()
RETURNS UUID
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    v_org_id TEXT;
BEGIN
    -- Read from PostgREST request.header.x-org-id setting
    v_org_id := current_setting('request.header.x-org-id', TRUE);

    IF v_org_id IS NULL OR v_org_id = '' THEN
        RETURN NULL;
    END IF;

    RETURN v_org_id::UUID;
EXCEPTION
    WHEN OTHERS THEN
        RETURN NULL;
END;
$$;

COMMENT ON FUNCTION morbac.current_org_id() IS
'Returns current organization ID from request.header.x-org-id (PostgREST compatible)';

-- RLS check function
CREATE OR REPLACE FUNCTION morbac.rls_check(
    p_activity TEXT,
    p_view TEXT
)
RETURNS BOOLEAN
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    v_user_id UUID;
    v_org_id UUID;
BEGIN
    v_user_id := morbac.current_user_id();
    v_org_id := morbac.current_org_id();

    -- If no user or org context, deny
    IF v_user_id IS NULL OR v_org_id IS NULL THEN
        RETURN FALSE;
    END IF;

    -- Call cached authorization decision function (default behavior)
    RETURN morbac.is_allowed(v_user_id, v_org_id, p_activity, p_view);
END;
$$;

COMMENT ON FUNCTION morbac.rls_check(TEXT, TEXT) IS
'RLS helper: checks if current user is allowed to perform activity on view in current org';

-- =============================================================================
-- OBLIGATIONS AND RECOMMENDATIONS
-- =============================================================================
-- Obligations and recommendations do NOT affect authorization
-- They are queryable for informational purposes

-- Pending obligations for a user in an organization
CREATE OR REPLACE FUNCTION morbac.pending_obligations(
    p_user_id UUID,
    p_org_id UUID
)
RETURNS TABLE(
    rule_id UUID,
    role_name TEXT,
    activity TEXT,
    view TEXT,
    context_name TEXT,
    created_at TIMESTAMPTZ
)
LANGUAGE plpgsql
STABLE
AS $$
BEGIN
    RETURN QUERY
    SELECT
        r.id,
        ro.name,
        r.activity,
        r.view,
        c.name,
        r.created_at
    FROM morbac.rules r
    INNER JOIN morbac.user_roles ur ON ur.role_id = r.role_id
    INNER JOIN morbac.roles ro ON ro.id = r.role_id
    INNER JOIN morbac.contexts c ON c.id = r.context_id
    WHERE ur.user_id = p_user_id
      AND r.org_id = p_org_id
      AND ur.org_id = p_org_id
      AND r.modality = 'obligation'
      AND morbac.eval_context(r.context_id) = TRUE
    ORDER BY r.created_at;
END;
$$;

COMMENT ON FUNCTION morbac.pending_obligations(UUID, UUID) IS
'Returns pending obligations for a user in an organization (informational only)';

-- Recommendations for a user in an organization
CREATE OR REPLACE FUNCTION morbac.pending_recommendations(
    p_user_id UUID,
    p_org_id UUID
)
RETURNS TABLE(
    rule_id UUID,
    role_name TEXT,
    activity TEXT,
    view TEXT,
    context_name TEXT,
    created_at TIMESTAMPTZ
)
LANGUAGE plpgsql
STABLE
AS $$
BEGIN
    RETURN QUERY
    SELECT
        r.id,
        ro.name,
        r.activity,
        r.view,
        c.name,
        r.created_at
    FROM morbac.rules r
    INNER JOIN morbac.user_roles ur ON ur.role_id = r.role_id
    INNER JOIN morbac.roles ro ON ro.id = r.role_id
    INNER JOIN morbac.contexts c ON c.id = r.context_id
    WHERE ur.user_id = p_user_id
      AND r.org_id = p_org_id
      AND ur.org_id = p_org_id
      AND r.modality = 'recommendation'
      AND morbac.eval_context(r.context_id) = TRUE
    ORDER BY r.created_at;
END;
$$;

COMMENT ON FUNCTION morbac.pending_recommendations(UUID, UUID) IS
'Returns recommendations for a user in an organization (informational only)';

-- =============================================================================
-- OBLIGATIONS FUNCTIONS
-- =============================================================================

-- Get all roles for a user in an organization
CREATE OR REPLACE FUNCTION morbac.user_roles_in_org(
    p_user_id UUID,
    p_org_id UUID
)
RETURNS TABLE(
    role_id UUID,
    role_name TEXT
)
LANGUAGE plpgsql
STABLE
AS $$
BEGIN
    RETURN QUERY
    SELECT r.id, r.name
    FROM morbac.roles r
    INNER JOIN morbac.user_roles ur ON ur.role_id = r.id
    WHERE ur.user_id = p_user_id
      AND ur.org_id = p_org_id
      AND r.org_id = p_org_id;
END;
$$;

COMMENT ON FUNCTION morbac.user_roles_in_org(UUID, UUID) IS
'Returns all roles for a user in an organization';

-- Check if user has specific role in organization
CREATE OR REPLACE FUNCTION morbac.user_has_role(
    p_user_id UUID,
    p_org_id UUID,
    p_role_name TEXT
)
RETURNS BOOLEAN
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    v_count INTEGER;
BEGIN
    SELECT COUNT(*) INTO v_count
    FROM morbac.roles r
    INNER JOIN morbac.user_roles ur ON ur.role_id = r.id
    WHERE ur.user_id = p_user_id
      AND ur.org_id = p_org_id
      AND r.org_id = p_org_id
      AND r.name = p_role_name;

    RETURN v_count > 0;
END;
$$;

COMMENT ON FUNCTION morbac.user_has_role(UUID, UUID, TEXT) IS
'Returns true if user has specific role in organization';

-- =============================================================================
-- ADMIN HELPER FUNCTIONS
-- =============================================================================

-- Helper: Check if user can assign/revoke roles
CREATE OR REPLACE FUNCTION morbac.can_manage_user_role(
    p_admin_user_id UUID,
    p_org_id UUID,
    p_target_role_id UUID
)
RETURNS BOOLEAN
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    v_role_name TEXT;
BEGIN
    -- Get role name
    SELECT name INTO v_role_name
    FROM morbac.roles
    WHERE id = p_target_role_id AND org_id = p_org_id;

    IF v_role_name IS NULL THEN
        RETURN FALSE;
    END IF;

    -- Check if admin has permission to manage this role
    RETURN morbac.is_admin_allowed(
        p_admin_user_id,
        p_org_id,
        'assign_role',
        v_role_name
    );
END;
$$;

COMMENT ON FUNCTION morbac.can_manage_user_role(UUID, UUID, UUID) IS
'Check if user can assign/revoke a specific role in organization';

-- Helper: Check if user can create/modify/delete roles
CREATE OR REPLACE FUNCTION morbac.can_manage_roles(
    p_user_id UUID,
    p_org_id UUID
)
RETURNS BOOLEAN
LANGUAGE plpgsql
STABLE
AS $$
BEGIN
    RETURN morbac.is_admin_allowed(
        p_user_id,
        p_org_id,
        'manage',
        'roles'
    );
END;
$$;

COMMENT ON FUNCTION morbac.can_manage_roles(UUID, UUID) IS
'Check if user can create/modify/delete roles in organization';

-- Helper: Check if user can manage policies
CREATE OR REPLACE FUNCTION morbac.can_manage_policies(
    p_user_id UUID,
    p_org_id UUID
)
RETURNS BOOLEAN
LANGUAGE plpgsql
STABLE
AS $$
BEGIN
    RETURN morbac.is_admin_allowed(
        p_user_id,
        p_org_id,
        'manage',
        'policies'
    );
END;
$$;

COMMENT ON FUNCTION morbac.can_manage_policies(UUID, UUID) IS
'Check if user can manage policies in organization';

-- Helper: Assign role to user (with permission check)
CREATE OR REPLACE FUNCTION morbac.admin_assign_role(
    p_admin_user_id UUID,
    p_target_user_id UUID,
    p_role_id UUID,
    p_org_id UUID
)
RETURNS BOOLEAN
LANGUAGE plpgsql
AS $$
BEGIN
    -- Check if admin has permission
    IF NOT morbac.can_manage_user_role(p_admin_user_id, p_org_id, p_role_id) THEN
        RAISE EXCEPTION 'User % does not have permission to assign role % in org %',
            p_admin_user_id, p_role_id, p_org_id;
    END IF;

    -- Check SoD violations
    IF array_length(morbac.check_sod_violation(p_target_user_id, p_org_id), 1) > 0 THEN
        RAISE EXCEPTION 'Role assignment would violate Separation of Duty constraints';
    END IF;

    -- Assign role
    INSERT INTO morbac.user_roles (user_id, role_id, org_id)
    VALUES (p_target_user_id, p_role_id, p_org_id)
    ON CONFLICT (user_id, role_id, org_id) DO NOTHING;

    -- Check cardinality after assignment
    DECLARE
        v_cardinality_error TEXT;
    BEGIN
        v_cardinality_error := morbac.check_cardinality_violation(p_role_id, p_org_id);
        IF v_cardinality_error IS NOT NULL THEN
            RAISE EXCEPTION 'Role assignment violates cardinality constraint: %', v_cardinality_error;
        END IF;
    END;

    RETURN TRUE;
END;
$$;

COMMENT ON FUNCTION morbac.admin_assign_role(UUID, UUID, UUID, UUID) IS
'Assign role to user with admin permission check and constraint validation';

-- Helper: Revoke role from user (with permission check)
CREATE OR REPLACE FUNCTION morbac.admin_revoke_role(
    p_admin_user_id UUID,
    p_target_user_id UUID,
    p_role_id UUID,
    p_org_id UUID
)
RETURNS BOOLEAN
LANGUAGE plpgsql
AS $$
BEGIN
    -- Check if admin has permission
    IF NOT morbac.can_manage_user_role(p_admin_user_id, p_org_id, p_role_id) THEN
        RAISE EXCEPTION 'User % does not have permission to revoke role % in org %',
            p_admin_user_id, p_role_id, p_org_id;
    END IF;

    -- Revoke role
    DELETE FROM morbac.user_roles
    WHERE user_id = p_target_user_id
      AND role_id = p_role_id
      AND org_id = p_org_id;

    -- Check cardinality after revocation
    DECLARE
        v_cardinality_error TEXT;
    BEGIN
        v_cardinality_error := morbac.check_cardinality_violation(p_role_id, p_org_id);
        IF v_cardinality_error IS NOT NULL THEN
            RAISE WARNING 'Role revocation may violate cardinality constraint: %', v_cardinality_error;
        END IF;
    END;

    RETURN TRUE;
END;
$$;

COMMENT ON FUNCTION morbac.admin_revoke_role(UUID, UUID, UUID, UUID) IS
'Revoke role from user with admin permission check';

-- =============================================================================
-- UTILITY RESOURCE PATTERN (GUIDANCE)
-- =============================================================================
--
-- For resources that belong to multiple organizations:
--
-- Create resource table (org-neutral):
--    CREATE TABLE app.documents (
--        id UUID PRIMARY KEY,
--        content TEXT,
--        ...
--    );
--
-- Create organization membership table:
--    CREATE TABLE app.document_orgs (
--        document_id UUID REFERENCES app.documents(id),
--        org_id UUID REFERENCES morbac.orgs(id),
--        PRIMARY KEY (document_id, org_id)
--    );
--
-- Apply RLS with multi-org support:
--    ALTER TABLE app.documents ENABLE ROW LEVEL SECURITY;
--
--    CREATE POLICY document_select ON app.documents
--    FOR SELECT
--    USING (
--        EXISTS (
--            SELECT 1 FROM app.document_orgs do
--            WHERE do.document_id = app.documents.id
--              AND do.org_id = morbac.current_org_id()
--        )
--        AND morbac.rls_check('read', 'documents')
--    );
--
-- This pattern allows a resource to be visible in multiple organizations
-- while enforcing OrBAC policy within each organization context.
--
-- =============================================================================

-- =============================================================================
-- INSTALLATION COMPLETE
-- =============================================================================

-- Grant usage on schema to public (adjust based on your security requirements)
-- GRANT USAGE ON SCHEMA morbac TO public;
-- GRANT SELECT ON ALL TABLES IN SCHEMA morbac TO public;
-- GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA morbac TO public;

-- For production, create specific roles and grant appropriate privileges
