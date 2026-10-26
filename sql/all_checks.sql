-- Verify installation before the functional checks.
DO $installation$
BEGIN
    IF (SELECT extversion FROM pg_extension WHERE extname = 'ml_preprocessing')
       IS DISTINCT FROM '1.0' THEN
        RAISE EXCEPTION 'Install or update ml_preprocessing to version 1.0 first';
    END IF;
    IF (SELECT count(*)
          FROM pg_extension AS e
          JOIN pg_depend AS d ON d.refclassid = 'pg_extension'::regclass
                             AND d.refobjid = e.oid AND d.deptype = 'e'
          JOIN pg_proc AS p ON d.classid = 'pg_proc'::regclass AND p.oid = d.objid
          JOIN pg_language AS l ON l.oid = p.prolang
         WHERE e.extname = 'ml_preprocessing' AND l.lanname = 'c'
           AND p.proname IN ('handle_missing_values','standardize_matrix','one_hot_encode_column')) != 3 THEN
        RAISE EXCEPTION 'All three preprocessing functions must be extension members implemented in C';
    END IF;
END
$installation$;

-- Run in a database where ml_preprocessing 0.2 is already installed.
-- psql -v ON_ERROR_STOP=1 -d ml_preprocessing_test < sql/missing_values.sql
DO $checks$
DECLARE
    query text;
BEGIN
    IF handle_missing_values(
        ARRAY[[1.0,NULL],[NULL,4.0],[3.0,6.0],[5.0,NULL]]::float8[], 'zeros'
    ) IS DISTINCT FROM ARRAY[[1,0],[0,4],[3,6],[5,0]]::float8[] THEN
        RAISE EXCEPTION 'zeros example failed';
    END IF;

    IF handle_missing_values(
        ARRAY[[1.0,NULL],[NULL,4.0],[3.0,6.0],[5.0,NULL]]::float8[]
    ) IS DISTINCT FROM ARRAY[[1,5],[3,4],[3,6],[5,5]]::float8[] THEN
        RAISE EXCEPTION 'default mean example failed';
    END IF;

    IF handle_missing_values(
        ARRAY[[1.0],[2.0],[100.0],[NULL]]::float8[], 'mean'
    ) IS DISTINCT FROM ARRAY[[1],[2],[100],[103.0/3]]::float8[] THEN
        RAISE EXCEPTION 'mean example failed';
    END IF;

    IF handle_missing_values(
        ARRAY[[1.0],[2.0],[100.0],[NULL]]::float8[], 'median'
    ) IS DISTINCT FROM ARRAY[[1],[2],[100],[2]]::float8[] THEN
        RAISE EXCEPTION 'odd median example failed';
    END IF;

    IF handle_missing_values(
        ARRAY[[1.0],[3.0],[9.0],[11.0],[NULL]]::float8[], 'median'
    ) IS DISTINCT FROM ARRAY[[1],[3],[9],[11],[6]]::float8[] THEN
        RAISE EXCEPTION 'even median example failed';
    END IF;

    IF handle_missing_values(
        ARRAY[[NULL,NULL],[NULL,NULL]]::float8[], 'zeros'
    ) IS DISTINCT FROM ARRAY[[0,0],[0,0]]::float8[] THEN
        RAISE EXCEPTION 'all-null zeros example failed';
    END IF;

    IF handle_missing_values(
        ARRAY[[1,2],[3,4]]::float8[], 'median'
    ) IS DISTINCT FROM ARRAY[[1,2],[3,4]]::float8[] THEN
        RAISE EXCEPTION 'known values were changed';
    END IF;

    IF handle_missing_values(
        '[0:1][-1:0]={{1,NULL},{3,8}}'::float8[], 'mean'
    ) IS DISTINCT FROM '[0:1][-1:0]={{1,8},{3,8}}'::float8[] THEN
        RAISE EXCEPTION 'array bounds were changed';
    END IF;

    IF handle_missing_values(NULL::float8[]) IS NOT NULL OR
       handle_missing_values(ARRAY[[1]]::float8[], NULL) IS NOT NULL THEN
        RAISE EXCEPTION 'SQL NULL argument handling failed';
    END IF;

    FOREACH query IN ARRAY ARRAY[
        $q$SELECT handle_missing_values(ARRAY[[1]]::float8[], 'unknown')$q$,
        $q$SELECT handle_missing_values(ARRAY[[NULL],[NULL]]::float8[], 'mean')$q$,
        $q$SELECT handle_missing_values(ARRAY[[NULL],[NULL]]::float8[], 'median')$q$,
        $q$SELECT handle_missing_values(ARRAY[]::float8[], 'zeros')$q$,
        $q$SELECT handle_missing_values(ARRAY[1,2]::float8[], 'zeros')$q$,
        $q$SELECT handle_missing_values(ARRAY[[[1]]]::float8[], 'zeros')$q$,
        $q$SELECT handle_missing_values(ARRAY[['NaN'::float8]], 'zeros')$q$,
        $q$SELECT handle_missing_values(ARRAY[['Infinity'::float8]], 'mean')$q$
    ] LOOP
        BEGIN
            EXECUTE query;
            RAISE EXCEPTION 'Expected SQLSTATE 22023: %', query;
        EXCEPTION
            WHEN invalid_parameter_value THEN NULL;
        END;
    END LOOP;

    IF handle_missing_values(ARRAY[[2],[NULL],[4]]::float8[]) IS DISTINCT FROM
       ARRAY[[2],[3],[4]]::float8[] THEN
        RAISE EXCEPTION 'function failed after expected errors';
    END IF;
END
$checks$;
SELECT 'All missing-value checks passed.' AS result;


-- Run after installing/upgrading ml_preprocessing to version 0.3.
DO $checks$
DECLARE
    r record;
    col integer;
    row_number integer;
    mean_z float8;
    stddev_z float8;
    query text;
BEGIN
    SELECT * INTO STRICT r FROM standardize_matrix(
        ARRAY[[1.0,10.0],[2.0,20.0],[3.0,30.0],[NULL,40.0]]::float8[]);
    IF r.means IS DISTINCT FROM ARRAY[2,25]::float8[] OR
       abs(r.stddevs[1] - sqrt(2.0/3.0)) > 1e-12 OR
       abs(r.stddevs[2] - sqrt(125.0)) > 1e-12 THEN
        RAISE EXCEPTION 'statistics differ from the thesis example';
    END IF;
    IF array_dims(r.standardized_matrix) IS DISTINCT FROM '[1:4][1:2]' OR
       r.standardized_matrix[4][1] IS NOT NULL THEN
        RAISE EXCEPTION 'matrix shape or missing-value mask changed';
    END IF;
    IF abs(r.standardized_matrix[1][1] + sqrt(1.5)) > 1e-12 OR
       abs(r.standardized_matrix[3][1] - sqrt(1.5)) > 1e-12 OR
       abs(r.standardized_matrix[4][2] - 15.0/sqrt(125.0)) > 1e-12 THEN
        RAISE EXCEPTION 'standardized values differ from the thesis example';
    END IF;
    FOR col IN 1..2 LOOP
        SELECT avg(r.standardized_matrix[g.i][col]),
               stddev_pop(r.standardized_matrix[g.i][col])
          INTO mean_z, stddev_z
          FROM generate_series(1,4) AS g(i);
        IF abs(mean_z) > 1e-12 OR abs(stddev_z - 1.0) > 1e-12 THEN
            RAISE EXCEPTION 'column % does not have mean 0 and population deviation 1', col;
        END IF;
    END LOOP;

    SELECT * INTO STRICT r FROM standardize_matrix(
        ARRAY[[5,NULL],[5,7],[5,NULL]]::float8[]);
    IF r.means IS DISTINCT FROM ARRAY[5,7]::float8[] OR
       r.stddevs IS DISTINCT FROM ARRAY[0,0]::float8[] OR
       r.standardized_matrix IS DISTINCT FROM ARRAY[[0,NULL],[0,0],[0,NULL]]::float8[] THEN
        RAISE EXCEPTION 'constant or single-known-value column failed';
    END IF;

    SELECT * INTO STRICT r FROM standardize_matrix(
        '[0:1][-1:0]={{1,NULL},{3,7}}'::float8[]);
    IF r.standardized_matrix IS DISTINCT FROM
       '[0:1][-1:0]={{-1,NULL},{1,0}}'::float8[] OR
       r.means IS DISTINCT FROM ARRAY[2,7]::float8[] THEN
        RAISE EXCEPTION 'nonstandard index bounds failed';
    END IF;

    -- SQL type names float8[] and float8[][] do not enforce the dimensions.
    FOREACH query IN ARRAY ARRAY[
        $q$SELECT * FROM standardize_matrix(ARRAY[]::float8[])$q$,
        $q$SELECT * FROM standardize_matrix(ARRAY[1,2]::float8[])$q$,
        $q$SELECT * FROM standardize_matrix(ARRAY[[[1]]]::float8[])$q$,
        $q$SELECT * FROM standardize_matrix(ARRAY[[NULL],[NULL]]::float8[])$q$,
        $q$SELECT * FROM standardize_matrix(ARRAY[['NaN'::float8]])$q$,
        $q$SELECT * FROM standardize_matrix(ARRAY[['Infinity'::float8]])$q$
    ] LOOP
        BEGIN
            EXECUTE query;
            RAISE EXCEPTION 'Expected SQLSTATE 22023: %', query;
        EXCEPTION
            WHEN invalid_parameter_value THEN NULL;
        END;
    END LOOP;

    SELECT count(*) INTO row_number FROM standardize_matrix(NULL::float8[]);
    IF row_number != 0 THEN
        RAISE EXCEPTION 'STRICT table function should return no rows for a NULL argument';
    END IF;

    -- Both implemented preprocessing functions must work together.
    SELECT * INTO STRICT r FROM standardize_matrix(handle_missing_values(
        ARRAY[[1,NULL],[NULL,4],[3,6],[5,NULL]]::float8[], 'mean'));
    IF r.means IS DISTINCT FROM ARRAY[3,5]::float8[] THEN
        RAISE EXCEPTION 'pipeline means failed';
    END IF;
    FOR col IN 1..2 LOOP
        SELECT avg(r.standardized_matrix[g.i][col]),
               stddev_pop(r.standardized_matrix[g.i][col])
          INTO mean_z, stddev_z
          FROM generate_series(1,4) AS g(i);
        IF abs(mean_z) > 1e-12 OR abs(stddev_z - 1.0) > 1e-12 THEN
            RAISE EXCEPTION 'pipeline normalization failed';
        END IF;
    END LOOP;
END
$checks$;
SELECT 'All standardization checks passed.' AS result;


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

SELECT 'All preprocessing checks passed.' AS result;
