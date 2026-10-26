#include "standardize_core.h"

#include <math.h>

MLStandardizeStatus
ml_pg_standardize_core(
    const double *input, const bool *is_null, size_t rows, size_t cols,
    double *output, double *means, double *stddevs, size_t *bad_column,
    void (*check_interrupts)(void))
{
    size_t col;

    for (col = 0; col < cols; ++col)
    {
        size_t row;
        size_t valid_count = 0;
        long double anchor = 0.0L;
        long double sum = 0.0L;
        long double mean;
        long double squared_sum = 0.0L;
        long double stddev;

        *bad_column = col;
        for (row = 0; row < rows; ++row)
        {
            size_t index = row * cols + col;

            if (check_interrupts != NULL && (row & 1023) == 0)
                check_interrupts();
            if (!is_null[index])
            {
                if (!isfinite(input[index]))
                    return ML_STD_NONFINITE_INPUT;
                if (valid_count == 0)
                    anchor = (long double) input[index];
                sum += (long double) input[index] - anchor;
                ++valid_count;
            }
        }
        if (valid_count == 0)
            return ML_STD_ALL_NULL_COLUMN;

        /* Centering the sum also keeps a constant column exactly constant. */
        mean = anchor + sum / valid_count;
        for (row = 0; row < rows; ++row)
        {
            size_t index = row * cols + col;

            if (check_interrupts != NULL && (row & 1023) == 0)
                check_interrupts();
            if (!is_null[index])
            {
                long double difference = (long double) input[index] - mean;

                squared_sum += difference * difference;
            }
        }
        /* Population standard deviation: divide by n_valid, not n_valid-1. */
        stddev = sqrtl(squared_sum / valid_count);
        means[col] = (double) mean;
        stddevs[col] = (double) stddev;
        if (!isfinite(means[col]) || !isfinite(stddevs[col]) ||
            (stddev != 0.0L && stddevs[col] == 0.0))
            return ML_STD_RESULT_OUT_OF_RANGE;

        for (row = 0; row < rows; ++row)
        {
            size_t index = row * cols + col;

            if (check_interrupts != NULL && (row & 1023) == 0)
                check_interrupts();
            if (is_null[index] || stddev == 0.0L)
                output[index] = 0.0;
            else
                output[index] = (double) (((long double) input[index] - mean) / stddev);
            if (!isfinite(output[index]))
                return ML_STD_RESULT_OUT_OF_RANGE;
        }
    }
    return ML_STD_OK;
}
