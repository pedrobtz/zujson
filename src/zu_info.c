#include "zujson.h"

/* Build facts that only the compiled object knows: the vendored yyjson version
 * from the header it was actually compiled against, and the nesting limit.
 *
 * max_depth is reported from ZUJSON_MAX_DEPTH rather than restated in R,
 * because the test suite reads it from here to decide what should and should
 * not be rejected -- a second copy that drifted would make those tests pass
 * while checking the wrong number. */
SEXP zujson_build_info(void) {
    const char *fields[] = {"yyjson", "max_depth", ""};
    SEXP out = PROTECT(Rf_mkNamed(VECSXP, fields));
    SET_VECTOR_ELT(out, 0, Rf_mkString(YYJSON_VERSION_STRING));
    SET_VECTOR_ELT(out, 1, Rf_ScalarInteger(ZUJSON_MAX_DEPTH));
    UNPROTECT(1);
    return out;
}
