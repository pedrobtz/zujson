#include "zujson.h"

/* Build facts that only the compiled object knows: the vendored yyjson version
 * from the header it was actually compiled against, and the nesting limit.
 *
 * max_depth and max_df_cells are reported from the constants rather than
 * restated in R, because the test suite reads them from here to decide what
 * should and should not be rejected -- a second copy that drifted would make
 * those tests pass while checking the wrong number.
 *
 * max_df_cells is a double: the limit is a count of cells, which can exceed
 * what an R integer holds. */
SEXP zujson_build_info(void) {
    const char *fields[] = {"yyjson", "max_depth", "max_df_cells", ""};
    SEXP out = PROTECT(Rf_mkNamed(VECSXP, fields));
    SET_VECTOR_ELT(out, 0, Rf_mkString(YYJSON_VERSION_STRING));
    SET_VECTOR_ELT(out, 1, Rf_ScalarInteger(ZUJSON_MAX_DEPTH));
    SET_VECTOR_ELT(out, 2, Rf_ScalarReal((double) ZUJSON_MAX_DF_CELLS));
    UNPROTECT(1);
    return out;
}
