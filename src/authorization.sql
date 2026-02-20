-- =============================================================================
-- AUTHORIZATION DECISION FUNCTION (CRITICAL)
-- =============================================================================
-- Implements the canonical OrBAC authorization decision
--
-- Semantics (from Multi-OrBAC paper):
-- - Access is allowed if and only if:
--   1. At least one applicable permission exists
--   2. AND no applicable prohibition exists
-- - Prohibitions have precedence over permissions
-- - Contexts must be evaluated
-- - Default deny (no permission = deny)
-- - Obligations and recommendations do NOT affect authorization

CREATE OR REPLACE FUNCTION morbac.is_allowed_nocache(
    p_user_id UUID,
    p_org_id UUID,
    p_activity TEXT,
    p_view TEXT
)
RETURNS BOOLEAN
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    v_rule RECORD;
BEGIN
    -- STEP 1: Check for prohibitions first (prohibition precedence)
    -- If any applicable prohibition exists, deny immediately
    -- Checks:
    -- - Direct rules for (activity, view) combinations
    -- - Activity hierarchy (senior activities imply junior)
    -- - View hierarchy (senior views imply junior)
    -- - Comprehensive roles (direct, delegated, derived, inherited)
    -- - Temporal validity (if rule has time constraints)

    FOR v_rule IN
        SELECT r.context_id
        FROM morbac.rules r
        WHERE r.org_id = p_org_id
          AND r.modality = 'prohibition'
          -- Match activity or any senior activity in hierarchy
          AND r.activity IN (
              SELECT activity FROM morbac.get_effective_activities(p_activity)
          )
          -- Match view or any senior view in hierarchy
          AND r.view IN (
              SELECT view FROM morbac.get_effective_views(p_view)
          )
          -- Match comprehensive roles (direct, delegated, derived, inherited)
          AND r.role_id IN (
              SELECT role_id FROM morbac.get_comprehensive_roles(p_user_id, p_org_id)
          )
          -- Check temporal validity
          AND morbac.is_rule_valid(r.valid_from, r.valid_until)
    LOOP
        -- Evaluate context
        IF morbac.eval_context(v_rule.context_id) THEN
            -- Prohibition found - immediate deny (prohibition precedence)
            RETURN FALSE;
        END IF;
    END LOOP;

    -- STEP 2: Check cross-organizational prohibitions
    FOR v_rule IN
        SELECT cr.context_id
        FROM morbac.cross_org_rules cr
        WHERE cr.target_org_id = p_org_id
          AND cr.modality = 'prohibition'
          AND cr.activity IN (SELECT activity FROM morbac.get_effective_activities(p_activity))
          AND cr.view IN (SELECT view FROM morbac.get_effective_views(p_view))
          -- User has role in source org
          AND cr.role_id IN (
              SELECT role_id FROM morbac.get_comprehensive_roles(p_user_id, cr.source_org_id)
          )
          -- Check temporal validity
          AND morbac.is_rule_valid(cr.valid_from, cr.valid_until)
    LOOP
        IF morbac.eval_context(v_rule.context_id) THEN
            RETURN FALSE;
        END IF;
    END LOOP;

    -- STEP 3: No prohibitions found, check for permissions
    FOR v_rule IN
        SELECT r.context_id
        FROM morbac.rules r
        WHERE r.org_id = p_org_id
          AND r.modality = 'permission'
          -- Match activity or any senior activity in hierarchy
          AND r.activity IN (
              SELECT activity FROM morbac.get_effective_activities(p_activity)
          )
          -- Match view or any senior view in hierarchy
          AND r.view IN (
              SELECT view FROM morbac.get_effective_views(p_view)
          )
          -- Match comprehensive roles
          AND r.role_id IN (
              SELECT role_id FROM morbac.get_comprehensive_roles(p_user_id, p_org_id)
          )
          -- Check temporal validity
          AND morbac.is_rule_valid(r.valid_from, r.valid_until)
    LOOP
        -- Evaluate context
        IF morbac.eval_context(v_rule.context_id) THEN
            -- Permission found and no prohibition - allow
            RETURN TRUE;
        END IF;
    END LOOP;

    -- STEP 4: Check cross-organizational permissions
    FOR v_rule IN
        SELECT cr.context_id
        FROM morbac.cross_org_rules cr
        WHERE cr.target_org_id = p_org_id
          AND cr.modality = 'permission'
          AND cr.activity IN (SELECT activity FROM morbac.get_effective_activities(p_activity))
          AND cr.view IN (SELECT view FROM morbac.get_effective_views(p_view))
          AND cr.role_id IN (
              SELECT role_id FROM morbac.get_comprehensive_roles(p_user_id, cr.source_org_id)
          )
          -- Check temporal validity
          AND morbac.is_rule_valid(cr.valid_from, cr.valid_until)
    LOOP
        IF morbac.eval_context(v_rule.context_id) THEN
            RETURN TRUE;
        END IF;
    END LOOP;

    -- No permission found - deny (default deny)
    RETURN FALSE;
END;
$$;

COMMENT ON FUNCTION morbac.is_allowed_nocache(UUID, UUID, TEXT, TEXT) IS
'Authorization without cache - use for debugging or when cache must be bypassed';

-- Cached authorization check (default, recommended for production use)
CREATE OR REPLACE FUNCTION morbac.is_allowed(
    p_user_id UUID,
    p_org_id UUID,
    p_activity TEXT,
    p_view TEXT
)
RETURNS BOOLEAN
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    v_cached_result BOOLEAN;
    v_computed_result BOOLEAN;
    v_expires_at TIMESTAMPTZ;
BEGIN
    -- Try cache first
    SELECT allowed, expires_at INTO v_cached_result, v_expires_at
    FROM morbac.auth_cache
    WHERE user_id = p_user_id
      AND org_id = p_org_id
      AND activity = p_activity
      AND view = p_view
      AND expires_at > CURRENT_TIMESTAMP;

    IF FOUND THEN
        RETURN v_cached_result;
    END IF;

    -- Cache miss - compute authorization
    v_computed_result := morbac.is_allowed_nocache(p_user_id, p_org_id, p_activity, p_view);

    -- Store in cache (TTL from config)
    INSERT INTO morbac.auth_cache (user_id, org_id, activity, view, allowed, expires_at)
    VALUES (
        p_user_id,
        p_org_id,
        p_activity,
        p_view,
        v_computed_result,
        CURRENT_TIMESTAMP + make_interval(secs => morbac.get_config('cache_ttl_seconds')::integer)
    )
    ON CONFLICT (user_id, org_id, activity, view) DO UPDATE
    SET allowed = v_computed_result,
        computed_at = CURRENT_TIMESTAMP,
        expires_at = CURRENT_TIMESTAMP + make_interval(secs => morbac.get_config('cache_ttl_seconds')::integer);

    RETURN v_computed_result;
END;
$$;

COMMENT ON FUNCTION morbac.is_allowed(UUID, UUID, TEXT, TEXT) IS
'Complete OrBAC authorization with caching (default) - use is_allowed_nocache() for debugging';
