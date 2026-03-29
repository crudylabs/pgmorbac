-- Row-Level Security helpers, compatible with PostgREST

CREATE OR REPLACE FUNCTION morbac.current_user_id()
RETURNS UUID
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    v_user_id TEXT;
BEGIN
    v_user_id := current_setting('morbac.user_id', TRUE);

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
'Returns current user ID from morbac.user_id session variable';

CREATE OR REPLACE FUNCTION morbac.current_org_id()
RETURNS UUID
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    v_org_id TEXT;
BEGIN
    v_org_id := current_setting('morbac.org_id', TRUE);

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
'Returns current organization ID from morbac.org_id session variable';

CREATE OR REPLACE FUNCTION morbac.get_user_orgs(p_user_id UUID)
RETURNS TABLE(org_id UUID)
LANGUAGE sql
STABLE
AS $$
    SELECT DISTINCT ur.org_id
    FROM morbac.user_roles ur
    WHERE ur.user_id = p_user_id
    UNION
    SELECT DISTINCT d.org_id
    FROM morbac.delegations d
    WHERE d.delegatee_id = p_user_id
      AND NOT d.revoked
      AND now() BETWEEN d.valid_from AND d.valid_until;
$$;

COMMENT ON FUNCTION morbac.get_user_orgs(UUID) IS
'Returns all org IDs the user has any direct role or active delegation in';

-- When p_row_org_id is provided and session org is NULL, checks permission in the row org (multi-org mode).
-- Usage: morbac.rls_check('read', 'documents', org_id)
CREATE OR REPLACE FUNCTION morbac.rls_check(
    p_activity   TEXT,
    p_view       TEXT,
    p_row_org_id UUID DEFAULT NULL
)
RETURNS BOOLEAN
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    v_user_id UUID;
    v_org_id  UUID;
BEGIN
    v_user_id := morbac.current_user_id();
    v_org_id  := morbac.current_org_id();

    IF v_user_id IS NULL THEN
        RETURN FALSE;
    END IF;

    IF v_org_id IS NOT NULL THEN
        IF p_row_org_id IS NOT NULL AND p_row_org_id <> v_org_id THEN
            RETURN FALSE;
        END IF;
        RETURN morbac.is_allowed(v_user_id, v_org_id, p_activity, p_view);
    END IF;

    IF p_row_org_id IS NOT NULL THEN
        RETURN morbac.is_allowed(v_user_id, p_row_org_id, p_activity, p_view);
    END IF;

    RETURN FALSE;
END;
$$;

COMMENT ON FUNCTION morbac.rls_check(TEXT, TEXT, UUID) IS
'RLS helper: checks if current user is allowed to perform activity on view. Pass row org_id to enable multi-org mode when no session org is set.';
