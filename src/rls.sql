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

    IF v_user_id IS NULL OR v_org_id IS NULL THEN
        RETURN FALSE;
    END IF;

    RETURN morbac.is_allowed(v_user_id, v_org_id, p_activity, p_view);
END;
$$;

COMMENT ON FUNCTION morbac.rls_check(TEXT, TEXT) IS
'RLS helper: checks if current user is allowed to perform activity on view in current org';
