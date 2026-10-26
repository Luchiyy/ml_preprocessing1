#include "postgres.h"

#include "catalog/pg_type_d.h"
#include "fmgr.h"
#include "funcapi.h"
#include "miscadmin.h"
#include "utils/array.h"
#include "utils/lsyscache.h"
#include "utils/tuplestore.h"

#include "standardize_core.h"

PG_FUNCTION_INFO_V1(pg_ml_standardize_matrix);

static void
check_standardize_interrupts(void)
{
    CHECK_FOR_INTERRUPTS();
}

/* Return one TABLE row: standardized_matrix, means, stddevs. */
Datum
pg_ml_standardize_matrix(PG_FUNCTION_ARGS)
{
    ArrayType *input = PG_GETARG_ARRAYTYPE_P(0);
    ReturnSetInfo *rsinfo = (ReturnSetInfo *) fcinfo->resultinfo;
    Datum *elements;
    bool *is_null;
    int count;
    int rows;
    int cols;
    int16 element_length;
    bool element_by_value;
    char element_alignment;
    double *numbers;
    double *standardized;
    double *means;
    double *stddevs;
    Datum *mean_elements;
    Datum *stddev_elements;
    Datum fields[3];
    bool field_nulls[3] = {false, false, false};
    size_t bad_column = 0;
    MLStandardizeStatus status;
    int i;

    InitMaterializedSRF(fcinfo, 0);
    if (ARR_NDIM(input) != 2)
        ereport(ERROR,
                (errcode(ERRCODE_INVALID_PARAMETER_VALUE),
                 errmsg("matrix must be a nonempty two-dimensional array")));
    if (ARR_ELEMTYPE(input) != FLOAT8OID)
        ereport(ERROR,
                (errcode(ERRCODE_DATATYPE_MISMATCH),
                 errmsg("matrix elements must have type double precision")));

    rows = ARR_DIMS(input)[0];
    cols = ARR_DIMS(input)[1];
    get_typlenbyvalalign(FLOAT8OID, &element_length,
                        &element_by_value, &element_alignment);
    deconstruct_array(input, FLOAT8OID, element_length,
                      element_by_value, element_alignment,
                      &elements, &is_null, &count);

    numbers = palloc0((Size) count * sizeof(double));
    standardized = palloc((Size) count * sizeof(double));
    means = palloc((Size) cols * sizeof(double));
    stddevs = palloc((Size) cols * sizeof(double));
    mean_elements = palloc((Size) cols * sizeof(Datum));
    stddev_elements = palloc((Size) cols * sizeof(Datum));
    for (i = 0; i < count; ++i)
    {
        if ((i & 1023) == 0)
            CHECK_FOR_INTERRUPTS();
        if (!is_null[i])
            numbers[i] = DatumGetFloat8(elements[i]);
    }

    status = ml_pg_standardize_core(numbers, is_null, rows, cols,
                                    standardized, means, stddevs, &bad_column,
                                    check_standardize_interrupts);
    if (status == ML_STD_ALL_NULL_COLUMN)
        ereport(ERROR,
                (errcode(ERRCODE_INVALID_PARAMETER_VALUE),
                 errmsg("column %d contains only NULL values",
                        ARR_LBOUND(input)[1] + (int) bad_column),
                 errhint("Fill missing values before standardization.")));
    if (status == ML_STD_NONFINITE_INPUT)
        ereport(ERROR,
                (errcode(ERRCODE_INVALID_PARAMETER_VALUE),
                 errmsg("matrix must contain only finite numbers or NULL")));
    if (status != ML_STD_OK)
        ereport(ERROR,
                (errcode(ERRCODE_NUMERIC_VALUE_OUT_OF_RANGE),
                 errmsg("standardization statistics or values are outside the double precision range")));

    for (i = 0; i < count; ++i)
    {
        if ((i & 1023) == 0)
            CHECK_FOR_INTERRUPTS();
        elements[i] = Float8GetDatum(standardized[i]);
    }
    for (i = 0; i < cols; ++i)
    {
        mean_elements[i] = Float8GetDatum(means[i]);
        stddev_elements[i] = Float8GetDatum(stddevs[i]);
    }

    fields[0] = PointerGetDatum(construct_md_array(
        elements, is_null, 2, ARR_DIMS(input), ARR_LBOUND(input),
        FLOAT8OID, element_length, element_by_value, element_alignment));
    fields[1] = PointerGetDatum(construct_array(
        mean_elements, cols, FLOAT8OID,
        element_length, element_by_value, element_alignment));
    fields[2] = PointerGetDatum(construct_array(
        stddev_elements, cols, FLOAT8OID,
        element_length, element_by_value, element_alignment));

    tuplestore_putvalues(rsinfo->setResult, rsinfo->setDesc, fields, field_nulls);

    pfree(DatumGetPointer(fields[0]));
    pfree(DatumGetPointer(fields[1]));
    pfree(DatumGetPointer(fields[2]));
    pfree(numbers);
    pfree(standardized);
    pfree(means);
    pfree(stddevs);
    pfree(mean_elements);
    pfree(stddev_elements);
    pfree(elements);
    pfree(is_null);
    PG_FREE_IF_COPY(input, 0);
    PG_RETURN_NULL();
}
