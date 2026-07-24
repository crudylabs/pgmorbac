-- =============================================================================
-- Unattributed (no-org) rule Tests
-- =============================================================================
-- Tests scope = 'unattributed': rules authored by an org that govern objects
-- with no org (org_id IS NULL), evaluated via is_allowed(user, NULL, ...).
--
-- Key properties:
--   - role-bound: the user must hold the rule's role in the declaring org
--   - partitioned: unattributed rules never reach real-org objects, and
--     org-scoped rules never reach no-org objects
--   - composes with prohibition precedence, revocation, delegation, multi-org
--   - has_permission() capability probe surfaces the grant
--
-- Fixtures created here (isolated from the GlobalTech scenario):
--   AttribCorp (org)  role triage   user Nomad
--   IntakeCorp (org)  role intake   user Nomad (multi-org over the same pool)
--
-- Prerequisites: 00_setup.sql -> 15_rls_check.sql
-- =============================================================================

\echo ''
\echo '================================================================'
\echo '16 -- UNATTRIBUTED'
\echo '================================================================'

RESET morbac.user_id;
RESET morbac.org_id;
RESET morbac.org_ids;

INSERT INTO morbac.orgs (id, name) VALUES
  ('40000000-0000-0000-0000-000000000001','AttribCorp'),
  ('40000000-0000-0000-0000-000000000002','IntakeCorp');

INSERT INTO morbac.roles (id, org_id, name) VALUES
  ('40000000-0000-0000-0000-0000000000a1','40000000-0000-0000-0000-000000000001','triage'),
  ('40000000-0000-0000-0000-0000000000a2','40000000-0000-0000-0000-000000000002','intake');

-- Nomad: triage in AttribCorp; Scout: delegatee
\set NOMAD '''40000000-0000-0000-0000-0000000000f1'''
\set SCOUT '''40000000-0000-0000-0000-0000000000f2'''
\set STRANGER '''40000000-0000-0000-0000-0000000000f9'''

INSERT INTO morbac.user_roles (user_id, role_id, org_id) VALUES
  (:NOMAD,'40000000-0000-0000-0000-0000000000a1','40000000-0000-0000-0000-000000000001');

\set CTX '(SELECT id FROM morbac.contexts WHERE name = ''always'')'

-- unattributed permission for triage
INSERT INTO morbac.rules (org_id, role_id, activity, view, context_id, modality, scope)
VALUES ('40000000-0000-0000-0000-000000000001','40000000-0000-0000-0000-0000000000a1',
        'read','documents', :CTX,'permission','unattributed');

\echo ''
\echo '--- 1. Authorization + role binding ---'

SELECT morbac.t('unattributed grant -> orphan object allowed',
    morbac.is_allowed_nocache(:NOMAD, NULL, 'read','documents'), TRUE);

SELECT morbac.t('stranger without role -> orphan denied',
    morbac.is_allowed_nocache(:STRANGER, NULL, 'read','documents'), FALSE);

\echo ''
\echo '--- 2. Partition: unattributed does not reach real-org objects ---'

SELECT morbac.t('unattributed rule does NOT grant AttribCorp object',
    morbac.is_allowed_nocache(:NOMAD, '40000000-0000-0000-0000-000000000001','read','documents'), FALSE);

-- add a self permission; now the org object is allowed, orphan still allowed
INSERT INTO morbac.rules (org_id, role_id, activity, view, context_id, modality, scope)
VALUES ('40000000-0000-0000-0000-000000000001','40000000-0000-0000-0000-0000000000a1',
        'read','documents', :CTX,'permission','self');

SELECT morbac.t('self rule grants AttribCorp object',
    morbac.is_allowed_nocache(:NOMAD, '40000000-0000-0000-0000-000000000001','read','documents'), TRUE);

SELECT morbac.t('orphan still allowed alongside self rule',
    morbac.is_allowed_nocache(:NOMAD, NULL, 'read','documents'), TRUE);

\echo ''
\echo '--- 3. Partition: org-scoped does not reach no-org objects ---'

-- remove the unattributed rule; self remains
DELETE FROM morbac.rules
WHERE org_id = '40000000-0000-0000-0000-000000000001'
  AND role_id = '40000000-0000-0000-0000-0000000000a1'
  AND scope = 'unattributed';

SELECT morbac.t('self rule does NOT reach orphan object',
    morbac.is_allowed_nocache(:NOMAD, NULL, 'read','documents'), FALSE);

SELECT morbac.t('AttribCorp object still allowed by self rule',
    morbac.is_allowed_nocache(:NOMAD, '40000000-0000-0000-0000-000000000001','read','documents'), TRUE);

-- restore unattributed permission for the remaining tests
INSERT INTO morbac.rules (org_id, role_id, activity, view, context_id, modality, scope)
VALUES ('40000000-0000-0000-0000-000000000001','40000000-0000-0000-0000-0000000000a1',
        'read','documents', :CTX,'permission','unattributed');

\echo ''
\echo '--- 4. Prohibition precedence on orphan objects ---'

INSERT INTO morbac.rules (org_id, role_id, activity, view, context_id, modality, scope, priority)
VALUES ('40000000-0000-0000-0000-000000000001','40000000-0000-0000-0000-0000000000a1',
        'read','documents', :CTX,'prohibition','unattributed', 10);

SELECT morbac.t('unattributed prohibition (prio 10) beats permission (prio 0)',
    morbac.is_allowed_nocache(:NOMAD, NULL, 'read','documents'), FALSE);

DELETE FROM morbac.rules
WHERE org_id = '40000000-0000-0000-0000-000000000001'
  AND role_id = '40000000-0000-0000-0000-0000000000a1'
  AND scope = 'unattributed' AND modality = 'prohibition';

\echo ''
\echo '--- 5. Revocation ---'

DELETE FROM morbac.user_roles WHERE user_id = :NOMAD;

SELECT morbac.t('revoke role -> orphan access removed',
    morbac.is_allowed_nocache(:NOMAD, NULL, 'read','documents'), FALSE);

INSERT INTO morbac.user_roles (user_id, role_id, org_id) VALUES
  (:NOMAD,'40000000-0000-0000-0000-0000000000a1','40000000-0000-0000-0000-000000000001');

\echo ''
\echo '--- 6. Delegation propagates orphan access ---'

INSERT INTO morbac.delegations (delegator_id, delegatee_id, role_id, org_id, valid_until)
VALUES (:NOMAD, :SCOUT, '40000000-0000-0000-0000-0000000000a1',
        '40000000-0000-0000-0000-000000000001', now() + interval '1 day');

SELECT morbac.t('delegatee gains orphan access via delegated role',
    morbac.is_allowed_nocache(:SCOUT, NULL, 'read','documents'), TRUE);

\echo ''
\echo '--- 7. Multi-org: independent authority over the same pool ---'

INSERT INTO morbac.user_roles (user_id, role_id, org_id) VALUES
  (:NOMAD,'40000000-0000-0000-0000-0000000000a2','40000000-0000-0000-0000-000000000002');
INSERT INTO morbac.rules (org_id, role_id, activity, view, context_id, modality, scope)
VALUES ('40000000-0000-0000-0000-000000000002','40000000-0000-0000-0000-0000000000a2',
        'write','documents', :CTX,'permission','unattributed');

SELECT morbac.t('IntakeCorp role independently grants orphan write',
    morbac.is_allowed_nocache(:NOMAD, NULL, 'write','documents'), TRUE);

\echo ''
\echo '--- 8. has_permission capability probe ---'

SELECT morbac.t('has_permission TRUE via orphan grant',
    morbac.has_permission(:NOMAD, 'read','documents'), TRUE);

SELECT morbac.t('has_permission FALSE for ungranted activity/view',
    morbac.has_permission(:STRANGER, 'read','documents'), FALSE);

\echo ''
\echo '--- 9. Org target triad: specific / unattributed / all ---'

-- role-based 'all': every org, unattributed included
INSERT INTO morbac.roles (id, org_id, name) VALUES
  ('40000000-0000-0000-0000-0000000000a3','40000000-0000-0000-0000-000000000001','overseer');
INSERT INTO morbac.user_roles (user_id, role_id, org_id) VALUES
  (:SCOUT,'40000000-0000-0000-0000-0000000000a3','40000000-0000-0000-0000-000000000001');
INSERT INTO morbac.rules (org_id, role_id, activity, view, context_id, modality, scope)
VALUES ('40000000-0000-0000-0000-000000000001','40000000-0000-0000-0000-0000000000a3',
        'approve','documents', :CTX,'permission','all');

SELECT morbac.t('scope all reaches a specific org',
    morbac.is_allowed_nocache(:SCOUT, '40000000-0000-0000-0000-000000000002','approve','documents'), TRUE);

SELECT morbac.t('scope all reaches unattributed objects',
    morbac.is_allowed_nocache(:SCOUT, NULL,'approve','documents'), TRUE);

-- roleless user_rule targeting unattributed (org_id NULL)
INSERT INTO morbac.user_rules (user_id, org_id, activity, view, context_id, modality)
VALUES (:STRANGER, NULL, 'read','reports', :CTX,'permission');

SELECT morbac.t('user_rule with no org grants unattributed objects',
    morbac.is_allowed_nocache(:STRANGER, NULL,'read','reports'), TRUE);

SELECT morbac.t('user_rule with no org does NOT reach a real org',
    morbac.is_allowed_nocache(:STRANGER, '40000000-0000-0000-0000-000000000001','read','reports'), FALSE);

-- roleless user_rule targeting a specific org stays partitioned
INSERT INTO morbac.user_rules (user_id, org_id, activity, view, context_id, modality)
VALUES (:STRANGER, '40000000-0000-0000-0000-000000000002', 'read','documents', :CTX,'permission');

SELECT morbac.t('user_rule with an org grants that org',
    morbac.is_allowed_nocache(:STRANGER, '40000000-0000-0000-0000-000000000002','read','documents'), TRUE);

SELECT morbac.t('user_rule with an org does NOT reach unattributed',
    morbac.is_allowed_nocache(:STRANGER, NULL,'read','documents'), FALSE);

\echo ''
\echo '--- 10. rls_check filter matrix ---'

SELECT set_config('morbac.user_id', :NOMAD, false);

RESET morbac.org_id;
RESET morbac.org_ids;
SELECT morbac.t('no filter: orphan row visible',
    morbac.rls_check('read','documents', NULL), TRUE);

SET morbac.org_id = '40000000-0000-0000-0000-000000000001';
SELECT morbac.t('single org pin: orphan row filtered out',
    morbac.rls_check('read','documents', NULL), FALSE);
RESET morbac.org_id;

SET morbac.org_ids = '[null]';
SELECT morbac.t('org_ids [null]: orphan row visible',
    morbac.rls_check('read','documents', NULL), TRUE);
SELECT morbac.t('org_ids [null]: real-org row filtered out',
    morbac.rls_check('read','documents', '40000000-0000-0000-0000-000000000001'::uuid), FALSE);

SET morbac.org_ids = '["40000000-0000-0000-0000-000000000001", null]';
SELECT morbac.t('org_ids [AttribCorp, null]: orphan row visible',
    morbac.rls_check('read','documents', NULL), TRUE);
SELECT morbac.t('org_ids [AttribCorp, null]: AttribCorp row visible',
    morbac.rls_check('read','documents', '40000000-0000-0000-0000-000000000001'::uuid), TRUE);

RESET morbac.user_id;
RESET morbac.org_ids;

\echo ''
\echo '=== Unattributed Tests Completed ==='
