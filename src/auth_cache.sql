-- Authorization decision cache to avoid repeated expensive computations.
-- TTL is configurable via morbac.config (cache_ttl_seconds).

CREATE TABLE morbac.auth_cache (
    user_id UUID NOT NULL,
    org_id UUID NOT NULL,
    activity TEXT NOT NULL,
    view TEXT NOT NULL,
    allowed BOOLEAN NOT NULL,
    computed_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    expires_at TIMESTAMPTZ NOT NULL DEFAULT (CURRENT_TIMESTAMP + INTERVAL '5 minutes'),
    PRIMARY KEY (user_id, org_id, activity, view)
);

CREATE INDEX idx_auth_cache_expires ON morbac.auth_cache(expires_at);
CREATE INDEX idx_auth_cache_user_org ON morbac.auth_cache(user_id, org_id);

COMMENT ON TABLE morbac.auth_cache IS
'Authorization decision cache - expires after 5 minutes or when policies change';

CREATE OR REPLACE FUNCTION morbac.invalidate_cache(p_user_id UUID DEFAULT NULL, p_org_id UUID DEFAULT NULL)
RETURNS VOID
LANGUAGE plpgsql
AS $$
BEGIN
    IF p_user_id IS NOT NULL AND p_org_id IS NOT NULL THEN
        DELETE FROM morbac.auth_cache WHERE user_id = p_user_id AND org_id = p_org_id;
    ELSIF p_org_id IS NOT NULL THEN
        DELETE FROM morbac.auth_cache WHERE org_id = p_org_id;
    ELSIF p_user_id IS NOT NULL THEN
        DELETE FROM morbac.auth_cache WHERE user_id = p_user_id;
    ELSE
        DELETE FROM morbac.auth_cache;
    END IF;
END;
$$;

COMMENT ON FUNCTION morbac.invalidate_cache(UUID, UUID) IS
'Invalidate auth cache for specific user/org or all entries';

CREATE OR REPLACE FUNCTION morbac.cleanup_auth_cache()
RETURNS INTEGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_deleted INTEGER;
BEGIN
    DELETE FROM morbac.auth_cache WHERE expires_at < CURRENT_TIMESTAMP;
    GET DIAGNOSTICS v_deleted = ROW_COUNT;
    RETURN v_deleted;
END;
$$;

COMMENT ON FUNCTION morbac.cleanup_auth_cache() IS
'Remove expired cache entries - call periodically via cron';

-- Invalidate cache on rule or role changes

CREATE OR REPLACE FUNCTION morbac.invalidate_cache_on_change()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_org_id UUID;
BEGIN
    IF TG_OP = 'DELETE' THEN
        BEGIN
            v_org_id := OLD.org_id;
        EXCEPTION WHEN undefined_column THEN
            v_org_id := NULL;
        END;
    ELSE
        BEGIN
            v_org_id := NEW.org_id;
        EXCEPTION WHEN undefined_column THEN
            v_org_id := NULL;
        END;
    END IF;
    IF v_org_id IS NOT NULL THEN
        DELETE FROM morbac.auth_cache WHERE org_id = v_org_id;
    END IF;
    RETURN COALESCE(NEW, OLD);
END;
$$;

CREATE TRIGGER trg_invalidate_cache_rules
AFTER INSERT OR UPDATE OR DELETE ON morbac.rules
FOR EACH ROW EXECUTE FUNCTION morbac.invalidate_cache_on_change();

CREATE TRIGGER trg_invalidate_cache_user_roles
AFTER INSERT OR UPDATE OR DELETE ON morbac.user_roles
FOR EACH ROW EXECUTE FUNCTION morbac.invalidate_cache_on_change();

CREATE TRIGGER trg_invalidate_cache_delegations
AFTER INSERT OR UPDATE OR DELETE ON morbac.delegations
FOR EACH ROW EXECUTE FUNCTION morbac.invalidate_cache_on_change();

CREATE TRIGGER trg_invalidate_cache_cross_org
AFTER INSERT OR UPDATE OR DELETE ON morbac.cross_org_rules
FOR EACH ROW EXECUTE FUNCTION morbac.invalidate_cache_on_change();

CREATE OR REPLACE FUNCTION morbac.invalidate_cache_on_user_rule_change()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_user_id UUID;
    v_org_id  UUID;
BEGIN
    IF TG_OP = 'DELETE' THEN
        v_user_id := OLD.user_id;
        v_org_id  := OLD.org_id;
    ELSE
        v_user_id := NEW.user_id;
        v_org_id  := NEW.org_id;
    END IF;
    DELETE FROM morbac.auth_cache WHERE user_id = v_user_id AND org_id = v_org_id;
    RETURN COALESCE(NEW, OLD);
END;
$$;

CREATE TRIGGER trg_invalidate_cache_user_rules
AFTER INSERT OR UPDATE OR DELETE ON morbac.user_rules
FOR EACH ROW EXECUTE FUNCTION morbac.invalidate_cache_on_user_rule_change();

-- Global rules have no org scope — any change invalidates the entire cache
CREATE OR REPLACE FUNCTION morbac.invalidate_cache_on_global_rule_change()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    DELETE FROM morbac.auth_cache;
    RETURN COALESCE(NEW, OLD);
END;
$$;

CREATE TRIGGER trg_invalidate_cache_global_rules
AFTER INSERT OR UPDATE OR DELETE ON morbac.global_rules
FOR EACH ROW EXECUTE FUNCTION morbac.invalidate_cache_on_global_rule_change();

-- system_principals changes affect prohibition bypass — invalidate per user
CREATE OR REPLACE FUNCTION morbac.invalidate_cache_on_system_principal_change()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_user_id UUID;
BEGIN
    v_user_id := CASE WHEN TG_OP = 'DELETE' THEN OLD.user_id ELSE NEW.user_id END;
    DELETE FROM morbac.auth_cache WHERE user_id = v_user_id;
    RETURN COALESCE(NEW, OLD);
END;
$$;

CREATE TRIGGER trg_invalidate_cache_system_principals
AFTER INSERT OR UPDATE OR DELETE ON morbac.system_principals
FOR EACH ROW EXECUTE FUNCTION morbac.invalidate_cache_on_system_principal_change();

-- Refresh materialized hierarchy views when hierarchies change

CREATE OR REPLACE FUNCTION morbac.refresh_on_hierarchy_change()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    PERFORM morbac.refresh_hierarchy_cache();
    DELETE FROM morbac.auth_cache;
    RETURN COALESCE(NEW, OLD);
END;
$$;

CREATE TRIGGER trg_refresh_role_hierarchy
AFTER INSERT OR UPDATE OR DELETE ON morbac.role_hierarchy
FOR EACH STATEMENT EXECUTE FUNCTION morbac.refresh_on_hierarchy_change();

CREATE TRIGGER trg_refresh_activity_hierarchy
AFTER INSERT OR UPDATE OR DELETE ON morbac.activity_hierarchy
FOR EACH STATEMENT EXECUTE FUNCTION morbac.refresh_on_hierarchy_change();

CREATE TRIGGER trg_refresh_view_hierarchy
AFTER INSERT OR UPDATE OR DELETE ON morbac.view_hierarchy
FOR EACH STATEMENT EXECUTE FUNCTION morbac.refresh_on_hierarchy_change();

-- Invalidate entire cache when org hierarchy changes.
-- Scoped rules (scope != 'self') depend on the org tree, so any org change
-- may affect which orgs a rule covers.

CREATE OR REPLACE FUNCTION morbac.invalidate_all_cache()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    DELETE FROM morbac.auth_cache;
    RETURN NULL;
END;
$$;

CREATE TRIGGER trg_invalidate_cache_orgs
AFTER INSERT OR UPDATE OR DELETE ON morbac.orgs
FOR EACH STATEMENT EXECUTE FUNCTION morbac.invalidate_all_cache();
