-- =============================================================================
-- VALIDATION FUNCTIONS
-- =============================================================================
--
-- Rule conflict detection (from Multi-OrBAC paper):
-- Conflicts exist when two rules share the same (org, role, activity, view, context)
-- but their modalities create a situation where one permanently overrides the other:
--   - prohibition + permission    -> permission is dead (always overridden)
--   - prohibition + obligation    -> obligation is always voided
--   - prohibition + recommendation -> recommendation is always voided
--   - obligation  + recommendation -> recommendation is always voided
--
-- Note: hierarchy-based overlaps are intentional design, not flagged here.

-- Check if role assignment would violate Separation of Duty
CREATE OR REPLACE FUNCTION morbac.check_sod_violation(
    p_user_id UUID,
    p_role_id UUID,
    p_org_id UUID
)
RETURNS BOOLEAN
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    v_conflict_exists BOOLEAN;
BEGIN
    -- Check if user already has a conflicting role
    SELECT EXISTS (
        SELECT 1
        FROM morbac.user_roles ur
        INNER JOIN morbac.sod_conflicts sod ON (
            (sod.role_a_id = ur.role_id AND sod.role_b_id = p_role_id)
            OR (sod.role_b_id = ur.role_id AND sod.role_a_id = p_role_id)
        )
        WHERE ur.user_id = p_user_id
          AND ur.org_id = p_org_id
          AND sod.org_id = p_org_id
    ) INTO v_conflict_exists;

    RETURN v_conflict_exists;
END;
$$;

COMMENT ON FUNCTION morbac.check_sod_violation(UUID, UUID, UUID) IS
'Returns true if assigning role would violate Separation of Duty constraints';

-- Check if role assignment would violate cardinality constraints
CREATE OR REPLACE FUNCTION morbac.check_cardinality_violation(
    p_role_id UUID,
    p_adding BOOLEAN DEFAULT TRUE
)
RETURNS TEXT
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    v_current_count INTEGER;
    v_min_users INTEGER;
    v_max_users INTEGER;
BEGIN
    -- Get current user count and constraints
    SELECT
        COUNT(DISTINCT ur.user_id),
        rc.min_users,
        rc.max_users
    INTO v_current_count, v_min_users, v_max_users
    FROM morbac.user_roles ur
    LEFT JOIN morbac.role_cardinality rc ON rc.role_id = ur.role_id
    WHERE ur.role_id = p_role_id
    GROUP BY rc.min_users, rc.max_users;

    -- Check max constraint when adding
    IF p_adding AND v_max_users IS NOT NULL THEN
        IF v_current_count >= v_max_users THEN
            RETURN format('Maximum users (%s) reached for role', v_max_users);
        END IF;
    END IF;

    -- Check min constraint when removing
    IF NOT p_adding AND v_min_users IS NOT NULL THEN
        IF v_current_count <= v_min_users THEN
            RETURN format('Minimum users (%s) required for role', v_min_users);
        END IF;
    END IF;

    RETURN NULL; -- No violation
END;
$$;

COMMENT ON FUNCTION morbac.check_cardinality_violation(UUID, BOOLEAN) IS
'Returns error message if cardinality constraint would be violated, NULL otherwise';

-- Detect direct modality conflicts for a candidate rule
CREATE OR REPLACE FUNCTION morbac.detect_rule_conflicts(
    p_org_id     UUID,
    p_role_id    UUID,
    p_activity   TEXT,
    p_view       TEXT,
    p_context_id UUID,
    p_modality   morbac.modality,
    p_exclude_id UUID DEFAULT NULL  -- exclude self on UPDATE
)
RETURNS TABLE(
    conflicting_rule_id  UUID,
    conflicting_modality morbac.modality,
    description          TEXT
)
LANGUAGE plpgsql
STABLE
AS $$
BEGIN
    RETURN QUERY
    SELECT
        r.id,
        r.modality,
        CASE
            WHEN p_modality = 'prohibition'
                THEN 'prohibition voids existing ' || r.modality::text
            WHEN r.modality = 'prohibition'
                THEN p_modality::text || ' will always be overridden by existing prohibition'
            WHEN p_modality = 'obligation' AND r.modality = 'recommendation'
                THEN 'obligation voids existing recommendation'
            ELSE
                'recommendation will always be overridden by existing obligation'
        END
    FROM morbac.rules r
    WHERE r.org_id     = p_org_id
      AND r.role_id    = p_role_id
      AND r.activity   = p_activity
      AND r.view       = p_view
      AND r.context_id = p_context_id
      AND r.modality  != p_modality
      AND (p_exclude_id IS NULL OR r.id != p_exclude_id)
      AND (
          (p_modality = 'prohibition'    AND r.modality IN ('permission', 'obligation', 'recommendation'))
          OR (r.modality = 'prohibition' AND p_modality IN ('permission', 'obligation', 'recommendation'))
          OR (p_modality = 'obligation'     AND r.modality = 'recommendation')
          OR (p_modality = 'recommendation' AND r.modality = 'obligation')
      );
END;
$$;

COMMENT ON FUNCTION morbac.detect_rule_conflicts(UUID, UUID, TEXT, TEXT, UUID, morbac.modality, UUID) IS
'Returns rules that directly conflict with the given tuple due to modality precedence (prohibition > obligation > recommendation > permission).';

-- Trigger: warn (non-blocking) when a new/updated rule conflicts with an existing one
CREATE OR REPLACE FUNCTION morbac.trg_warn_rule_conflicts()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_conflict RECORD;
BEGIN
    FOR v_conflict IN
        SELECT * FROM morbac.detect_rule_conflicts(
            NEW.org_id, NEW.role_id, NEW.activity, NEW.view, NEW.context_id, NEW.modality,
            CASE WHEN TG_OP = 'UPDATE' THEN NEW.id ELSE NULL END
        )
    LOOP
        RAISE WARNING 'Rule conflict: % (conflicts with rule %)',
            v_conflict.description, v_conflict.conflicting_rule_id;
    END LOOP;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_rules_conflict_check ON morbac.rules;
CREATE TRIGGER trg_rules_conflict_check
BEFORE INSERT OR UPDATE ON morbac.rules
FOR EACH ROW EXECUTE FUNCTION morbac.trg_warn_rule_conflicts();

COMMENT ON FUNCTION morbac.trg_warn_rule_conflicts() IS
'Trigger function: emits a WARNING (non-blocking) when a rule conflicts with an existing rule due to modality precedence.';
