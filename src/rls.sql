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

CREATE OR REPLACE FUNCTION morbac.current_target_user_id()
RETURNS UUID
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    v_user_id TEXT;
BEGIN
    v_user_id := current_setting('morbac.target_user_id', TRUE);

    IF v_user_id IS NULL OR v_user_id = '' THEN
        RETURN NULL;
    END IF;

    RETURN v_user_id::UUID;
EXCEPTION
    WHEN OTHERS THEN
        RETURN NULL;
END;
$$;

COMMENT ON FUNCTION morbac.current_target_user_id() IS
'Returns target user ID filter from morbac.target_user_id session variable';

-- Set via: SET morbac.org_ids = '["uuid1","uuid2"]'
CREATE OR REPLACE FUNCTION morbac.current_org_ids()
RETURNS UUID[]
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    v_raw TEXT;
BEGIN
    v_raw := current_setting('morbac.org_ids', TRUE);

    IF v_raw IS NULL OR v_raw = '' THEN
        RETURN NULL;
    END IF;

    RETURN ARRAY(SELECT jsonb_array_elements_text(v_raw::jsonb)::UUID);
EXCEPTION
    WHEN OTHERS THEN
        RETURN NULL;
END;
$$;

COMMENT ON FUNCTION morbac.current_org_ids() IS
'Returns org ID list from morbac.org_ids session variable (JSON array)';

CREATE OR REPLACE FUNCTION morbac.get_user_orgs(p_user_id UUID)
RETURNS TABLE(org_id UUID)
LANGUAGE sql
STABLE
SECURITY DEFINER
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

-- Org scoping: morbac.org_id (single) > morbac.org_ids (list) > all orgs.
-- User scoping: morbac.target_user_id filters rows to a specific user.
-- Pass row columns to enable scoping: rls_check('read', 'docs', org_id, user_id)
CREATE OR REPLACE FUNCTION morbac.rls_check(
    p_activity    TEXT,
    p_view        TEXT,
    p_row_org_id  UUID DEFAULT NULL,
    p_row_user_id UUID DEFAULT NULL
)
RETURNS BOOLEAN
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    v_user_id        UUID;
    v_org_id         UUID;
    v_org_ids        UUID[];
    v_target_user_id UUID;
BEGIN
    v_user_id := morbac.current_user_id();

    IF v_user_id IS NULL THEN
        RETURN FALSE;
    END IF;

    -- User filter: if morbac.target_user_id is set, only rows matching that user pass
    IF p_row_user_id IS NOT NULL THEN
        v_target_user_id := morbac.current_target_user_id();
        IF v_target_user_id IS NOT NULL AND p_row_user_id <> v_target_user_id THEN
            RETURN FALSE;
        END IF;
    END IF;

    v_org_id := morbac.current_org_id();

    IF v_org_id IS NOT NULL THEN
        IF p_row_org_id IS NOT NULL AND p_row_org_id <> v_org_id THEN
            RETURN FALSE;
        END IF;
        RETURN morbac.is_allowed(v_user_id, v_org_id, p_activity, p_view);
    END IF;

    v_org_ids := morbac.current_org_ids();

    IF v_org_ids IS NOT NULL THEN
        IF p_row_org_id IS NOT NULL AND NOT (p_row_org_id = ANY(v_org_ids)) THEN
            RETURN FALSE;
        END IF;
        -- p_row_org_id NULL: global row — is_allowed(NULL) checks global_rules only
        RETURN morbac.is_allowed(v_user_id, p_row_org_id, p_activity, p_view);
    END IF;

    -- No org context: use row's org (or NULL for global rows — global_rules only)
    RETURN morbac.is_allowed(v_user_id, p_row_org_id, p_activity, p_view);
END;
$$;

COMMENT ON FUNCTION morbac.rls_check(TEXT, TEXT, UUID, UUID) IS
'RLS helper: checks if current user is allowed to perform activity on view. Pass row org_id for org scoping (single org, org list, or all orgs). Pass row user_id to filter by morbac.target_user_id session variable.';
