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

-- Get a named scope of organizations relative to a given org
--
-- Supported scopes:
--   'self'        — the org itself only (depth = 0)
--   'children'    — direct children only (descendants at depth = 1)
--   'descendants' — all descendants, excluding self (depth > 0)
--   'subtree'     — self + all descendants (equivalent to get_org_descendants)
--   'parent'      — direct parent only (ancestor at depth = 1)
--   'ancestors'   — all ancestors, excluding self (depth > 0)
--   'lineage'     — self + all ancestors (equivalent to get_org_ancestors)
--   'root'        — topmost ancestor only (max depth ancestor)
--
-- Optional p_max_depth limits how many levels are traversed (NULL = unlimited).
-- For upward scopes (parent/ancestors/lineage/root) depth counts steps toward root.
-- For downward scopes (children/descendants/subtree) depth counts steps toward leaves.
CREATE OR REPLACE FUNCTION morbac.get_org_scope(
    p_org_id    UUID,
    p_scope     TEXT,
    p_max_depth INTEGER DEFAULT NULL
)
RETURNS TABLE(org_id UUID, depth INTEGER)
LANGUAGE plpgsql
STABLE
AS $$
BEGIN
    CASE p_scope
        WHEN 'self' THEN
            RETURN QUERY
            SELECT p_org_id, 0;

        WHEN 'children' THEN
            RETURN QUERY
            SELECT d.org_id, d.depth
            FROM morbac.get_org_descendants(p_org_id) d
            WHERE d.depth = 1
              AND (p_max_depth IS NULL OR d.depth <= p_max_depth);

        WHEN 'descendants' THEN
            RETURN QUERY
            SELECT d.org_id, d.depth
            FROM morbac.get_org_descendants(p_org_id) d
            WHERE d.depth > 0
              AND (p_max_depth IS NULL OR d.depth <= p_max_depth);

        WHEN 'subtree' THEN
            RETURN QUERY
            SELECT d.org_id, d.depth
            FROM morbac.get_org_descendants(p_org_id) d
            WHERE (p_max_depth IS NULL OR d.depth <= p_max_depth);

        WHEN 'parent' THEN
            RETURN QUERY
            SELECT a.org_id, a.depth
            FROM morbac.get_org_ancestors(p_org_id) a
            WHERE a.depth = 1
              AND (p_max_depth IS NULL OR a.depth <= p_max_depth);

        WHEN 'ancestors' THEN
            RETURN QUERY
            SELECT a.org_id, a.depth
            FROM morbac.get_org_ancestors(p_org_id) a
            WHERE a.depth > 0
              AND (p_max_depth IS NULL OR a.depth <= p_max_depth);

        WHEN 'lineage' THEN
            RETURN QUERY
            SELECT a.org_id, a.depth
            FROM morbac.get_org_ancestors(p_org_id) a
            WHERE (p_max_depth IS NULL OR a.depth <= p_max_depth);

        WHEN 'root' THEN
            RETURN QUERY
            SELECT a.org_id, a.depth
            FROM morbac.get_org_ancestors(p_org_id) a
            ORDER BY a.depth DESC
            LIMIT 1;

        ELSE
            RAISE EXCEPTION 'get_org_scope: unknown scope "%". Valid scopes: self, children, descendants, subtree, parent, ancestors, lineage, root', p_scope;
    END CASE;
END;
$$;

COMMENT ON FUNCTION morbac.get_org_scope(UUID, TEXT, INTEGER) IS
'Returns a named set of organizations relative to p_org_id. Scopes: self, children, descendants, subtree, parent, ancestors, lineage, root. Optional p_max_depth limits traversal depth.';

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
        -- Recursive case: junior roles (inherited by the user's assigned roles)
        SELECT rh.junior_role_id, er.depth + 1
        FROM effective_roles er
        INNER JOIN morbac.role_hierarchy rh ON rh.senior_role_id = er.role_id
    )
    SELECT DISTINCT ON (effective_roles.role_id) effective_roles.role_id, effective_roles.depth
    FROM effective_roles
    ORDER BY effective_roles.role_id, effective_roles.depth;
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
    SELECT DISTINCT ON (inherited_roles.role_id) inherited_roles.role_id, inherited_roles.depth
    FROM inherited_roles
    ORDER BY inherited_roles.role_id, inherited_roles.depth;
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
    SELECT DISTINCT ON (effective_activities.activity) effective_activities.activity, effective_activities.depth
    FROM effective_activities
    ORDER BY effective_activities.activity, effective_activities.depth;
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
    SELECT DISTINCT ON (effective_views.view) effective_views.view, effective_views.depth
    FROM effective_views
    ORDER BY effective_views.view, effective_views.depth;
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

                -- Role hierarchy (junior roles inherited by user's roles)
                SELECT rh.junior_role_id, er.source || '_inherited', er.depth + 1
                FROM effective_roles er
                INNER JOIN morbac.role_hierarchy rh ON rh.senior_role_id = er.role_id
    )
    SELECT DISTINCT ON (effective_roles.role_id) effective_roles.role_id, effective_roles.source, effective_roles.depth
    FROM effective_roles
    WHERE effective_roles.role_id IS NOT NULL
    ORDER BY effective_roles.role_id, effective_roles.depth;

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
    SELECT DISTINCT ON (inherited_roles.role_id) inherited_roles.role_id, inherited_roles.depth
    FROM inherited_roles
    ORDER BY inherited_roles.role_id, inherited_roles.depth;
END;
$$;

COMMENT ON FUNCTION morbac.get_inherited_roles(UUID) IS
'Returns all roles inherited by a role (transitive closure via role hierarchy)';
