#include "zujson.h"

/* The vendored yyjson version, read from the header the package was actually
 * compiled against. tools/vendor-yyjson.R and the test suite both assert on
 * it, so a silent upstream bump cannot go unnoticed. */
SEXP zujson_yyjson_version(void) {
    return Rf_mkString(YYJSON_VERSION_STRING);
}
