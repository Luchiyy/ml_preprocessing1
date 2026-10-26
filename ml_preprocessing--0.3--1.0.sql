CREATE FUNCTION one_hot_encode_column(column_values anyarray, column_name text)
RETURNS TABLE (
    encoded_matrix double precision[],
    feature_names text[]
)
AS 'MODULE_PATHNAME', 'pg_ml_one_hot_encode_column'
LANGUAGE C VOLATILE STRICT PARALLEL UNSAFE;

COMMENT ON FUNCTION one_hot_encode_column(anyarray, text) IS
    'Encodes text-sorted categories as a category-by-observation matrix and returns unique feature labels.';
