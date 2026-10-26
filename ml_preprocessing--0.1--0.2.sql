CREATE FUNCTION handle_missing_values(
    matrix double precision[],
    method text DEFAULT 'mean'
)
RETURNS double precision[]
AS 'MODULE_PATHNAME', 'pg_ml_handle_missing_values'
LANGUAGE C IMMUTABLE STRICT PARALLEL SAFE;

COMMENT ON FUNCTION handle_missing_values(double precision[], text) IS
    'Fills NULL elements of a 2D matrix using zeros, column mean, or column median.';
