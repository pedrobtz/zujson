#include <math.h>
#include <string.h>
#include <limits.h>
#include "zujson.h"

/* ---------------------------------------------------------------------------
 * R -> JSON
 *
 * See ?json_write for the mapping table. The two rules that carry most of it:
 * a fully named vector or list becomes an object and anything else becomes an
 * array, and a length-1 atomic vector unboxes to a bare scalar unless it is
 * wrapped in I() or auto_unbox is off.
 *
 * The mutable document is owned by an external pointer for the whole build, so
 * zu_stop() and R_CheckUserInterrupt() may be called anywhere below without
 * leaking it.
 * ------------------------------------------------------------------------- */

typedef struct {
    yyjson_mut_doc *doc;
    int auto_unbox;
    unsigned long n_vals;               /* interrupt check counter */
} zu_wctx;

/* yyjson's constructors return NULL only on allocation failure. */
static yyjson_mut_val *zu_ok(yyjson_mut_val *v) {
    if (!v) zu_stop("zujson_write_error", "out of memory building JSON");
    return v;
}

/* Depth counts containers, not values: the root object is level 1 and a string
 * inside it is not a level of its own. Checking where a container is built
 * rather than on entry keeps the limit meaning the same thing in both
 * directions. */
static void zu_check_depth(int depth) {
    if (depth > ZUJSON_MAX_DEPTH)
        zu_stop("zujson_depth_error",
                "R object nests deeper than %d levels", ZUJSON_MAX_DEPTH);
}

static void zu_tick(zu_wctx *ctx) {
    if ((++ctx->n_vals & 0xFFFFu) == 0) R_CheckUserInterrupt();
}

/* ---- scalars ------------------------------------------------------------- */

/* Every flavour of missing becomes null: JSON has no NA, and null is the only
 * thing a receiving API can be expected to understand. Non-finite doubles go
 * the same way -- NaN and Infinity are not JSON. */
static yyjson_mut_val *zu_w_lgl(zu_wctx *ctx, int v) {
    return zu_ok(v == NA_LOGICAL ? yyjson_mut_null(ctx->doc)
                                 : yyjson_mut_bool(ctx->doc, v != 0));
}

static yyjson_mut_val *zu_w_int(zu_wctx *ctx, int v) {
    return zu_ok(v == NA_INTEGER ? yyjson_mut_null(ctx->doc)
                                 : yyjson_mut_sint(ctx->doc, (int64_t) v));
}

/* Whole doubles are written without a decimal point. R has no integer literal
 * -- `1` is a double -- and yyjson's real writer would emit `1.0`, which a
 * schema expecting an integer will reject.
 *
 * The bound is int64's range, not 2^53. A double that is already a whole
 * number *is* exactly that integer, whatever its magnitude, so converting is
 * lossless; 2^53 is where consecutive integers stop being representable, which
 * is a different question and the wrong test here. Written as `>= min` and
 * `< max` because 2^63 itself is not representable as an int64. */
#define ZU_DBL_INT_MIN (-9223372036854775808.0)   /* -2^63, exact          */
#define ZU_DBL_INT_MAX 9223372036854775808.0      /*  2^63, exclusive      */

static yyjson_mut_val *zu_w_dbl(zu_wctx *ctx, double v) {
    if (!R_FINITE(v)) return zu_ok(yyjson_mut_null(ctx->doc));
    if (v == floor(v) && v >= ZU_DBL_INT_MIN && v < ZU_DBL_INT_MAX)
        return zu_ok(yyjson_mut_sint(ctx->doc, (int64_t) v));
    return zu_ok(yyjson_mut_real(ctx->doc, v));
}

/* A name being quoted back inside an error message, where throwing a second
 * condition on the way out of the first would lose the real one. */
static const char *zu_char_msg(SEXP s) {
    return Rf_getCharCE(s) == CE_BYTES ? "<bytes>" : Rf_translateCharUTF8(s);
}

/* translateCharUTF8 is a no-op for UTF-8 and ASCII, and converts otherwise.
 * When it does convert it allocates on the R_alloc stack, so the vmax pair
 * keeps a long character vector from accumulating one buffer per element.
 *
 * "bytes" is refused before it gets there: it means R does not know the
 * encoding, and translateCharUTF8() answers that with a bare simpleError
 * raised inside R, which would escape the zujson_error contract. This is the
 * only place a string's bytes are read on the way out, the way zu_mkchar() is
 * the only place one is made on the way in, so the two cannot drift. */
static yyjson_mut_val *zu_w_str(zu_wctx *ctx, SEXP s) {
    if (s == NA_STRING) return zu_ok(yyjson_mut_null(ctx->doc));
    if (Rf_getCharCE(s) == CE_BYTES)
        zu_stop("zujson_write_error",
                "a string is marked \"bytes\", an unknown encoding that "
                "cannot be converted to the UTF-8 JSON requires");
    const void *vmax = vmaxget();
    const char *u = Rf_translateCharUTF8(s);
    yyjson_mut_val *v = yyjson_mut_strncpy(ctx->doc, u, strlen(u));
    vmaxset(vmax);
    return zu_ok(v);
}

static yyjson_mut_val *zu_w_text(zu_wctx *ctx, const char *s, size_t n) {
    return zu_ok(yyjson_mut_strncpy(ctx->doc, s, n));
}

/* ---- dates and times ----------------------------------------------------- */

/* Howard Hinnant's civil_from_days: days since 1970-01-01 to a proleptic
 * Gregorian date, with no locale, no time zone database and no libc calendar
 * call -- which is what makes the output identical on every platform. */
static void zu_civil(int64_t z, int *yy, int *mm, int *dd) {
    z += 719468;
    int64_t era = (z >= 0 ? z : z - 146096) / 146097;
    unsigned doe = (unsigned) (z - era * 146097);
    unsigned yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365;
    int64_t y = (int64_t) yoe + era * 400;
    unsigned doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    unsigned mp = (5 * doy + 2) / 153;
    unsigned d = doy - (153 * mp + 2) / 5 + 1;
    unsigned m = mp < 10 ? mp + 3 : mp - 9;
    *yy = (int) (y + (m <= 2));
    *mm = (int) m;
    *dd = (int) d;
}

/* The days-from-epoch either side of the four-digit years ISO 8601 writes:
 * 0000-01-01 and 9999-12-31. R's Date and POSIXct are doubles and hold far
 * more than that, and a value past the range is two separate problems --
 * converting it to int64_t at all is undefined behaviour once it is outside
 * that type, and even where it is not, the year overruns "%04d" and the
 * seconds-of-day arithmetic loses enough precision to print fields like
 * "T-596523:-14:-8". Neither is a timestamp any API can read, so it is a write
 * error rather than an approximation. */
#define ZU_DAY_MIN (-719528.0)
#define ZU_DAY_MAX ( 2932896.0)

static void zu_check_day(double days, const char *what) {
    if (!(days >= ZU_DAY_MIN && days <= ZU_DAY_MAX))
        zu_stop("zujson_write_error",
                "a %s of %.17g days from 1970-01-01 is outside the "
                "0000-01-01 to 9999-12-31 range ISO 8601 can write", what,
                days);
}

static yyjson_mut_val *zu_w_date(zu_wctx *ctx, double days) {
    if (!R_FINITE(days)) return zu_ok(yyjson_mut_null(ctx->doc));
    days = floor(days);
    zu_check_day(days, "Date");
    int y, m, d;
    zu_civil((int64_t) days, &y, &m, &d);
    char buf[32];
    int n = snprintf(buf, sizeof(buf), "%04d-%02d-%02d", y, m, d);
    return zu_w_text(ctx, buf, (size_t) n);
}

/* POSIXct is an instant, so it is always written as UTC regardless of the
 * tzone attribute -- the same moment, in the one form every API accepts.
 * Sub-second parts are dropped; RFC 3339 to the second is what HTTP APIs use. */
static yyjson_mut_val *zu_w_time(zu_wctx *ctx, double secs) {
    if (!R_FINITE(secs)) return zu_ok(yyjson_mut_null(ctx->doc));
    /* Floor to whole seconds *before* splitting off the days. Splitting the
     * raw value first lets `secs - fdays * 86400` round to exactly 86400 for
     * an instant a hair below midnight, which printed hour 24 (#41). Once
     * `whole` is an integer every step below is exact: it is under 2^53 in
     * magnitude for any day that passes the range check. */
    double whole = floor(secs);
    double fdays = floor(whole / 86400.0);
    zu_check_day(fdays, "POSIXct");
    int rem = (int) (whole - fdays * 86400.0);
    int y, m, d;
    zu_civil((int64_t) fdays, &y, &m, &d);
    char buf[48];
    int n = snprintf(buf, sizeof(buf), "%04d-%02d-%02dT%02d:%02d:%02dZ",
                     y, m, d, rem / 3600, (rem / 60) % 60, rem % 60);
    return zu_w_text(ctx, buf, (size_t) n);
}

/* ---- vector element kinds ------------------------------------------------ */

typedef enum {
    ZU_A_LGL, ZU_A_INT, ZU_A_DBL, ZU_A_STR,
    ZU_A_FACTOR, ZU_A_DATE, ZU_A_TIME, ZU_A_I64,
    ZU_A_LIST, ZU_A_NONE
} zu_atom;

/* POSIXlt is a list of 11 broken-down time fields, so without this it would
 * serialize as {"sec":...,"min":...,"gmtoff":...} -- valid JSON, and never
 * what anyone meant by sending a timestamp. It is called from every place a
 * value enters the writer: the dispatcher, each data frame column, and the
 * NDJSON top level. A POSIXlt reaching a data frame column or NDJSON without
 * passing through here was written field by field (#40). */
static void zu_refuse_posixlt(SEXP x) {
    if (Rf_inherits(x, "POSIXlt"))
        zu_stop("zujson_unsupported_type",
                "cannot serialize a POSIXlt; convert it with as.POSIXct() first");
}

static int zu_all_na_lgl(SEXP x) {
    R_xlen_t n = XLENGTH(x);
    const int *p = LOGICAL_RO(x);
    for (R_xlen_t i = 0; i < n; i++)
        if (p[i] != NA_LOGICAL) return 0;
    return 1;
}

/* A Date or POSIXct is a number of days or seconds, so only numeric storage
 * carries one. An all-NA logical is how R spells a missing date
 * (`structure(NA, class = "Date")`), and it is written as the nulls it holds.
 * Anything else reached REAL() unchecked and raised a bare error (#43). */
static zu_atom zu_time_kind(SEXP x, zu_atom kind, const char *what) {
    switch (TYPEOF(x)) {
    case REALSXP:
    case INTSXP:
        return kind;
    case LGLSXP:
        if (zu_all_na_lgl(x)) return ZU_A_LGL;
        /* fall through */
    default:
        zu_stop("zujson_unsupported_type",
                "cannot serialize a %s stored as '%s'; only a numeric %s "
                "carries a value", what, Rf_type2char((SEXPTYPE) TYPEOF(x)),
                what);
        return ZU_A_NONE;                /* not reached */
    }
}

/* Classed vectors are recognised by class first, so a Date is a date rather
 * than the number of days it is stored as. The class decides the kind only
 * when the storage type agrees with it; a mismatch is refused rather than
 * handed to an accessor that would raise a bare error (#43). An unrecognised
 * class falls through to the underlying type, which is permissive by design:
 * a new class should not be a hard failure. */
static zu_atom zu_atom_kind(SEXP x, SEXP *levels) {
    *levels = R_NilValue;
    if (Rf_isFactor(x)) {
        SEXP lv = Rf_getAttrib(x, R_LevelsSymbol);
        if (lv != R_NilValue && TYPEOF(lv) != STRSXP)
            zu_stop("zujson_unsupported_type",
                    "cannot serialize a factor whose levels are '%s', not "
                    "character", Rf_type2char((SEXPTYPE) TYPEOF(lv)));
        *levels = lv;
        return ZU_A_FACTOR;
    }
    /* bit64 keeps each int64 in the bits of a double. Falling through to the
     * double wrote those bits as denormals -- 1 as 5e-324 -- which is the case
     * §6 calls indefensible: the underlying type does not carry the value
     * (#48). Recognised by class name alone, so bit64 is not a dependency. */
    if (Rf_inherits(x, "integer64")) {
        if (TYPEOF(x) != REALSXP)
            zu_stop("zujson_unsupported_type",
                    "cannot serialize an integer64 stored as '%s'",
                    Rf_type2char((SEXPTYPE) TYPEOF(x)));
        return ZU_A_I64;
    }
    if (Rf_inherits(x, "Date"))    return zu_time_kind(x, ZU_A_DATE, "Date");
    if (Rf_inherits(x, "POSIXct")) return zu_time_kind(x, ZU_A_TIME, "POSIXct");
    switch (TYPEOF(x)) {
    case LGLSXP:  return ZU_A_LGL;
    case INTSXP:  return ZU_A_INT;
    case REALSXP: return ZU_A_DBL;
    case STRSXP:  return ZU_A_STR;
    case VECSXP:  return ZU_A_LIST;
    default:      return ZU_A_NONE;
    }
}

static double zu_num_elt(SEXP x, R_xlen_t i) {
    if (TYPEOF(x) == INTSXP)
        return INTEGER(x)[i] == NA_INTEGER ? NA_REAL : (double) INTEGER(x)[i];
    return REAL(x)[i];
}

static yyjson_mut_val *zu_from_sexp(SEXP x, zu_wctx *ctx, int depth);

/* One element of an atomic (or classed atomic) vector. */
static yyjson_mut_val *zu_w_elt(SEXP x, zu_atom kind, SEXP levels,
                                R_xlen_t i, zu_wctx *ctx, int depth) {
    switch (kind) {
    case ZU_A_LGL: return zu_w_lgl(ctx, LOGICAL(x)[i]);
    case ZU_A_INT: return zu_w_int(ctx, INTEGER(x)[i]);
    case ZU_A_DBL: return zu_w_dbl(ctx, REAL(x)[i]);
    case ZU_A_STR: return zu_w_str(ctx, STRING_ELT(x, i));
    case ZU_A_FACTOR: {
        int code = INTEGER(x)[i];
        if (code == NA_INTEGER || code < 1 || code > Rf_length(levels))
            return zu_ok(yyjson_mut_null(ctx->doc));
        return zu_w_str(ctx, STRING_ELT(levels, code - 1));
    }
    case ZU_A_DATE: return zu_w_date(ctx, zu_num_elt(x, i));
    case ZU_A_TIME: return zu_w_time(ctx, zu_num_elt(x, i));
    case ZU_A_I64: {
        int64_t v;
        memcpy(&v, &REAL(x)[i], sizeof v);   /* the bits, not the double */
        if (v == INT64_MIN) return zu_ok(yyjson_mut_null(ctx->doc));
        return zu_ok(yyjson_mut_sint(ctx->doc, v));
    }
    case ZU_A_LIST: return zu_from_sexp(VECTOR_ELT(x, i), ctx, depth + 1);
    default:
        zu_stop("zujson_unsupported_type",
                "cannot serialize an R object of type '%s'",
                Rf_type2char((SEXPTYPE) TYPEOF(x)));
        return NULL;                     /* not reached */
    }
}

/* ---- names --------------------------------------------------------------- */

/* Names are honoured only when every one of them is usable as a JSON key.
 * Partial names would otherwise produce {"a":1,"":2}, which is valid JSON and
 * almost never what the caller meant, so those become an array instead. */
static int zu_fully_named(SEXP nms, R_xlen_t n) {
    if (nms == R_NilValue || TYPEOF(nms) != STRSXP || XLENGTH(nms) != n)
        return 0;
    for (R_xlen_t i = 0; i < n; i++) {
        SEXP s = STRING_ELT(nms, i);
        if (s == NA_STRING || XLENGTH(s) == 0) return 0;
    }
    return 1;
}

static void zu_obj_add(yyjson_mut_val *obj, SEXP nms, R_xlen_t i,
                       yyjson_mut_val *val, zu_wctx *ctx) {
    yyjson_mut_val *key = zu_w_str(ctx, STRING_ELT(nms, i));
    /* Silently dropping a key/value pair would be the worst possible failure
     * mode for a request body, so the one way this can fail is checked even
     * though zu_fully_named() should already have made it impossible. */
    if (!yyjson_mut_obj_add(obj, key, val))
        zu_stop("zujson_write_error", "could not add key '%s' to a JSON object",
                zu_char_msg(STRING_ELT(nms, i)));
}

/* ---- data frames --------------------------------------------------------- */

/* A data frame is planned once and then emitted row by row. The plan exists
 * because NDJSON needs the same rows as separate documents rather than as one
 * array, and resolving each column's kind per cell would be wasteful in both
 * callers. */
typedef struct {
    R_xlen_t ncol, nrow;
    SEXP nms;                  /* column names, validated non-empty          */
    zu_atom *kinds;            /* one per column, R_alloc'd                  */
    SEXP levels;               /* VECSXP: factor levels per column, or NULL  */
} zu_df_plan;

/* Everything in the plan that the GC could reclaim lives in one VECSXP that
 * the caller allocates, PROTECTs and hands in: the names attribute and the
 * per-column levels. Both are reachable from `df` and so were already safe,
 * but neither that nor the protection itself could be checked where it was
 * written. A PROTECT here matched by an UNPROTECT in the caller is a balance
 * no per-function analysis can verify -- rchk read it as unprotecting more
 * than was protected in both callers -- and reachability through an attribute
 * is not something it can see at all.
 *
 * The keeper costs one stack slot and makes both local. Each value is stored
 * into it on the line after it is obtained, with nothing allocating in
 * between, so the window the old comment worried about is closed at the point
 * it opens rather than by an argument about what the loop does today. */
#define ZU_DF_KEEP_NMS    0
#define ZU_DF_KEEP_LEVELS 1
#define ZU_DF_KEEP_N      2

static void zu_df_plan_init(SEXP df, zu_df_plan *plan, SEXP keep) {
    /* The class says data frame; the structure has to agree before anything
     * reads it, or XLENGTH()/VECTOR_ELT() raise bare errors (#43). */
    if (TYPEOF(df) != VECSXP)
        zu_stop("zujson_unsupported_type",
                "cannot serialize a data frame stored as '%s', not a list of "
                "columns", Rf_type2char((SEXPTYPE) TYPEOF(df)));
    R_xlen_t ncol = XLENGTH(df);
    SEXP nms = Rf_getAttrib(df, R_NamesSymbol);
    SET_VECTOR_ELT(keep, ZU_DF_KEEP_NMS, nms);
    if (!zu_fully_named(nms, ncol))
        zu_stop("zujson_unsupported_type",
                "data frame columns must all be named");

    for (R_xlen_t j = 0; j < ncol; j++) {
        SEXP col = VECTOR_ELT(df, j);
        if (!Rf_isVector(col))
            zu_stop("zujson_unsupported_type",
                    "column '%s' is a '%s', not a vector",
                    zu_char_msg(STRING_ELT(nms, j)),
                    Rf_type2char((SEXPTYPE) TYPEOF(col)));
    }

    /* With no columns there is no column to measure, but the rows still exist:
     * df[, 0] is n rows of nothing, which is n empty objects. A hand-built
     * frame with no row.names at all has none. */
    SEXP rn = Rf_getAttrib(df, R_RowNamesSymbol);
    R_xlen_t nrow = ncol > 0 ? XLENGTH(VECTOR_ELT(df, 0))
                             : (rn == R_NilValue ? 0 : XLENGTH(rn));

    zu_atom *kinds = (zu_atom *) R_alloc((size_t) (ncol > 0 ? ncol : 1),
                                         sizeof(zu_atom));
    SEXP levels = Rf_allocVector(VECSXP, ncol);
    SET_VECTOR_ELT(keep, ZU_DF_KEEP_LEVELS, levels);
    plan->levels = levels;

    for (R_xlen_t j = 0; j < ncol; j++) {
        SEXP col = VECTOR_ELT(df, j);
        zu_refuse_posixlt(col);
        if (Rf_inherits(col, "data.frame"))
            zu_stop("zujson_unsupported_type",
                    "column '%s' is itself a data frame, which is not supported",
                    zu_char_msg(STRING_ELT(nms, j)));
        if (XLENGTH(col) != nrow)
            zu_stop("zujson_unsupported_type",
                    "column '%s' has %ld rows, expected %ld",
                    zu_char_msg(STRING_ELT(nms, j)),
                    (long) XLENGTH(col), (long) nrow);
        SEXP lv;
        kinds[j] = zu_atom_kind(col, &lv);
        SET_VECTOR_ELT(levels, j, lv);
    }
    plan->ncol = ncol;
    plan->nrow = nrow;
    plan->nms = nms;
    plan->kinds = kinds;
}

/* One row as a JSON object. `depth` is the level of the object itself. */
static yyjson_mut_val *zu_df_row(SEXP df, const zu_df_plan *plan, R_xlen_t i,
                                 zu_wctx *ctx, int depth) {
    yyjson_mut_val *row = zu_ok(yyjson_mut_obj(ctx->doc));
    for (R_xlen_t j = 0; j < plan->ncol; j++) {
        /* `depth`, not depth + 1: a cell is charged the way an object member
         * is everywhere else, by handing zu_w_elt() the level of the object
         * holding it. zu_w_elt() adds the level itself, and only for a cell
         * that is a container. Adding one here too charged a list column
         * twice, which rejected a frame whose JSON was exactly at the limit. */
        yyjson_mut_val *v = zu_w_elt(VECTOR_ELT(df, j), plan->kinds[j],
                                     VECTOR_ELT(plan->levels, j),
                                     i, ctx, depth);
        zu_obj_add(row, plan->nms, j, v, ctx);
    }
    return row;
}

/* Row oriented, because that is what an HTTP API means by a table. */
static yyjson_mut_val *zu_w_df(SEXP df, zu_wctx *ctx, int depth) {
    zu_df_plan plan;
    SEXP keep = PROTECT(Rf_allocVector(VECSXP, ZU_DF_KEEP_N));
    zu_df_plan_init(df, &plan, keep);

    /* A data frame is the one value that emits *two* container levels at once:
     * the array of rows at `depth`, and each row object at `depth + 1`. Both
     * have to be charged, or json_write() can emit JSON that json_parse()
     * then rejects as too deep. A frame with no rows emits only the array, so
     * it is charged only that one: charging it two refused `[]` at a depth
     * json_parse() reads (#57). */
    zu_check_depth(plan.nrow > 0 ? depth + 1 : depth);

    yyjson_mut_val *arr = zu_ok(yyjson_mut_arr(ctx->doc));
    for (R_xlen_t i = 0; i < plan.nrow; i++) {
        yyjson_mut_arr_add_val(arr, zu_df_row(df, &plan, i, ctx, depth + 1));
        zu_tick(ctx);
    }
    UNPROTECT(1);
    return arr;
}


/* ---- the dispatcher ------------------------------------------------------ */

static yyjson_mut_val *zu_from_sexp(SEXP x, zu_wctx *ctx, int depth) {
    zu_tick(ctx);

    if (x == R_NilValue) return zu_ok(yyjson_mut_null(ctx->doc));

    /* I() marks a length-1 vector that must stay an array. It is checked
     * before the class dispatch because I() prepends to the class vector. */
    int as_is = Rf_inherits(x, "AsIs");

    zu_refuse_posixlt(x);

    if (Rf_inherits(x, "data.frame")) return zu_w_df(x, ctx, depth);

    SEXP levels;
    zu_atom kind = zu_atom_kind(x, &levels);
    if (kind == ZU_A_NONE)
        zu_stop("zujson_unsupported_type",
                "cannot serialize an R object of type '%s'",
                Rf_type2char((SEXPTYPE) TYPEOF(x)));

    /* Both are attributes of `x`, so both were already safe -- and, as with
     * the plan's keeper above, safe by an argument no checker can follow. On
     * the stack they are safe by inspection. Two slots per level against a
     * depth capped at ZUJSON_MAX_DEPTH is at most 2000, against a protect
     * stack of 50000. */
    PROTECT(levels);
    R_xlen_t n = XLENGTH(x);
    SEXP nms = PROTECT(Rf_getAttrib(x, R_NamesSymbol));

    /* An empty list with a names attribute is the only empty container that
     * writes as {} -- that is what makes json_parse("{}") round-trip. */
    int named = (kind == ZU_A_LIST)
        ? (nms != R_NilValue && zu_fully_named(nms, n))
        : (n > 0 && zu_fully_named(nms, n));

    if (named) {
        zu_check_depth(depth);
        yyjson_mut_val *obj = zu_ok(yyjson_mut_obj(ctx->doc));
        for (R_xlen_t i = 0; i < n; i++) {
            zu_obj_add(obj, nms, i,
                       zu_w_elt(x, kind, levels, i, ctx, depth), ctx);
            zu_tick(ctx);
        }
        UNPROTECT(2);
        return obj;
    }

    if (ctx->auto_unbox && !as_is && n == 1 && kind != ZU_A_LIST) {
        /* After the call, not before: it reads `levels` and can allocate. */
        yyjson_mut_val *val = zu_w_elt(x, kind, levels, 0, ctx, depth);
        UNPROTECT(2);
        return val;
    }

    zu_check_depth(depth);
    yyjson_mut_val *arr = zu_ok(yyjson_mut_arr(ctx->doc));
    for (R_xlen_t i = 0; i < n; i++) {
        yyjson_mut_arr_add_val(arr, zu_w_elt(x, kind, levels, i, ctx, depth));
        zu_tick(ctx);
    }
    UNPROTECT(2);
    return arr;
}

/* ---- entry point --------------------------------------------------------- */

SEXP zujson_write(SEXP x_, SEXP pretty_, SEXP auto_unbox_, SEXP as_raw_) {
    int pretty = Rf_asLogical(pretty_);
    int as_raw = Rf_asLogical(as_raw_);

    SEXP owner = PROTECT(zu_owner_mut_doc());
    yyjson_mut_doc *doc = yyjson_mut_doc_new(NULL);
    if (!doc)
        zu_stop("zujson_write_error",
                "out of memory allocating a JSON document");
    zu_owner_hold(owner, doc);

    zu_wctx ctx = { doc, Rf_asLogical(auto_unbox_), 0 };
    yyjson_mut_doc_set_root(doc, zu_from_sexp(x_, &ctx, 1));

    size_t len = 0;
    yyjson_write_err werr;
    yyjson_write_flag flg = pretty ? YYJSON_WRITE_PRETTY_TWO_SPACES
                                   : YYJSON_WRITE_NOFLAG;
    /* The buffer is malloc'd by yyjson and the allocations below can
     * longjmp, so its owner exists before it does. */
    SEXP buf_owner = PROTECT(zu_owner_buf());
    char *buf = yyjson_mut_write_opts(doc, flg, NULL, &len, &werr);
    if (!buf)                            /* the owners' finalizers free the doc */
        zu_stop("zujson_write_error", "could not write JSON: %s", werr.msg);
    zu_owner_hold(buf_owner, buf);
    SEXP out;
    if (as_raw) {
        out = PROTECT(Rf_allocVector(RAWSXP, (R_xlen_t) len));
        memcpy(RAW(out), buf, len);
    } else {
        if (len > (size_t) INT_MAX)
            zu_stop("zujson_write_error",
                    "JSON is %lu bytes, too long for a single R string; "
                    "use json_write_raw()", (unsigned long) len);
        out = PROTECT(Rf_allocVector(STRSXP, 1));
        SET_STRING_ELT(out, 0, Rf_mkCharLenCE(buf, (int) len, CE_UTF8));
    }

    zu_extptr_release(buf_owner);
    zu_extptr_release(owner);
    UNPROTECT(3);
    return out;
}

/* ---------------------------------------------------------------------------
 * NDJSON
 *
 * One line per record, so each record gets its own document and its own write.
 * The lines are joined here, into the one value the caller gets: a string, or
 * with `as_raw` bytes built directly. Joining in R with paste() raised R's own
 * bare error past 2^31 - 1 bytes, and the raw variant was built from that
 * string, so it could never exceed one either (#47).
 *
 * There is deliberately no `pretty` here. Indented JSON contains newlines, and
 * a newline inside a record is precisely what NDJSON framing cannot survive --
 * a pretty-printed NDJSON stream is a corrupt one, not a nicer one.
 * ------------------------------------------------------------------------- */
SEXP zujson_write_lines(SEXP x_, SEXP auto_unbox_, SEXP as_raw_) {
    int auto_unbox = Rf_asLogical(auto_unbox_);
    int as_raw = Rf_asLogical(as_raw_);
    /* A POSIXlt is a list, so without this each of its 11 fields became a
     * record (#40). */
    zu_refuse_posixlt(x_);
    int is_df = Rf_inherits(x_, "data.frame");

    zu_df_plan plan;
    R_xlen_t n;

    /* Protected in both branches, not just the data frame one, so the count at
     * the end no longer depends on which was taken -- the PROTECT(R_NilValue)
     * that used to stand in for the plan on the list branch is gone with it. */
    SEXP keep = PROTECT(Rf_allocVector(VECSXP, ZU_DF_KEEP_N));
    if (is_df) {
        zu_df_plan_init(x_, &plan, keep);
        n = plan.nrow;
    } else {
        if (TYPEOF(x_) != VECSXP)
            zu_stop("zujson_unsupported_type",
                    "NDJSON needs a list of records or a data frame, not '%s'",
                    Rf_type2char((SEXPTYPE) TYPEOF(x_)));
        n = XLENGTH(x_);
    }

    SEXP lines = PROTECT(Rf_allocVector(STRSXP, n));
    size_t total = 0;

    for (R_xlen_t i = 0; i < n; i++) {
        SEXP owner = PROTECT(zu_owner_mut_doc());
        yyjson_mut_doc *doc = yyjson_mut_doc_new(NULL);
        if (!doc)
            zu_stop("zujson_write_error",
                    "out of memory allocating a JSON document");
        zu_owner_hold(owner, doc);

        zu_wctx ctx = { doc, auto_unbox, 0 };
        yyjson_mut_doc_set_root(doc, is_df
            ? zu_df_row(x_, &plan, i, &ctx, 1)
            : zu_from_sexp(VECTOR_ELT(x_, i), &ctx, 1));

        size_t len = 0;
        yyjson_write_err werr;
        SEXP buf_owner = PROTECT(zu_owner_buf());
        char *buf = yyjson_mut_write_opts(doc, YYJSON_WRITE_NOFLAG, NULL,
                                          &len, &werr);
        if (!buf)
            zu_stop("zujson_write_error",
                    "could not write NDJSON record %ld: %s",
                    (long) (i + 1), werr.msg);
        zu_owner_hold(buf_owner, buf);

        if (len > (size_t) INT_MAX)
            zu_stop("zujson_write_error",
                    "NDJSON record %ld is %lu bytes, too long for an R string",
                    (long) (i + 1), (unsigned long) len);
        SET_STRING_ELT(lines, i, Rf_mkCharLenCE(buf, (int) len, CE_UTF8));
        total += len + 1;                /* the record and its newline */

        zu_extptr_release(buf_owner);
        zu_extptr_release(owner);
        UNPROTECT(2);

        if ((i & 0x3FF) == 0) R_CheckUserInterrupt();
    }

    /* One copy into the result. A string is one CHARSXP, so it is refused past
     * INT_MAX bytes with the class the contract promises; bytes have no such
     * ceiling, which is why the error points there. */
    SEXP out;
    char *dst;
    if (as_raw) {
        out = PROTECT(Rf_allocVector(RAWSXP, (R_xlen_t) total));
        dst = (char *) RAW(out);
    } else {
        if (total > (size_t) INT_MAX)
            zu_stop("zujson_write_error",
                    "the NDJSON body is %lu bytes, too long for a single R "
                    "string; use json_write_ndjson_raw()",
                    (unsigned long) total);
        out = PROTECT(Rf_allocVector(STRSXP, 1));
        dst = R_alloc(total > 0 ? total : 1, 1);
    }
    size_t at = 0;
    for (R_xlen_t i = 0; i < n; i++) {
        SEXP line = STRING_ELT(lines, i);
        size_t len = (size_t) LENGTH(line);
        memcpy(dst + at, CHAR(line), len);
        dst[at + len] = '\n';
        at += len + 1;
    }
    if (!as_raw)
        SET_STRING_ELT(out, 0, Rf_mkCharLenCE(dst, (int) total, CE_UTF8));

    UNPROTECT(3);   /* out, lines, and the plan's keeper */
    return out;
}
