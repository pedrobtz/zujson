#include <stdarg.h>
#include <stdlib.h>
#include "zujson.h"

/* ---------------------------------------------------------------------------
 * Structured conditions
 *
 * Rf_error() would be simpler, but the test suite asserts on condition classes
 * rather than on message text, so wording can change without breaking forty
 * tests. Building the condition here rather than re-signalling in R keeps the
 * class attached to the place that knows what actually went wrong.
 * ------------------------------------------------------------------------- */

void zu_stop(const char *cls, const char *fmt, ...) {
    char msg[512];
    va_list ap;
    va_start(ap, fmt);
    vsnprintf(msg, sizeof(msg), fmt, ap);
    va_end(ap);

    const char *fields[] = {"message", "call", ""};
    SEXP cond = PROTECT(Rf_mkNamed(VECSXP, fields));
    SET_VECTOR_ELT(cond, 0, Rf_mkString(msg));
    SET_VECTOR_ELT(cond, 1, R_NilValue);

    SEXP klass = PROTECT(Rf_allocVector(STRSXP, 4));
    SET_STRING_ELT(klass, 0, Rf_mkChar(cls));
    SET_STRING_ELT(klass, 1, Rf_mkChar("zujson_error"));
    SET_STRING_ELT(klass, 2, Rf_mkChar("error"));
    SET_STRING_ELT(klass, 3, Rf_mkChar("condition"));
    Rf_setAttrib(cond, R_ClassSymbol, klass);

    SEXP call = PROTECT(Rf_lang2(Rf_install("stop"), cond));
    Rf_eval(call, R_BaseEnv);            /* longjmps out */

    UNPROTECT(3);                        /* not reached */
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
