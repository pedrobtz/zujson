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
 * 5e7 cells is ~400 MB of doubles, and the frame is not the whole peak: the
 * scatter pass in zu_arr_df() holds an n_rows x n_keys matrix of pointers for
 * the length of the build, whatever the sparsity, so the same order again --
 * ~800 MB together on a 64-bit build. That is still clear of any real tabular
 * response (100k rows x 200 columns is 2e7) and three orders of magnitude
 * below what the pathological body reaches. This is the default;
 * `zujson.max_df_cells` overrides it per session, and the R side is what reads
 * that option. */
#define ZUJSON_MAX_DF_CELLS 50000000

/* ---- structured conditions (zu_cond.c) ---- */

/* Signals an R condition of class
 *   c(<class>, "zujson_error", "error", "condition")
 * and does not return. Like Rf_error() it longjmps, so it must not be called
 * while a bare malloc'd pointer is live -- give the pointer to R first (see
 * zu_owner_*). */
void zu_stop(const char *cls, const char *fmt, ...);

/* The NDJSON line a record is being built from, or 0. While it is set,
 * zu_stop() prefixes "line N: " to its message, so an error raised deep in the
 * tree builder names the line the way a reader error does. zu_stop() clears
 * it; every .Call entry point that can raise clears it too, so a longjmp that
 * did not pass through zu_stop() cannot leave it behind for the next call. */
extern unsigned long zu_err_line;
/* What zu_err_line counts: "line" for the NDJSON reader, "record" for the
 * NDJSON writer, which sets it while each record is built (#70). */
extern const char *zu_err_what;

/* The longest prefix of `s` (of `len` bytes) no longer than `max` bytes that
 * does not end inside a UTF-8 sequence: for quoting a key into a message. */
size_t zu_utf8_cut(const char *s, size_t len, size_t max);

/* A string's bytes as UTF-8, or NULL when they are not valid in the encoding
 * the string declares. Rf_translateCharUTF8() never fails: it writes "<xx>"
 * for a byte it cannot convert, which turned an unmarked "café" under the C
 * locale into the ASCII text "caf<c3><a9>" in both directions (#42). Callers
 * raise their own classed error on NULL. May allocate on the R_alloc stack, so
 * wrap a loop in vmaxget()/vmaxset(); never call it on NA or CE_BYTES. */
const char *zu_utf8(SEXP s);

/* A name for quoting into a condition message: always valid UTF-8, with any
 * byte that is not shown as <xx>. zu_stop() marks every message UTF-8, so a
 * name passed through unvalidated made a message marked UTF-8 that was not
 * (#76). Allocates on the R_alloc stack; never fails. */
const char *zu_msg_str(SEXP s);

/* ---- external pointers owning C memory across a longjmp (zu_cond.c) ---- */

/* Each returns an empty EXTPTRSXP, for the caller to protect, with a finalizer
 * that frees whatever it comes to hold, so a condition signalled further down
 * cannot leak it. Make the owner first, then allocate the resource, then
 * zu_owner_hold() it on the very next line: zu_owner_hold() allocates nothing,
 * so the resource is never bare across anything that can longjmp (#52).
 * Release eagerly on the success path with zu_extptr_release(). */
SEXP zu_owner_doc(void);
SEXP zu_owner_mut_doc(void);
SEXP zu_owner_buf(void);
void zu_owner_hold(SEXP xp, void *p);
void zu_extptr_release(SEXP xp);

/* ---- .Call entry points ---- */
SEXP zujson_parse_str(SEXP x_, SEXP simplify_, SEXP df_);   /* zu_parse.c */
SEXP zujson_parse_raw(SEXP x_, SEXP simplify_, SEXP df_);   /* zu_parse.c */
SEXP zujson_validate_str(SEXP x_);                     /* zu_parse.c */
SEXP zujson_validate_raw(SEXP x_);                     /* zu_parse.c */
SEXP zujson_write(SEXP x_, SEXP pretty_,               /* zu_write.c */
                  SEXP auto_unbox_, SEXP as_raw_);
SEXP zujson_parse_ndjson_str(SEXP x_, SEXP simplify_, SEXP df_);
SEXP zujson_parse_ndjson_raw(SEXP x_, SEXP simplify_, SEXP df_);
SEXP zujson_write_lines(SEXP x_, SEXP auto_unbox_,     /* zu_write.c */
                        SEXP as_raw_);
SEXP zujson_build_info(void);                          /* zu_info.c  */

#endif /* ZUJSON_H */
