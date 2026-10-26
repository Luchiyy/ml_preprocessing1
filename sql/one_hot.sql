-- Run after installing/upgrading ml_preprocessing to version 1.0.
DO $checks$
DECLARE
    r record;
    query text;
    row_count integer;
BEGIN
    SELECT * INTO STRICT r FROM one_hot_encode_column(
        ARRAY['red','blue','red',NULL]::text[], 'color');
    IF r.feature_names IS DISTINCT FROM ARRAY['color_blue','color_red'] OR
       r.encoded_matrix IS DISTINCT FROM ARRAY[[0,1,0,0],[1,0,1,0]]::float8[] THEN
        RAISE EXCEPTION 'text categories, NULL, or category-by-observation orientation failed';
    END IF;

    SELECT * INTO STRICT r FROM one_hot_encode_column(ARRAY[2,10,2,1], 'code');
    IF r.feature_names IS DISTINCT FROM ARRAY['code_1','code_10','code_2'] OR
       r.encoded_matrix IS DISTINCT FROM ARRAY[[0,0,0,1],[0,1,0,0],[1,0,1,0]]::float8[] THEN
        RAISE EXCEPTION 'integer categories must sort as text';
    END IF;

    SELECT * INTO STRICT r FROM one_hot_encode_column(ARRAY[true,false,true], 'flag');
    IF r.feature_names IS DISTINCT FROM ARRAY['flag_f','flag_t'] OR
       r.encoded_matrix IS DISTINCT FROM ARRAY[[0,1,0],[1,0,1]]::float8[] THEN
        RAISE EXCEPTION 'boolean categories failed';
    END IF;

    SELECT * INTO STRICT r FROM one_hot_encode_column(
        ARRAY['00000000-0000-0000-0000-000000000002',
              '00000000-0000-0000-0000-000000000001']::uuid[], 'id');
    IF r.encoded_matrix IS DISTINCT FROM ARRAY[[0,1],[1,0]]::float8[] OR
       r.feature_names IS DISTINCT FROM ARRAY[
           'id_00000000_0000_0000_0000_000000000001',
           'id_00000000_0000_0000_0000_000000000002'] THEN
        RAISE EXCEPTION 'UUID categories or special-character replacement failed';
    END IF;

    SELECT * INTO STRICT r FROM one_hot_encode_column(ARRAY['a-b','a b','a_b'], 'x');
    IF r.feature_names IS DISTINCT FROM ARRAY['x_a_b','x_a_b_2','x_a_b_3'] OR
       r.encoded_matrix IS DISTINCT FROM ARRAY[[0,1,0],[1,0,0],[0,0,1]]::float8[] THEN
        RAISE EXCEPTION 'name collisions must not merge distinct categories';
    END IF;

    SELECT * INTO STRICT r FROM one_hot_encode_column(
        ARRAY['a b','a-b','a_b_2'], 'x');
    IF r.feature_names IS DISTINCT FROM ARRAY['x_a_b','x_a_b_2','x_a_b_2_2'] THEN
        RAISE EXCEPTION 'a generated suffix collided with another category';
    END IF;

    SELECT * INTO STRICT r FROM one_hot_encode_column(ARRAY['',''], 'x');
    IF r.feature_names IS DISTINCT FROM ARRAY['x_'] OR
       r.encoded_matrix IS DISTINCT FROM ARRAY[[1,1]]::float8[] THEN
        RAISE EXCEPTION 'empty strings are valid categories';
    END IF;

    SELECT * INTO STRICT r FROM one_hot_encode_column(
        '[0:3]={red,blue,red,NULL}'::text[], 'color');
    IF r.encoded_matrix IS DISTINCT FROM ARRAY[[0,1,0,0],[1,0,1,0]]::float8[] THEN
        RAISE EXCEPTION 'observation order changed for nonstandard bounds';
    END IF;

    SELECT count(*) INTO row_count FROM one_hot_encode_column(NULL::text[], 'x');
    IF row_count != 0 THEN
        RAISE EXCEPTION 'NULL array should produce no rows';
    END IF;
    SELECT count(*) INTO row_count FROM one_hot_encode_column(ARRAY['a'], NULL);
    IF row_count != 0 THEN
        RAISE EXCEPTION 'NULL name should produce no rows';
    END IF;

    FOREACH query IN ARRAY ARRAY[
        $q$SELECT * FROM one_hot_encode_column(ARRAY[]::text[], 'x')$q$,
        $q$SELECT * FROM one_hot_encode_column(ARRAY[NULL,NULL]::text[], 'x')$q$,
        $q$SELECT * FROM one_hot_encode_column(ARRAY[['a','b']], 'x')$q$
    ] LOOP
        BEGIN
            EXECUTE query;
            RAISE EXCEPTION 'Expected SQLSTATE 22023: %', query;
        EXCEPTION
            WHEN invalid_parameter_value THEN NULL;
        END;
    END LOOP;

    SELECT * INTO STRICT r FROM one_hot_encode_column(ARRAY['a','a'], 'x');
    IF r.encoded_matrix IS DISTINCT FROM ARRAY[[1,1]]::float8[] THEN
        RAISE EXCEPTION 'function failed after expected errors';
    END IF;
END
$checks$;
SELECT 'All one-hot checks passed.' AS result;
