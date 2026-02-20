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
