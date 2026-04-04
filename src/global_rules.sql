-- Global rules: Rule(user_id, activity, view, context, modality)
--
-- No org_id or role_id — applies system-wide regardless of org membership or roles.
-- user_id NULL = every user; non-NULL = specific user only.
-- activity NULL = any activity; view NULL = any view.
--
-- Evaluated at steps 3.5 (prohibitions) and 6.5 (permissions) in is_allowed_nocache().
-- When activity/view are set, hierarchy resolution applies normally.

CREATE TABLE morbac.global_rules (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID,
    activity TEXT REFERENCES morbac.activities(name) ON DELETE CASCADE,
    view TEXT REFERENCES morbac.views(name) ON DELETE CASCADE,
    context_id UUID NOT NULL REFERENCES morbac.contexts(id) ON DELETE CASCADE,
    modality morbac.modality NOT NULL,
    priority INTEGER,
    valid_from TIMESTAMPTZ,
    valid_until TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    is_active BOOLEAN NOT NULL DEFAULT FALSE,
    metadata JSONB DEFAULT '{}'::jsonb,
    CHECK (valid_until IS NULL OR valid_from IS NULL OR valid_until > valid_from),
    UNIQUE(user_id, activity, view, context_id, modality)
);

CREATE INDEX idx_global_rules_user_id ON morbac.global_rules(user_id);
CREATE INDEX idx_global_rules_activity_view ON morbac.global_rules(activity, view);
CREATE INDEX idx_global_rules_modality ON morbac.global_rules(modality);
CREATE INDEX idx_global_rules_fast_lookup ON morbac.global_rules(modality)
    INCLUDE (user_id, activity, view, context_id)
    WHERE is_active = true;

COMMENT ON TABLE morbac.global_rules IS
'System-wide rules with no org or role binding. user_id NULL = all users; activity/view NULL = any activity/view.';
COMMENT ON COLUMN morbac.global_rules.user_id IS
'NULL = all users; non-NULL = this specific user only';
COMMENT ON COLUMN morbac.global_rules.activity IS
'NULL = any activity; non-NULL = specific activity (hierarchy applies)';
COMMENT ON COLUMN morbac.global_rules.view IS
'NULL = any view; non-NULL = specific view (hierarchy applies)';

CREATE OR REPLACE FUNCTION morbac.global_rules_set_is_active()
RETURNS TRIGGER AS $$
BEGIN
    NEW.is_active := (
        (NEW.valid_from IS NULL OR NEW.valid_from <= CURRENT_TIMESTAMP)
        AND (NEW.valid_until IS NULL OR NEW.valid_until > CURRENT_TIMESTAMP)
    );
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_global_rules_set_is_active ON morbac.global_rules;
CREATE TRIGGER trg_global_rules_set_is_active
BEFORE INSERT OR UPDATE ON morbac.global_rules
FOR EACH ROW EXECUTE FUNCTION morbac.global_rules_set_is_active();
