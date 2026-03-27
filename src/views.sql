-- Views are global abstract object categories (not org-scoped)

CREATE TABLE morbac.views (
    name TEXT PRIMARY KEY,
    description TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

COMMENT ON TABLE morbac.views IS 'Views - abstract object categories in OrBAC model (global)';

-- Senior views inherit from junior views (e.g., confidential_documents is a documents)
CREATE TABLE morbac.view_hierarchy (
    senior_view TEXT NOT NULL REFERENCES morbac.views(name) ON DELETE CASCADE,
    junior_view TEXT NOT NULL REFERENCES morbac.views(name) ON DELETE CASCADE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (senior_view, junior_view),
    CHECK (senior_view != junior_view)
);

CREATE INDEX idx_view_hierarchy_senior ON morbac.view_hierarchy(senior_view);
CREATE INDEX idx_view_hierarchy_junior ON morbac.view_hierarchy(junior_view);

COMMENT ON TABLE morbac.view_hierarchy IS 'View hierarchy - senior views inherit from junior views';
COMMENT ON COLUMN morbac.view_hierarchy.senior_view IS 'Senior view (more specific)';
COMMENT ON COLUMN morbac.view_hierarchy.junior_view IS 'Junior view (more general)';
