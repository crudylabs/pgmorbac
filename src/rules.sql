-- Core OrBAC rule relation: Rule(org, role, activity, view, context, modality)

CREATE TABLE morbac.rules (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    org_id UUID NOT NULL REFERENCES morbac.orgs(id) ON DELETE CASCADE,
    role_id UUID NOT NULL REFERENCES morbac.roles(id) ON DELETE CASCADE,
    activity TEXT NOT NULL REFERENCES morbac.activities(name) ON DELETE CASCADE,
    view TEXT NOT NULL REFERENCES morbac.views(name) ON DELETE CASCADE,
    context_id UUID NOT NULL REFERENCES morbac.contexts(id) ON DELETE CASCADE,
    modality morbac.modality NOT NULL,
    priority INTEGER,
    valid_from TIMESTAMPTZ,
    valid_until TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    is_active BOOLEAN NOT NULL DEFAULT FALSE,
    metadata JSONB DEFAULT '{}'::jsonb,
    UNIQUE(org_id, role_id, activity, view, context_id, modality),
    CHECK (valid_until IS NULL OR valid_from IS NULL OR valid_until > valid_from)
);

CREATE INDEX idx_rules_org_role ON morbac.rules(org_id, role_id);
CREATE INDEX idx_rules_activity_view ON morbac.rules(activity, view);
CREATE INDEX idx_rules_modality ON morbac.rules(modality);
CREATE INDEX idx_rules_lookup ON morbac.rules(org_id, role_id, activity, view, modality);
CREATE INDEX idx_rules_fast_lookup ON morbac.rules(org_id, activity, modality, view)
INCLUDE (role_id, context_id)
WHERE is_active = true;

COMMENT ON TABLE morbac.rules IS 'Core OrBAC rules - Permission, Prohibition, Obligation, Recommendation';
COMMENT ON COLUMN morbac.rules.modality IS 'Deontic modality: permission, prohibition, obligation, recommendation';
COMMENT ON COLUMN morbac.rules.priority IS 'Optional rule priority (higher wins). NULL = 0. A permission with higher priority than a prohibition overrides it.';

-- Trigger to maintain is_active based on temporal validity

CREATE OR REPLACE FUNCTION morbac.rules_set_is_active()
RETURNS TRIGGER AS $$
BEGIN
    NEW.is_active := (
        (NEW.valid_from IS NULL OR NEW.valid_from <= CURRENT_TIMESTAMP)
        AND (NEW.valid_until IS NULL OR NEW.valid_until > CURRENT_TIMESTAMP)
    );
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_rules_set_is_active ON morbac.rules;
CREATE TRIGGER trg_rules_set_is_active
BEFORE INSERT OR UPDATE ON morbac.rules
FOR EACH ROW EXECUTE FUNCTION morbac.rules_set_is_active();

-- Check if a rule is currently valid based on temporal constraints

CREATE OR REPLACE FUNCTION morbac.is_rule_valid(
    p_valid_from TIMESTAMPTZ,
    p_valid_until TIMESTAMPTZ
)
RETURNS BOOLEAN
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    v_now TIMESTAMPTZ := CURRENT_TIMESTAMP;
BEGIN
    IF p_valid_from IS NOT NULL AND v_now < p_valid_from THEN
        RETURN FALSE;
    END IF;

    IF p_valid_until IS NOT NULL AND v_now >= p_valid_until THEN
        RETURN FALSE;
    END IF;

    RETURN TRUE;
END;
$$;

COMMENT ON FUNCTION morbac.is_rule_valid(TIMESTAMPTZ, TIMESTAMPTZ) IS
'Check if a rule is currently valid based on temporal constraints';
