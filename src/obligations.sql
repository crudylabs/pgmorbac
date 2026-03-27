-- Obligations and recommendations do NOT affect authorization decisions.
-- They are queryable for informational purposes (task lists, compliance prompts, etc.).
--
-- Conflict resolution (from Multi-OrBAC paper):
-- - A prohibition voids any applicable obligation for the same (activity, view)
-- - A prohibition or obligation voids any applicable recommendation for the same (activity, view)

-- Returns pending obligations not voided by an applicable prohibition
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
    INNER JOIN morbac.roles ro ON ro.id = r.role_id
    INNER JOIN morbac.contexts c ON c.id = r.context_id
    WHERE r.org_id = p_org_id
      AND r.modality = 'obligation'
      AND r.role_id IN (
          SELECT role_id FROM morbac.get_comprehensive_roles(p_user_id, p_org_id)
      )
      AND morbac.is_rule_valid(r.valid_from, r.valid_until)
      AND morbac.eval_context(r.context_id)
      -- Prohibition voids obligation unless the obligation has strictly higher priority
      AND NOT EXISTS (
          SELECT 1
          FROM morbac.rules p
          WHERE p.org_id = p_org_id
            AND p.modality = 'prohibition'
            AND p.activity IN (SELECT ea.activity FROM morbac.get_effective_activities(r.activity) ea)
            AND p.view IN (SELECT ev.view FROM morbac.get_effective_views(r.view) ev)
            AND p.role_id IN (
                SELECT role_id FROM morbac.get_comprehensive_roles(p_user_id, p_org_id)
            )
            AND morbac.is_rule_valid(p.valid_from, p.valid_until)
            AND morbac.eval_context(p.context_id)
            AND COALESCE(p.priority, 0) >= COALESCE(r.priority, 0)
      )
    ORDER BY r.created_at;
END;
$$;

COMMENT ON FUNCTION morbac.pending_obligations(UUID, UUID) IS
'Returns pending obligations for a user in an organization (informational only). Prohibitions void applicable obligations per Multi-OrBAC conflict resolution.';

-- Returns recommendations not voided by an applicable prohibition or obligation
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
    INNER JOIN morbac.roles ro ON ro.id = r.role_id
    INNER JOIN morbac.contexts c ON c.id = r.context_id
    WHERE r.org_id = p_org_id
      AND r.modality = 'recommendation'
      AND r.role_id IN (
          SELECT role_id FROM morbac.get_comprehensive_roles(p_user_id, p_org_id)
      )
      AND morbac.is_rule_valid(r.valid_from, r.valid_until)
      AND morbac.eval_context(r.context_id)
      -- Prohibition or obligation voids recommendation unless recommendation has strictly higher priority
      AND NOT EXISTS (
          SELECT 1
          FROM morbac.rules p
          WHERE p.org_id = p_org_id
            AND p.modality IN ('prohibition', 'obligation')
            AND p.activity IN (SELECT ea.activity FROM morbac.get_effective_activities(r.activity) ea)
            AND p.view IN (SELECT ev.view FROM morbac.get_effective_views(r.view) ev)
            AND p.role_id IN (
                SELECT role_id FROM morbac.get_comprehensive_roles(p_user_id, p_org_id)
            )
            AND morbac.is_rule_valid(p.valid_from, p.valid_until)
            AND morbac.eval_context(p.context_id)
            AND COALESCE(p.priority, 0) >= COALESCE(r.priority, 0)
      )
    ORDER BY r.created_at;
END;
$$;

COMMENT ON FUNCTION morbac.pending_recommendations(UUID, UUID) IS
'Returns recommendations for a user in an organization (informational only). Prohibitions and obligations void applicable recommendations per Multi-OrBAC conflict resolution.';

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
