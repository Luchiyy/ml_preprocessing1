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
