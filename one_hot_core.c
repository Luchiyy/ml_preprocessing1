#include "one_hot_core.h"

#include <stdlib.h>
#include <string.h>

static int
compare_references(const void *a, const void *b)
{
    const MLOneHotReference *x = a;
    const MLOneHotReference *y = b;

    return strcmp(x->value, y->value);
}

size_t
ml_pg_one_hot_index(
    const char *const *values, const bool *is_null, size_t count,
    const char **categories, MLOneHotReference *work, int *indexes,
    void (*check_interrupts)(void))
{
    size_t valid_count = 0;
    size_t unique_count = 0;
    size_t i;

    for (i = 0; i < count; ++i)
    {
        if (check_interrupts != NULL && (i & 1023) == 0)
            check_interrupts();
        indexes[i] = -1;
        if (!is_null[i])
        {
            work[valid_count].value = values[i];
            work[valid_count].row = i;
            ++valid_count;
        }
    }
    qsort(work, valid_count, sizeof(*work), compare_references);
    for (i = 0; i < valid_count; ++i)
    {
        if (check_interrupts != NULL && (i & 1023) == 0)
            check_interrupts();
        if (unique_count == 0 ||
            strcmp(work[i].value, categories[unique_count - 1]) != 0)
            categories[unique_count++] = work[i].value;
        indexes[work[i].row] = (int) (unique_count - 1);
    }
    return unique_count;
}
