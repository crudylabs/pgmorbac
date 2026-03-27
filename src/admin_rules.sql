-- Meta-policies defining who can create/modify policies (AdministrationPermission)

CREATE TABLE morbac.admin_rules (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    org_id UUID NOT NULL REFERENCES morbac.orgs(id) ON DELETE CASCADE,
    role_id UUID NOT NULL REFERENCES morbac.roles(id) ON DELETE CASCADE,
    admin_activity TEXT NOT NULL,
    admin_target TEXT NOT NULL,
    context_id UUID NOT NULL REFERENCES morbac.contexts(id) ON DELETE CASCADE,
    modality morbac.modality NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    metadata JSONB DEFAULT '{}'::jsonb,
    UNIQUE(org_id, role_id, admin_activity, admin_target, context_id, modality)
);

CREATE INDEX idx_admin_rules_org_role ON morbac.admin_rules(org_id, role_id);

COMMENT ON TABLE morbac.admin_rules IS 'Administration rules - meta-policies for policy management';
COMMENT ON COLUMN morbac.admin_rules.admin_activity IS 'Admin action: create_rule, modify_rule, delete_rule, assign_role, etc.';
COMMENT ON COLUMN morbac.admin_rules.admin_target IS 'What can be administered: rules, roles, users, orgs, etc.';
