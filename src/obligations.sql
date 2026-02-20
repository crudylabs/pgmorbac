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
