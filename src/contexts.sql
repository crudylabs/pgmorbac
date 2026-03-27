-- Contexts represent conditions under which rules apply, implemented as callable predicates

CREATE TABLE morbac.contexts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL UNIQUE,
    description TEXT,
    evaluator REGPROC NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_contexts_name ON morbac.contexts(name);

COMMENT ON TABLE morbac.contexts IS 'Contexts - conditions under which rules apply (callable predicates)';
COMMENT ON COLUMN morbac.contexts.evaluator IS 'Function that evaluates this context (returns boolean)';

-- Default context that always evaluates to true

CREATE OR REPLACE FUNCTION morbac.context_always()
RETURNS BOOLEAN
LANGUAGE plpgsql
STABLE
AS $$
BEGIN
    RETURN TRUE;
END;
$$;

COMMENT ON FUNCTION morbac.context_always() IS 'Default context evaluator - always returns true';

INSERT INTO morbac.contexts (name, description, evaluator)
VALUES (
    'always',
    'Default context - always evaluates to true',
    'morbac.context_always'::regproc
);

CREATE OR REPLACE FUNCTION morbac.eval_context(p_context_id UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    v_evaluator REGPROC;
    v_result BOOLEAN;
BEGIN
    SELECT evaluator INTO v_evaluator
    FROM morbac.contexts
    WHERE id = p_context_id;

    IF v_evaluator IS NULL THEN
        RAISE EXCEPTION 'Context % not found', p_context_id;
    END IF;

    EXECUTE format('SELECT %s()', v_evaluator::text) INTO v_result;

    RETURN COALESCE(v_result, FALSE);
END;
$$;

COMMENT ON FUNCTION morbac.eval_context(UUID) IS 'Evaluates a context by calling its evaluator function';
