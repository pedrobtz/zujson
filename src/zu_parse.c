#include <limits.h>
#include <string.h>
#include "zujson.h"

/* ---------------------------------------------------------------------------
 * JSON -> R
 *
 * Objects always become named lists. Arrays become an atomic vector when every
 * element agrees on a type, and a list otherwise; see the lattice below and
 * ?json_parse for the full table.
 * ------------------------------------------------------------------------- */

/* Array element kinds, ordered so that the numeric family promotes by taking
 * the maximum: null < logical < integer < double. Strings are a separate kind
 * that only tolerates nulls, and anything else falls back to a list. */
typedef enum {
    ZU_K_NULL = 0,
    ZU_K_LGL  = 1,
    ZU_K_INT  = 2,
    ZU_K_DBL  = 3,
    ZU_K_STR  = 4,
    ZU_K_LIST = 5
} zu_kind;

/* Simplification mode. Must agree with ZU_SIMPLIFY in R/utils.R.
 *
 * PRESERVE is v1's behaviour and the default: an array whose elements do not
 * share a kind stays a list, so a field that is usually numeric and sometimes
 * a string is visible rather than papered over. COERCE is the opt-in that
 * follows R's own promotion to character instead, for callers who would rather
 * have the uniform shape. NONE makes every array a list. */
typedef enum {
    ZU_S_NONE     = 0,
    ZU_S_PRESERVE = 1,
    ZU_S_COERCE   = 2
} zu_mode;

/* R's integer is int32 and NA_INTEGER is INT_MIN, so a JSON integer equal to
 * INT_MIN would come back as NA. Both it and anything wider promote to double,
 * which represents them exactly up to 2^53. */
static int zu_fits_int(int64_t v) {
    return v > (int64_t) INT_MIN && v <= (int64_t) INT_MAX;
}

/* A number too big for any finite double (1e309) or wider than int64/uint64
 * arrives as YYJSON_TYPE_RAW under BIGNUM_AS_RAW, holding the original token.
 *
 * Two things make reading it with a pointer and no length correct:
 *
 *  - The token is always followed by a delimiter -- ',', ']', '}' or space --
 *    or by the end of yyjson's buffer, which is zero-padded by
 *    YYJSON_PADDING_SIZE on every read path. We never pass READ_INSITU, so the
 *    buffer is always yyjson's own padded copy and never R's memory.
 *    R_strtod stops at the first byte that cannot continue a number, so it
 *    consumes the token and nothing after it.
 *  - R_strtod rather than strtod because strtod reads the decimal point in the
 *    C locale of the moment: under a comma-decimal locale it would stop at the
 *    '.' of 1.5e400 and return 1. R_strtod is the one R's own as.numeric()
 *    uses, so the value is what writing the token in R source would give --
 *    Inf here, and the nearest double for a 30-digit integer. */
static double zu_raw_dbl(yyjson_val *v) {
    return R_strtod(yyjson_get_raw(v), NULL);
}

/* "Is this value a number?", asked by every path that sorts numbers from
 * strings. It has to count RAW, or a big number falls through to the branch
 * that treats it as a JSON string and comes back as the token's text. */
static int zu_is_num(yyjson_val *v) {
    return yyjson_is_num(v) || yyjson_is_raw(v);
}

static zu_kind zu_val_kind(yyjson_val *v) {
    switch (yyjson_get_type(v)) {
    case YYJSON_TYPE_NULL: return ZU_K_NULL;
    case YYJSON_TYPE_BOOL: return ZU_K_LGL;
    case YYJSON_TYPE_STR:  return ZU_K_STR;
    /* Never ZU_K_INT: a raw number is out of int64 range or infinite, so it
     * is a double whatever it says. This is also what keeps zu_as_int() from
     * ever seeing one. */
    case YYJSON_TYPE_RAW:  return ZU_K_DBL;
    case YYJSON_TYPE_NUM:
        switch (yyjson_get_subtype(v)) {
        case YYJSON_SUBTYPE_SINT:
            return zu_fits_int(yyjson_get_sint(v)) ? ZU_K_INT : ZU_K_DBL;
        case YYJSON_SUBTYPE_UINT: {
            uint64_t u = yyjson_get_uint(v);
            return (u <= (uint64_t) INT_MAX) ? ZU_K_INT : ZU_K_DBL;
        }
        default: return ZU_K_DBL;
        }
    default: return ZU_K_LIST;           /* array or object */
    }
}

/* The decision procedure, applied over one array:
 *   nested container                      -> list
 *   string present and non-string present -> list
 *   string present (with nulls only)      -> character
 *   numeric family only                   -> logical | integer | double
 *   empty, or all null                    -> logical
 */
/* Running state of the lattice over one sequence of values. */
typedef struct {
    zu_kind num_max;
    int has_str;
    int has_num;
} zu_lat;

#define ZU_LAT_INIT { ZU_K_NULL, 0, 0 }

/* Fold one value into the lattice. Returns 0 as soon as the sequence is known
 * to need a list, so callers stop early.
 *
 * The array path and the data-frame column path both go through here: the rule
 * is subtle enough -- and the difference between the two modes narrow enough --
 * that having it written twice is how the two would quietly diverge. */
static int zu_lat_step(zu_lat *st, zu_kind k, zu_mode mode) {
    if (k == ZU_K_LIST) return 0;               /* a container never coerces */
    if (k == ZU_K_STR) {
        st->has_str = 1;
    } else if (k != ZU_K_NULL) {
        st->has_num = 1;
        if (k > st->num_max) st->num_max = k;
    }
    /* The one place the two modes differ: strings mixed with the numeric
     * family are a list under PRESERVE and a character vector under COERCE.
     * Everything else -- the promotions inside the numeric family, nested
     * containers, all-null -- is identical. */
    if (st->has_str && st->has_num && mode != ZU_S_COERCE) return 0;
    return 1;
}

static zu_kind zu_lat_finish(const zu_lat *st) {
    if (st->has_str) return ZU_K_STR;
    return st->has_num ? st->num_max : ZU_K_LGL;
}

static zu_kind zu_arr_kind(yyjson_val *arr, zu_mode mode) {
    zu_lat st = ZU_LAT_INIT;
    size_t idx, max;
    yyjson_val *v;

    yyjson_arr_foreach(arr, idx, max, v)
        if (!zu_lat_step(&st, zu_val_kind(v), mode)) return ZU_K_LIST;
    return zu_lat_finish(&st);
}

/* ---- scalar extraction --------------------------------------------------- */

static int zu_as_lgl(yyjson_val *v) {
    if (yyjson_is_null(v)) return NA_LOGICAL;
    return yyjson_get_bool(v) ? TRUE : FALSE;
}

static int zu_as_int(yyjson_val *v) {
    switch (yyjson_get_type(v)) {
    case YYJSON_TYPE_NULL: return NA_INTEGER;
    case YYJSON_TYPE_BOOL: return yyjson_get_bool(v) ? 1 : 0;
    default:               return (int) yyjson_get_sint(v);
    }
}

static double zu_as_dbl(yyjson_val *v) {
    switch (yyjson_get_type(v)) {
    case YYJSON_TYPE_NULL: return NA_REAL;
    case YYJSON_TYPE_BOOL: return yyjson_get_bool(v) ? 1.0 : 0.0;
    case YYJSON_TYPE_RAW:  return zu_raw_dbl(v);
    default:
        if (yyjson_get_subtype(v) == YYJSON_SUBTYPE_UINT)
            return (double) yyjson_get_uint(v);
        if (yyjson_get_subtype(v) == YYJSON_SUBTYPE_SINT)
            return (double) yyjson_get_sint(v);
        return yyjson_get_real(v);
    }
}

/* The one place a CHARSXP is made, so every string and every object key gets
 * the same two guards.
 *
 * yyjson guarantees valid UTF-8 (validation is on), so the CE_UTF8 mark is
 * accurate and R will not re-encode the bytes. What it does not guarantee is
 * that R can hold the result:
 *
 *  - mkCharLenCE takes an int, so a string past INT_MAX would arrive as a
 *    negative length and be read off the end;
 *  - "\u0000" is perfectly legal JSON but decodes to a NUL, and an R string
 *    cannot contain one. Left to mkCharLenCE this raises a bare simpleError
 *    from the R internals, which would escape the zujson_error contract that
 *    callers handle on. */
static SEXP zu_mkchar(const char *dat, size_t len, const char *what) {
    if (len > (size_t) INT_MAX)
        zu_stop("zujson_parse_error",
                "JSON contains %s of %lu bytes, too long for R",
                what, (unsigned long) len);
    if (memchr(dat, '\0', len) != NULL)
        zu_stop("zujson_parse_error",
                "JSON contains %s with an embedded NUL (\\u0000), "
                "which an R string cannot hold", what);
    return Rf_mkCharLenCE(dat, (int) len, CE_UTF8);
}

static SEXP zu_as_char(yyjson_val *v) {
    if (yyjson_is_null(v)) return NA_STRING;
    return zu_mkchar(yyjson_get_str(v), yyjson_get_len(v), "a string");
}

/* Building a large tree is the slow half of parsing, so it has to be
 * interruptible. R_CheckUserInterrupt() longjmps, which is safe here only
 * because the document is owned by an external pointer. */
static unsigned long zu_n_vals = 0;

static void zu_tick(void) {
    if ((++zu_n_vals & 0xFFFFu) == 0) R_CheckUserInterrupt();
}

/* ---- recursive builder --------------------------------------------------- */

static SEXP zu_to_sexp(yyjson_val *v, zu_mode mode, int df, int depth);

/* Fill a character vector from an array that also holds numbers or booleans.
 * Only reachable under ZU_S_COERCE, since PRESERVE makes that array a list.
 *
 * The strings have to be the ones R itself would produce -- 1/3 is
 * "0.333333333333333", not "%g" of it -- so the numbers are gathered into one
 * numeric vector and coerced in a single call rather than formatted here.
 * Booleans are spelled out directly: as.character(TRUE) is "TRUE", which needs
 * no help. JSON null becomes NA_STRING and never the string "NA", which is
 * what coercing a list element would have given.
 *
 * `num_max` is the kind the numeric elements agreed on, so the gathering
 * vector is integer unless some element forced a double. */
static SEXP zu_arr_coerce_str(yyjson_val *arr, zu_kind num_max) {
    R_xlen_t n = (R_xlen_t) yyjson_arr_size(arr);
    R_xlen_t n_num = 0, j = 0;
    size_t idx, max;
    yyjson_val *v;
    SEXP nums, strs, out;

    yyjson_arr_foreach(arr, idx, max, v)
        if (zu_is_num(v)) n_num++;

    nums = PROTECT(Rf_allocVector(num_max == ZU_K_DBL ? REALSXP : INTSXP,
                                  n_num));
    yyjson_arr_foreach(arr, idx, max, v) {
        if (!zu_is_num(v)) continue;
        if (num_max == ZU_K_DBL) REAL(nums)[j] = zu_as_dbl(v);
        else                     INTEGER(nums)[j] = zu_as_int(v);
        j++;
    }
    strs = PROTECT(Rf_coerceVector(nums, STRSXP));

    out = PROTECT(Rf_allocVector(STRSXP, n));
    j = 0;
    yyjson_arr_foreach(arr, idx, max, v) {
        if (zu_is_num(v)) {
            SET_STRING_ELT(out, idx, STRING_ELT(strs, j++));
        } else if (yyjson_is_bool(v)) {
            SET_STRING_ELT(out, idx,
                           Rf_mkChar(yyjson_get_bool(v) ? "TRUE" : "FALSE"));
        } else if (yyjson_is_null(v)) {
            SET_STRING_ELT(out, idx, NA_STRING);
        } else {
            SET_STRING_ELT(out, idx, zu_as_char(v));
        }
    }
    UNPROTECT(3);
    return out;
}

/* An atomic array: one allocation, then a straight fill. */
static SEXP zu_arr_atomic(yyjson_val *arr, zu_kind kind) {
    R_xlen_t n = (R_xlen_t) yyjson_arr_size(arr);
    zu_n_vals += (unsigned long) n;
    if (n > 0xFFFF) R_CheckUserInterrupt();
    size_t idx, max;
    yyjson_val *v;
    SEXP out;

    switch (kind) {
    case ZU_K_LGL:
        out = PROTECT(Rf_allocVector(LGLSXP, n));
        yyjson_arr_foreach(arr, idx, max, v) LOGICAL(out)[idx] = zu_as_lgl(v);
        break;
    case ZU_K_INT:
        out = PROTECT(Rf_allocVector(INTSXP, n));
        yyjson_arr_foreach(arr, idx, max, v) INTEGER(out)[idx] = zu_as_int(v);
        break;
    case ZU_K_DBL:
        out = PROTECT(Rf_allocVector(REALSXP, n));
        yyjson_arr_foreach(arr, idx, max, v) REAL(out)[idx] = zu_as_dbl(v);
        break;
    default: {                            /* ZU_K_STR */
        /* Strings and nulls only is the common case and stays a straight
         * fill; anything else in there means COERCE put it here. */
        zu_kind num_max = ZU_K_NULL;
        yyjson_arr_foreach(arr, idx, max, v) {
            if (zu_is_num(v)) {
                zu_kind k = zu_val_kind(v);
                if (k > num_max) num_max = k;
            } else if (yyjson_is_bool(v) && num_max < ZU_K_LGL) {
                num_max = ZU_K_LGL;
            }
        }
        if (num_max != ZU_K_NULL) return zu_arr_coerce_str(arr, num_max);
        out = PROTECT(Rf_allocVector(STRSXP, n));
        yyjson_arr_foreach(arr, idx, max, v) SET_STRING_ELT(out, idx, zu_as_char(v));
        break;
    }
    }
    UNPROTECT(1);
    return out;
}

static SEXP zu_arr_list(yyjson_val *arr, zu_mode mode, int df, int depth) {
    R_xlen_t n = (R_xlen_t) yyjson_arr_size(arr);
    SEXP out = PROTECT(Rf_allocVector(VECSXP, n));
    size_t idx, max;
    yyjson_val *v;
    /* The child is unprotected on return, but SET_VECTOR_ELT is the very next
     * thing that happens and nothing between them allocates. */
    yyjson_arr_foreach(arr, idx, max, v)
        SET_VECTOR_ELT(out, idx, zu_to_sexp(v, mode, df, depth + 1));
    UNPROTECT(1);
    return out;
}

static SEXP zu_obj(yyjson_val *obj, zu_mode mode, int df, int depth) {
    R_xlen_t n = (R_xlen_t) yyjson_obj_size(obj);
    SEXP out = PROTECT(Rf_allocVector(VECSXP, n));
    SEXP nms = PROTECT(Rf_allocVector(STRSXP, n));

    yyjson_obj_iter iter;
    yyjson_obj_iter_init(obj, &iter);
    yyjson_val *key;
    R_xlen_t i = 0;
    while ((key = yyjson_obj_iter_next(&iter)) != NULL) {
        SET_STRING_ELT(nms, i,
                       zu_mkchar(yyjson_get_str(key), yyjson_get_len(key),
                                 "an object key"));
        SET_VECTOR_ELT(out, i,
                       zu_to_sexp(yyjson_obj_iter_get_val(key), mode, df, depth + 1));
        i++;
    }
    Rf_setAttrib(out, R_NamesSymbol, nms);
    UNPROTECT(2);
    return out;
}

/* ---- data frame simplification ------------------------------------------
 *
 * Opt-in, via `data_frame = TRUE`. An array becomes a data frame when it is
 * non-empty and every element is an object -- the shape an API uses for a list
 * of records. Anything else is left exactly as it was.
 *
 * Columns are the union of the keys, in the order first seen, because that is
 * the order the document itself puts them in and records are not required to
 * agree. A record missing a key contributes NA rather than shortening the
 * column, so every column has one entry per row and the frame is rectangular
 * by construction.
 *
 * Each column is then simplified with the active mode, through the same
 * lattice an array goes through: a column of mixed kinds is a list column
 * under PRESERVE, a character column under COERCE.
 * ------------------------------------------------------------------------- */

static int zu_arr_all_obj(yyjson_val *arr) {
    size_t idx, max;
    yyjson_val *v;

    if (yyjson_arr_size(arr) == 0) return 0;    /* [] stays logical(0) */
    yyjson_arr_foreach(arr, idx, max, v)
        if (!yyjson_is_obj(v)) return 0;
    return 1;
}

typedef struct { const char *dat; size_t len; } zu_key;

/* The union of the keys, first-seen order.
 *
 * Dedup is a linear scan. Records in a real response share a key set, so this
 * is O(rows x cols); a hostile body where every record invents new keys makes
 * it quadratic in the number of distinct keys, which is why the loop ticks the
 * interrupt check rather than running unbounded. */
static R_xlen_t zu_collect_keys(yyjson_val *arr, zu_key *keys, R_xlen_t cap) {
    R_xlen_t n_keys = 0, i;
    size_t idx, max;
    yyjson_val *row;

    yyjson_arr_foreach(arr, idx, max, row) {
        yyjson_obj_iter iter;
        yyjson_val *key;
        yyjson_obj_iter_init(row, &iter);
        while ((key = yyjson_obj_iter_next(&iter)) != NULL) {
            const char *kd = yyjson_get_str(key);
            size_t kl = yyjson_get_len(key);
            int seen = 0;
            zu_tick();
            for (i = 0; i < n_keys; i++) {
                if (keys[i].len == kl && memcmp(keys[i].dat, kd, kl) == 0) {
                    seen = 1;
                    break;
                }
            }
            if (!seen && n_keys < cap) {
                keys[n_keys].dat = kd;
                keys[n_keys].len = kl;
                n_keys++;
            }
        }
    }
    return n_keys;
}

/* One column, as an atomic vector. A NULL entry is a key the record did not
 * have, and reads as NA -- the same as an explicit JSON null, which is the
 * right call here: both mean "no value for this row". */
static SEXP zu_col_atomic(yyjson_val **vals, R_xlen_t n, zu_kind kind) {
    SEXP out;
    R_xlen_t i;

    switch (kind) {
    case ZU_K_LGL:
        out = PROTECT(Rf_allocVector(LGLSXP, n));
        for (i = 0; i < n; i++)
            LOGICAL(out)[i] = vals[i] ? zu_as_lgl(vals[i]) : NA_LOGICAL;
        break;
    case ZU_K_INT:
        out = PROTECT(Rf_allocVector(INTSXP, n));
        for (i = 0; i < n; i++)
            INTEGER(out)[i] = vals[i] ? zu_as_int(vals[i]) : NA_INTEGER;
        break;
    case ZU_K_DBL:
        out = PROTECT(Rf_allocVector(REALSXP, n));
        for (i = 0; i < n; i++)
            REAL(out)[i] = vals[i] ? zu_as_dbl(vals[i]) : NA_REAL;
        break;
    default: {                            /* ZU_K_STR */
        /* Same two cases as the array path: strings and nulls only is a
         * straight fill, anything else means COERCE put it here and the
         * numbers have to be formatted the way R formats them. */
        SEXP nums, strs;
        R_xlen_t n_num = 0, j = 0;
        zu_kind num_max = ZU_K_NULL;

        for (i = 0; i < n; i++) {
            if (vals[i] && zu_is_num(vals[i])) {
                zu_kind k = zu_val_kind(vals[i]);
                if (k > num_max) num_max = k;
                n_num++;
            } else if (vals[i] && yyjson_is_bool(vals[i])
                       && num_max < ZU_K_LGL) {
                num_max = ZU_K_LGL;
            }
        }
        if (n_num == 0 && num_max == ZU_K_NULL) {
            out = PROTECT(Rf_allocVector(STRSXP, n));
            for (i = 0; i < n; i++)
                SET_STRING_ELT(out, i,
                               vals[i] ? zu_as_char(vals[i]) : NA_STRING);
            break;
        }
        nums = PROTECT(Rf_allocVector(num_max == ZU_K_DBL ? REALSXP : INTSXP,
                                      n_num));
        for (i = 0; i < n; i++) {
            if (!vals[i] || !zu_is_num(vals[i])) continue;
            if (num_max == ZU_K_DBL) REAL(nums)[j] = zu_as_dbl(vals[i]);
            else                     INTEGER(nums)[j] = zu_as_int(vals[i]);
            j++;
        }
        strs = PROTECT(Rf_coerceVector(nums, STRSXP));
        out = PROTECT(Rf_allocVector(STRSXP, n));
        j = 0;
        for (i = 0; i < n; i++) {
            if (!vals[i] || yyjson_is_null(vals[i])) {
                SET_STRING_ELT(out, i, NA_STRING);
            } else if (zu_is_num(vals[i])) {
                SET_STRING_ELT(out, i, STRING_ELT(strs, j++));
            } else if (yyjson_is_bool(vals[i])) {
                SET_STRING_ELT(out, i,
                               Rf_mkChar(yyjson_get_bool(vals[i]) ? "TRUE"
                                                                 : "FALSE"));
            } else {
                SET_STRING_ELT(out, i, zu_as_char(vals[i]));
            }
        }
        UNPROTECT(2);                     /* nums, strs; `out` stays */
        break;
    }
    }
    UNPROTECT(1);
    return out;
}

static SEXP zu_arr_df(yyjson_val *arr, zu_mode mode, int df, int depth) {
    R_xlen_t n_rows = (R_xlen_t) yyjson_arr_size(arr);
    R_xlen_t cap = 0, n_keys, c, r;
    size_t idx, max;
    yyjson_val *row, **vals;
    zu_key *keys;
    SEXP out, nms, rn;

    yyjson_arr_foreach(arr, idx, max, row)
        cap += (R_xlen_t) yyjson_obj_size(row);

    /* R_alloc: freed when .Call returns, including on the longjmp out of
     * zu_stop(), which a malloc here would leak. */
    keys = (zu_key *) R_alloc((size_t) (cap > 0 ? cap : 1), sizeof(zu_key));
    n_keys = zu_collect_keys(arr, keys, cap);

    out = PROTECT(Rf_allocVector(VECSXP, n_keys));
    nms = PROTECT(Rf_allocVector(STRSXP, n_keys));
    vals = (yyjson_val **) R_alloc((size_t) (n_rows > 0 ? n_rows : 1),
                                   sizeof(yyjson_val *));

    for (c = 0; c < n_keys; c++) {
        zu_lat st = ZU_LAT_INIT;
        int atomic = 1;
        zu_kind kind;

        r = 0;
        yyjson_arr_foreach(arr, idx, max, row)
            vals[r++] = yyjson_obj_getn(row, keys[c].dat, keys[c].len);

        for (r = 0; r < n_rows; r++) {
            zu_kind k = vals[r] ? zu_val_kind(vals[r]) : ZU_K_NULL;
            if (!zu_lat_step(&st, k, mode)) { atomic = 0; break; }
        }
        kind = zu_lat_finish(&st);

        if (atomic) {
            SET_VECTOR_ELT(out, c, zu_col_atomic(vals, n_rows, kind));
        } else {
            SEXP col = PROTECT(Rf_allocVector(VECSXP, n_rows));
            for (r = 0; r < n_rows; r++)
                SET_VECTOR_ELT(col, r,
                               vals[r] ? zu_to_sexp(vals[r], mode, df, depth + 1)
                                       : R_NilValue);
            SET_VECTOR_ELT(out, c, col);
            UNPROTECT(1);
        }
        SET_STRING_ELT(nms, c, zu_mkchar(keys[c].dat, keys[c].len,
                                         "an object key"));
    }

    /* Compact row names: c(NA, -n) is how R stores 1:n without holding it. */
    rn = PROTECT(Rf_allocVector(INTSXP, 2));
    INTEGER(rn)[0] = NA_INTEGER;
    INTEGER(rn)[1] = -(int) n_rows;

    Rf_setAttrib(out, R_NamesSymbol, nms);
    Rf_setAttrib(out, R_RowNamesSymbol, rn);
    Rf_setAttrib(out, R_ClassSymbol, Rf_mkString("data.frame"));
    UNPROTECT(3);
    return out;
}

/* Depth counts containers, not values: the root array is level 1 and a scalar
 * inside it is not a level of its own. Checking here rather than on every
 * value keeps the limit meaning the same thing in both directions. */
static void zu_check_depth(int depth) {
    if (depth > ZUJSON_MAX_DEPTH)
        zu_stop("zujson_depth_error",
                "JSON nests deeper than %d levels", ZUJSON_MAX_DEPTH);
}

static SEXP zu_to_sexp(yyjson_val *v, zu_mode mode, int df, int depth) {
    zu_tick();
    switch (yyjson_get_type(v)) {
    case YYJSON_TYPE_NULL: return R_NilValue;
    case YYJSON_TYPE_BOOL: return Rf_ScalarLogical(yyjson_get_bool(v));
    case YYJSON_TYPE_STR: {
        SEXP s = PROTECT(Rf_allocVector(STRSXP, 1));
        SET_STRING_ELT(s, 0, zu_as_char(v));
        UNPROTECT(1);
        return s;
    }
    case YYJSON_TYPE_RAW:
    case YYJSON_TYPE_NUM:
        return zu_val_kind(v) == ZU_K_INT
            ? Rf_ScalarInteger(zu_as_int(v))
            : Rf_ScalarReal(zu_as_dbl(v));
    case YYJSON_TYPE_ARR: {
        zu_check_depth(depth);
        if (mode == ZU_S_NONE) return zu_arr_list(v, mode, df, depth);
        /* An array of objects is a frame before it is a list: the check comes
         * first so the records are read as rows rather than simplified away. */
        if (df && zu_arr_all_obj(v)) return zu_arr_df(v, mode, df, depth);
        zu_kind kind = zu_arr_kind(v, mode);
        return kind == ZU_K_LIST
            ? zu_arr_list(v, mode, df, depth)
            : zu_arr_atomic(v, kind);
    }
    case YYJSON_TYPE_OBJ:
        zu_check_depth(depth);
        return zu_obj(v, mode, df, depth);
    default:
        zu_stop("zujson_parse_error", "unhandled JSON value type");
        return R_NilValue;               /* not reached */
    }
}

/* ---- entry points -------------------------------------------------------- */

/* The doc is handed to R before any SEXP is allocated: zu_stop() and R's
 * allocators both longjmp, and a bare yyjson_doc * would leak on either. */
static SEXP zu_finish(yyjson_doc *doc, zu_mode mode, int df) {
    zu_n_vals = 0;
    SEXP owner = PROTECT(zu_extptr_own_doc(doc));
    SEXP out = PROTECT(zu_to_sexp(yyjson_doc_get_root(doc), mode, df, 1));
    zu_extptr_release(owner);
    UNPROTECT(2);
    return out;
}

/* One flag set for every read path, so json_parse() and json_validate() can
 * never disagree about what counts as parseable.
 *
 * BOM: RFC 8259 forbids emitting one but allows ignoring it, and real APIs do
 * emit them. Rejecting a response body over three leading bytes would be a
 * pointless failure for the use case this package exists to serve.
 *
 * BIGNUM_AS_RAW: without it yyjson rejects the whole document when a number
 * overflows to infinity, so one absurd value anywhere in a response body makes
 * the body unparseable. RFC 8259 sets no limit on the magnitude of a number,
 * so 1e309 is valid JSON and refusing it is our bug, not the sender's. With
 * the flag the token arrives as YYJSON_TYPE_RAW and zu_raw_dbl() converts it
 * to Inf, which is what R's own as.numeric("1e309") gives.
 *
 * Deliberately not ALLOW_INF_AND_NAN: that also accepts the bare literals
 * NaN, inf and -Infinity, which are not JSON at all. Since json_validate()
 * shares this flag set, it would start calling those documents valid. */
#define ZUJSON_READ_FLAGS (YYJSON_READ_ALLOW_BOM | YYJSON_READ_BIGNUM_AS_RAW)

static SEXP zu_read_mem(const char *dat, size_t len, zu_mode mode, int df) {
    yyjson_read_err err;
    /* No YYJSON_READ_INSITU: yyjson copies into its own buffer, so R's
     * immutable CHAR()/RAW() data is never written through. */
    yyjson_doc *doc = yyjson_read_opts((char *) dat, len,
                                       ZUJSON_READ_FLAGS, NULL, &err);
    if (!doc)
        zu_stop("zujson_parse_error", "invalid JSON at byte %lu: %s",
                (unsigned long) err.pos, err.msg);
    return zu_finish(doc, mode, df);
}

SEXP zujson_parse_str(SEXP x_, SEXP simplify_, SEXP df_) {
    SEXP s = STRING_ELT(x_, 0);
    if (s == NA_STRING)
        zu_stop("zujson_parse_error", "`x` is NA, not JSON text");
    /* translateCharUTF8 is a no-op for the common UTF-8/ASCII case and
     * converts a latin1 or native-encoded string otherwise. */
    const char *dat = Rf_translateCharUTF8(s);
    return zu_read_mem(dat, strlen(dat), (zu_mode) Rf_asInteger(simplify_),
                       Rf_asLogical(df_));
}

SEXP zujson_parse_raw(SEXP x_, SEXP simplify_, SEXP df_) {
    return zu_read_mem((const char *) RAW(x_), (size_t) XLENGTH(x_),
                       (zu_mode) Rf_asInteger(simplify_), Rf_asLogical(df_));
}

SEXP zujson_parse_file(SEXP path_, SEXP simplify_, SEXP df_) {
    const char *path = Rf_translateCharUTF8(STRING_ELT(path_, 0));
    yyjson_read_err err;
    yyjson_doc *doc = yyjson_read_file(path, ZUJSON_READ_FLAGS, NULL, &err);
    if (!doc) {
        /* "could not open it" and "its contents are not JSON" are different
         * problems with different fixes, so they get different classes. */
        if (err.code == YYJSON_READ_ERROR_FILE_OPEN ||
            err.code == YYJSON_READ_ERROR_FILE_READ)
            zu_stop("zujson_io_error", "could not read '%s': %s", path, err.msg);
        zu_stop("zujson_parse_error", "invalid JSON in '%s' at byte %lu: %s",
                path, (unsigned long) err.pos, err.msg);
    }
    return zu_finish(doc, (zu_mode) Rf_asInteger(simplify_), Rf_asLogical(df_));
}

/* Validation parses and throws the tree away: yyjson has no cheaper
 * "check only" mode, and building nothing in R is most of the saving anyway. */
static SEXP zu_validate_mem(const char *dat, size_t len) {
    yyjson_read_err err;
    yyjson_doc *doc = yyjson_read_opts((char *) dat, len,
                                       ZUJSON_READ_FLAGS, NULL, &err);
    if (!doc) return Rf_ScalarLogical(FALSE);
    yyjson_doc_free(doc);
    return Rf_ScalarLogical(TRUE);
}

SEXP zujson_validate_str(SEXP x_) {
    SEXP s = STRING_ELT(x_, 0);
    if (s == NA_STRING) return Rf_ScalarLogical(FALSE);
    const char *dat = Rf_translateCharUTF8(s);
    return zu_validate_mem(dat, strlen(dat));
}

SEXP zujson_validate_raw(SEXP x_) {
    return zu_validate_mem((const char *) RAW(x_), (size_t) XLENGTH(x_));
}

/* ---------------------------------------------------------------------------
 * NDJSON (application/x-ndjson): one JSON value per line.
 *
 * Framing is by newline, and that is safe rather than merely conventional: a
 * raw 0x0A is not legal inside a JSON string (it has to be escaped), so a line
 * break can never fall inside a record. This is the property the whole format
 * rests on, and it is what lets a reader find record boundaries without
 * parsing.
 *
 * Deliberately stricter than yyjson's YYJSON_READ_STOP_WHEN_DONE, which would
 * also accept newline-free concatenated JSON. Accepting more than the content
 * type promises is a lenience nobody asked for.
 * ------------------------------------------------------------------------- */

static int zu_line_blank(const char *s, size_t n) {
    for (size_t i = 0; i < n; i++)
        if (s[i] != ' ' && s[i] != '\t' && s[i] != '\r' && s[i] != '\n')
            return 0;
    return 1;
}

/* End of the line starting at `i`: `*stop` excludes the newline and a CR
 * before it, `*next` is where the following line begins. */
static void zu_line_bounds(const char *dat, size_t len, size_t i,
                           size_t *stop, size_t *next) {
    size_t j = i;
    while (j < len && dat[j] != '\n') j++;
    *next = (j < len) ? j + 1 : j;
    if (j > i && dat[j - 1] == '\r') j--;   /* tolerate CRLF: servers send it */
    *stop = j;
}

static SEXP zu_read_ndjson(const char *dat, size_t len, zu_mode mode, int df) {
    size_t i, stop, next;

    /* Counted first so the result can be allocated exactly once. Scanning for
     * newlines twice is far cheaper than growing a list record by record. */
    R_xlen_t n = 0;
    for (i = 0; i < len; i = next) {
        zu_line_bounds(dat, len, i, &stop, &next);
        if (!zu_line_blank(dat + i, stop - i)) n++;
    }

    SEXP out = PROTECT(Rf_allocVector(VECSXP, n));
    R_xlen_t k = 0;
    unsigned long lineno = 0;

    for (i = 0; i < len; i = next) {
        zu_line_bounds(dat, len, i, &stop, &next);
        lineno++;
        if (zu_line_blank(dat + i, stop - i)) continue;  /* blank lines are not records */

        yyjson_read_err err;
        yyjson_doc *doc = yyjson_read_opts((char *) dat + i, stop - i,
                                           ZUJSON_READ_FLAGS, NULL, &err);
        /* The line number is the whole point: "invalid JSON at byte 41827" is
         * useless in a 10,000-record body. */
        if (!doc)
            zu_stop("zujson_parse_error",
                    "invalid JSON on line %lu at byte %lu of that line: %s",
                    lineno, (unsigned long) err.pos, err.msg);

        SEXP owner = PROTECT(zu_extptr_own_doc(doc));
        SET_VECTOR_ELT(out, k++, zu_to_sexp(yyjson_doc_get_root(doc), mode, df, 1));
        zu_extptr_release(owner);
        UNPROTECT(1);

        if ((lineno & 0x3FFu) == 0) R_CheckUserInterrupt();
    }

    UNPROTECT(1);
    return out;
}

SEXP zujson_parse_ndjson_str(SEXP x_, SEXP simplify_, SEXP df_) {
    SEXP s = STRING_ELT(x_, 0);
    if (s == NA_STRING)
        zu_stop("zujson_parse_error", "`x` is NA, not NDJSON text");
    const char *dat = Rf_translateCharUTF8(s);
    return zu_read_ndjson(dat, strlen(dat), (zu_mode) Rf_asInteger(simplify_),
                          Rf_asLogical(df_));
}

SEXP zujson_parse_ndjson_raw(SEXP x_, SEXP simplify_, SEXP df_) {
    return zu_read_ndjson((const char *) RAW(x_), (size_t) XLENGTH(x_),
                          (zu_mode) Rf_asInteger(simplify_),
                          Rf_asLogical(df_));
}
