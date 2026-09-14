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
 * what an R integer holds. max_xlen is the ceiling the option is clamped to,
 * and is here for the same reason as the others: R_xlen_t is ptrdiff_t on a
 * build with long vectors and int on one without, so R cannot know the number
 * and a literal restated there would be wrong on half the builds. It is
 * internal -- zu_df_cells() clamps with it and zujson_info() drops it, since
 * what a caller wants is the limit in force, not the ceiling it sits under. */
SEXP zujson_build_info(void) {
    const char *fields[] = {"yyjson", "max_depth", "max_df_cells",
                            "max_xlen", ""};
    SEXP out = PROTECT(Rf_mkNamed(VECSXP, fields));
    SET_VECTOR_ELT(out, 0, Rf_mkString(YYJSON_VERSION_STRING));
    SET_VECTOR_ELT(out, 1, Rf_ScalarInteger(ZUJSON_MAX_DEPTH));
    SET_VECTOR_ELT(out, 2, Rf_ScalarReal((double) ZUJSON_MAX_DF_CELLS));
    SET_VECTOR_ELT(out, 3, Rf_ScalarReal((double) R_XLEN_T_MAX));
    UNPROTECT(1);
    return out;
}
