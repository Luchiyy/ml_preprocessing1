#include "postgres.h"

#include <math.h>

#include "catalog/pg_type_d.h"
#include "fmgr.h"
#include "miscadmin.h"
#include "utils/array.h"
#include "utils/builtins.h"
#include "utils/lsyscache.h"

PG_FUNCTION_INFO_V1(pg_ml_handle_missing_values);

typedef enum
{
    ML_FILL_ZEROS,
    ML_FILL_MEAN,
    ML_FILL_MEDIAN
} MLFillMethod;

/* Values passed to qsort have already been checked for finiteness. */
static int
compare_doubles(const void *a, const void *b)
{
    double x = *((const double *) a);
    double y = *((const double *) b);

    return (x > y) - (x < y);
}

/*
 * PostgreSQL adaptation of the standalone library's per-column algorithm.
 * Datum holds SQL values; is_null is the separate missing-value mask.
 * PostgreSQL owns the allocated memory, including on ERROR.
 */
Datum
pg_ml_handle_missing_values(PG_FUNCTION_ARGS)
{
    ArrayType *input = PG_GETARG_ARRAYTYPE_P(0);
    char *method_name = text_to_cstring(PG_GETARG_TEXT_PP(1));
    MLFillMethod method;
    Datum *values;
    bool *is_null;
    int count;
    int rows;
    int cols;
    int16 element_length;
    bool element_by_value;
    char element_alignment;
    double *column_values = NULL;
    ArrayType *output;
    int i;
    int col;

    if (strcmp(method_name, "zeros") == 0)
        method = ML_FILL_ZEROS;
    else if (strcmp(method_name, "mean") == 0)
        method = ML_FILL_MEAN;
    else if (strcmp(method_name, "median") == 0)
        method = ML_FILL_MEDIAN;
    else
        ereport(ERROR,
                (errcode(ERRCODE_INVALID_PARAMETER_VALUE),
                 errmsg("unknown missing-value method: %s", method_name),
                 errhint("Use zeros, mean, or median.")));

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
                      &values, &is_null, &count);

    for (i = 0; i < count; ++i)
    {
        if ((i & 1023) == 0)
            CHECK_FOR_INTERRUPTS();
        if (!is_null[i] && !isfinite(DatumGetFloat8(values[i])))
            ereport(ERROR,
                    (errcode(ERRCODE_INVALID_PARAMETER_VALUE),
                     errmsg("matrix must contain only finite numbers or NULL")));
    }

    if (method == ML_FILL_ZEROS)
    {
        for (i = 0; i < count; ++i)
        {
            if ((i & 1023) == 0)
                CHECK_FOR_INTERRUPTS();
            if (is_null[i])
                values[i] = Float8GetDatum(0.0);
        }
    }
    else
    {
        if (method == ML_FILL_MEDIAN)
            column_values = palloc((Size) rows * sizeof(double));

        for (col = 0; col < cols; ++col)
        {
            int valid_count = 0;
            long double sum = 0.0L;
            double fill_value;
            int row;

            CHECK_FOR_INTERRUPTS();
            for (row = 0; row < rows; ++row)
            {
                int index = row * cols + col;

                if ((row & 1023) == 0)
                    CHECK_FOR_INTERRUPTS();
                if (!is_null[index])
                {
                    double value = DatumGetFloat8(values[index]);

                    if (method == ML_FILL_MEAN)
                        sum += (long double) value;
                    else
                        column_values[valid_count] = value;
                    ++valid_count;
                }
            }

            if (valid_count == 0)
                ereport(ERROR,
                        (errcode(ERRCODE_INVALID_PARAMETER_VALUE),
                         errmsg("column %d contains only NULL values",
                                ARR_LBOUND(input)[1] + col),
                         errhint("Use zeros or provide a known value in each column.")));

            if (method == ML_FILL_MEAN)
                fill_value = (double) (sum / valid_count);
            else
            {
                qsort(column_values, valid_count, sizeof(double), compare_doubles);
                if (valid_count % 2 == 1)
                    fill_value = column_values[valid_count / 2];
                else
                {
                    int right = valid_count / 2;

                    fill_value = (double) (((long double) column_values[right - 1] +
                                           (long double) column_values[right]) / 2.0L);
                }
            }

            if (!isfinite(fill_value))
                ereport(ERROR,
                        (errcode(ERRCODE_NUMERIC_VALUE_OUT_OF_RANGE),
                         errmsg("fill value is outside the finite double precision range")));

            for (row = 0; row < rows; ++row)
            {
                int index = row * cols + col;

                if ((row & 1023) == 0)
                    CHECK_FOR_INTERRUPTS();
                if (is_null[index])
                    values[index] = Float8GetDatum(fill_value);
            }
        }
    }

    /* No NULLs remain. Preserve dimensions and index lower bounds. */
    output = construct_md_array(values, NULL, 2,
                                ARR_DIMS(input), ARR_LBOUND(input),
                                FLOAT8OID, element_length,
                                element_by_value, element_alignment);
    if (column_values != NULL)
        pfree(column_values);
    pfree(values);
    pfree(is_null);
    pfree(method_name);
    PG_FREE_IF_COPY(input, 0);
    PG_RETURN_ARRAYTYPE_P(output);
}
