-- System principals: backend service accounts defined at deploy time.
--
-- Registered user_ids are fully protected at the trigger level:
--   - No role assignments, revocations, or negative assignments
--   - No user_rules (permissions or prohibitions)
--   - No delegations involving them
--   - No targeted global_rules prohibitions
--   - All prohibitions are skipped in is_allowed_nocache() (see authorization.sql)
--
-- This table has no INSERT/UPDATE/DELETE RLS policies — only the database owner
-- can register or remove system principals (done in SQL at deploy time).
-- SELECT is gated by is_allowed() like all other system tables.

CREATE TABLE morbac.system_principals (
    user_id UUID PRIMARY KEY,
    description TEXT
);

COMMENT ON TABLE morbac.system_principals IS
'Registry of backend service accounts. Immutable at the trigger level — no policy can touch them.';
COMMENT ON COLUMN morbac.system_principals.user_id IS
'External user UUID of the service account';

-- Shared guard for tables with a single user_id column

CREATE OR REPLACE FUNCTION morbac.raise_if_system_principal()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_user_id UUID;
BEGIN
    v_user_id := CASE WHEN TG_OP = 'DELETE' THEN OLD.user_id ELSE NEW.user_id END;
    IF EXISTS (SELECT 1 FROM morbac.system_principals WHERE user_id = v_user_id) THEN
        RAISE EXCEPTION 'operation blocked: % is a system principal', v_user_id;
    END IF;
    RETURN COALESCE(NEW, OLD);
END;
$$;

CREATE TRIGGER trg_system_principal_user_roles
BEFORE INSERT OR UPDATE OR DELETE ON morbac.user_roles
FOR EACH ROW EXECUTE FUNCTION morbac.raise_if_system_principal();

CREATE TRIGGER trg_system_principal_user_rules
BEFORE INSERT OR UPDATE OR DELETE ON morbac.user_rules
FOR EACH ROW EXECUTE FUNCTION morbac.raise_if_system_principal();

CREATE TRIGGER trg_system_principal_negative_roles
BEFORE INSERT OR UPDATE OR DELETE ON morbac.negative_role_assignments
FOR EACH ROW EXECUTE FUNCTION morbac.raise_if_system_principal();

-- Delegations have two user_id columns

CREATE OR REPLACE FUNCTION morbac.raise_if_system_principal_delegation()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM morbac.system_principals
        WHERE user_id IN (NEW.delegator_id, NEW.delegatee_id)
    ) THEN
        RAISE EXCEPTION 'operation blocked: delegations cannot involve system principals';
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_system_principal_delegations
BEFORE INSERT OR UPDATE ON morbac.delegations
FOR EACH ROW EXECUTE FUNCTION morbac.raise_if_system_principal_delegation();

-- Global rules: all operations on rows belonging to a system principal are blocked.
-- This protects both the permission rules defined for them and prevents prohibitions
-- from being added against them. Define their rules at deploy time as the DB owner.

CREATE OR REPLACE FUNCTION morbac.raise_if_system_principal_global_rule()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_user_id UUID;
BEGIN
    v_user_id := CASE WHEN TG_OP = 'DELETE' THEN OLD.user_id ELSE NEW.user_id END;
    IF v_user_id IS NOT NULL
       AND EXISTS (SELECT 1 FROM morbac.system_principals WHERE user_id = v_user_id)
    THEN
        -- allow initial deploy-time insert when no rules exist yet for this principal
        IF TG_OP = 'INSERT'
           AND NOT EXISTS (SELECT 1 FROM morbac.global_rules WHERE user_id = v_user_id)
        THEN
            RETURN NEW;
        END IF;
        RAISE EXCEPTION 'operation blocked: global rules for system principal % are immutable', v_user_id;
    END IF;
    RETURN COALESCE(NEW, OLD);
END;
$$;

CREATE TRIGGER trg_system_principal_global_rules
BEFORE INSERT OR UPDATE OR DELETE ON morbac.global_rules
FOR EACH ROW EXECUTE FUNCTION morbac.raise_if_system_principal_global_rule();
