-- Optional whitelist of valid (activity, view) pairs.
-- If any binding exists for an activity, rules may only use listed views.
-- Activities with no bindings are unconstrained.

CREATE TABLE morbac.activity_view_bindings (
    activity TEXT NOT NULL REFERENCES morbac.activities(name) ON DELETE CASCADE,
    view     TEXT NOT NULL REFERENCES morbac.views(name) ON DELETE CASCADE,
    PRIMARY KEY (activity, view)
);

COMMENT ON TABLE morbac.activity_view_bindings IS
'Optional whitelist of valid (activity, view) pairs. Constrains rule creation on a per-activity basis.';

CREATE OR REPLACE FUNCTION morbac.trg_check_activity_view_binding()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    IF EXISTS (SELECT 1 FROM morbac.activity_view_bindings WHERE activity = NEW.activity)
       AND NOT EXISTS (SELECT 1 FROM morbac.activity_view_bindings WHERE activity = NEW.activity AND view = NEW.view)
    THEN
        RAISE EXCEPTION 'Activity "%" is not allowed on view "%" — add a binding to morbac.activity_view_bindings to permit it',
            NEW.activity, NEW.view;
    END IF;
    RETURN NEW;
END;
$$;

COMMENT ON FUNCTION morbac.trg_check_activity_view_binding() IS
'Blocks rule creation when an activity has bindings but the target view is not among them.';

DROP TRIGGER IF EXISTS trg_activity_view_binding_check ON morbac.rules;
CREATE TRIGGER trg_activity_view_binding_check
BEFORE INSERT OR UPDATE ON morbac.rules
FOR EACH ROW EXECUTE FUNCTION morbac.trg_check_activity_view_binding();

DROP TRIGGER IF EXISTS trg_activity_view_binding_check ON morbac.cross_org_rules;
CREATE TRIGGER trg_activity_view_binding_check
BEFORE INSERT OR UPDATE ON morbac.cross_org_rules
FOR EACH ROW EXECUTE FUNCTION morbac.trg_check_activity_view_binding();
