-- Rules that grant access across organization boundaries

CREATE TABLE morbac.cross_org_rules (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    source_org_id UUID NOT NULL REFERENCES morbac.orgs(id) ON DELETE CASCADE,
    target_org_id UUID NOT NULL REFERENCES morbac.orgs(id) ON DELETE CASCADE,
    role_id UUID NOT NULL REFERENCES morbac.roles(id) ON DELETE CASCADE,
    activity TEXT NOT NULL REFERENCES morbac.activities(name) ON DELETE CASCADE,
    view TEXT NOT NULL REFERENCES morbac.views(name) ON DELETE CASCADE,
    context_id UUID NOT NULL REFERENCES morbac.contexts(id) ON DELETE CASCADE,
    modality morbac.modality NOT NULL,
    priority INTEGER,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    valid_from TIMESTAMPTZ,
    valid_until TIMESTAMPTZ,
    metadata JSONB DEFAULT '{}'::jsonb,
    CHECK (source_org_id != target_org_id),
    CHECK (valid_until IS NULL OR valid_from IS NULL OR valid_until > valid_from),
    UNIQUE(source_org_id, target_org_id, role_id, activity, view, context_id, modality)
);

CREATE INDEX idx_cross_org_rules_source ON morbac.cross_org_rules(source_org_id, role_id);
CREATE INDEX idx_cross_org_rules_target ON morbac.cross_org_rules(target_org_id);
CREATE INDEX idx_cross_org_rules_temporal ON morbac.cross_org_rules(valid_from, valid_until);

COMMENT ON TABLE morbac.cross_org_rules IS 'Inter-organizational rules for cross-org access';
COMMENT ON COLUMN morbac.cross_org_rules.source_org_id IS 'Organization where user has role';
COMMENT ON COLUMN morbac.cross_org_rules.target_org_id IS 'Organization where resource resides';
