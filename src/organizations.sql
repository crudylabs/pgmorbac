CREATE TABLE morbac.orgs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL UNIQUE,
    parent_id UUID REFERENCES morbac.orgs(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    metadata JSONB DEFAULT '{}'::jsonb
);

CREATE INDEX idx_orgs_name ON morbac.orgs(name);
CREATE INDEX idx_orgs_parent ON morbac.orgs(parent_id);

COMMENT ON TABLE morbac.orgs IS 'Organizations - first-class entities in Multi-OrBAC with hierarchy support';
