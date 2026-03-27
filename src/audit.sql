-- Optional audit logging for tracking changes to security-critical tables.
-- Enable/disable per table with morbac.enable_audit() / morbac.disable_audit().

CREATE TABLE morbac.audit_log (
    id BIGSERIAL PRIMARY KEY,
    timestamp TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    user_id UUID,
    org_id UUID,
    table_name TEXT NOT NULL,
    operation TEXT NOT NULL,
    record_id UUID,
    old_data JSONB,
    new_data JSONB,
    changed_fields TEXT[],
    session_username TEXT DEFAULT SESSION_USER,
    client_addr INET DEFAULT INET_CLIENT_ADDR(),
    application_name TEXT DEFAULT CURRENT_SETTING('application_name', true),
    metadata JSONB DEFAULT '{}'::jsonb
);

CREATE INDEX idx_audit_log_timestamp ON morbac.audit_log(timestamp DESC);
CREATE INDEX idx_audit_log_user_id ON morbac.audit_log(user_id);
CREATE INDEX idx_audit_log_org_id ON morbac.audit_log(org_id);
CREATE INDEX idx_audit_log_table_operation ON morbac.audit_log(table_name, operation);
CREATE INDEX idx_audit_log_record_id ON morbac.audit_log(record_id);

COMMENT ON TABLE morbac.audit_log IS 'Audit trail for security-critical operations';
COMMENT ON COLUMN morbac.audit_log.user_id IS 'Application user (from morbac.current_user_id() if available)';
COMMENT ON COLUMN morbac.audit_log.org_id IS 'Organization context (from morbac.current_org_id() if available)';
COMMENT ON COLUMN morbac.audit_log.operation IS 'INSERT, UPDATE, DELETE, or custom operation name';
COMMENT ON COLUMN morbac.audit_log.changed_fields IS 'Array of field names that changed (for UPDATE operations)';
COMMENT ON COLUMN morbac.audit_log.session_username IS 'Database session user';
COMMENT ON COLUMN morbac.audit_log.client_addr IS 'Client IP address';

CREATE OR REPLACE FUNCTION morbac.audit_trigger()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_old_data JSONB;
    v_new_data JSONB;
    v_changed_fields TEXT[];
    v_user_id UUID;
    v_org_id UUID;
    v_record_id UUID;
BEGIN
    BEGIN
        v_user_id := morbac.current_user_id();
    EXCEPTION WHEN OTHERS THEN
        v_user_id := NULL;
    END;

    BEGIN
        v_org_id := morbac.current_org_id();
    EXCEPTION WHEN OTHERS THEN
        v_org_id := NULL;
    END;

    IF TG_OP = 'DELETE' THEN
        v_old_data := row_to_json(OLD)::jsonb;
        v_new_data := NULL;
        v_record_id := (v_old_data->>'id')::uuid;
    ELSIF TG_OP = 'INSERT' THEN
        v_old_data := NULL;
        v_new_data := row_to_json(NEW)::jsonb;
        v_record_id := (v_new_data->>'id')::uuid;
    ELSIF TG_OP = 'UPDATE' THEN
        v_old_data := row_to_json(OLD)::jsonb;
        v_new_data := row_to_json(NEW)::jsonb;
        v_record_id := (v_new_data->>'id')::uuid;

        SELECT array_agg(key)
        INTO v_changed_fields
        FROM jsonb_each(v_old_data)
        WHERE v_old_data->key IS DISTINCT FROM v_new_data->key;
    END IF;

    IF v_org_id IS NULL THEN
        IF v_new_data ? 'org_id' THEN
            v_org_id := (v_new_data->>'org_id')::uuid;
        ELSIF v_old_data ? 'org_id' THEN
            v_org_id := (v_old_data->>'org_id')::uuid;
        END IF;
    END IF;

    INSERT INTO morbac.audit_log (
        user_id,
        org_id,
        table_name,
        operation,
        record_id,
        old_data,
        new_data,
        changed_fields
    ) VALUES (
        v_user_id,
        v_org_id,
        TG_TABLE_NAME,
        TG_OP,
        v_record_id,
        v_old_data,
        v_new_data,
        v_changed_fields
    );

    IF TG_OP = 'DELETE' THEN
        RETURN OLD;
    ELSE
        RETURN NEW;
    END IF;
END;
$$;

COMMENT ON FUNCTION morbac.audit_trigger() IS
'Generic audit trigger function - captures INSERT/UPDATE/DELETE operations';

CREATE OR REPLACE FUNCTION morbac.enable_audit(p_table_name TEXT)
RETURNS VOID
LANGUAGE plpgsql
AS $$
DECLARE
    v_trigger_name TEXT;
BEGIN
    v_trigger_name := 'audit_' || p_table_name;

    EXECUTE format(
        'CREATE TRIGGER %I AFTER INSERT OR UPDATE OR DELETE ON morbac.%I ' ||
        'FOR EACH ROW EXECUTE FUNCTION morbac.audit_trigger()',
        v_trigger_name,
        p_table_name
    );

    RAISE NOTICE 'Audit logging enabled for morbac.%', p_table_name;
END;
$$;

COMMENT ON FUNCTION morbac.enable_audit(TEXT) IS
'Enable audit logging on a morbac table - creates audit trigger';

CREATE OR REPLACE FUNCTION morbac.disable_audit(p_table_name TEXT)
RETURNS VOID
LANGUAGE plpgsql
AS $$
DECLARE
    v_trigger_name TEXT;
BEGIN
    v_trigger_name := 'audit_' || p_table_name;

    EXECUTE format(
        'DROP TRIGGER IF EXISTS %I ON morbac.%I',
        v_trigger_name,
        p_table_name
    );

    RAISE NOTICE 'Audit logging disabled for morbac.%', p_table_name;
END;
$$;

COMMENT ON FUNCTION morbac.disable_audit(TEXT) IS
'Disable audit logging on a morbac table - removes audit trigger';
