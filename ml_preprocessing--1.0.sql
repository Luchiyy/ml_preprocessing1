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

CREATE FUNCTION one_hot_encode_column(column_values anyarray, column_name text)
RETURNS TABLE (
    encoded_matrix double precision[],
    feature_names text[]
)
AS 'MODULE_PATHNAME', 'pg_ml_one_hot_encode_column'
LANGUAGE C VOLATILE STRICT PARALLEL UNSAFE;

COMMENT ON FUNCTION one_hot_encode_column(anyarray, text) IS
    'Encodes text-sorted categories as a category-by-observation matrix and returns unique feature labels.';
