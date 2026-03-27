-- Authorization decision function implementing canonical OrBAC semantics.
--
-- Access is allowed if and only if:
--   1. At least one applicable permission exists
--   2. AND no applicable prohibition exists (or permission has strictly higher priority)
-- Default deny (no permission = deny).
-- Obligations and recommendations do NOT affect authorization.
--
-- Priority resolution:
-- - Each rule has an optional integer priority (NULL = 0, lowest)
-- - When both a prohibition and a permission apply, the higher-priority rule wins
-- - Tie goes to prohibition (modality precedence from the Multi-OrBAC paper)

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
    v_rule                     RECORD;
    v_max_prohibition_priority INTEGER := NULL;
    v_max_permission_priority  INTEGER := NULL;
BEGIN
    -- STEP 1: Local prohibitions — find the highest-priority applicable one
    FOR v_rule IN
        SELECT r.context_id, COALESCE(r.priority, 0) AS prio
        FROM morbac.rules r
        WHERE r.org_id = p_org_id
          AND r.modality = 'prohibition'
          AND r.activity IN (SELECT activity FROM morbac.get_effective_activities(p_activity))
          AND r.view     IN (SELECT view     FROM morbac.get_effective_views(p_view))
          AND r.role_id  IN (SELECT role_id  FROM morbac.get_comprehensive_roles(p_user_id, p_org_id))
          AND morbac.is_rule_valid(r.valid_from, r.valid_until)
        ORDER BY COALESCE(r.priority, 0) DESC
    LOOP
        IF morbac.eval_context(v_rule.context_id) THEN
            v_max_prohibition_priority := v_rule.prio;
            EXIT;
        END IF;
    END LOOP;

    -- STEP 2: Cross-org prohibitions — update max if a higher priority is found
    FOR v_rule IN
        SELECT cr.context_id, COALESCE(cr.priority, 0) AS prio
        FROM morbac.cross_org_rules cr
        WHERE cr.target_org_id = p_org_id
          AND cr.modality = 'prohibition'
          AND cr.activity IN (SELECT activity FROM morbac.get_effective_activities(p_activity))
          AND cr.view     IN (SELECT view     FROM morbac.get_effective_views(p_view))
          AND cr.role_id  IN (SELECT role_id  FROM morbac.get_comprehensive_roles(p_user_id, cr.source_org_id))
          AND morbac.is_rule_valid(cr.valid_from, cr.valid_until)
        ORDER BY COALESCE(cr.priority, 0) DESC
    LOOP
        IF morbac.eval_context(v_rule.context_id) THEN
            IF v_max_prohibition_priority IS NULL OR v_rule.prio > v_max_prohibition_priority THEN
                v_max_prohibition_priority := v_rule.prio;
            END IF;
            EXIT;
        END IF;
    END LOOP;

    -- STEP 3: Local permissions — find the highest-priority applicable one
    FOR v_rule IN
        SELECT r.context_id, COALESCE(r.priority, 0) AS prio
        FROM morbac.rules r
        WHERE r.org_id = p_org_id
          AND r.modality = 'permission'
          AND r.activity IN (SELECT activity FROM morbac.get_effective_activities(p_activity))
          AND r.view     IN (SELECT view     FROM morbac.get_effective_views(p_view))
          AND r.role_id  IN (SELECT role_id  FROM morbac.get_comprehensive_roles(p_user_id, p_org_id))
          AND morbac.is_rule_valid(r.valid_from, r.valid_until)
        ORDER BY COALESCE(r.priority, 0) DESC
    LOOP
        IF morbac.eval_context(v_rule.context_id) THEN
            v_max_permission_priority := v_rule.prio;
            EXIT;
        END IF;
    END LOOP;

    -- STEP 4: Cross-org permissions — update max if higher found
    FOR v_rule IN
        SELECT cr.context_id, COALESCE(cr.priority, 0) AS prio
        FROM morbac.cross_org_rules cr
        WHERE cr.target_org_id = p_org_id
          AND cr.modality = 'permission'
          AND cr.activity IN (SELECT activity FROM morbac.get_effective_activities(p_activity))
          AND cr.view     IN (SELECT view     FROM morbac.get_effective_views(p_view))
          AND cr.role_id  IN (SELECT role_id  FROM morbac.get_comprehensive_roles(p_user_id, cr.source_org_id))
          AND morbac.is_rule_valid(cr.valid_from, cr.valid_until)
        ORDER BY COALESCE(cr.priority, 0) DESC
    LOOP
        IF morbac.eval_context(v_rule.context_id) THEN
            IF v_max_permission_priority IS NULL OR v_rule.prio > v_max_permission_priority THEN
                v_max_permission_priority := v_rule.prio;
            END IF;
            EXIT;
        END IF;
    END LOOP;

    -- STEP 5: Priority resolution
    IF v_max_prohibition_priority IS NULL THEN
        RETURN v_max_permission_priority IS NOT NULL;
    END IF;

    IF v_max_permission_priority IS NOT NULL
       AND v_max_permission_priority > v_max_prohibition_priority THEN
        RETURN TRUE;
    END IF;

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
VOLATILE
AS $$
DECLARE
    v_cached_result BOOLEAN;
    v_computed_result BOOLEAN;
    v_expires_at TIMESTAMPTZ;
BEGIN
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

    v_computed_result := morbac.is_allowed_nocache(p_user_id, p_org_id, p_activity, p_view);

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
