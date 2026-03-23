-- =============================================================================
-- POLICY DSL TABLE
-- =============================================================================
-- Simplified table for developers to declare policy
-- Uses friendly names instead of UUIDs

CREATE TABLE morbac.policy (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    org_name TEXT NOT NULL,
    role_name TEXT NOT NULL,
    activity TEXT NOT NULL,
    view TEXT NOT NULL,
    modality morbac.modality NOT NULL,
    context_name TEXT NOT NULL DEFAULT 'always',
    priority INTEGER,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    compiled BOOLEAN NOT NULL DEFAULT FALSE
);

-- UNIQUE including priority: NULL treated as -1 so two NULL-priority rows for the same tuple conflict
CREATE UNIQUE INDEX idx_policy_unique
    ON morbac.policy(org_name, role_name, activity, view, modality, context_name, COALESCE(priority, -1));

CREATE INDEX idx_policy_not_compiled ON morbac.policy(compiled) WHERE NOT compiled;

COMMENT ON TABLE morbac.policy IS 'Policy DSL - simplified policy declaration using names';
COMMENT ON COLUMN morbac.policy.org_name IS 'Organization name (resolved during compilation)';
COMMENT ON COLUMN morbac.policy.role_name IS 'Role name (resolved during compilation)';
COMMENT ON COLUMN morbac.policy.activity IS 'Activity name';
COMMENT ON COLUMN morbac.policy.view IS 'View name';
COMMENT ON COLUMN morbac.policy.modality IS 'Deontic modality';
COMMENT ON COLUMN morbac.policy.context_name IS 'Context name (default: always)';
COMMENT ON COLUMN morbac.policy.priority IS 'Optional rule priority (higher wins over lower; NULL = 0)';
COMMENT ON COLUMN morbac.policy.compiled IS 'Whether this policy entry has been compiled into rules';

-- Helper function to check administration permissions
CREATE OR REPLACE FUNCTION morbac.is_admin_allowed(
    p_user_id UUID,
    p_org_id UUID,
    p_admin_activity TEXT,
    p_admin_target TEXT
)
RETURNS BOOLEAN
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    v_rule RECORD;
BEGIN
    -- Check for admin prohibitions first
    FOR v_rule IN
        SELECT ar.context_id
        FROM morbac.admin_rules ar
        WHERE ar.org_id = p_org_id
          AND ar.admin_activity = p_admin_activity
          AND ar.admin_target = p_admin_target
          AND ar.modality = 'prohibition'
          AND ar.role_id IN (
              SELECT role_id FROM morbac.get_comprehensive_roles(p_user_id, p_org_id)
          )
    LOOP
        IF morbac.eval_context(v_rule.context_id) THEN
            RETURN FALSE;
        END IF;
    END LOOP;

    -- Check for admin permissions
    FOR v_rule IN
        SELECT ar.context_id
        FROM morbac.admin_rules ar
        WHERE ar.org_id = p_org_id
          AND ar.admin_activity = p_admin_activity
          AND ar.admin_target = p_admin_target
          AND ar.modality = 'permission'
          AND ar.role_id IN (
              SELECT role_id FROM morbac.get_comprehensive_roles(p_user_id, p_org_id)
          )
    LOOP
        IF morbac.eval_context(v_rule.context_id) THEN
            RETURN TRUE;
        END IF;
    END LOOP;

    RETURN FALSE; -- Default deny
END;
$$;

COMMENT ON FUNCTION morbac.is_admin_allowed(UUID, UUID, TEXT, TEXT) IS
'Checks administration permissions for policy management operations';

-- =============================================================================
-- POLICY COMPILER
-- =============================================================================
-- Translates policy DSL entries into concrete rules
-- Resolves names to IDs
-- Idempotent - safe to run multiple times

CREATE OR REPLACE FUNCTION morbac.compile_policy()
RETURNS TABLE(
    compiled_count INTEGER,
    error_count INTEGER,
    errors TEXT[]
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_policy RECORD;
    v_org_id UUID;
    v_role_id UUID;
    v_context_id UUID;
    v_compiled INTEGER := 0;
    v_errors TEXT[] := ARRAY[]::TEXT[];
    v_error_count INTEGER := 0;
BEGIN
    -- Process all uncompiled policy entries
    FOR v_policy IN
        SELECT * FROM morbac.policy WHERE NOT compiled
    LOOP
        BEGIN
            -- Resolve organization
            SELECT id INTO STRICT v_org_id
            FROM morbac.orgs
            WHERE name = v_policy.org_name;

            -- Resolve role within organization
            SELECT id INTO STRICT v_role_id
            FROM morbac.roles
            WHERE org_id = v_org_id AND name = v_policy.role_name;

            -- Resolve context
            SELECT id INTO STRICT v_context_id
            FROM morbac.contexts
            WHERE name = v_policy.context_name;

            -- Ensure activity exists
            INSERT INTO morbac.activities (name)
            VALUES (v_policy.activity)
            ON CONFLICT (name) DO NOTHING;

            -- Ensure view exists
            INSERT INTO morbac.views (name)
            VALUES (v_policy.view)
            ON CONFLICT (name) DO NOTHING;

            -- Insert rule (ignore if already exists)
            INSERT INTO morbac.rules (org_id, role_id, activity, view, context_id, modality, priority)
            VALUES (v_org_id, v_role_id, v_policy.activity, v_policy.view, v_context_id, v_policy.modality, v_policy.priority)
            ON CONFLICT (org_id, role_id, activity, view, context_id, modality) DO NOTHING;

            -- Mark as compiled
            UPDATE morbac.policy SET compiled = TRUE WHERE id = v_policy.id;

            v_compiled := v_compiled + 1;

        EXCEPTION WHEN OTHERS THEN
            v_error_count := v_error_count + 1;
            v_errors := array_append(v_errors,
                format('Policy %s: %s', v_policy.id, SQLERRM));
        END;
    END LOOP;

    RETURN QUERY SELECT v_compiled, v_error_count, v_errors;
END;
$$;

COMMENT ON FUNCTION morbac.compile_policy() IS
'Compiles policy DSL entries into concrete rules - idempotent and safe to run multiple times';
