CREATE TABLE morbac.config (
    key TEXT PRIMARY KEY,
    value TEXT NOT NULL,
    description TEXT,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

COMMENT ON TABLE morbac.config IS 'Extension configuration - edit values to customize behavior';

INSERT INTO morbac.config (key, value, description) VALUES
    ('cache_ttl_seconds',       '300',             'Authorization cache time-to-live in seconds (default: 5 minutes)'),
    ('hierarchy_max_depth',     '10',              'Maximum depth for hierarchy traversal to prevent infinite loops'),
    ('enable_audit_by_default', 'false',           'Whether to enable audit logging by default on installation'),
    -- System view names used in RLS policies on morbac tables.
    -- Override with morbac.set_config() to use your own naming conventions.
    -- The configured name must exist in morbac.views and your rules must reference it.
    ('system_view.orgs',            'orgs',            'View name for morbac.orgs table access control'),
    ('system_view.roles',           'roles',           'View name for morbac.roles table access control'),
    ('system_view.rules',           'rules',           'View name for morbac.rules table access control'),
    ('system_view.user_roles',      'user_roles',      'View name for morbac.user_roles table access control'),
    ('system_view.contexts',        'contexts',        'View name for morbac.contexts table access control'),
    ('system_view.activities',      'activities',      'View name for morbac.activities table access control'),
    ('system_view.views',           'views',           'View name for morbac.views table access control'),
    ('system_view.delegations',     'delegations',     'View name for morbac.delegations table access control'),
    ('system_view.cross_org_rules', 'cross_org_rules', 'View name for morbac.cross_org_rules table access control'),
    ('system_view.user_rules',      'user_rules',      'View name for morbac.user_rules table access control'),
    ('system_view.global_rules',       'global_rules',       'View name for morbac.global_rules table access control'),
    ('system_view.system_principals',  'system_principals',  'View name for morbac.system_principals table access control');

CREATE OR REPLACE FUNCTION morbac.get_config(p_key TEXT)
RETURNS TEXT
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
AS $$
DECLARE
    v_value TEXT;
BEGIN
    SELECT value INTO v_value FROM morbac.config WHERE key = p_key;
    RETURN v_value;
EXCEPTION
    WHEN OTHERS THEN
        RETURN NULL;
END;
$$;

COMMENT ON FUNCTION morbac.get_config(TEXT) IS
'Get configuration value by key';

CREATE OR REPLACE FUNCTION morbac.set_config(p_key TEXT, p_value TEXT)
RETURNS VOID
LANGUAGE plpgsql
AS $$
BEGIN
    UPDATE morbac.config
    SET value = p_value, updated_at = CURRENT_TIMESTAMP
    WHERE key = p_key;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Configuration key % does not exist', p_key;
    END IF;
END;
$$;

COMMENT ON FUNCTION morbac.set_config(TEXT, TEXT) IS
'Set configuration value by key';
