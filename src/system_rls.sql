-- RLS policies for morbac system tables.
--
-- is_allowed() and its internal callees are SECURITY DEFINER, so they run as
-- the extension owner and bypass RLS. This prevents infinite recursion when
-- these policies fire.
--
-- View names used in rules are config-driven (system_view.*).
-- Override with morbac.set_config('system_view.orgs', 'my_orgs') etc.
-- The new name must exist in morbac.views and your rules must reference it.
--
-- RLS is disabled for the superuser/extension owner by default (PostgreSQL
-- behavior). Bootstrap the first organization and superuser role as the
-- database owner before enabling this in production.

-- morbac.orgs
-- Row's org context is the org itself.
ALTER TABLE morbac.orgs ENABLE ROW LEVEL SECURITY;

CREATE POLICY orgs_select ON morbac.orgs FOR SELECT
    USING (morbac.is_allowed(morbac.current_user_id(), id, 'read',
        morbac.get_config('system_view.orgs')));

CREATE POLICY orgs_insert ON morbac.orgs FOR INSERT
    WITH CHECK (morbac.is_allowed(morbac.current_user_id(), morbac.current_org_id(), 'create',
        morbac.get_config('system_view.orgs')));

CREATE POLICY orgs_update ON morbac.orgs FOR UPDATE
    USING (morbac.is_allowed(morbac.current_user_id(), id, 'update',
        morbac.get_config('system_view.orgs')));

CREATE POLICY orgs_delete ON morbac.orgs FOR DELETE
    USING (morbac.is_allowed(morbac.current_user_id(), id, 'delete',
        morbac.get_config('system_view.orgs')));

-- morbac.roles
ALTER TABLE morbac.roles ENABLE ROW LEVEL SECURITY;

CREATE POLICY roles_select ON morbac.roles FOR SELECT
    USING (morbac.is_allowed(morbac.current_user_id(), org_id, 'read',
        morbac.get_config('system_view.roles')));

CREATE POLICY roles_insert ON morbac.roles FOR INSERT
    WITH CHECK (morbac.is_allowed(morbac.current_user_id(), org_id, 'create',
        morbac.get_config('system_view.roles')));

CREATE POLICY roles_update ON morbac.roles FOR UPDATE
    USING (morbac.is_allowed(morbac.current_user_id(), org_id, 'update',
        morbac.get_config('system_view.roles')));

CREATE POLICY roles_delete ON morbac.roles FOR DELETE
    USING (morbac.is_allowed(morbac.current_user_id(), org_id, 'delete',
        morbac.get_config('system_view.roles')));

-- morbac.rules
ALTER TABLE morbac.rules ENABLE ROW LEVEL SECURITY;

CREATE POLICY rules_select ON morbac.rules FOR SELECT
    USING (morbac.is_allowed(morbac.current_user_id(), org_id, 'read',
        morbac.get_config('system_view.rules')));

CREATE POLICY rules_insert ON morbac.rules FOR INSERT
    WITH CHECK (morbac.is_allowed(morbac.current_user_id(), org_id, 'create',
        morbac.get_config('system_view.rules')));

CREATE POLICY rules_update ON morbac.rules FOR UPDATE
    USING (morbac.is_allowed(morbac.current_user_id(), org_id, 'update',
        morbac.get_config('system_view.rules')));

CREATE POLICY rules_delete ON morbac.rules FOR DELETE
    USING (morbac.is_allowed(morbac.current_user_id(), org_id, 'delete',
        morbac.get_config('system_view.rules')));

-- morbac.user_roles
ALTER TABLE morbac.user_roles ENABLE ROW LEVEL SECURITY;

CREATE POLICY user_roles_select ON morbac.user_roles FOR SELECT
    USING (morbac.is_allowed(morbac.current_user_id(), org_id, 'read',
        morbac.get_config('system_view.user_roles')));

CREATE POLICY user_roles_insert ON morbac.user_roles FOR INSERT
    WITH CHECK (morbac.is_allowed(morbac.current_user_id(), org_id, 'create',
        morbac.get_config('system_view.user_roles')));

CREATE POLICY user_roles_delete ON morbac.user_roles FOR DELETE
    USING (morbac.is_allowed(morbac.current_user_id(), org_id, 'delete',
        morbac.get_config('system_view.user_roles')));

-- morbac.contexts (global — use current session org for writes)
ALTER TABLE morbac.contexts ENABLE ROW LEVEL SECURITY;

CREATE POLICY contexts_select ON morbac.contexts FOR SELECT
    USING (morbac.is_allowed(morbac.current_user_id(), morbac.current_org_id(), 'read',
        morbac.get_config('system_view.contexts')));

CREATE POLICY contexts_insert ON morbac.contexts FOR INSERT
    WITH CHECK (morbac.is_allowed(morbac.current_user_id(), morbac.current_org_id(), 'create',
        morbac.get_config('system_view.contexts')));

CREATE POLICY contexts_update ON morbac.contexts FOR UPDATE
    USING (morbac.is_allowed(morbac.current_user_id(), morbac.current_org_id(), 'update',
        morbac.get_config('system_view.contexts')));

CREATE POLICY contexts_delete ON morbac.contexts FOR DELETE
    USING (morbac.is_allowed(morbac.current_user_id(), morbac.current_org_id(), 'delete',
        morbac.get_config('system_view.contexts')));

-- morbac.activities (global — use current session org for writes)
ALTER TABLE morbac.activities ENABLE ROW LEVEL SECURITY;

CREATE POLICY activities_select ON morbac.activities FOR SELECT
    USING (morbac.is_allowed(morbac.current_user_id(), morbac.current_org_id(), 'read',
        morbac.get_config('system_view.activities')));

CREATE POLICY activities_insert ON morbac.activities FOR INSERT
    WITH CHECK (morbac.is_allowed(morbac.current_user_id(), morbac.current_org_id(), 'create',
        morbac.get_config('system_view.activities')));

CREATE POLICY activities_update ON morbac.activities FOR UPDATE
    USING (morbac.is_allowed(morbac.current_user_id(), morbac.current_org_id(), 'update',
        morbac.get_config('system_view.activities')));

CREATE POLICY activities_delete ON morbac.activities FOR DELETE
    USING (morbac.is_allowed(morbac.current_user_id(), morbac.current_org_id(), 'delete',
        morbac.get_config('system_view.activities')));

-- morbac.views (global — use current session org for writes)
ALTER TABLE morbac.views ENABLE ROW LEVEL SECURITY;

CREATE POLICY views_select ON morbac.views FOR SELECT
    USING (morbac.is_allowed(morbac.current_user_id(), morbac.current_org_id(), 'read',
        morbac.get_config('system_view.views')));

CREATE POLICY views_insert ON morbac.views FOR INSERT
    WITH CHECK (morbac.is_allowed(morbac.current_user_id(), morbac.current_org_id(), 'create',
        morbac.get_config('system_view.views')));

CREATE POLICY views_update ON morbac.views FOR UPDATE
    USING (morbac.is_allowed(morbac.current_user_id(), morbac.current_org_id(), 'update',
        morbac.get_config('system_view.views')));

CREATE POLICY views_delete ON morbac.views FOR DELETE
    USING (morbac.is_allowed(morbac.current_user_id(), morbac.current_org_id(), 'delete',
        morbac.get_config('system_view.views')));

-- morbac.delegations
ALTER TABLE morbac.delegations ENABLE ROW LEVEL SECURITY;

CREATE POLICY delegations_select ON morbac.delegations FOR SELECT
    USING (morbac.is_allowed(morbac.current_user_id(), org_id, 'read',
        morbac.get_config('system_view.delegations')));

CREATE POLICY delegations_insert ON morbac.delegations FOR INSERT
    WITH CHECK (morbac.is_allowed(morbac.current_user_id(), org_id, 'create',
        morbac.get_config('system_view.delegations')));

CREATE POLICY delegations_update ON morbac.delegations FOR UPDATE
    USING (morbac.is_allowed(morbac.current_user_id(), org_id, 'update',
        morbac.get_config('system_view.delegations')));

CREATE POLICY delegations_delete ON morbac.delegations FOR DELETE
    USING (morbac.is_allowed(morbac.current_user_id(), org_id, 'delete',
        morbac.get_config('system_view.delegations')));

-- morbac.cross_org_rules
ALTER TABLE morbac.cross_org_rules ENABLE ROW LEVEL SECURITY;

CREATE POLICY cross_org_rules_select ON morbac.cross_org_rules FOR SELECT
    USING (morbac.is_allowed(morbac.current_user_id(), source_org_id, 'read',
        morbac.get_config('system_view.cross_org_rules')));

CREATE POLICY cross_org_rules_insert ON morbac.cross_org_rules FOR INSERT
    WITH CHECK (morbac.is_allowed(morbac.current_user_id(), source_org_id, 'create',
        morbac.get_config('system_view.cross_org_rules')));

CREATE POLICY cross_org_rules_update ON morbac.cross_org_rules FOR UPDATE
    USING (morbac.is_allowed(morbac.current_user_id(), source_org_id, 'update',
        morbac.get_config('system_view.cross_org_rules')));

CREATE POLICY cross_org_rules_delete ON morbac.cross_org_rules FOR DELETE
    USING (morbac.is_allowed(morbac.current_user_id(), source_org_id, 'delete',
        morbac.get_config('system_view.cross_org_rules')));
