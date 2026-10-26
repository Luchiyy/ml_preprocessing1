CREATE FUNCTION ml_preprocessing_ping()
RETURNS text
AS 'MODULE_PATHNAME', 'ml_preprocessing_ping'
LANGUAGE C IMMUTABLE PARALLEL SAFE;

COMMENT ON FUNCTION ml_preprocessing_ping() IS
    'Checks that the PostgreSQL server can call the C extension module.';

CREATE FUNCTION handle_missing_values(
    matrix double precision[],
    method text DEFAULT 'mean'
)
RETURNS double precision[]
AS 'MODULE_PATHNAME', 'pg_ml_handle_missing_values'
LANGUAGE C IMMUTABLE STRICT PARALLEL SAFE;

COMMENT ON FUNCTION handle_missing_values(double precision[], text) IS
    'Fills NULL elements of a 2D matrix using zeros, column mean, or column median.';
