CREATE FUNCTION ml_preprocessing_ping()
RETURNS text
AS 'MODULE_PATHNAME', 'ml_preprocessing_ping'
LANGUAGE C IMMUTABLE PARALLEL SAFE;

COMMENT ON FUNCTION ml_preprocessing_ping() IS
    'Checks that the PostgreSQL server can call the C extension module.';
