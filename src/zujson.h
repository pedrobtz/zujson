#ifndef ZUJSON_H
#define ZUJSON_H

#define R_NO_REMAP
#include <R.h>
#include <Rinternals.h>
#include "yyjson.h"

/* Maximum container nesting accepted or produced, in either direction.
 *
 * yyjson's own reader is iterative, but our tree builders are recursive, so an
 * untrusted body of 100k nested arrays would otherwise walk off the C stack
 * before any R code saw it. 1000 is far beyond what any real API sends and far
 * below what the smallest supported stack survives. */
#define ZUJSON_MAX_DEPTH 1000

/* ---- structured conditions (zu_cond.c) ---- */

/* Signals an R condition of class
 *   c(<class>, "zujson_error", "error", "condition")
 * and does not return. Like Rf_error() it longjmps, so it must not be called
 * while a bare malloc'd pointer is live -- give the pointer to R first (see
 * zu_extptr_own_*). */
void zu_stop(const char *cls, const char *fmt, ...);

/* ---- external pointers owning C memory across a longjmp (zu_cond.c) ---- */

/* Each returns a protected-by-the-caller EXTPTRSXP with a finalizer that frees
 * the payload, so a condition signalled further down cannot leak it. Release
 * eagerly on the success path with zu_extptr_release(). */
SEXP zu_extptr_own_doc(yyjson_doc *doc);
SEXP zu_extptr_own_mut_doc(yyjson_mut_doc *doc);
SEXP zu_extptr_own_buf(void *buf);
void zu_extptr_release(SEXP xp);

/* ---- .Call entry points ---- */
SEXP zujson_parse_str(SEXP x_, SEXP simplify_, SEXP df_);   /* zu_parse.c */
SEXP zujson_parse_raw(SEXP x_, SEXP simplify_, SEXP df_);   /* zu_parse.c */
SEXP zujson_parse_file(SEXP path_, SEXP simplify_, SEXP df_); /* zu_parse.c */
SEXP zujson_validate_str(SEXP x_);                     /* zu_parse.c */
SEXP zujson_validate_raw(SEXP x_);                     /* zu_parse.c */
SEXP zujson_write(SEXP x_, SEXP pretty_,               /* zu_write.c */
                  SEXP auto_unbox_, SEXP as_raw_);
SEXP zujson_parse_ndjson_str(SEXP x_, SEXP simplify_, SEXP df_);
SEXP zujson_parse_ndjson_raw(SEXP x_, SEXP simplify_, SEXP df_);
SEXP zujson_write_lines(SEXP x_, SEXP auto_unbox_);    /* zu_write.c */
SEXP zujson_build_info(void);                          /* zu_info.c  */

#endif /* ZUJSON_H */
