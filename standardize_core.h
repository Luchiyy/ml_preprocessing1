#ifndef ML_STANDARDIZE_CORE_H
#define ML_STANDARDIZE_CORE_H

#include <stdbool.h>
#include <stddef.h>

typedef enum
{
    ML_STD_OK = 0,
    ML_STD_ALL_NULL_COLUMN,
    ML_STD_NONFINITE_INPUT,
    ML_STD_RESULT_OUT_OF_RANGE
} MLStandardizeStatus;

/*
 * Internal allocation-free numerical kernel. Arrays are row-major.
 * Preconditions: positive validated dimensions and non-NULL buffers;
 * input/is_null/output have rows*cols elements, means/stddevs have cols.
 * Missing output slots are zero; their original mask is preserved by caller.
 * On error, bad_column receives the zero-based column offset.
 * The optional callback allows the PostgreSQL adapter to handle cancellation.
 */
MLStandardizeStatus ml_pg_standardize_core(
    const double *input, const bool *is_null, size_t rows, size_t cols,
    double *output, double *means, double *stddevs, size_t *bad_column,
    void (*check_interrupts)(void));

#endif
