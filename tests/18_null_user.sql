-- =============================================================================
-- NULL user Tests
-- =============================================================================
-- is_allowed() and is_allowed_nocache() answer FALSE for a NULL user id, as
-- rls_check() does, instead of failing on the auth_cache NOT NULL constraint.
--
-- Prerequisites: 00_setup.sql -> 17_is_allowed_equivalence.sql
-- =============================================================================

\echo ''
\echo '================================================================'
\echo '18 -- NULL USER'
\echo '================================================================'

SELECT morbac.t('is_allowed NULL user, org',
    morbac.is_allowed(NULL, '10000000-0000-0000-0000-000000000001'::uuid, 'read', 'documents'),
    FALSE);

SELECT morbac.t('is_allowed NULL user, no org',
    morbac.is_allowed(NULL, NULL, 'read', 'documents'),
    FALSE);

SELECT morbac.t('is_allowed_nocache NULL user, org',
    morbac.is_allowed_nocache(NULL, '10000000-0000-0000-0000-000000000001'::uuid, 'read', 'documents'),
    FALSE);

SELECT morbac.t('is_allowed NULL user writes nothing to auth_cache',
    NOT EXISTS (SELECT 1 FROM morbac.auth_cache WHERE user_id IS NULL),
    TRUE);
