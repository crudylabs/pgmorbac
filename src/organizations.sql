-- =============================================================================
-- ORGANIZATIONS
-- =============================================================================
-- Organizations are first-class entities in Multi-OrBAC
-- Each organization has its own policy space

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
COMMENT ON COLUMN morbac.orgs.id IS 'Unique organization identifier';
COMMENT ON COLUMN morbac.orgs.name IS 'Organization name (unique)';
COMMENT ON COLUMN morbac.orgs.parent_id IS 'Parent organization for hierarchical organizations';
COMMENT ON COLUMN morbac.orgs.metadata IS 'Optional metadata for organization';
