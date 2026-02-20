-- =============================================================================
-- VALIDATION FUNCTIONS
-- =============================================================================

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
