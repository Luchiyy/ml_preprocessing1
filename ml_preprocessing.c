#include "postgres.h"

#include "fmgr.h"
#include "utils/builtins.h"

/* Metadata checked by PostgreSQL when it loads this module. */
PG_MODULE_MAGIC;

/* Register the version-1 C calling convention for this function. */
PG_FUNCTION_INFO_V1(ml_preprocessing_ping);

Datum
ml_preprocessing_ping(PG_FUNCTION_ARGS)
{
    PG_RETURN_TEXT_P(cstring_to_text("C extension works"));
}
