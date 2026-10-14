-- pgmorbac 1.0.0 -> 1.0.1
--
-- is_allowed_nocache() resolved the user's roles once per row of the whole
-- rules table, so its cost grew with every tenant's rules. It now resolves
-- them once per org where the user can hold a role, before reading rules.
-- Decisions are unchanged.

-- Role-bound rules (rules, cross_org_rules) apply only in orgs where the user
-- holds a role. Those roles are resolved once per org that has a direct
-- assignment, delegation or derived role for the user and a rule matching the
-- request, then the matching rules are read through that (org, role) set.
-- Resolving roles per rule row instead made the cost grow with every rule of
-- every tenant.

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
    v_activities               TEXT[];
    v_views                    TEXT[];
    v_held_org                 UUID[];
    v_held_role                UUID[];
    v_local_modality           morbac.modality[];
    v_local_context            UUID[];
    v_local_prio               INTEGER[];
    v_cross_modality           morbac.modality[];
    v_cross_context            UUID[];
    v_cross_prio               INTEGER[];
BEGIN
    v_is_system_principal := EXISTS (
        SELECT 1 FROM morbac.system_principals WHERE user_id = p_user_id
    );

    v_activities := ARRAY(SELECT activity FROM morbac.get_effective_activities(p_activity));
    v_views      := ARRAY(SELECT view     FROM morbac.get_effective_views(p_view));

    -- Roles the user holds, per org. get_comprehensive_roles() returns nothing
    -- in an org without a direct assignment, delegation or derived role for the
    -- user, and its result only matters where a rule matches the request.
    WITH orgs AS MATERIALIZED (
        SELECT o.org_id
        FROM (
            SELECT ur.org_id FROM morbac.user_roles ur WHERE ur.user_id = p_user_id
            UNION
            SELECT d.org_id FROM morbac.delegations d WHERE d.delegatee_id = p_user_id
            UNION
            SELECT ro.org_id FROM morbac.derived_roles dr
            INNER JOIN morbac.roles ro ON ro.id = dr.role_id
        ) o
        WHERE EXISTS (
                SELECT 1 FROM morbac.rules r
                WHERE r.org_id = o.org_id
                  AND r.activity = ANY (v_activities)
                  AND r.view     = ANY (v_views)
            )
           OR EXISTS (
                SELECT 1 FROM morbac.cross_org_rules cr
                WHERE cr.source_org_id = o.org_id
                  AND cr.target_org_id = p_org_id
                  AND cr.activity = ANY (v_activities)
                  AND cr.view     = ANY (v_views)
            )
    ),
    held AS (
        SELECT DISTINCT c.org_id, g.role_id
        FROM orgs c
        CROSS JOIN LATERAL morbac.get_comprehensive_roles(p_user_id, c.org_id) g
    )
    SELECT array_agg(h.org_id ORDER BY h.org_id, h.role_id),
           array_agg(h.role_id ORDER BY h.org_id, h.role_id)
    INTO v_held_org, v_held_role
    FROM held h;

    -- Local rules applicable at p_org_id (prohibitions are not collected for
    -- system principals, which skip them)
    WITH matched AS MATERIALIZED (
        SELECT r.org_id, r.scope, r.modality, r.context_id, COALESCE(r.priority, 0) AS prio
        FROM unnest(v_held_org, v_held_role) AS h(org_id, role_id)
        INNER JOIN morbac.rules r ON r.org_id = h.org_id AND r.role_id = h.role_id
        WHERE r.activity = ANY (v_activities)
          AND r.view     = ANY (v_views)
          AND (r.modality = 'permission' OR (r.modality = 'prohibition' AND NOT v_is_system_principal))
          AND morbac.is_rule_valid(r.valid_from, r.valid_until)
    ),
    in_scope AS MATERIALIZED (
        SELECT s.org_id, s.scope
        FROM (SELECT DISTINCT m.org_id, m.scope FROM matched m) s
        WHERE morbac.org_in_scope(p_org_id, s.org_id, s.scope)
    )
    SELECT array_agg(m.modality   ORDER BY m.prio DESC, m.modality, m.context_id),
           array_agg(m.context_id ORDER BY m.prio DESC, m.modality, m.context_id),
           array_agg(m.prio       ORDER BY m.prio DESC, m.modality, m.context_id)
    INTO v_local_modality, v_local_context, v_local_prio
    FROM matched m
    INNER JOIN in_scope s ON s.org_id = m.org_id AND s.scope = m.scope;

    -- Cross-org rules into p_org_id whose role the user holds in the source org
    SELECT array_agg(cr.modality                 ORDER BY COALESCE(cr.priority, 0) DESC, cr.modality, cr.context_id),
           array_agg(cr.context_id               ORDER BY COALESCE(cr.priority, 0) DESC, cr.modality, cr.context_id),
           array_agg(COALESCE(cr.priority, 0)    ORDER BY COALESCE(cr.priority, 0) DESC, cr.modality, cr.context_id)
    INTO v_cross_modality, v_cross_context, v_cross_prio
    FROM unnest(v_held_org, v_held_role) AS h(org_id, role_id)
    INNER JOIN morbac.cross_org_rules cr ON cr.source_org_id = h.org_id AND cr.role_id = h.role_id
    WHERE cr.target_org_id = p_org_id
      AND cr.activity = ANY (v_activities)
      AND cr.view     = ANY (v_views)
      AND (cr.modality = 'permission' OR (cr.modality = 'prohibition' AND NOT v_is_system_principal))
      AND morbac.is_rule_valid(cr.valid_from, cr.valid_until);

    -- STEPS 1-3.5: Prohibitions - skipped entirely for system principals
    IF NOT v_is_system_principal THEN

        -- STEP 1: Local prohibitions - find the highest-priority applicable one
        FOR v_rule IN
            SELECT u.context_id, u.prio
            FROM unnest(v_local_modality, v_local_context, v_local_prio) AS u(modality, context_id, prio)
            WHERE u.modality = 'prohibition'
            ORDER BY u.prio DESC
        LOOP
            IF morbac.eval_context(v_rule.context_id) THEN
                v_max_prohibition_priority := v_rule.prio;
                EXIT;
            END IF;
        END LOOP;

        -- STEP 2: Cross-org prohibitions - update max if a higher priority is found
        FOR v_rule IN
            SELECT u.context_id, u.prio
            FROM unnest(v_cross_modality, v_cross_context, v_cross_prio) AS u(modality, context_id, prio)
            WHERE u.modality = 'prohibition'
            ORDER BY u.prio DESC
        LOOP
            IF morbac.eval_context(v_rule.context_id) THEN
                IF v_max_prohibition_priority IS NULL OR v_rule.prio > v_max_prohibition_priority THEN
                    v_max_prohibition_priority := v_rule.prio;
                END IF;
                EXIT;
            END IF;
        END LOOP;

        -- STEP 3: User-level prohibitions - direct user rules, update max if higher
        FOR v_rule IN
            SELECT ur.context_id, COALESCE(ur.priority, 0) AS prio
            FROM morbac.user_rules ur
            WHERE ur.user_id = p_user_id
              AND ur.org_id IS NOT DISTINCT FROM p_org_id
              AND ur.modality = 'prohibition'
              AND ur.activity = ANY (v_activities)
              AND ur.view     = ANY (v_views)
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
              AND (gr.activity IS NULL OR gr.activity = ANY (v_activities))
              AND (gr.view     IS NULL OR gr.view     = ANY (v_views))
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

    -- STEP 4: Local permissions - find the highest-priority applicable one
    FOR v_rule IN
        SELECT u.context_id, u.prio
        FROM unnest(v_local_modality, v_local_context, v_local_prio) AS u(modality, context_id, prio)
        WHERE u.modality = 'permission'
        ORDER BY u.prio DESC
    LOOP
        IF morbac.eval_context(v_rule.context_id) THEN
            v_max_permission_priority := v_rule.prio;
            EXIT;
        END IF;
    END LOOP;

    -- STEP 5: Cross-org permissions - update max if higher found
    FOR v_rule IN
        SELECT u.context_id, u.prio
        FROM unnest(v_cross_modality, v_cross_context, v_cross_prio) AS u(modality, context_id, prio)
        WHERE u.modality = 'permission'
        ORDER BY u.prio DESC
    LOOP
        IF morbac.eval_context(v_rule.context_id) THEN
            IF v_max_permission_priority IS NULL OR v_rule.prio > v_max_permission_priority THEN
                v_max_permission_priority := v_rule.prio;
            END IF;
            EXIT;
        END IF;
    END LOOP;

    -- STEP 6: User-level permissions - direct user rules, update max if higher
    FOR v_rule IN
        SELECT ur.context_id, COALESCE(ur.priority, 0) AS prio
        FROM morbac.user_rules ur
        WHERE ur.user_id = p_user_id
          AND ur.org_id IS NOT DISTINCT FROM p_org_id
          AND ur.modality = 'permission'
          AND ur.activity = ANY (v_activities)
          AND ur.view     = ANY (v_views)
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
          AND (gr.activity IS NULL OR gr.activity = ANY (v_activities))
          AND (gr.view     IS NULL OR gr.view     = ANY (v_views))
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
