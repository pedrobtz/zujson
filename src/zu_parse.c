#include <limits.h>
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

/* R's integer is int32 and NA_INTEGER is INT_MIN, so a JSON integer equal to
 * INT_MIN would come back as NA. Both it and anything wider promote to double,
 * which represents them exactly up to 2^53. */
static int zu_fits_int(int64_t v) {
    return v > (int64_t) INT_MIN && v <= (int64_t) INT_MAX;
}

static zu_kind zu_val_kind(yyjson_val *v) {
    switch (yyjson_get_type(v)) {
    case YYJSON_TYPE_NULL: return ZU_K_NULL;
    case YYJSON_TYPE_BOOL: return ZU_K_LGL;
    case YYJSON_TYPE_STR:  return ZU_K_STR;
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
static zu_kind zu_arr_kind(yyjson_val *arr) {
    zu_kind num_max = ZU_K_NULL;
    int has_str = 0, has_num = 0;
    size_t idx, max;
    yyjson_val *v;

    yyjson_arr_foreach(arr, idx, max, v) {
        zu_kind k = zu_val_kind(v);
        if (k == ZU_K_LIST) return ZU_K_LIST;
        if (k == ZU_K_STR) {
            has_str = 1;
        } else if (k != ZU_K_NULL) {
            has_num = 1;
            if (k > num_max) num_max = k;
        }
        if (has_str && has_num) return ZU_K_LIST;
    }
    if (has_str) return ZU_K_STR;
    return has_num ? num_max : ZU_K_LGL;
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
    default:
        if (yyjson_get_subtype(v) == YYJSON_SUBTYPE_UINT)
            return (double) yyjson_get_uint(v);
        if (yyjson_get_subtype(v) == YYJSON_SUBTYPE_SINT)
            return (double) yyjson_get_sint(v);
        return yyjson_get_real(v);
    }
}

/* yyjson guarantees valid UTF-8 (validation is on), so the encoding mark is
 * accurate and R will not re-encode the bytes.
 *
 * The length guard matters because mkCharLenCE takes an int: a string past
 * INT_MAX would arrive as a negative length and be read off the end. R cannot
 * hold such a string anyway, so refusing is the only option. */
static SEXP zu_as_char(yyjson_val *v) {
    if (yyjson_is_null(v)) return NA_STRING;
    size_t len = yyjson_get_len(v);
    if (len > (size_t) INT_MAX)
        zu_stop("zujson_parse_error",
                "JSON contains a string of %lu bytes, too long for R",
                (unsigned long) len);
    return Rf_mkCharLenCE(yyjson_get_str(v), (int) len, CE_UTF8);
}

/* Building a large tree is the slow half of parsing, so it has to be
 * interruptible. R_CheckUserInterrupt() longjmps, which is safe here only
 * because the document is owned by an external pointer. */
static unsigned long zu_n_vals = 0;

static void zu_tick(void) {
    if ((++zu_n_vals & 0xFFFFu) == 0) R_CheckUserInterrupt();
}

/* ---- recursive builder --------------------------------------------------- */

static SEXP zu_to_sexp(yyjson_val *v, int simplify, int depth);

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
    default:                              /* ZU_K_STR */
        out = PROTECT(Rf_allocVector(STRSXP, n));
        yyjson_arr_foreach(arr, idx, max, v) SET_STRING_ELT(out, idx, zu_as_char(v));
        break;
    }
    UNPROTECT(1);
    return out;
}

static SEXP zu_arr_list(yyjson_val *arr, int simplify, int depth) {
    R_xlen_t n = (R_xlen_t) yyjson_arr_size(arr);
    SEXP out = PROTECT(Rf_allocVector(VECSXP, n));
    size_t idx, max;
    yyjson_val *v;
    /* The child is unprotected on return, but SET_VECTOR_ELT is the very next
     * thing that happens and nothing between them allocates. */
    yyjson_arr_foreach(arr, idx, max, v)
        SET_VECTOR_ELT(out, idx, zu_to_sexp(v, simplify, depth + 1));
    UNPROTECT(1);
    return out;
}

static SEXP zu_obj(yyjson_val *obj, int simplify, int depth) {
    R_xlen_t n = (R_xlen_t) yyjson_obj_size(obj);
    SEXP out = PROTECT(Rf_allocVector(VECSXP, n));
    SEXP nms = PROTECT(Rf_allocVector(STRSXP, n));

    yyjson_obj_iter iter;
    yyjson_obj_iter_init(obj, &iter);
    yyjson_val *key;
    R_xlen_t i = 0;
    while ((key = yyjson_obj_iter_next(&iter)) != NULL) {
        SET_STRING_ELT(nms, i,
                       Rf_mkCharLenCE(yyjson_get_str(key),
                                      (int) yyjson_get_len(key), CE_UTF8));
        SET_VECTOR_ELT(out, i,
                       zu_to_sexp(yyjson_obj_iter_get_val(key), simplify, depth + 1));
        i++;
    }
    Rf_setAttrib(out, R_NamesSymbol, nms);
    UNPROTECT(2);
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

static SEXP zu_to_sexp(yyjson_val *v, int simplify, int depth) {
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
    case YYJSON_TYPE_NUM:
        return zu_val_kind(v) == ZU_K_INT
            ? Rf_ScalarInteger(zu_as_int(v))
            : Rf_ScalarReal(zu_as_dbl(v));
    case YYJSON_TYPE_ARR: {
        zu_check_depth(depth);
        if (!simplify) return zu_arr_list(v, simplify, depth);
        zu_kind kind = zu_arr_kind(v);
        return kind == ZU_K_LIST
            ? zu_arr_list(v, simplify, depth)
            : zu_arr_atomic(v, kind);
    }
    case YYJSON_TYPE_OBJ:
        zu_check_depth(depth);
        return zu_obj(v, simplify, depth);
    default:
        zu_stop("zujson_parse_error", "unhandled JSON value type");
        return R_NilValue;               /* not reached */
    }
}

/* ---- entry points -------------------------------------------------------- */

/* The doc is handed to R before any SEXP is allocated: zu_stop() and R's
 * allocators both longjmp, and a bare yyjson_doc * would leak on either. */
static SEXP zu_finish(yyjson_doc *doc, int simplify) {
    zu_n_vals = 0;
    SEXP owner = PROTECT(zu_extptr_own_doc(doc));
    SEXP out = PROTECT(zu_to_sexp(yyjson_doc_get_root(doc), simplify, 1));
    zu_extptr_release(owner);
    UNPROTECT(2);
    return out;
}

static SEXP zu_read_mem(const char *dat, size_t len, int simplify) {
    yyjson_read_err err;
    /* No YYJSON_READ_INSITU: yyjson copies into its own buffer, so R's
     * immutable CHAR()/RAW() data is never written through. */
    yyjson_doc *doc = yyjson_read_opts((char *) dat, len, 0, NULL, &err);
    if (!doc)
        zu_stop("zujson_parse_error", "invalid JSON at byte %lu: %s",
                (unsigned long) err.pos, err.msg);
    return zu_finish(doc, simplify);
}

SEXP zujson_parse_str(SEXP x_, SEXP simplify_) {
    SEXP s = STRING_ELT(x_, 0);
    if (s == NA_STRING)
        zu_stop("zujson_parse_error", "`x` is NA, not JSON text");
    /* translateCharUTF8 is a no-op for the common UTF-8/ASCII case and
     * converts a latin1 or native-encoded string otherwise. */
    const char *dat = Rf_translateCharUTF8(s);
    return zu_read_mem(dat, strlen(dat), Rf_asLogical(simplify_));
}

SEXP zujson_parse_raw(SEXP x_, SEXP simplify_) {
    return zu_read_mem((const char *) RAW(x_), (size_t) XLENGTH(x_),
                       Rf_asLogical(simplify_));
}

SEXP zujson_parse_file(SEXP path_, SEXP simplify_) {
    const char *path = Rf_translateCharUTF8(STRING_ELT(path_, 0));
    yyjson_read_err err;
    yyjson_doc *doc = yyjson_read_file(path, 0, NULL, &err);
    if (!doc)
        zu_stop("zujson_parse_error", "invalid JSON in '%s' at byte %lu: %s",
                path, (unsigned long) err.pos, err.msg);
    return zu_finish(doc, Rf_asLogical(simplify_));
}

/* Validation parses and throws the tree away: yyjson has no cheaper
 * "check only" mode, and building nothing in R is most of the saving anyway. */
static SEXP zu_validate_mem(const char *dat, size_t len) {
    yyjson_read_err err;
    yyjson_doc *doc = yyjson_read_opts((char *) dat, len, 0, NULL, &err);
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
