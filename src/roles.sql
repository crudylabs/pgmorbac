-- Roles are scoped to organizations and abstract sets of subjects

CREATE TABLE morbac.roles (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    org_id UUID NOT NULL REFERENCES morbac.orgs(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    description TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE(org_id, name)
);

CREATE INDEX idx_roles_org_id ON morbac.roles(org_id);
CREATE INDEX idx_roles_org_name ON morbac.roles(org_id, name);

COMMENT ON TABLE morbac.roles IS 'Roles scoped to organizations - abstract sets of subjects';

-- Senior roles inherit permissions from junior roles

CREATE TABLE morbac.role_hierarchy (
    senior_role_id UUID NOT NULL REFERENCES morbac.roles(id) ON DELETE CASCADE,
    junior_role_id UUID NOT NULL REFERENCES morbac.roles(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (senior_role_id, junior_role_id),
    CHECK (senior_role_id != junior_role_id)
);

CREATE INDEX idx_role_hierarchy_senior ON morbac.role_hierarchy(senior_role_id);
CREATE INDEX idx_role_hierarchy_junior ON morbac.role_hierarchy(junior_role_id);

COMMENT ON TABLE morbac.role_hierarchy IS 'Role hierarchy - senior roles inherit from junior roles';
COMMENT ON COLUMN morbac.role_hierarchy.senior_role_id IS 'Senior role (inherits permissions)';
COMMENT ON COLUMN morbac.role_hierarchy.junior_role_id IS 'Junior role (provides permissions)';

-- Maps users to roles within organizations; user_id is external (e.g., from auth system)

CREATE TABLE morbac.user_roles (
    user_id UUID NOT NULL,
    role_id UUID NOT NULL REFERENCES morbac.roles(id) ON DELETE CASCADE,
    org_id UUID NOT NULL REFERENCES morbac.orgs(id) ON DELETE CASCADE,
    assigned_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (user_id, role_id, org_id)
);

CREATE INDEX idx_user_roles_user_org ON morbac.user_roles(user_id, org_id);
CREATE INDEX idx_user_roles_role ON morbac.user_roles(role_id);
CREATE INDEX idx_user_roles_fast ON morbac.user_roles(user_id, org_id) INCLUDE (role_id);

COMMENT ON TABLE morbac.user_roles IS 'Maps users to roles within organizations';
COMMENT ON COLUMN morbac.user_roles.user_id IS 'External user identifier';

-- Temporary delegation of a role from one user to another, time-bounded

CREATE TABLE morbac.delegations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    delegator_id UUID NOT NULL,
    delegatee_id UUID NOT NULL,
    role_id UUID NOT NULL REFERENCES morbac.roles(id) ON DELETE CASCADE,
    org_id UUID NOT NULL REFERENCES morbac.orgs(id) ON DELETE CASCADE,
    valid_from TIMESTAMPTZ NOT NULL DEFAULT now(),
    valid_until TIMESTAMPTZ NOT NULL,
    revoked BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CHECK (delegator_id != delegatee_id),
    CHECK (valid_until > valid_from)
);

CREATE INDEX idx_delegations_delegatee ON morbac.delegations(delegatee_id, org_id);
CREATE INDEX idx_delegations_validity ON morbac.delegations(valid_from, valid_until) WHERE NOT revoked;

COMMENT ON TABLE morbac.delegations IS 'Temporary delegation of roles from one user to another';
COMMENT ON COLUMN morbac.delegations.valid_from IS 'Delegation start time';
COMMENT ON COLUMN morbac.delegations.valid_until IS 'Delegation end time';
COMMENT ON COLUMN morbac.delegations.revoked IS 'Whether delegation has been revoked';

-- Explicitly prevent users from ever getting certain roles; takes precedence over positive assignments

CREATE TABLE morbac.negative_role_assignments (
    user_id UUID NOT NULL,
    role_id UUID NOT NULL REFERENCES morbac.roles(id) ON DELETE CASCADE,
    org_id UUID NOT NULL REFERENCES morbac.orgs(id) ON DELETE CASCADE,
    reason TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (user_id, role_id, org_id)
);

CREATE INDEX idx_negative_assignments ON morbac.negative_role_assignments(user_id, org_id);

COMMENT ON TABLE morbac.negative_role_assignments IS 'Explicit prohibition of role assignments';
COMMENT ON COLUMN morbac.negative_role_assignments.reason IS 'Reason for prohibition';

-- Mutually exclusive roles that cannot be held simultaneously

CREATE TABLE morbac.sod_conflicts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    role_a_id UUID NOT NULL REFERENCES morbac.roles(id) ON DELETE CASCADE,
    role_b_id UUID NOT NULL REFERENCES morbac.roles(id) ON DELETE CASCADE,
    org_id UUID NOT NULL REFERENCES morbac.orgs(id) ON DELETE CASCADE,
    description TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CHECK (role_a_id != role_b_id),
    UNIQUE (role_a_id, role_b_id, org_id)
);

CREATE INDEX idx_sod_conflicts_org ON morbac.sod_conflicts(org_id);
CREATE INDEX idx_sod_conflicts_roles ON morbac.sod_conflicts(role_a_id, role_b_id);

COMMENT ON TABLE morbac.sod_conflicts IS 'Separation of Duty: mutually exclusive roles';

-- Min/max user count constraints per role

CREATE TABLE morbac.role_cardinality (
    role_id UUID PRIMARY KEY REFERENCES morbac.roles(id) ON DELETE CASCADE,
    min_users INTEGER,
    max_users INTEGER,
    description TEXT,
    CHECK (min_users IS NULL OR min_users >= 0),
    CHECK (max_users IS NULL OR max_users >= 1),
    CHECK (min_users IS NULL OR max_users IS NULL OR max_users >= min_users)
);

COMMENT ON TABLE morbac.role_cardinality IS 'Cardinality constraints for roles (min/max number of users)';
COMMENT ON COLUMN morbac.role_cardinality.min_users IS 'Minimum number of users required for this role';
COMMENT ON COLUMN morbac.role_cardinality.max_users IS 'Maximum number of users allowed for this role';

-- Roles computed dynamically based on conditions rather than explicit assignment

CREATE TABLE morbac.derived_roles (
    role_id UUID PRIMARY KEY REFERENCES morbac.roles(id) ON DELETE CASCADE,
    condition_evaluator REGPROC NOT NULL,
    description TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

COMMENT ON TABLE morbac.derived_roles IS 'Roles computed dynamically based on conditions';
COMMENT ON COLUMN morbac.derived_roles.condition_evaluator IS 'Function(user_id, org_id) returning boolean';
