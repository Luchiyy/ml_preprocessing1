#ifndef ML_ONE_HOT_CORE_H
#define ML_ONE_HOT_CORE_H

#include <stdbool.h>
#include <stddef.h>

typedef struct
{
    const char *value;
    size_t row;
} MLOneHotReference;

/*
 * Internal numerical-independent indexing kernel; allocates no memory.
 * Preconditions: count <= INT_MAX; every buffer has at least count slots;
 * a nonmissing values[i] is a valid NUL-terminated string.
 * Returns the number of categories. NULL observations receive index -1.
 * Categories are compared and sorted by their text using strcmp.
 */
size_t ml_pg_one_hot_index(
    const char *const *values, const bool *is_null, size_t count,
    const char **categories, MLOneHotReference *work, int *indexes,
    void (*check_interrupts)(void));

#endif
