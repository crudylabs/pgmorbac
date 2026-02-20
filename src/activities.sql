-- =============================================================================
-- ACTIVITIES
-- =============================================================================
-- Activities represent abstract actions in OrBAC
-- These are global abstractions (not org-scoped)

CREATE TABLE morbac.activities (
    name TEXT PRIMARY KEY,
    description TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

COMMENT ON TABLE morbac.activities IS 'Activities - abstract actions in OrBAC model (global)';
COMMENT ON COLUMN morbac.activities.name IS 'Activity name (unique, global)';

-- =============================================================================
-- ACTIVITY HIERARCHY
-- =============================================================================
-- Activities can inherit from other activities
-- e.g., "write" implies "read", "admin_delete" implies "delete"

CREATE TABLE morbac.activity_hierarchy (
    senior_activity TEXT NOT NULL REFERENCES morbac.activities(name) ON DELETE CASCADE,
    junior_activity TEXT NOT NULL REFERENCES morbac.activities(name) ON DELETE CASCADE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (senior_activity, junior_activity),
    CHECK (senior_activity != junior_activity)
);

CREATE INDEX idx_activity_hierarchy_senior ON morbac.activity_hierarchy(senior_activity);
CREATE INDEX idx_activity_hierarchy_junior ON morbac.activity_hierarchy(junior_activity);

COMMENT ON TABLE morbac.activity_hierarchy IS 'Activity hierarchy - senior activities imply junior activities';
COMMENT ON COLUMN morbac.activity_hierarchy.senior_activity IS 'Senior activity (implies junior)';
COMMENT ON COLUMN morbac.activity_hierarchy.junior_activity IS 'Junior activity (implied by senior)';
