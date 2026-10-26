-- Open psql in a database where ml_preprocessing is installed.
SELECT extname, extversion FROM pg_extension WHERE extname = 'ml_preprocessing';

SELECT handle_missing_values(
    ARRAY[[1.0,NULL],[NULL,4.0],[3.0,6.0],[5.0,NULL]]::float8[], 'mean');

SELECT * FROM standardize_matrix(
    ARRAY[[1.0,10.0],[2.0,20.0],[3.0,30.0],[NULL,40.0]]::float8[]);

SELECT * FROM one_hot_encode_column(
    ARRAY['red','blue','red',NULL]::text[], 'color');

SELECT * FROM standardize_matrix(handle_missing_values(
    ARRAY[[1.0,NULL],[NULL,4.0],[3.0,6.0],[5.0,NULL]]::float8[], 'mean'));
