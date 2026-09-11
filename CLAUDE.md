# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

`zujson` is an R package: **JSON in and out of ordinary R vectors and lists**, backed by vendored yyjson sources and no system library. It exists to serve `zuhttp` — parsing a response body and building a request body are the two things it is designed around.

The framing that governs every design decision: **zujson is the JSON an HTTP client needs, not a `jsonlite` replacement.** When a choice would add breadth at the cost of a mapping you can hold in your head, it is the wrong choice.

## Current state

**Version is `0.0.0.9000`: never released, no tags, not on CRAN.** The earlier `0.1.0` was a number in DESCRIPTION, not a release, and NEWS.md now says so. Two consequences: there is no released version to stay compatible with, so a mapping may still change if the design argues for it; and NEWS.md stays a single section until there is a real release, at which point its heading and DESCRIPTION `Version` move together. **That heading must carry the version number** — `# zujson 0.0.0.9000 (development version)`. R CMD check parses NEWS.md for `# <pkg> <version>` and reports `Problems with news in 'NEWS.md': No news entries found` as a NOTE if no heading has one, so the bare usethis-style `# zujson (development version)` costs a clean check once it is the only heading. yyjson 0.12.0 is vendored under `src/vendor/yyjson/`, and the public API is `json_parse()`, `json_parse_raw()`, `json_parse_file()`, `json_write()`, `json_write_raw()`, `json_validate()`, `json_parse_ndjson()`, `json_write_ndjson()`, `json_write_ndjson_raw()`, `zujson_info()`. `devtools::check(cran = TRUE)` is 0/0/0; 1157 tests pass, green under `shuffle = TRUE`, and both directions are clean under `gctorture(TRUE)`.

**Landed since 0.1.0, so do not plan them again:** `simplify` gained named modes (`"preserve"` the default, `"coerce"`, `"none"`, with `TRUE`/`FALSE` as exact synonyms for the first and last); `data_frame = TRUE` turns an array of objects into a data frame wherever one appears; sanitizer and fuzzing CI exists (`hardening.yaml`, `tools/sanitizer-exercise.R`, `test-fuzz.R`); a number past double range parses as `Inf` rather than failing the read.

**One acceptance criterion is open, deliberately.** Design §14.9 names `zuhttp`, which is still an empty skeleton in its own repo. The shapes it will use are covered in `test-roundtrip.R`, but the criterion cannot close until there is something to integrate with.

**What is left in design §15 is blocked on that same thing**, not on effort here: a public C API through `LinkingTo: zujson`, and the streaming object of §13. Both are worth doing only once a real caller exists to shape them. Read §15 before starting anything — its list is kept current with strikethroughs.

**Do not run `devtools::document()` with an older roxygen2 than `Config/roxygen2/version` in DESCRIPTION.** A downgrade silently rewrites `man/` and adds a `RoxygenNote` field; check `git diff DESCRIPTION man/` afterwards and revert anything that is not your change.

- `.agents/design-zujson.md` — numbered sections §1–§15 (§5–§6 the type mappings and why they are what they are, §7 the error model, §8 the memory model, §9 depth limiting, §13 NDJSON and the deferred streaming design, §14 acceptance criteria).

## Commands

```sh
Rscript -e 'devtools::document()'                     # roxygen -> NAMESPACE + man/
Rscript -e 'devtools::load_all()'                     # compile + load
Rscript -e 'devtools::test()'
Rscript -e 'devtools::test(shuffle = TRUE)'           # required before calling anything done
Rscript -e 'devtools::check(cran = TRUE)'             # target: 0 errors, 0 warnings, 0 notes
Rscript -e 'devtools::test(filter = "write")'         # tests/testthat/test-write.R
Rscript tools/sanitizer-exercise.R                    # base R only; what hardening.yaml runs
Rscript tools/jsontestsuite.R                         # nst/JSONTestSuite conformance; needs network once
```

Both `tools/` scripts call `library(zujson)`, so they run against an **installed** package, not `load_all()`. `JSONTESTSUITE_DIR=<checkout>` skips the download.

Offline, `check()` emits a spurious `checking for future file timestamps ... NOTE`. Suppress it to see the real result:

```sh
Rscript -e 'devtools::check(env_vars = c("_R_CHECK_SYSTEM_CLOCK_" = "0"), cran = TRUE)'
```

PROTECT discipline is checked by hand, since there is no CI job for it yet:

```sh
Rscript -e 'devtools::load_all(); gctorture(TRUE); <exercise both directions>'
```

`-pedantic` builds emit one warning from R's own `R_ext/Boolean.h` (`enum :int` is a C23 extension). It is not ours and not yyjson's.

### Vendored sources

`src/vendor/yyjson/` is yyjson 0.12.0 verbatim and is **never edited in place**. Refresh with `Rscript tools/vendor-yyjson.R`, review the diff, and commit it with the version bump in that script. Nothing is disabled at compile time — UTF-8 validation and the reader's number handling are exactly what make it safe to point at an untrusted body.

The version is asserted in two places that must move together: `tools/vendor-yyjson.R` and the literal in `test-info.R`. The test carries a literal because `tools/` is not installed.

Object files must never reach the tarball — `.Rbuildignore` excludes `src/**/*.o`, `*.o.tmp` and `*.so`/`*.dll`. A stale `.o` is otherwise shipped *and* relinked in preference to a fresh compile.

## Architecture

```
R API (json_*)            R/{parse,write,ndjson,info,utils}.R
        |
.Call boundary            src/init.c
        |
   zu_parse.c  zu_write.c        zu_cond.c: conditions + memory ownership
        \          /
        vendored yyjson
```

**Two mappings, both stated in full in `?json_parse` and `?json_write`, both derived in design §5–§6.** Parsing is *type-preserving*, not coercing: `[1,"a"]` is a list, never `c("1","a")`. Serializing has two rules — a fully named vector or list is an object and anything else is an array; a length-1 atomic vector unboxes unless `I()`-wrapped.

**Every documented mapping row has a test.** The tables in the roxygen, the design doc and the test files are the same table three times; changing one means changing all three.

### Naming

| layer | prefix |
| --- | --- |
| R exports | `json_` (plus `zujson_info()`) |
| R internals | `zu_` |
| C internals | `zu_` |
| `.Call` entry points | `zujson_` |

`json_parse` / `json_write` mirrors `zuxml`'s `xml_parse` / `xml_write` so the family reads consistently from `zuhttp`.

NDJSON lives in `zu_parse.c` and `zu_write.c` next to the single-document code rather than in its own file, so the static helpers (`zu_to_sexp`, `zu_from_sexp`, `ZUJSON_READ_FLAGS`, `zu_df_plan`) stay private to their translation unit. Splitting it out would mean exporting all four through the internal header for one caller.

**Adding a C source file means editing `OBJECTS` in `src/Makevars` by hand** (and `Makevars.win`, which is a copy). R auto-compiles only `src/*.c`, yyjson lives in a subdirectory, and a `$(wildcard)` would force `SystemRequirements: GNU make`. A file that is not in `OBJECTS` is silently not built.

## Invariants that are easy to break

- **Anything holding heap state across a longjmp must be owned by R.** `zu_stop()`, `R_CheckUserInterrupt()` and every R allocator jump straight past a `free()`. The `yyjson_doc`, the `yyjson_mut_doc` and yyjson's output buffer are each handed to a finalized external pointer (`zu_extptr_own_*` in `src/zu_cond.c`) *before* the first thing that can jump, and released eagerly on the success path. This is why no C function here has an error cleanup path, and why `zu_stop()` is safe to call from anywhere in either recursion. Finalizers clear the address before freeing, which is what makes eager release and a later GC pass mutually safe.
- **Depth counts containers, not values.** The root container is level 1; a scalar inside it is not a level of its own. Check where a container is *built*, not on entry to every value — the obvious version makes the two directions disagree by one, and the parser's atomic-array shortcut hides it. `nested_json()`/`nested_list()` in `helper-expect.R` are what pin this down.
- **`zu_mkchar()` is the only place a CHARSXP is made, and it must stay that way.** Both guards live there — the `INT_MAX` length check and the embedded-NUL check — so string values and object keys cannot drift apart. The NUL one is not theoretical: `"\u0000"` is valid JSON, and letting it reach `Rf_mkCharLenCE` raises a bare `simpleError` from the R internals that escapes the `zujson_error` contract entirely. That is the single most important thing not to regress, because `zuhttp`'s error handling is built on that contract.
- **A data frame emits two container levels and must be charged for both.** It is the only value that does. Charging it one lets `json_write()` emit JSON that `json_parse()` then rejects — output the package will not read back, which is the worst bug shape available here. `test-write.R` pins both sides of the boundary.
- **NDJSON framing rests on one fact: a raw newline cannot appear inside a JSON string.** That is why splitting on `\n` can never cut a record, and why `json_write_ndjson()` has no `pretty` argument — indented JSON contains newlines, so pretty-printed NDJSON is corrupt, not prettier. Do not add one. The reader is also deliberately stricter than `YYJSON_READ_STOP_WHEN_DONE`, which would accept newline-free concatenated JSON the content type does not promise.
- **`zu_df_plan`/`zu_df_row()` are shared by `json_write()` and NDJSON** so the two cannot disagree about how a data frame row becomes an object. A change to row shape belongs there, not in either caller.
- **`ZUJSON_READ_FLAGS` is shared by every read path** so `json_parse()` and `json_validate()` cannot disagree about what parses. Add a read flag there or not at all.
- **`NA_INTEGER == INT_MIN`.** A JSON `-2147483648` must promote to `double`, or it comes back as `NA`. Same for anything above `INT_MAX`.
- **A number past double range is `Inf`, not a parse failure.** RFC 8259 caps no magnitude, so `1e309` is valid JSON; rejecting it would let one absurd value make a whole response body unreadable. `YYJSON_READ_BIGNUM_AS_RAW` delivers the token as `YYJSON_TYPE_RAW` and `zu_raw_dbl()` converts it. Two traps: it must be **`R_strtod`, not `strtod`**, which reads the decimal point in the current C locale and would turn `1.5e400` into `1` under a comma-decimal locale; and **not `ALLOW_INF_AND_NAN`**, which also accepts the bare `Infinity`/`NaN` literals that are not JSON — and since the flags are shared, `json_validate()` would start calling those documents valid. Every "is this a number?" test goes through `zu_is_num()` so `NUM` and `RAW` cannot drift apart.
- **Whole doubles are written without a decimal point.** R has no integer literal, so `1` is a double and yyjson's real writer emits `1.0`, which a schema expecting an integer rejects. The bound is **int64's range, not 2^53** — a double that is already whole *is* that integer at any magnitude, so converting is lossless; 2^53 is where consecutive integers stop being representable, which is a different question and the wrong test.
- **Every string crossing into JSON goes through `Rf_translateCharUTF8`**, wrapped in `vmaxget`/`vmaxset` so a long character vector does not accumulate one R_alloc buffer per element. Every string coming back is marked `CE_UTF8` — accurate only because yyjson's UTF-8 validation is on.
- **`I()` is checked before the class dispatch**, because `I()` prepends to the class vector.
- **Partial names produce an array, not `{"a":1,"":2}`.** `zu_fully_named()` is the one place that decides object-vs-array; it requires every name present, non-`NA` and non-empty.
- **Conditions are built in C, not re-signalled in R.** `zu_stop()` attaches the class where the cause is known. R-side argument checks raise the same 4-element class vector so the boundary is invisible to a caller. Everything inherits `zujson_error`.
- **`json_parse()` takes raw as well as character** so `zuhttp` never needs a conversion step, and `json_write_raw()` returns bytes for the same reason. Do not let either direction acquire a mandatory string detour.

## Testing conventions

- **Self-sufficient.** Every test builds its own inputs inside the `test_that()` block; no file-scope objects.
- **Assert on condition classes, never message text.** `expect_error(..., class = "zujson_depth_error")`.
- **Order independence.** `devtools::test(shuffle = TRUE)` is part of the definition of done.
- **`expect_json()` asserts on exact output bytes** — that is what a serializer is for. **`expect_roundtrip()` uses `identical()`**, so an integer quietly becoming a double fails.
- Helpers in `helper-expect.R`: `expect_json()`, `expect_roundtrip()`, `nested_json()`, `nested_list()`.
- `test-conditions.R` interleaves failing and succeeding calls fifty times; that is what would catch the memory model above being wrong.
- **`test-interop-jsonlite.R` uses jsonlite as an oracle, not as a suite to port.** jsonlite's own tests are self-referential — 60 of 77 `fromJSON()` calls are `fromJSON(toJSON(x))` roundtrips, and the `toJSON()` side is saturated with arguments this package deliberately lacks — so there is nothing to import. The file instead pins two tables over JSON *text*: where the two packages agree, and a **divergence table** where they are meant not to (`[]` → `logical(0)`, `preserve` on `[1,"a"]`, no matrix detection, data frames only on request). The divergence table is the valuable half: it fires if a change makes zujson quietly more jsonlite-like than design §5 says. Both tables assert zujson's own expected value, so a jsonlite change fails with the blame in the right place. jsonlite is `Suggests` only and every block opens with `skip_if_not_installed("jsonlite")`.
- **CRAN budget: the suite finishes in a few seconds.** Keep it there.

Outside testthat, and now real: `.github/workflows/hardening.yaml` runs `tools/sanitizer-exercise.R` under clang-asan, clang-ubsan and gcc-asan and fuzzes the parser through the R API. That script uses nothing but base R and spends most of its effort on the error paths, where an R error longjmps past the explicit free — so **a new C error path belongs in it as well as in testthat.** `test-fuzz.R` runs a smaller version of the same idea on every test run.

**External conformance is `tools/jsontestsuite.R`**, against a pinned commit of `nst/JSONTestSuite`: 95/95 must-accept and 188/188 must-reject, with the implementation-defined set at 12 accepted / 23 rejected (all 23 invalid UTF-8 or lone surrogates, which yyjson refuses because validation is on). That `i_` count is recorded in the script as a baseline and flagged when it moves, because moving it is how you tell a read-flag change apart from a conformance regression — enabling `BIGNUM_AS_RAW` moved exactly five `i_` files and no `y_`/`n_` answer. The script also re-derives the `json_parse()`/`json_validate()` divergence from the outside and finds exactly the two NUL-escape files, which is independent confirmation of the `zu_mkchar()` invariant above.

Still missing: valgrind, and `rchk` for PROTECT discipline. Until those exist, `gctorture(TRUE)` over both directions is the check that a change to the C layer has to pass, and it is still required by the definition of done below — the sanitizers run in CI, after the fact.

## Definition of done for any change

`devtools::document()` and `devtools::check(cran = TRUE)` clean (0/0/0); `devtools::test(shuffle = TRUE)` green; `gctorture(TRUE)` clean if C changed; new public surface has roxygen docs with runnable examples; any mapping change updated in all three places it is written down (roxygen, `.agents/design-zujson.md`, tests).
