-- Direct user-level rules: Rule(user, org, activity, view, context, modality)
--
-- Grants or prohibits access for a specific user in an org, bypassing the role system.
-- Evaluated alongside regular rules and cross_org_rules in is_allowed_nocache().
-- Priority resolution follows the same semantics: higher priority wins, ties go to prohibition.
--
-- Org target: a specific org, or NULL for unattributed (no-org) objects.
-- For the same user across every org, use morbac.global_rules.

CREATE TABLE morbac.user_rules (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL,
    org_id UUID REFERENCES morbac.orgs(id) ON DELETE CASCADE,
    activity TEXT NOT NULL REFERENCES morbac.activities(name) ON DELETE CASCADE,
    view TEXT NOT NULL REFERENCES morbac.views(name) ON DELETE CASCADE,
    context_id UUID NOT NULL REFERENCES morbac.contexts(id) ON DELETE CASCADE,
    modality morbac.modality NOT NULL,
    priority INTEGER,
    valid_from TIMESTAMPTZ,
    valid_until TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    metadata JSONB DEFAULT '{}'::jsonb,
    CHECK (valid_until IS NULL OR valid_from IS NULL OR valid_until > valid_from),
    UNIQUE(user_id, org_id, activity, view, context_id, modality)
);

-- NULLs are distinct in UNIQUE, so the unattributed target needs its own index
CREATE UNIQUE INDEX idx_user_rules_unattributed_unique
    ON morbac.user_rules(user_id, activity, view, context_id, modality)
    WHERE org_id IS NULL;

CREATE INDEX idx_user_rules_user_org ON morbac.user_rules(user_id, org_id);
CREATE INDEX idx_user_rules_activity_view ON morbac.user_rules(activity, view);
CREATE INDEX idx_user_rules_modality ON morbac.user_rules(modality);
CREATE INDEX idx_user_rules_lookup ON morbac.user_rules(user_id, org_id, activity, modality, view);

COMMENT ON TABLE morbac.user_rules IS 'Direct user-level rules - grant or prohibit access for a specific user, bypassing the role system';
COMMENT ON COLUMN morbac.user_rules.user_id IS 'User this rule applies to directly';
COMMENT ON COLUMN morbac.user_rules.org_id IS 'Org where the resource resides; NULL targets unattributed (no-org) objects';
COMMENT ON COLUMN morbac.user_rules.modality IS 'Deontic modality: permission, prohibition, obligation, recommendation';
COMMENT ON COLUMN morbac.user_rules.priority IS 'Optional priority (higher wins). NULL = 0. Follows same resolution as morbac.rules.';
