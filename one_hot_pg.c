#include "postgres.h"

#include "catalog/pg_type_d.h"
#include "fmgr.h"
#include "funcapi.h"
#include "mb/pg_wchar.h"
#include "miscadmin.h"
#include "utils/array.h"
#include "utils/builtins.h"
#include "utils/lsyscache.h"
#include "utils/memutils.h"
#include "utils/tuplestore.h"

#include "one_hot_core.h"

PG_FUNCTION_INFO_V1(pg_ml_one_hot_encode_column);

static void
check_one_hot_interrupts(void)
{
    CHECK_FOR_INTERRUPTS();
}

/* One replacement underscore per non-ASCII or special character. */
static char *
sanitize_category(const char *value)
{
    char *result = palloc(strlen(value) + 1);
    char *out = result;
    const char *p = value;

    while (*p != '\0')
    {
        unsigned char c = (unsigned char) *p;
        int length = pg_mblen(p);

        if (length == 1 &&
            ((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') ||
             (c >= '0' && c <= '9') || c == '_'))
            *out++ = (char) c;
        else
            *out++ = '_';
        p += length;
    }
    *out = '\0';
    return result;
}

/*
 * A collision after sanitization does not merge the original categories.
 * Add suffixes _2, _3, ... until the feature label is unique.
 */
static char *
make_unique_feature_name(const char *prefix, const char *category,
                         char **previous, int previous_count)
{
    char *clean = sanitize_category(category);
    char *base = psprintf("%s_%s", prefix, clean);
    char *candidate = base;
    int suffix = 2;

    pfree(clean);
    for (;;)
    {
        bool collision = false;
        int j;

        for (j = 0; j < previous_count; ++j)
        {
            if ((j & 1023) == 0)
                CHECK_FOR_INTERRUPTS();
            if (strcmp(candidate, previous[j]) == 0)
            {
                collision = true;
                break;
            }
        }
        if (!collision)
            break;
        if (candidate != base)
            pfree(candidate);
        candidate = psprintf("%s_%d", base, suffix++);
    }
    if (candidate != base)
        pfree(base);
    return candidate;
}

/* Return a TABLE row: matrix[k][n] and feature_names[k]. */
Datum
pg_ml_one_hot_encode_column(PG_FUNCTION_ARGS)
{
    ArrayType *input = PG_GETARG_ARRAYTYPE_P(0);
    char *prefix = text_to_cstring(PG_GETARG_TEXT_PP(1));
    ReturnSetInfo *rsinfo = (ReturnSetInfo *) fcinfo->resultinfo;
    Oid element_type = ARR_ELEMTYPE(input);
    Oid output_function;
    bool type_is_varlena;
    int16 input_length;
    bool input_by_value;
    char input_alignment;
    int16 float_length;
    bool float_by_value;
    char float_alignment;
    Datum *elements;
    bool *is_null;
    int count;
    char **texts;
    const char **categories;
    MLOneHotReference *work;
    int *indexes;
    int category_count;
    Size total;
    Datum *encoded;
    char **feature_names;
    Datum *feature_elements;
    Datum fields[2];
    bool field_nulls[2] = {false, false};
    int dims[2];
    int lower_bounds[2] = {1, 1};
    int16 text_length;
    bool text_by_value;
    char text_alignment;
    int i;
    Size position;

    InitMaterializedSRF(fcinfo, 0);
    if (ARR_NDIM(input) != 1)
        ereport(ERROR,
                (errcode(ERRCODE_INVALID_PARAMETER_VALUE),
                 errmsg("column_values must be a nonempty one-dimensional array")));

    get_typlenbyvalalign(element_type, &input_length,
                        &input_by_value, &input_alignment);
    getTypeOutputInfo(element_type, &output_function, &type_is_varlena);
    deconstruct_array(input, element_type, input_length,
                      input_by_value, input_alignment,
                      &elements, &is_null, &count);

    /* Every allocation is checked by PostgreSQL before conversion to bytes. */
    if ((Size) count > MaxAllocSize / sizeof(MLOneHotReference))
        ereport(ERROR,
                (errcode(ERRCODE_PROGRAM_LIMIT_EXCEEDED),
                 errmsg("too many observations for one-hot encoding")));
    texts = palloc0((Size) count * sizeof(char *));
    categories = palloc((Size) count * sizeof(char *));
    work = palloc((Size) count * sizeof(MLOneHotReference));
    indexes = palloc((Size) count * sizeof(int));

    for (i = 0; i < count; ++i)
    {
        if ((i & 1023) == 0)
            CHECK_FOR_INTERRUPTS();
        if (!is_null[i])
            texts[i] = OidOutputFunctionCall(output_function, elements[i]);
    }
    category_count = (int) ml_pg_one_hot_index(
        (const char *const *) texts, is_null, count,
        categories, work, indexes, check_one_hot_interrupts);
    if (category_count == 0)
        ereport(ERROR,
                (errcode(ERRCODE_INVALID_PARAMETER_VALUE),
                 errmsg("column_values contains only NULL values")));

    if ((Size) category_count > MaxArraySize / (Size) count)
        ereport(ERROR,
                (errcode(ERRCODE_PROGRAM_LIMIT_EXCEEDED),
                 errmsg("one-hot matrix is too large")));
    total = (Size) category_count * (Size) count;
    encoded = palloc(total * sizeof(Datum));
    for (position = 0; position < total; ++position)
    {
        if ((position & 1023) == 0)
            CHECK_FOR_INTERRUPTS();
        encoded[position] = Float8GetDatum(0.0);
    }
    for (i = 0; i < count; ++i)
    {
        if ((i & 1023) == 0)
            CHECK_FOR_INTERRUPTS();
        if (indexes[i] >= 0)
            encoded[(Size) indexes[i] * count + i] = Float8GetDatum(1.0);
    }

    feature_names = palloc((Size) category_count * sizeof(char *));
    feature_elements = palloc((Size) category_count * sizeof(Datum));
    for (i = 0; i < category_count; ++i)
    {
        CHECK_FOR_INTERRUPTS();
        feature_names[i] = make_unique_feature_name(prefix, categories[i], feature_names, i);
        feature_elements[i] = CStringGetTextDatum(feature_names[i]);
    }

    dims[0] = category_count;
    dims[1] = count;
    get_typlenbyvalalign(FLOAT8OID, &float_length,
                        &float_by_value, &float_alignment);
    fields[0] = PointerGetDatum(construct_md_array(
        encoded, NULL, 2, dims, lower_bounds, FLOAT8OID,
        float_length, float_by_value, float_alignment));
    get_typlenbyvalalign(TEXTOID, &text_length, &text_by_value, &text_alignment);
    fields[1] = PointerGetDatum(construct_array(
        feature_elements, category_count, TEXTOID,
        text_length, text_by_value, text_alignment));

    tuplestore_putvalues(rsinfo->setResult, rsinfo->setDesc, fields, field_nulls);
    pfree(DatumGetPointer(fields[0]));
    pfree(DatumGetPointer(fields[1]));
    for (i = 0; i < count; ++i)
        if (texts[i] != NULL)
            pfree(texts[i]);
    for (i = 0; i < category_count; ++i)
    {
        pfree(feature_names[i]);
        pfree(DatumGetPointer(feature_elements[i]));
    }
    pfree(prefix);
    pfree(texts);
    pfree(categories);
    pfree(work);
    pfree(indexes);
    pfree(encoded);
    pfree(feature_names);
    pfree(feature_elements);
    pfree(elements);
    pfree(is_null);
    PG_FREE_IF_COPY(input, 0);
    PG_RETURN_NULL();
}
