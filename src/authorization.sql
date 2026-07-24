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
--
-- Org target (p_org_id): a specific org, or NULL meaning the object is
-- unattributed (has no org). NULL never means "any org".
--
-- Scope:
-- - rules.scope selects which objects a rule covers: a specific org
--   (self/subtree/descendants/...), 'unattributed', or 'all'.
--   Evaluated at query time via org_in_scope() — new orgs are covered automatically.
-- - cross_org_rules.source_org_id is always required: user must hold the role there.
-- - user_rules target a specific user directly (no role required); their org_id
--   is a specific org, or NULL for unattributed objects.
-- - global_rules apply to every org, unattributed included.

CREATE OR REPLACE FUNCTION morbac.is_allowed_nocache(
    p_user_id UUID,
    p_org_id UUID,
    p_activity TEXT,
    p_view TEXT
)
RETURNS BOOLEAN
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
AS $$
DECLARE
    v_rule                     RECORD;
    v_max_prohibition_priority INTEGER := NULL;
    v_max_permission_priority  INTEGER := NULL;
    v_is_system_principal      BOOLEAN;
BEGIN
    v_is_system_principal := EXISTS (
        SELECT 1 FROM morbac.system_principals WHERE user_id = p_user_id
    );

    -- STEPS 1-3.5: Prohibitions — skipped entirely for system principals
    IF NOT v_is_system_principal THEN

        -- STEP 1: Local prohibitions — find the highest-priority applicable one
        FOR v_rule IN
            SELECT r.context_id, COALESCE(r.priority, 0) AS prio
            FROM morbac.rules r
            WHERE morbac.org_in_scope(p_org_id, r.org_id, r.scope)
              AND r.modality = 'prohibition'
              AND r.activity IN (SELECT activity FROM morbac.get_effective_activities(p_activity))
              AND r.view     IN (SELECT view     FROM morbac.get_effective_views(p_view))
              AND r.role_id  IN (SELECT role_id  FROM morbac.get_comprehensive_roles(p_user_id, r.org_id))
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
              AND cr.role_id IN (SELECT role_id FROM morbac.get_comprehensive_roles(p_user_id, cr.source_org_id))
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

        -- STEP 3: User-level prohibitions — direct user rules, update max if higher
        FOR v_rule IN
            SELECT ur.context_id, COALESCE(ur.priority, 0) AS prio
            FROM morbac.user_rules ur
            WHERE ur.user_id = p_user_id
              AND ur.org_id IS NOT DISTINCT FROM p_org_id
              AND ur.modality = 'prohibition'
              AND ur.activity IN (SELECT activity FROM morbac.get_effective_activities(p_activity))
              AND ur.view     IN (SELECT view     FROM morbac.get_effective_views(p_view))
              AND morbac.is_rule_valid(ur.valid_from, ur.valid_until)
            ORDER BY COALESCE(ur.priority, 0) DESC
        LOOP
            IF morbac.eval_context(v_rule.context_id) THEN
                IF v_max_prohibition_priority IS NULL OR v_rule.prio > v_max_prohibition_priority THEN
                    v_max_prohibition_priority := v_rule.prio;
                END IF;
                EXIT;
            END IF;
        END LOOP;

        -- STEP 3.5: Global prohibitions
        FOR v_rule IN
            SELECT gr.context_id, COALESCE(gr.priority, 0) AS prio
            FROM morbac.global_rules gr
            WHERE (gr.user_id IS NULL OR gr.user_id = p_user_id)
              AND gr.modality = 'prohibition'
              AND (gr.activity IS NULL OR gr.activity IN (SELECT activity FROM morbac.get_effective_activities(p_activity)))
              AND (gr.view     IS NULL OR gr.view     IN (SELECT view     FROM morbac.get_effective_views(p_view)))
              AND morbac.is_rule_valid(gr.valid_from, gr.valid_until)
            ORDER BY COALESCE(gr.priority, 0) DESC
        LOOP
            IF morbac.eval_context(v_rule.context_id) THEN
                IF v_max_prohibition_priority IS NULL OR v_rule.prio > v_max_prohibition_priority THEN
                    v_max_prohibition_priority := v_rule.prio;
                END IF;
                EXIT;
            END IF;
        END LOOP;

    END IF; -- v_is_system_principal

    -- STEP 4: Local permissions — find the highest-priority applicable one
    FOR v_rule IN
        SELECT r.context_id, COALESCE(r.priority, 0) AS prio
        FROM morbac.rules r
        WHERE morbac.org_in_scope(p_org_id, r.org_id, r.scope)
          AND r.modality = 'permission'
          AND r.activity IN (SELECT activity FROM morbac.get_effective_activities(p_activity))
          AND r.view     IN (SELECT view     FROM morbac.get_effective_views(p_view))
          AND r.role_id  IN (SELECT role_id  FROM morbac.get_comprehensive_roles(p_user_id, r.org_id))
          AND morbac.is_rule_valid(r.valid_from, r.valid_until)
        ORDER BY COALESCE(r.priority, 0) DESC
    LOOP
        IF morbac.eval_context(v_rule.context_id) THEN
            v_max_permission_priority := v_rule.prio;
            EXIT;
        END IF;
    END LOOP;

    -- STEP 5: Cross-org permissions — update max if higher found
    FOR v_rule IN
        SELECT cr.context_id, COALESCE(cr.priority, 0) AS prio
        FROM morbac.cross_org_rules cr
        WHERE cr.target_org_id = p_org_id
          AND cr.modality = 'permission'
          AND cr.activity IN (SELECT activity FROM morbac.get_effective_activities(p_activity))
          AND cr.view     IN (SELECT view     FROM morbac.get_effective_views(p_view))
          AND cr.role_id IN (SELECT role_id FROM morbac.get_comprehensive_roles(p_user_id, cr.source_org_id))
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

    -- STEP 6: User-level permissions — direct user rules, update max if higher
    FOR v_rule IN
        SELECT ur.context_id, COALESCE(ur.priority, 0) AS prio
        FROM morbac.user_rules ur
        WHERE ur.user_id = p_user_id
          AND ur.org_id IS NOT DISTINCT FROM p_org_id
          AND ur.modality = 'permission'
          AND ur.activity IN (SELECT activity FROM morbac.get_effective_activities(p_activity))
          AND ur.view     IN (SELECT view     FROM morbac.get_effective_views(p_view))
          AND morbac.is_rule_valid(ur.valid_from, ur.valid_until)
        ORDER BY COALESCE(ur.priority, 0) DESC
    LOOP
        IF morbac.eval_context(v_rule.context_id) THEN
            IF v_max_permission_priority IS NULL OR v_rule.prio > v_max_permission_priority THEN
                v_max_permission_priority := v_rule.prio;
            END IF;
            EXIT;
        END IF;
    END LOOP;

    -- STEP 6.5: Global permissions
    FOR v_rule IN
        SELECT gr.context_id, COALESCE(gr.priority, 0) AS prio
        FROM morbac.global_rules gr
        WHERE (gr.user_id IS NULL OR gr.user_id = p_user_id)
          AND gr.modality = 'permission'
          AND (gr.activity IS NULL OR gr.activity IN (SELECT activity FROM morbac.get_effective_activities(p_activity)))
          AND (gr.view     IS NULL OR gr.view     IN (SELECT view     FROM morbac.get_effective_views(p_view)))
          AND morbac.is_rule_valid(gr.valid_from, gr.valid_until)
        ORDER BY COALESCE(gr.priority, 0) DESC
    LOOP
        IF morbac.eval_context(v_rule.context_id) THEN
            IF v_max_permission_priority IS NULL OR v_rule.prio > v_max_permission_priority THEN
                v_max_permission_priority := v_rule.prio;
            END IF;
            EXIT;
        END IF;
    END LOOP;

    -- STEP 7: Priority resolution
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
SECURITY DEFINER
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

    -- NULL org_id (global-rules-only path) cannot be stored in auth_cache (org_id NOT NULL PK).
    -- Global rule changes flush the entire cache anyway, so skipping is safe.
    IF p_org_id IS NULL THEN
        RETURN v_computed_result;
    END IF;

    BEGIN
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
    EXCEPTION WHEN read_only_sql_transaction THEN
        NULL;
    END;

    RETURN v_computed_result;
END;
$$;

COMMENT ON FUNCTION morbac.is_allowed(UUID, UUID, TEXT, TEXT) IS
'Complete OrBAC authorization with caching (default) - use is_allowed_nocache() for debugging';

-- Capability probe: does the user hold the permission in ANY context (any org
-- they are a member of, or the no-org bucket, or via global rules)? Intended
-- for UI feature gating, not object-level enforcement. Prohibitions are honored
-- per context: a context counts only if is_allowed() returns true there.
-- Pure cross-org grants into a non-member org are not counted.
CREATE OR REPLACE FUNCTION morbac.has_permission(
    p_user_id UUID,
    p_activity TEXT,
    p_view TEXT
)
RETURNS BOOLEAN
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
AS $$
BEGIN
    RETURN EXISTS (
        SELECT 1
        FROM morbac.get_user_orgs(p_user_id) o
        WHERE morbac.is_allowed(p_user_id, o.org_id, p_activity, p_view)
    ) OR morbac.is_allowed(p_user_id, NULL, p_activity, p_view);
END;
$$;

COMMENT ON FUNCTION morbac.has_permission(UUID, TEXT, TEXT) IS
'Capability probe for UI gating: TRUE if the user is allowed the activity/view in any member org, the no-org bucket, or via global rules. Not a substitute for object-level is_allowed().';
