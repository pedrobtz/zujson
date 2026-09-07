#include "zujson.h"
#include <R_ext/Rdynload.h>

static const R_CallMethodDef CallEntries[] = {
    {"zujson_parse_str",      (DL_FUNC) &zujson_parse_str,      2},
    {"zujson_parse_raw",      (DL_FUNC) &zujson_parse_raw,      2},
    {"zujson_parse_file",     (DL_FUNC) &zujson_parse_file,     2},
    {"zujson_validate_str",   (DL_FUNC) &zujson_validate_str,   1},
    {"zujson_validate_raw",   (DL_FUNC) &zujson_validate_raw,   1},
    {"zujson_write",          (DL_FUNC) &zujson_write,          4},
    {"zujson_yyjson_version", (DL_FUNC) &zujson_yyjson_version, 0},
    {NULL, NULL, 0}
};

void R_init_zujson(DllInfo *dll) {
    R_registerRoutines(dll, NULL, CallEntries, NULL, NULL);
    R_useDynamicSymbols(dll, FALSE);
}
