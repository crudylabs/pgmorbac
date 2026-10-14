-- =============================================================================
-- is_allowed_nocache() equivalence with the 1.0.0 implementation
-- =============================================================================
-- 1.0.1 resolves roles once per org instead of once per rule row. This file
-- keeps the 1.0.0 function as a reference and compares both on a seeded random
-- fixture: org forest, role hierarchy, negative assignments, delegations,
-- derived roles, activity/view hierarchies, every rule scope, priorities,
-- prohibitions, contexts that are false or NULL, validity windows, cross-org,
-- user and global rules, and a system principal holding roles.
--
-- It then adds rules for many unrelated tenants and checks that the cost of a
-- decision no longer follows the total rule count.
--
-- Prerequisites: 00_setup.sql
-- =============================================================================

\echo ''
\echo '================================================================'
\echo '17 - is_allowed_nocache EQUIVALENCE AND SCALING'
\echo '================================================================'

SET client_min_messages = error;

-- Reference: the 1.0.0 body, unchanged except for its name
CREATE OR REPLACE FUNCTION morbac.is_allowed_nocache_1_0_0(
    p_user_id UUID,
    p_org_id UUID,
    p_activity TEXT,
    p_view TEXT
)
RETURNS BOOLEAN
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
AS $$
DECLARE
    v_rule                     RECORD;
    v_max_prohibition_priority INTEGER := NULL;
    v_max_permission_priority  INTEGER := NULL;
    v_is_system_principal      BOOLEAN;
BEGIN
    v_is_system_principal := EXISTS (
        SELECT 1 FROM morbac.system_principals WHERE user_id = p_user_id
    );

    -- STEPS 1-3.5: Prohibitions - skipped entirely for system principals
    IF NOT v_is_system_principal THEN

        -- STEP 1: Local prohibitions - find the highest-priority applicable one
        FOR v_rule IN
            SELECT r.context_id, COALESCE(r.priority, 0) AS prio
            FROM morbac.rules r
            WHERE morbac.org_in_scope(p_org_id, r.org_id, r.scope)
              AND r.modality = 'prohibition'
              AND r.activity IN (SELECT activity FROM morbac.get_effective_activities(p_activity))
              AND r.view     IN (SELECT view     FROM morbac.get_effective_views(p_view))
              AND r.role_id  IN (SELECT role_id  FROM morbac.get_comprehensive_roles(p_user_id, r.org_id))
              AND morbac.is_rule_valid(r.valid_from, r.valid_until)
            ORDER BY COALESCE(r.priority, 0) DESC
        LOOP
            IF morbac.eval_context(v_rule.context_id) THEN
                v_max_prohibition_priority := v_rule.prio;
                EXIT;
            END IF;
        END LOOP;

        -- STEP 2: Cross-org prohibitions - update max if a higher priority is found
        FOR v_rule IN
            SELECT cr.context_id, COALESCE(cr.priority, 0) AS prio
            FROM morbac.cross_org_rules cr
            WHERE cr.target_org_id = p_org_id
              AND cr.modality = 'prohibition'
              AND cr.activity IN (SELECT activity FROM morbac.get_effective_activities(p_activity))
              AND cr.view     IN (SELECT view     FROM morbac.get_effective_views(p_view))
              AND cr.role_id IN (SELECT role_id FROM morbac.get_comprehensive_roles(p_user_id, cr.source_org_id))
              AND morbac.is_rule_valid(cr.valid_from, cr.valid_until)
            ORDER BY COALESCE(cr.priority, 0) DESC
        LOOP
            IF morbac.eval_context(v_rule.context_id) THEN
                IF v_max_prohibition_priority IS NULL OR v_rule.prio > v_max_prohibition_priority THEN
                    v_max_prohibition_priority := v_rule.prio;
                END IF;
                EXIT;
            END IF;
        END LOOP;

        -- STEP 3: User-level prohibitions - direct user rules, update max if higher
        FOR v_rule IN
            SELECT ur.context_id, COALESCE(ur.priority, 0) AS prio
            FROM morbac.user_rules ur
            WHERE ur.user_id = p_user_id
              AND ur.org_id IS NOT DISTINCT FROM p_org_id
              AND ur.modality = 'prohibition'
              AND ur.activity IN (SELECT activity FROM morbac.get_effective_activities(p_activity))
              AND ur.view     IN (SELECT view     FROM morbac.get_effective_views(p_view))
              AND morbac.is_rule_valid(ur.valid_from, ur.valid_until)
            ORDER BY COALESCE(ur.priority, 0) DESC
        LOOP
            IF morbac.eval_context(v_rule.context_id) THEN
                IF v_max_prohibition_priority IS NULL OR v_rule.prio > v_max_prohibition_priority THEN
                    v_max_prohibition_priority := v_rule.prio;
                END IF;
                EXIT;
            END IF;
        END LOOP;

        -- STEP 3.5: Global prohibitions
        FOR v_rule IN
            SELECT gr.context_id, COALESCE(gr.priority, 0) AS prio
            FROM morbac.global_rules gr
            WHERE (gr.user_id IS NULL OR gr.user_id = p_user_id)
              AND gr.modality = 'prohibition'
              AND (gr.activity IS NULL OR gr.activity IN (SELECT activity FROM morbac.get_effective_activities(p_activity)))
              AND (gr.view     IS NULL OR gr.view     IN (SELECT view     FROM morbac.get_effective_views(p_view)))
              AND morbac.is_rule_valid(gr.valid_from, gr.valid_until)
            ORDER BY COALESCE(gr.priority, 0) DESC
        LOOP
            IF morbac.eval_context(v_rule.context_id) THEN
                IF v_max_prohibition_priority IS NULL OR v_rule.prio > v_max_prohibition_priority THEN
                    v_max_prohibition_priority := v_rule.prio;
                END IF;
                EXIT;
            END IF;
        END LOOP;

    END IF; -- v_is_system_principal

    -- STEP 4: Local permissions - find the highest-priority applicable one
    FOR v_rule IN
        SELECT r.context_id, COALESCE(r.priority, 0) AS prio
        FROM morbac.rules r
        WHERE morbac.org_in_scope(p_org_id, r.org_id, r.scope)
          AND r.modality = 'permission'
          AND r.activity IN (SELECT activity FROM morbac.get_effective_activities(p_activity))
          AND r.view     IN (SELECT view     FROM morbac.get_effective_views(p_view))
          AND r.role_id  IN (SELECT role_id  FROM morbac.get_comprehensive_roles(p_user_id, r.org_id))
          AND morbac.is_rule_valid(r.valid_from, r.valid_until)
        ORDER BY COALESCE(r.priority, 0) DESC
    LOOP
        IF morbac.eval_context(v_rule.context_id) THEN
            v_max_permission_priority := v_rule.prio;
            EXIT;
        END IF;
    END LOOP;

    -- STEP 5: Cross-org permissions - update max if higher found
    FOR v_rule IN
        SELECT cr.context_id, COALESCE(cr.priority, 0) AS prio
        FROM morbac.cross_org_rules cr
        WHERE cr.target_org_id = p_org_id
          AND cr.modality = 'permission'
          AND cr.activity IN (SELECT activity FROM morbac.get_effective_activities(p_activity))
          AND cr.view     IN (SELECT view     FROM morbac.get_effective_views(p_view))
          AND cr.role_id IN (SELECT role_id FROM morbac.get_comprehensive_roles(p_user_id, cr.source_org_id))
          AND morbac.is_rule_valid(cr.valid_from, cr.valid_until)
        ORDER BY COALESCE(cr.priority, 0) DESC
    LOOP
        IF morbac.eval_context(v_rule.context_id) THEN
            IF v_max_permission_priority IS NULL OR v_rule.prio > v_max_permission_priority THEN
                v_max_permission_priority := v_rule.prio;
            END IF;
            EXIT;
        END IF;
    END LOOP;

    -- STEP 6: User-level permissions - direct user rules, update max if higher
    FOR v_rule IN
        SELECT ur.context_id, COALESCE(ur.priority, 0) AS prio
        FROM morbac.user_rules ur
        WHERE ur.user_id = p_user_id
          AND ur.org_id IS NOT DISTINCT FROM p_org_id
          AND ur.modality = 'permission'
          AND ur.activity IN (SELECT activity FROM morbac.get_effective_activities(p_activity))
          AND ur.view     IN (SELECT view     FROM morbac.get_effective_views(p_view))
          AND morbac.is_rule_valid(ur.valid_from, ur.valid_until)
        ORDER BY COALESCE(ur.priority, 0) DESC
    LOOP
        IF morbac.eval_context(v_rule.context_id) THEN
            IF v_max_permission_priority IS NULL OR v_rule.prio > v_max_permission_priority THEN
                v_max_permission_priority := v_rule.prio;
            END IF;
            EXIT;
        END IF;
    END LOOP;

    -- STEP 6.5: Global permissions
    FOR v_rule IN
        SELECT gr.context_id, COALESCE(gr.priority, 0) AS prio
        FROM morbac.global_rules gr
        WHERE (gr.user_id IS NULL OR gr.user_id = p_user_id)
          AND gr.modality = 'permission'
          AND (gr.activity IS NULL OR gr.activity IN (SELECT activity FROM morbac.get_effective_activities(p_activity)))
          AND (gr.view     IS NULL OR gr.view     IN (SELECT view     FROM morbac.get_effective_views(p_view)))
          AND morbac.is_rule_valid(gr.valid_from, gr.valid_until)
        ORDER BY COALESCE(gr.priority, 0) DESC
    LOOP
        IF morbac.eval_context(v_rule.context_id) THEN
            IF v_max_permission_priority IS NULL OR v_rule.prio > v_max_permission_priority THEN
                v_max_permission_priority := v_rule.prio;
            END IF;
            EXIT;
        END IF;
    END LOOP;

    -- STEP 7: Priority resolution
    IF v_max_prohibition_priority IS NULL THEN
        RETURN v_max_permission_priority IS NOT NULL;
    END IF;

    IF v_max_permission_priority IS NOT NULL
       AND v_max_permission_priority > v_max_prohibition_priority THEN
        RETURN TRUE;
    END IF;

    RETURN FALSE;
END;
$$;

CREATE OR REPLACE FUNCTION morbac.eq_context_never() RETURNS BOOLEAN LANGUAGE sql STABLE AS 'SELECT FALSE';
CREATE OR REPLACE FUNCTION morbac.eq_context_null() RETURNS BOOLEAN LANGUAGE sql STABLE AS 'SELECT NULL::BOOLEAN';
CREATE OR REPLACE FUNCTION morbac.eq_derived(p_user_id UUID, p_org_id UUID) RETURNS BOOLEAN
LANGUAGE sql STABLE AS $$
    SELECT get_byte(decode(md5(p_user_id::text || p_org_id::text), 'hex'), 0) % 3 = 0
$$;

INSERT INTO morbac.contexts (name, evaluator) VALUES
    ('eq_never', 'morbac.eq_context_never'::regproc),
    ('eq_null',  'morbac.eq_context_null'::regproc);

INSERT INTO morbac.activities (name) VALUES ('eq_read'), ('eq_write'), ('eq_admin');
INSERT INTO morbac.activity_hierarchy (senior_activity, junior_activity) VALUES
    ('eq_admin', 'eq_write'), ('eq_write', 'eq_read');
INSERT INTO morbac.views (name) VALUES ('eq_doc'), ('eq_secret'), ('eq_misc');
INSERT INTO morbac.view_hierarchy (senior_view, junior_view) VALUES ('eq_secret', 'eq_doc');

CREATE TABLE morbac.eq_users (n INT PRIMARY KEY, id UUID NOT NULL);
CREATE TABLE morbac.eq_orgs  (n INT PRIMARY KEY, id UUID NOT NULL);
CREATE TABLE morbac.eq_roles (n INT PRIMARY KEY, id UUID NOT NULL);

DO $$
DECLARE
    v_ctx_always UUID := (SELECT id FROM morbac.contexts WHERE name = 'always');
    v_ctx_never  UUID := (SELECT id FROM morbac.contexts WHERE name = 'eq_never');
    v_ctx_null   UUID := (SELECT id FROM morbac.contexts WHERE name = 'eq_null');
    v_scopes     TEXT[] := ARRAY['self','children','descendants','subtree','parent','ancestors','lineage','root','unattributed','all'];
    v_acts       TEXT[] := ARRAY['eq_read','eq_write','eq_admin'];
    v_views      TEXT[] := ARRAY['eq_doc','eq_secret','eq_misc'];
    v_org        UUID;
    v_role       UUID;
    v_x          DOUBLE PRECISION;
    v_from       TIMESTAMPTZ;
    v_until      TIMESTAMPTZ;
    v_rec        RECORD;
    v_src        INT;
    v_dst        INT;
BEGIN
    PERFORM setseed(0.17);

    -- Org forest: 12 orgs, each either a new root or the child of an earlier one
    FOR i IN 0..11 LOOP
        v_org := md5('eq_org_' || i)::uuid;
        INSERT INTO morbac.orgs (id, name, parent_id) VALUES (
            v_org, 'eq_org_' || i,
            CASE WHEN i = 0 OR random() < 0.15 THEN NULL
                 ELSE md5('eq_org_' || floor(random() * i)::int)::uuid END
        );
        INSERT INTO morbac.eq_orgs VALUES (i, v_org);
    END LOOP;

    -- Roles, with an acyclic hierarchy (senior n -> junior m only when n < m)
    FOR i IN 0..13 LOOP
        v_role := md5('eq_role_' || i)::uuid;
        INSERT INTO morbac.roles (id, org_id, name)
        VALUES (v_role, md5('eq_org_' || floor(random() * 12)::int)::uuid, 'eq_role_' || i);
        INSERT INTO morbac.eq_roles VALUES (i, v_role);
    END LOOP;
    FOR i IN 0..13 LOOP
        FOR j IN (i + 1)..13 LOOP
            IF random() < 0.12 THEN
                INSERT INTO morbac.role_hierarchy (senior_role_id, junior_role_id)
                SELECT a.id, b.id FROM morbac.eq_roles a, morbac.eq_roles b WHERE a.n = i AND b.n = j;
            END IF;
        END LOOP;
    END LOOP;
    INSERT INTO morbac.derived_roles (role_id, condition_evaluator)
    SELECT id, 'morbac.eq_derived'::regproc FROM morbac.eq_roles WHERE n IN (3, 11);

    -- Users and their assignments: mostly in the role's own org, sometimes elsewhere
    FOR i IN 0..10 LOOP
        INSERT INTO morbac.eq_users VALUES (i, md5('eq_user_' || i)::uuid);
    END LOOP;
    FOR i IN 0..10 LOOP
        FOR k IN 1..(1 + floor(random() * 3)::int) LOOP
            v_role := md5('eq_role_' || floor(random() * 14)::int)::uuid;
            v_org := (SELECT r.org_id FROM morbac.roles r WHERE r.id = v_role);
            IF random() < 0.25 THEN
                v_org := md5('eq_org_' || floor(random() * 12)::int)::uuid;
            END IF;
            INSERT INTO morbac.user_roles (user_id, role_id, org_id)
            VALUES ((SELECT id FROM morbac.eq_users WHERE n = i), v_role, v_org)
            ON CONFLICT DO NOTHING;
        END LOOP;
    END LOOP;

    -- Negative assignments: some cancel a held role, some target an inherited one
    INSERT INTO morbac.negative_role_assignments (user_id, role_id, org_id)
    SELECT ur.user_id, ur.role_id, ur.org_id FROM morbac.user_roles ur
    JOIN morbac.eq_users u ON u.id = ur.user_id
    ORDER BY md5(ur.user_id::text || ur.role_id::text) LIMIT 3;
    INSERT INTO morbac.negative_role_assignments (user_id, role_id, org_id)
    SELECT ur.user_id, rh.junior_role_id, ur.org_id FROM morbac.user_roles ur
    JOIN morbac.eq_users u ON u.id = ur.user_id
    JOIN morbac.role_hierarchy rh ON rh.senior_role_id = ur.role_id
    ORDER BY md5(ur.user_id::text || rh.junior_role_id::text) LIMIT 2
    ON CONFLICT DO NOTHING;

    -- Delegations: active, expired, future and revoked
    FOR v_rec IN
        SELECT ur.user_id, ur.role_id, ur.org_id, row_number() OVER (ORDER BY md5(ur.user_id::text || ur.role_id::text)) AS k
        FROM morbac.user_roles ur JOIN morbac.eq_users u ON u.id = ur.user_id
        LIMIT 8
    LOOP
        INSERT INTO morbac.delegations (delegator_id, delegatee_id, role_id, org_id, valid_from, valid_until, revoked)
        SELECT v_rec.user_id, u.id, v_rec.role_id, v_rec.org_id,
               CASE v_rec.k % 4 WHEN 1 THEN now() - interval '2 days' WHEN 2 THEN now() + interval '1 day' ELSE now() - interval '1 day' END,
               CASE v_rec.k % 4 WHEN 1 THEN now() - interval '1 day' WHEN 2 THEN now() + interval '2 days' ELSE now() + interval '1 day' END,
               v_rec.k % 4 = 3
        FROM morbac.eq_users u
        WHERE u.id <> v_rec.user_id
        ORDER BY md5(u.id::text || v_rec.k::text) LIMIT 1;
    END LOOP;

    -- Role-bound rules
    FOR i IN 1..450 LOOP
        v_x := random();
        v_from := NULL; v_until := NULL;
        IF v_x < 0.08 THEN
            v_from := now() - interval '2 days'; v_until := now() - interval '1 day';
        ELSIF v_x < 0.16 THEN
            v_from := now() + interval '1 day';
        ELSIF v_x < 0.22 THEN
            v_from := now() - interval '1 day'; v_until := now() + interval '1 day';
        END IF;
        INSERT INTO morbac.rules (org_id, role_id, activity, view, context_id, modality, scope, priority, valid_from, valid_until)
        VALUES (
            md5('eq_org_' || floor(random() * 12)::int)::uuid,
            md5('eq_role_' || floor(random() * 14)::int)::uuid,
            v_acts[1 + floor(random() * 3)::int],
            v_views[1 + floor(random() * 3)::int],
            CASE WHEN random() < 0.7 THEN v_ctx_always WHEN random() < 0.5 THEN v_ctx_never ELSE v_ctx_null END,
            (CASE WHEN random() < 0.55 THEN 'permission' WHEN random() < 0.8 THEN 'prohibition' ELSE 'obligation' END)::morbac.modality,
            v_scopes[1 + floor(random() * 10)::int],
            CASE WHEN random() < 0.4 THEN NULL ELSE floor(random() * 5)::int END,
            v_from, v_until
        ) ON CONFLICT DO NOTHING;
    END LOOP;

    FOR i IN 1..70 LOOP
        v_src := floor(random() * 12)::int;
        v_dst := floor(random() * 12)::int;
        CONTINUE WHEN v_src = v_dst;
        INSERT INTO morbac.cross_org_rules (source_org_id, target_org_id, role_id, activity, view, context_id, modality, priority, valid_from)
        VALUES (md5('eq_org_' || v_src)::uuid, md5('eq_org_' || v_dst)::uuid,
               md5('eq_role_' || floor(random() * 14)::int)::uuid,
               v_acts[1 + floor(random() * 3)::int],
               v_views[1 + floor(random() * 3)::int],
               CASE WHEN random() < 0.8 THEN v_ctx_always ELSE v_ctx_never END,
               (CASE WHEN random() < 0.6 THEN 'permission' ELSE 'prohibition' END)::morbac.modality,
               CASE WHEN random() < 0.4 THEN NULL ELSE floor(random() * 5)::int END,
               CASE WHEN random() < 0.1 THEN now() + interval '1 day' END
        ) ON CONFLICT DO NOTHING;
    END LOOP;

    FOR i IN 1..60 LOOP
        INSERT INTO morbac.user_rules (user_id, org_id, activity, view, context_id, modality, priority)
        VALUES (
            md5('eq_user_' || floor(random() * 10)::int)::uuid,
            CASE WHEN random() < 0.2 THEN NULL ELSE md5('eq_org_' || floor(random() * 12)::int)::uuid END,
            v_acts[1 + floor(random() * 3)::int],
            v_views[1 + floor(random() * 3)::int],
            CASE WHEN random() < 0.8 THEN v_ctx_always ELSE v_ctx_never END,
            (CASE WHEN random() < 0.5 THEN 'permission' ELSE 'prohibition' END)::morbac.modality,
            CASE WHEN random() < 0.4 THEN NULL ELSE floor(random() * 5)::int END
        ) ON CONFLICT DO NOTHING;
    END LOOP;

    FOR i IN 1..10 LOOP
        INSERT INTO morbac.global_rules (user_id, activity, view, context_id, modality, priority)
        VALUES (
            CASE WHEN i <= 2 THEN NULL ELSE md5('eq_user_' || floor(random() * 10)::int)::uuid END,
            CASE WHEN random() < 0.3 THEN NULL ELSE v_acts[1 + floor(random() * 3)::int] END,
            CASE WHEN random() < 0.3 THEN NULL ELSE v_views[1 + floor(random() * 3)::int] END,
            v_ctx_always,
            (CASE WHEN i % 2 = 0 THEN 'permission' ELSE 'prohibition' END)::morbac.modality,
            floor(random() * 5)::int
        ) ON CONFLICT DO NOTHING;
    END LOOP;

    -- User 10 holds roles, then becomes a system principal: its prohibitions are skipped
    INSERT INTO morbac.system_principals (user_id, description)
    SELECT id, 'eq system principal' FROM morbac.eq_users WHERE n = 10;
END;
$$;

CREATE TABLE morbac.eq_cases AS
SELECT u.id AS user_id, o.id AS org_id, a.activity, v.view
FROM morbac.eq_users u
CROSS JOIN (SELECT id FROM morbac.eq_orgs UNION ALL SELECT NULL::UUID) o
CROSS JOIN (VALUES ('eq_read'), ('eq_write'), ('eq_admin')) a(activity)
CROSS JOIN (VALUES ('eq_doc'), ('eq_secret'), ('eq_misc')) v(view);

CREATE TABLE morbac.eq_results AS
SELECT c.*,
       morbac.is_allowed_nocache_1_0_0(c.user_id, c.org_id, c.activity, c.view) AS expected,
       morbac.is_allowed_nocache(c.user_id, c.org_id, c.activity, c.view)       AS actual
FROM morbac.eq_cases c;

SELECT CASE WHEN count(*) FILTER (WHERE expected IS DISTINCT FROM actual) = 0
            THEN 'CHECK PASS: ' || count(*) || ' decisions identical to 1.0.0'
            ELSE 'CHECK FAIL: ' || count(*) FILTER (WHERE expected IS DISTINCT FROM actual) || ' of ' || count(*) || ' decisions differ from 1.0.0'
       END
FROM morbac.eq_results;

SELECT morbac.t('fixture yields both allowed and denied decisions',
    (SELECT count(*) FILTER (WHERE expected) >= 50 AND count(*) FILTER (WHERE NOT expected) >= 50 FROM morbac.eq_results), TRUE);

SELECT morbac.t('fixture rules cover every scope',
    (SELECT count(DISTINCT r.scope) FROM morbac.rules r JOIN morbac.eq_orgs o ON o.id = r.org_id) = 10, TRUE);

SELECT morbac.t('system principal is allowed somewhere',
    (SELECT bool_or(actual) FROM morbac.eq_results r JOIN morbac.eq_users u ON u.id = r.user_id WHERE u.n = 10), TRUE);

-- Scaling: 60 unrelated tenants, each with its own roles and ~40 rules on the
-- same activities and views. The fixture users hold no role there.
DO $$
DECLARE
    v_org  UUID;
    v_role UUID;
    v_ctx  UUID := (SELECT id FROM morbac.contexts WHERE name = 'always');
BEGIN
    FOR t IN 1..60 LOOP
        v_org := gen_random_uuid();
        v_role := gen_random_uuid();
        INSERT INTO morbac.orgs (id, name) VALUES (v_org, 'eq_tenant_' || t);
        INSERT INTO morbac.roles (id, org_id, name) VALUES (v_role, v_org, 'tenant_role');
        INSERT INTO morbac.user_roles (user_id, role_id, org_id) VALUES (gen_random_uuid(), v_role, v_org);
        INSERT INTO morbac.rules (org_id, role_id, activity, view, context_id, modality, scope)
        SELECT v_org, v_role, a, v, v_ctx, 'permission', s
        FROM unnest(ARRAY['eq_read','eq_write','eq_admin']) a,
             unnest(ARRAY['eq_doc','eq_secret','eq_misc']) v,
             unnest(ARRAY['self','subtree','children','lineage']) s;
    END LOOP;
END;
$$;

SELECT CASE WHEN count(*) FILTER (WHERE r.expected IS DISTINCT FROM morbac.is_allowed_nocache(r.user_id, r.org_id, r.activity, r.view)) = 0
            THEN 'CHECK PASS: decisions unchanged after adding unrelated tenants'
            ELSE 'CHECK FAIL: unrelated tenants changed ' || count(*) FILTER (WHERE r.expected IS DISTINCT FROM morbac.is_allowed_nocache(r.user_id, r.org_id, r.activity, r.view)) || ' decisions'
       END
FROM morbac.eq_results r;

-- Old and new on the same sample after the tenants were added. The 1.0.0 cost
-- grows with every rule in the table; the new one must stay well below it.
CREATE TABLE morbac.eq_sample AS
SELECT * FROM morbac.eq_results ORDER BY md5(user_id::text || COALESCE(org_id::text, '') || activity || view) LIMIT 8;

DO $$
DECLARE
    v_rec   RECORD;
    v_t0    TIMESTAMPTZ;
    v_old   INTERVAL;
    v_new   INTERVAL;
    v_ok    BOOLEAN := TRUE;
BEGIN
    v_t0 := clock_timestamp();
    FOR v_rec IN SELECT * FROM morbac.eq_sample LOOP
        IF morbac.is_allowed_nocache_1_0_0(v_rec.user_id, v_rec.org_id, v_rec.activity, v_rec.view) IS DISTINCT FROM v_rec.expected THEN
            v_ok := FALSE;
        END IF;
    END LOOP;
    v_old := clock_timestamp() - v_t0;

    v_t0 := clock_timestamp();
    FOR i IN 1..10 LOOP
        FOR v_rec IN SELECT * FROM morbac.eq_sample LOOP
            IF morbac.is_allowed_nocache(v_rec.user_id, v_rec.org_id, v_rec.activity, v_rec.view) IS DISTINCT FROM v_rec.expected THEN
                v_ok := FALSE;
            END IF;
        END LOOP;
    END LOOP;
    v_new := (clock_timestamp() - v_t0) / 10;

    CREATE TEMP TABLE eq_timing AS SELECT v_old AS old_cost, v_new AS new_cost, v_ok AS ok;
END;
$$;

SELECT morbac.t('1.0.0 reference still agrees after adding tenants', (SELECT ok FROM eq_timing), TRUE);
SELECT morbac.t('decision cost is at least 10x below 1.0.0 with ' || (SELECT count(*) FROM morbac.rules) || ' rules (1.0.0 '
                || (SELECT round(extract(epoch FROM old_cost) * 1000 / 8, 2) FROM eq_timing) || ' ms, now '
                || (SELECT round(extract(epoch FROM new_cost) * 1000 / 8, 2) FROM eq_timing) || ' ms per call)',
    (SELECT new_cost * 10 < old_cost FROM eq_timing), TRUE);

DROP TABLE eq_timing;
DROP TABLE morbac.eq_sample, morbac.eq_results, morbac.eq_cases, morbac.eq_roles, morbac.eq_orgs, morbac.eq_users;
DROP FUNCTION morbac.is_allowed_nocache_1_0_0(UUID, UUID, TEXT, TEXT);

RESET client_min_messages;

\echo ''
\echo '=== Equivalence Tests Completed ==='
