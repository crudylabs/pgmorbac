CREATE TYPE morbac.modality AS ENUM (
    'permission',
    'prohibition',
    'obligation',
    'recommendation'
);

COMMENT ON TYPE morbac.modality IS 'Deontic modalities: permission, prohibition, obligation, recommendation';
