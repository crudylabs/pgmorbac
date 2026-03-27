CREATE OR REPLACE FUNCTION morbac.can_manage_user_role(
    p_admin_user_id UUID,
    p_org_id UUID,
    p_target_role_id UUID
)
RETURNS BOOLEAN
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    v_role_name TEXT;
BEGIN
    SELECT name INTO v_role_name
    FROM morbac.roles
    WHERE id = p_target_role_id AND org_id = p_org_id;

    IF v_role_name IS NULL THEN
        RETURN FALSE;
    END IF;

    RETURN morbac.is_admin_allowed(
        p_admin_user_id,
        p_org_id,
        'assign_role',
        v_role_name
    );
END;
$$;

COMMENT ON FUNCTION morbac.can_manage_user_role(UUID, UUID, UUID) IS
'Check if user can assign/revoke a specific role in organization';

CREATE OR REPLACE FUNCTION morbac.can_manage_roles(
    p_user_id UUID,
    p_org_id UUID
)
RETURNS BOOLEAN
LANGUAGE plpgsql
STABLE
AS $$
BEGIN
    RETURN morbac.is_admin_allowed(
        p_user_id,
        p_org_id,
        'manage',
        'roles'
    );
END;
$$;

COMMENT ON FUNCTION morbac.can_manage_roles(UUID, UUID) IS
'Check if user can create/modify/delete roles in organization';

CREATE OR REPLACE FUNCTION morbac.can_manage_policies(
    p_user_id UUID,
    p_org_id UUID
)
RETURNS BOOLEAN
LANGUAGE plpgsql
STABLE
AS $$
BEGIN
    RETURN morbac.is_admin_allowed(
        p_user_id,
        p_org_id,
        'manage',
        'policies'
    );
END;
$$;

COMMENT ON FUNCTION morbac.can_manage_policies(UUID, UUID) IS
'Check if user can manage policies in organization';

CREATE OR REPLACE FUNCTION morbac.admin_assign_role(
    p_admin_user_id UUID,
    p_target_user_id UUID,
    p_role_id UUID,
    p_org_id UUID
)
RETURNS BOOLEAN
LANGUAGE plpgsql
AS $$
BEGIN
    IF NOT morbac.can_manage_user_role(p_admin_user_id, p_org_id, p_role_id) THEN
        RAISE EXCEPTION 'User % does not have permission to assign role % in org %',
            p_admin_user_id, p_role_id, p_org_id;
    END IF;

    IF morbac.check_sod_violation(p_target_user_id, p_role_id, p_org_id) THEN
        RAISE EXCEPTION 'Role assignment would violate Separation of Duty constraints';
    END IF;

    INSERT INTO morbac.user_roles (user_id, role_id, org_id)
    VALUES (p_target_user_id, p_role_id, p_org_id)
    ON CONFLICT (user_id, role_id, org_id) DO NOTHING;

    DECLARE
        v_cardinality_error TEXT;
    BEGIN
        v_cardinality_error := morbac.check_cardinality_violation(p_role_id);
        IF v_cardinality_error IS NOT NULL THEN
            RAISE EXCEPTION 'Role assignment violates cardinality constraint: %', v_cardinality_error;
        END IF;
    END;

    RETURN TRUE;
END;
$$;

COMMENT ON FUNCTION morbac.admin_assign_role(UUID, UUID, UUID, UUID) IS
'Assign role to user with admin permission check and constraint validation';

CREATE OR REPLACE FUNCTION morbac.admin_revoke_role(
    p_admin_user_id UUID,
    p_target_user_id UUID,
    p_role_id UUID,
    p_org_id UUID
)
RETURNS BOOLEAN
LANGUAGE plpgsql
AS $$
BEGIN
    IF NOT morbac.can_manage_user_role(p_admin_user_id, p_org_id, p_role_id) THEN
        RAISE EXCEPTION 'User % does not have permission to revoke role % in org %',
            p_admin_user_id, p_role_id, p_org_id;
    END IF;

    DELETE FROM morbac.user_roles
    WHERE user_id = p_target_user_id
      AND role_id = p_role_id
      AND org_id = p_org_id;

    DECLARE
        v_cardinality_error TEXT;
    BEGIN
        v_cardinality_error := morbac.check_cardinality_violation(p_role_id, FALSE);
        IF v_cardinality_error IS NOT NULL THEN
            RAISE WARNING 'Role revocation may violate cardinality constraint: %', v_cardinality_error;
        END IF;
    END;

    RETURN TRUE;
END;
$$;

COMMENT ON FUNCTION morbac.admin_revoke_role(UUID, UUID, UUID, UUID) IS
'Revoke role from user with admin permission check';
