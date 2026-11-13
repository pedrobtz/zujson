#include <stdarg.h>
#include <stdlib.h>
#include <string.h>
#include <R_ext/Riconv.h>
#include "zujson.h"

/* ---------------------------------------------------------------------------
 * Structured conditions
 *
 * Rf_error() would be simpler, but the test suite asserts on condition classes
 * rather than on message text, so wording can change without breaking forty
 * tests. Building the condition here rather than re-signalling in R keeps the
 * class attached to the place that knows what actually went wrong.
 * ------------------------------------------------------------------------- */

unsigned long zu_err_line = 0;
const char *zu_err_what = "line";

size_t zu_utf8_cut(const char *s, size_t len, size_t max) {
    size_t n = len < max ? len : max;
    /* Find where the last sequence in the first n bytes starts, and drop it
     * when its lead byte promises more bytes than the cut kept. */
    size_t j = n;
    while (j > 0 && n - j < 4 && ((unsigned char) s[j - 1] & 0xC0) == 0x80) j--;
    if (j == 0) return n;
    unsigned char lead = (unsigned char) s[j - 1];
    size_t want = lead >= 0xF0 ? 4 : lead >= 0xE0 ? 3 : lead >= 0xC0 ? 2 : 1;
    return (j - 1) + want > n ? j - 1 : n;
}

/* Bytes R's latin1 leaves undefined. R reads "latin1" as Windows-1252, where
 * these five have no character, so translateCharUTF8() writes "<81>" for them
 * on every platform. */
static int zu_cp1252_undefined(const char *c) {
    for (; *c; c++) {
        unsigned char b = (unsigned char) *c;
        if (b == 0x81 || b == 0x8D || b == 0x8F || b == 0x90 || b == 0x9D)
            return 1;
    }
    return 0;
}

static int zu_ascii(const char *c) {
    for (; *c; c++)
        if ((unsigned char) *c >= 0x80) return 0;
    return 1;
}

const char *zu_utf8(SEXP s) {
    const char *c = CHAR(s);
    cetype_t ce = Rf_getCharCE(s);
    if (ce == CE_UTF8 || zu_ascii(c)) return c;   /* validated by yyjson */
    if (ce == CE_LATIN1)
        return zu_cp1252_undefined(c) ? NULL : Rf_translateCharUTF8(s);

    /* Native text in a UTF-8 locale needs no conversion: R hands back the
     * CHARSXP's own bytes, and yyjson validates them in both directions. Only
     * a session in another charset goes on to the checked conversion. Sending
     * this, the commonest input, through iconv as well made json_write() 8x
     * slower and asked for 4x a parsed body in scratch memory (#67). */
    if (Rf_translateCharUTF8(s) == c) return c;

    /* Native and not ASCII: convert from the locale's charset with a check,
     * through R's own iconv, which reports the byte it cannot convert rather
     * than substituting for it. The buffer comes first: R_alloc can longjmp,
     * and the iconv descriptor is not R's to free. A byte of any charset R
     * runs in is at most four of UTF-8. */
    size_t in_left = strlen(c), out_cap = 4 * in_left + 1, out_left = out_cap;
    char *buf = R_alloc(out_cap, 1), *out = buf;
    void *cd = Riconv_open("UTF-8", "");
    if (cd == (void *) -1) return NULL;
    const char *in = c;
    size_t r = Riconv(cd, &in, &in_left, &out, &out_left);
    if (r != (size_t) -1)
        r = Riconv(cd, NULL, NULL, &out, &out_left);   /* flush any state */
    Riconv_close(cd);
    if (r == (size_t) -1 || in_left != 0 || out_left == 0) return NULL;
    *out = '\0';
    return buf;
}

/* The length of the valid UTF-8 sequence starting at p, or 0. Reads no
 * further than the first byte that fails, so the string's NUL stops it. */
static size_t zu_utf8_seq(const unsigned char *p) {
    unsigned char c = p[0];
    if (c < 0x80) return 1;
    if (c >= 0xC2 && c <= 0xDF) return (p[1] & 0xC0) == 0x80 ? 2 : 0;
    if (c >= 0xE0 && c <= 0xEF) {
        if ((p[1] & 0xC0) != 0x80 || (p[2] & 0xC0) != 0x80) return 0;
        if ((c == 0xE0 && p[1] < 0xA0) || (c == 0xED && p[1] >= 0xA0)) return 0;
        return 3;
    }
    if (c >= 0xF0 && c <= 0xF4) {
        if ((p[1] & 0xC0) != 0x80 || (p[2] & 0xC0) != 0x80 ||
            (p[3] & 0xC0) != 0x80) return 0;
        if ((c == 0xF0 && p[1] < 0x90) || (c == 0xF4 && p[1] >= 0x90)) return 0;
        return 4;
    }
    return 0;
}

const char *zu_msg_str(SEXP s) {
    if (Rf_getCharCE(s) == CE_BYTES) return "<bytes>";
    const unsigned char *t = (const unsigned char *) Rf_translateCharUTF8(s);
    size_t n = strlen((const char *) t), i = 0, k;
    for (i = 0; i < n; i += k)
        if (!(k = zu_utf8_seq(t + i))) break;
    if (i >= n) return (const char *) t;
    char *out = R_alloc(4 * n + 1, 1), *o = out;
    for (i = 0; i < n; ) {
        k = zu_utf8_seq(t + i);
        if (k) { memcpy(o, t + i, k); o += k; i += k; }
        else   { snprintf(o, 5, "<%02x>", t[i]); o += 4; i++; }
    }
    *o = '\0';
    return out;
}

/* The message is built from UTF-8 parts -- every key and name in it went
 * through translateCharUTF8() -- so it is marked UTF-8 rather than native,
 * and a cut at the buffer's end is moved back to a character boundary. Both
 * left messages that were not valid UTF-8 (#53). */
void zu_stop(const char *cls, const char *fmt, ...) {
    char msg[512];
    size_t off = 0;
    if (zu_err_line) {
        int k = snprintf(msg, sizeof(msg), "%s %lu: ", zu_err_what, zu_err_line);
        off = k > 0 ? (size_t) k : 0;
        zu_err_line = 0;
    }
    va_list ap;
    va_start(ap, fmt);
    int w = vsnprintf(msg + off, sizeof(msg) - off, fmt, ap);
    va_end(ap);
    if (w > 0 && off + (size_t) w >= sizeof(msg))
        msg[zu_utf8_cut(msg, sizeof(msg) - 1, sizeof(msg) - 1)] = '\0';

    const char *fields[] = {"message", "call", ""};
    SEXP cond = PROTECT(Rf_mkNamed(VECSXP, fields));
    SEXP text = PROTECT(Rf_mkCharCE(msg, CE_UTF8));
    SET_VECTOR_ELT(cond, 0, Rf_ScalarString(text));
    SET_VECTOR_ELT(cond, 1, R_NilValue);

    SEXP klass = PROTECT(Rf_allocVector(STRSXP, 4));
    SET_STRING_ELT(klass, 0, Rf_mkChar(cls));
    SET_STRING_ELT(klass, 1, Rf_mkChar("zujson_error"));
    SET_STRING_ELT(klass, 2, Rf_mkChar("error"));
    SET_STRING_ELT(klass, 3, Rf_mkChar("condition"));
    Rf_setAttrib(cond, R_ClassSymbol, klass);

    SEXP call = PROTECT(Rf_lang2(Rf_install("stop"), cond));
    Rf_eval(call, R_BaseEnv);            /* longjmps out */

    UNPROTECT(4);                        /* not reached */
    Rf_error("zujson: stop() returned");
}

/* ---------------------------------------------------------------------------
 * External pointers that own C memory
 *
 * zu_stop() and R's own allocators both longjmp straight past any free() below
 * them, so nothing heap-allocated may be held in a bare local while either can
 * fire. Handing the pointer to a finalized external pointer makes R the owner
 * for the duration; the success path still frees eagerly via
 * zu_extptr_release().
 *
 * The owner is made *before* the resource it will own, empty, and the resource
 * is stored into it with zu_owner_hold(), which allocates nothing. Making the
 * owner after the resource -- three R allocations while the yyjson document or
 * buffer was a bare pointer -- was itself the first thing that could longjmp,
 * and an allocation failure there leaked the resource (#52). So every caller
 * runs: owner, then allocate, then hold, with nothing between the last two.
 *
 * The tag slot records which kind of payload the pointer holds, so one release
 * function can free all three. Every finalizer clears the address first, which
 * is what makes eager release and a later GC pass mutually safe, and treats a
 * NULL address -- an owner whose resource was never allocated -- as nothing to
 * do.
 * ------------------------------------------------------------------------- */

typedef enum { ZU_OWN_DOC = 0, ZU_OWN_MUT_DOC = 1, ZU_OWN_BUF = 2 } zu_own_kind;

static void zu_free_payload(SEXP xp) {
    void *p = R_ExternalPtrAddr(xp);
    if (!p) return;
    R_ClearExternalPtr(xp);              /* clear first: guards double free */
    switch ((zu_own_kind) INTEGER(R_ExternalPtrTag(xp))[0]) {
    case ZU_OWN_DOC:     yyjson_doc_free((yyjson_doc *) p); break;
    case ZU_OWN_MUT_DOC: yyjson_mut_doc_free((yyjson_mut_doc *) p); break;
    case ZU_OWN_BUF:     free(p); break;
    }
}

static SEXP zu_owner(zu_own_kind kind) {
    SEXP tag = PROTECT(Rf_ScalarInteger((int) kind));
    SEXP xp = PROTECT(R_MakeExternalPtr(NULL, tag, R_NilValue));
    R_RegisterCFinalizerEx(xp, zu_free_payload, TRUE);  /* TRUE = run at exit */
    UNPROTECT(2);
    return xp;
}

SEXP zu_owner_doc(void)     { return zu_owner(ZU_OWN_DOC); }
SEXP zu_owner_mut_doc(void) { return zu_owner(ZU_OWN_MUT_DOC); }
SEXP zu_owner_buf(void)     { return zu_owner(ZU_OWN_BUF); }

/* No allocation, so it cannot longjmp: called on the line after the resource
 * is allocated, the resource is never bare across anything that can. */
void zu_owner_hold(SEXP xp, void *p) {
    R_SetExternalPtrAddr(xp, p);
}

/* Free now rather than at the next GC. The finalizer stays registered but the
 * address is NULL by then, so it runs as a no-op. */
void zu_extptr_release(SEXP xp) {
    if (TYPEOF(xp) == EXTPTRSXP) zu_free_payload(xp);
}
