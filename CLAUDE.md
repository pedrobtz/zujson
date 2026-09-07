# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

`zujson` is an R package: **JSON in and out of ordinary R vectors and lists**, backed by vendored yyjson sources and no system library. It exists to serve `zuhttp` — parsing a response body and building a request body are the two things it is designed around.

The framing that governs every design decision: **zujson is the JSON an HTTP client needs, not a `jsonlite` replacement.** When a choice would add breadth at the cost of a mapping you can hold in your head, it is the wrong choice.

## Current state

**v1 is complete (version 0.1.0).** yyjson 0.12.0 is vendored under `src/vendor/yyjson/`, and the public API is `json_parse()`, `json_parse_raw()`, `json_parse_file()`, `json_write()`, `json_write_raw()`, `json_validate()`, `zujson_info()`. `devtools::check(cran = TRUE)` is 0/0/0; 391 tests pass, green under `shuffle = TRUE`, and both directions are clean under `gctorture(TRUE)`.

**One acceptance criterion is open, deliberately.** Design §13.9 names `zuhttp`, which is still an empty skeleton in its own repo. The shapes it will use are covered in `test-roundtrip.R`, but the criterion cannot close until there is something to integrate with.

**Phase 2 is design §14**, not more of §13.9: a `coerce` simplification mode, data frame simplification on parse, then a public C API through `LinkingTo: zujson` once a caller actually exists.

- `design-zujson.md` — numbered sections §1–§14 (§5–§6 the type mappings and why they are what they are, §7 the error model, §8 the memory model, §9 depth limiting, §13 acceptance criteria).

## Commands

```sh
Rscript -e 'devtools::document()'                     # roxygen -> NAMESPACE + man/
Rscript -e 'devtools::load_all()'                     # compile + load
Rscript -e 'devtools::test()'
Rscript -e 'devtools::test(shuffle = TRUE)'           # required before calling anything done
Rscript -e 'devtools::check(cran = TRUE)'             # target: 0 errors, 0 warnings, 0 notes
Rscript -e 'devtools::test(filter = "write")'         # tests/testthat/test-write.R
```

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
R API (json_*)            R/{parse,write,info,utils}.R
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

**Adding a C source file means editing `OBJECTS` in `src/Makevars` by hand** (and `Makevars.win`, which is a copy). R auto-compiles only `src/*.c`, yyjson lives in a subdirectory, and a `$(wildcard)` would force `SystemRequirements: GNU make`. A file that is not in `OBJECTS` is silently not built.

## Invariants that are easy to break

- **Anything holding heap state across a longjmp must be owned by R.** `zu_stop()`, `R_CheckUserInterrupt()` and every R allocator jump straight past a `free()`. The `yyjson_doc`, the `yyjson_mut_doc` and yyjson's output buffer are each handed to a finalized external pointer (`zu_extptr_own_*` in `src/zu_cond.c`) *before* the first thing that can jump, and released eagerly on the success path. This is why no C function here has an error cleanup path, and why `zu_stop()` is safe to call from anywhere in either recursion. Finalizers clear the address before freeing, which is what makes eager release and a later GC pass mutually safe.
- **Depth counts containers, not values.** The root container is level 1; a scalar inside it is not a level of its own. Check where a container is *built*, not on entry to every value — the obvious version makes the two directions disagree by one, and the parser's atomic-array shortcut hides it. `nested_json()`/`nested_list()` in `helper-expect.R` are what pin this down.
- **`NA_INTEGER == INT_MIN`.** A JSON `-2147483648` must promote to `double`, or it comes back as `NA`. Same for anything above `INT_MAX`.
- **Whole doubles are written without a decimal point.** R has no integer literal, so `1` is a double and yyjson's real writer emits `1.0`, which a schema expecting an integer rejects. The ±2^53 bound is where doubles stop representing consecutive integers exactly.
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
- **CRAN budget: the suite finishes in a few seconds.** Keep it there.

Deliberately outside testthat, for phase 2: ASan/UBSan and valgrind jobs, `rchk` for PROTECT discipline, and parser fuzzing. Until those exist, `gctorture(TRUE)` over both directions is the check that a change to the C layer has to pass.

## Definition of done for any change

`devtools::document()` and `devtools::check(cran = TRUE)` clean (0/0/0); `devtools::test(shuffle = TRUE)` green; `gctorture(TRUE)` clean if C changed; new public surface has roxygen docs with runnable examples; any mapping change updated in all three places it is written down (roxygen, `design-zujson.md`, tests).
