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

-- Set via: SET morbac.org_ids = '["uuid1","uuid2"]' or '["uuid1", null]' or '[null]'.
-- A JSON null element names the no-org (unattributed) bucket, distinct from
-- the real org UUIDs which populate org_ids.
CREATE OR REPLACE FUNCTION morbac.current_org_filter(
    OUT org_ids              UUID[],
    OUT include_unattributed BOOLEAN
)
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    v_raw  TEXT := current_setting('morbac.org_ids', TRUE);
    v_json JSONB;
BEGIN
    org_ids := NULL;
    include_unattributed := FALSE;

    IF v_raw IS NULL OR v_raw = '' THEN
        RETURN;
    END IF;

    v_json := v_raw::jsonb;
    org_ids := ARRAY(
        SELECT x::UUID
        FROM jsonb_array_elements_text(v_json) x
        WHERE x IS NOT NULL
    );
    include_unattributed := EXISTS (
        SELECT 1 FROM jsonb_array_elements(v_json) e WHERE e = 'null'::jsonb
    );
EXCEPTION
    WHEN OTHERS THEN
        org_ids := NULL;
        include_unattributed := FALSE;
END;
$$;

COMMENT ON FUNCTION morbac.current_org_filter() IS
'Parses morbac.org_ids (JSON array) once into real org UUIDs plus a flag for whether the no-org bucket (JSON null element) was requested.';

CREATE OR REPLACE FUNCTION morbac.current_org_ids()
RETURNS UUID[]
LANGUAGE sql
STABLE
AS $$
    SELECT org_ids FROM morbac.current_org_filter();
$$;

COMMENT ON FUNCTION morbac.current_org_ids() IS
'Returns the real org UUIDs from morbac.org_ids (JSON null elements excluded). See current_org_filter() for the no-org bucket flag.';

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

-- rls_check has two forms, distinguished by arity so a NULL never carries two
-- meanings:
--
--   rls_check(activity, view)                       -- table has no org column
--   rls_check(activity, view, row_org_id[, row_user_id]) -- row-scoped by org
--
-- In the 3/4-arg form row_org_id is the record's org, and a NULL value means the
-- record is unattributed (no org) -- never "no org dimension". The 2-arg form
-- carries no org dimension and evaluates against the session org context.

DROP FUNCTION IF EXISTS morbac.rls_check(TEXT, TEXT, UUID, UUID);

CREATE OR REPLACE FUNCTION morbac.rls_check(
    p_activity TEXT,
    p_view     TEXT
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
    IF v_user_id IS NULL THEN
        RETURN FALSE;
    END IF;

    v_org_id := morbac.current_org_id();
    IF v_org_id IS NOT NULL THEN
        RETURN morbac.is_allowed(v_user_id, v_org_id, p_activity, p_view);
    END IF;

    RETURN morbac.is_allowed(v_user_id, NULL, p_activity, p_view);
END;
$$;

COMMENT ON FUNCTION morbac.rls_check(TEXT, TEXT) IS
'RLS helper for tables without an org column. Uses the session org context (morbac.org_id), else org-independent rules. For row-scoped tables use the 3/4-arg form.';

-- Org scoping: morbac.org_id (single) > morbac.org_ids (list) > all orgs.
-- User scoping: morbac.target_user_id filters rows to a specific user.
CREATE OR REPLACE FUNCTION morbac.rls_check(
    p_activity    TEXT,
    p_view        TEXT,
    p_row_org_id  UUID,
    p_row_user_id UUID DEFAULT NULL
)
RETURNS BOOLEAN
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    v_user_id         UUID;
    v_org_id          UUID;
    v_org_ids         UUID[];
    v_include_unattr  BOOLEAN;
    v_target_user_id  UUID;
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

    -- Single org selection: exact bucket only. An unattributed row (NULL org) is
    -- DISTINCT from the pin and is filtered out (use the org_ids list for both).
    v_org_id := morbac.current_org_id();

    IF v_org_id IS NOT NULL THEN
        IF p_row_org_id IS DISTINCT FROM v_org_id THEN
            RETURN FALSE;
        END IF;
        RETURN morbac.is_allowed(v_user_id, v_org_id, p_activity, p_view);
    END IF;

    -- Org list selection: real orgs and/or the unattributed bucket (JSON null element).
    SELECT f.org_ids, f.include_unattributed
    INTO v_org_ids, v_include_unattr
    FROM morbac.current_org_filter() f;

    IF v_org_ids IS NOT NULL OR v_include_unattr THEN
        IF p_row_org_id IS NULL THEN
            IF NOT v_include_unattr THEN
                RETURN FALSE;
            END IF;
            RETURN morbac.is_allowed(v_user_id, NULL, p_activity, p_view);
        END IF;
        IF v_org_ids IS NULL OR NOT (p_row_org_id = ANY(v_org_ids)) THEN
            RETURN FALSE;
        END IF;
        RETURN morbac.is_allowed(v_user_id, p_row_org_id, p_activity, p_view);
    END IF;

    -- No selection set: all authorized rows. The row's own org drives the decision
    -- (unattributed row -> unattributed + org-independent rules).
    RETURN morbac.is_allowed(v_user_id, p_row_org_id, p_activity, p_view);
END;
$$;

COMMENT ON FUNCTION morbac.rls_check(TEXT, TEXT, UUID, UUID) IS
'RLS helper for row-scoped tables. p_row_org_id is the record org; NULL means unattributed. Select records via morbac.org_id (single org, unattributed excluded) or morbac.org_ids (JSON array; a null element adds the unattributed bucket). No selection = all authorized rows including unattributed. Pass row user_id to filter by morbac.target_user_id.';
