-- Activities are global abstract actions (not org-scoped)

CREATE TABLE morbac.activities (
    name TEXT PRIMARY KEY,
    description TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

COMMENT ON TABLE morbac.activities IS 'Activities - abstract actions in OrBAC model (global)';

-- Senior activities imply junior activities (e.g., write implies read)
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

INSERT INTO morbac.activities (name, description) VALUES
    ('create', 'Create new entities'),
    ('read',   'Read or list entities'),
    ('update', 'Modify existing entities'),
    ('delete', 'Remove entities')
ON CONFLICT (name) DO NOTHING;
