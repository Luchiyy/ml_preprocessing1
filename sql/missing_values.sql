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
