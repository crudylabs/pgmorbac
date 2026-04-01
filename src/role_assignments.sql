-- assign_role / revoke_role: convenience wrappers that enforce SoD and
-- cardinality constraints. Access control is handled by RLS on morbac.user_roles.

CREATE OR REPLACE FUNCTION morbac.assign_role(
    p_target_user_id UUID,
    p_role_id UUID,
    p_org_id UUID
)
RETURNS VOID
LANGUAGE plpgsql
AS $$
BEGIN
    IF morbac.check_sod_violation(p_target_user_id, p_role_id, p_org_id) THEN
        RAISE EXCEPTION 'Role assignment would violate Separation of Duty constraints';
    END IF;

    -- INSERT triggers RLS policy on morbac.user_roles (create on user_roles view)
    INSERT INTO morbac.user_roles (user_id, role_id, org_id)
    VALUES (p_target_user_id, p_role_id, p_org_id)
    ON CONFLICT (user_id, role_id, org_id) DO NOTHING;

    DECLARE
        v_error TEXT;
    BEGIN
        v_error := morbac.check_cardinality_violation(p_role_id);
        IF v_error IS NOT NULL THEN
            RAISE EXCEPTION 'Role assignment violates cardinality constraint: %', v_error;
        END IF;
    END;
END;
$$;

COMMENT ON FUNCTION morbac.assign_role(UUID, UUID, UUID) IS
'Assign role with SoD and cardinality validation. RLS on morbac.user_roles enforces authorization.';

CREATE OR REPLACE FUNCTION morbac.revoke_role(
    p_target_user_id UUID,
    p_role_id UUID,
    p_org_id UUID
)
RETURNS VOID
LANGUAGE plpgsql
AS $$
BEGIN
    -- DELETE triggers RLS policy on morbac.user_roles (delete on user_roles view)
    DELETE FROM morbac.user_roles
    WHERE user_id = p_target_user_id
      AND role_id = p_role_id
      AND org_id = p_org_id;

    DECLARE
        v_error TEXT;
    BEGIN
        v_error := morbac.check_cardinality_violation(p_role_id, FALSE);
        IF v_error IS NOT NULL THEN
            RAISE WARNING 'Role revocation may violate cardinality constraint: %', v_error;
        END IF;
    END;
END;
$$;

COMMENT ON FUNCTION morbac.revoke_role(UUID, UUID, UUID) IS
'Revoke role with cardinality validation. RLS on morbac.user_roles enforces authorization.';
