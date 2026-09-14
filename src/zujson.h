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

/* Maximum cells (records x columns) in a data frame built by data_frame=TRUE.
 *
 * The frame is rectangular however ragged the records are, so its size is set
 * by the *union* of the keys, not by how much JSON arrived: 5000 records that
 * share no keys is a 5000 x 5000 frame -- 96 MB -- from 72 kB of body. A cap
 * on the product is the only thing that bounds that, since every other cost
 * here is already bounded by the length of the input -- and no limit upstream
 * can stand in for it, because the blow-up is quadratic in the body: a 1 MB
 * cap still admits ~75k records and so ~5.6e9 cells.
 *
 * 5e7 cells is ~400 MB of doubles: clear of any real tabular response (100k
 * rows x 200 columns is 2e7) and three orders of magnitude below what the
 * pathological body reaches. This is the default; `zujson.max_df_cells`
 * overrides it per session, and the R side is what reads that option. */
#define ZUJSON_MAX_DF_CELLS 50000000

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
