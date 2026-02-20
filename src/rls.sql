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
