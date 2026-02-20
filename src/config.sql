-- =============================================================================
-- CONFIGURATION
-- =============================================================================
-- Centralized configuration for pg_morbac extension
-- Edit these values to customize behavior

CREATE TABLE morbac.config (
    key TEXT PRIMARY KEY,
    value TEXT NOT NULL,
    description TEXT,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

COMMENT ON TABLE morbac.config IS 'Extension configuration - edit values to customize behavior';

-- Insert default configuration values
INSERT INTO morbac.config (key, value, description) VALUES
    ('cache_ttl_seconds', '300', 'Authorization cache time-to-live in seconds (default: 5 minutes)'),
    ('hierarchy_max_depth', '10', 'Maximum depth for hierarchy traversal to prevent infinite loops'),
    ('enable_audit_by_default', 'false', 'Whether to enable audit logging by default on installation');

-- Helper function to get configuration values
CREATE OR REPLACE FUNCTION morbac.get_config(p_key TEXT)
RETURNS TEXT
LANGUAGE plpgsql
STABLE
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

-- Helper function to set configuration values
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
