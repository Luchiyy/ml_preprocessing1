CREATE FUNCTION standardize_matrix(matrix double precision[])
RETURNS TABLE (
    standardized_matrix double precision[],
    means double precision[],
    stddevs double precision[]
)
AS 'MODULE_PATHNAME', 'pg_ml_standardize_matrix'
LANGUAGE C IMMUTABLE STRICT PARALLEL SAFE;

COMMENT ON FUNCTION standardize_matrix(double precision[]) IS
    'Standardizes columns using population deviation, preserves NULL elements, and returns statistics.';
