# CLAUDE.md

<!-- markdownlint-disable-next-line MD013 -->
This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Shared conventions

The portfolio's shared rules are synced into `.claude/shared/` from
`pedrobtz/packages:claude/shared/`. Never edit them here. Where this file and
a shared file disagree, this file wins for this package.

@.claude/shared/workflow.md
@.claude/shared/r-package.md
@.claude/shared/ci.md
@.claude/shared/native-code.md
@.claude/shared/correctness.md
@.claude/shared/assurance.md

## What this is

`zujson` is an R package: **JSON in and out of ordinary R vectors and
lists**, backed by vendored yyjson sources and no system library. It exists
to serve `zuhttp`: parsing a response body and building a request body are
the two things it is designed around.

The framing that governs every design decision: **zujson is the JSON an HTTP
client needs, not a `jsonlite` replacement.** When a choice would add breadth
at the cost of a mapping you can hold in your head, it is the wrong choice.

The specification is
[.agents/design-zujson.md](.agents/design-zujson.md), and it outranks this
file. Its numbered sections §1–§15: §5–§6 the type mappings and why they are
what they are, §7 the error model, §8 the memory model, §9 depth limiting,
§13 NDJSON and the deferred streaming design, §14 acceptance criteria, §15
what is left. Read §15 before starting anything: its list is kept current
with strikethroughs.

## Current state

Version 0.1.0 is on CRAN, published 2026-10-02 (crandb, checked
2026-11-11). The default branch is `0.1.0.9000`, and its `NEWS.md`
development section is still empty.

The public API is `json_parse()`, `json_parse_raw()`, `json_parse_file()`,
`json_write()`, `json_write_raw()`, `json_validate()`, `json_parse_ndjson()`,
`json_write_ndjson()`, `json_write_ndjson_raw()` and `zujson_info()`. yyjson
0.12.0 is vendored under `src/vendor/yyjson/`. Before submission,
`devtools::check(cran = TRUE)` was 0/0/0, 1224 tests passed, green under
`shuffle = TRUE`, and both directions were clean under `gctorture(TRUE)`.

0.1.0 shipped, so do not plan these again: `simplify`'s named modes
(`"preserve"` the default, `"coerce"`, `"none"`, with `TRUE`/`FALSE` as exact
synonyms for the first and last); `data_frame = TRUE` turning an array of
objects into a data frame wherever one appears; native-code CI through the
reusable workflows in `pedrobtz/r-actions`; a number past double range
parsing as `Inf` rather than failing the read.

**One acceptance criterion is open, deliberately.** Design §14.9 names
`zuhttp`. The shapes it will use are covered in `test-roundtrip.R`, but the
criterion cannot close until there is something to integrate with. **What is
left in design §15 is blocked on that same thing**, not on effort here: a
public C API through `LinkingTo: zujson`, and the streaming object of §13.
Both are worth doing only once a real caller exists to shape them. The
design still calls `zuhttp` a skeleton; it now imports `zujson (>= 0.1.0)`
(local clone, 2026-11-11), so check whether that has unblocked them.

## Versions and dependents

The current version's parent issue is `#17` for `v0.1.1`. Sibling packages
that depend on this one (local clones, 2026-11-11): `zuhttp`, `zujose`,
`zudedup`, `zugeo` and `zulm` in `Imports`; `zuarrow`, `zudate`, `zumime`,
`zuproto` and `zutoml` in `Suggests`. A mapping change after 0.1.0 is a
breaking change for all of them.

## Commands

The everyday `devtools` commands are in `.claude/shared/r-package.md`. This
package checks with `cran = TRUE`, target 0 errors, 0 warnings, 0 notes:

```sh
Rscript -e 'devtools::check(cran = TRUE)'
Rscript tools/sanitizer-exercise.R  # base R only; what native-checks.yaml runs
Rscript tools/jsontestsuite.R       # nst/JSONTestSuite; needs network once
Rscript tools/vendor-yyjson.R       # refresh src/vendor/yyjson/
```

Both test scripts in `tools/` call `library(zujson)`, so they run against an
**installed** package, not `load_all()`. `JSONTESTSUITE_DIR=<checkout>`
skips the download.

Offline, `check()` emits a spurious `checking for future file timestamps ...
NOTE`. Suppress it to see the real result:

```sh
Rscript -e 'devtools::check(
  env_vars = c("_R_CHECK_SYSTEM_CLOCK_" = "0"), cran = TRUE)'
```

PROTECT discipline has two CI jobs, `rchk` statically and blocking and
`gctorture` at step 100, but both run after the fact, so a C change is still
checked by hand first:

```sh
Rscript -e 'devtools::load_all(); gctorture(TRUE); <exercise both directions>'
```

**Do not run `devtools::document()` with an older roxygen2 than
`Config/roxygen2/version` in DESCRIPTION.** A downgrade silently rewrites
`man/` and adds a `RoxygenNote` field; check `git diff DESCRIPTION man/`
afterwards and revert anything that is not your change.

`-pedantic` builds emit one warning from R's own `R_ext/Boolean.h`
(`enum :int` is a C23 extension). It is not ours and not yyjson's.

## Architecture

```text
R API (json_*)            R/{parse,write,ndjson,info,utils}.R
        |
.Call boundary            src/init.c
        |
   zu_parse.c  zu_write.c        zu_cond.c: conditions + memory ownership
        \          /
        vendored yyjson
```

**Two mappings, both stated in full in `?json_parse` and `?json_write`, both
derived in design §5–§6.** Parsing is *type-preserving*, not coercing:
`[1,"a"]` is a list, never `c("1","a")`. Serializing has two rules: a fully
named vector or list is an object and anything else is an array; a length-1
atomic vector unboxes unless `I()`-wrapped.

**Every documented mapping row has a test.** The tables in the roxygen, the
design doc and the test files are the same table three times; changing one
means changing all three.

### Naming

| layer | prefix |
| --- | --- |
| R exports | `json_` (plus `zujson_info()`) |
| R internals | `zu_` |
| C internals | `zu_` |
| `.Call` entry points | `zujson_` |

`json_parse` / `json_write` mirrors `zuxml`'s `xml_parse` / `xml_write` so
the family reads consistently from `zuhttp`.

NDJSON lives in `zu_parse.c` and `zu_write.c` next to the single-document
code rather than in its own file, so the static helpers (`zu_to_sexp`,
`zu_from_sexp`, `ZUJSON_READ_FLAGS`, `zu_df_plan`) stay private to their
translation unit. Splitting it out would mean exporting all four through the
internal header for one caller.

**Adding a C source file means editing `OBJECTS` in `src/Makevars` by hand**
(and `Makevars.win`, which is a copy). R auto-compiles only `src/*.c`,
yyjson lives in a subdirectory, and a `$(wildcard)` would force
`SystemRequirements: GNU make`. A file that is not in `OBJECTS` is silently
not built.

## Invariants that are easy to break

- **Anything holding heap state across a longjmp must be owned by R.**
  `zu_stop()`, `R_CheckUserInterrupt()` and every R allocator jump straight
  past a `free()`. The `yyjson_doc`, the `yyjson_mut_doc` and yyjson's output
  buffer are each owned by a finalized external pointer (`zu_owner_*` in
  `src/zu_cond.c`) that is made *before* the resource exists: owner, then
  allocate, then `zu_owner_hold()` on the next line, which allocates nothing.
  Making the owner after the resource was itself the first thing that could
  jump, three R allocations with the resource bare (#52): keep that order at
  every new call site. Owners are released eagerly on the success path. This is why no C function here has an error
  cleanup path, and why `zu_stop()` is safe to call from anywhere in either
  recursion. Finalizers clear the address before freeing, which is what makes
  eager release and a later GC pass mutually safe.
- **Depth counts containers, not values.** The root container is level 1; a
  scalar inside it is not a level of its own. Check where a container is
  *built*, not on entry to every value: the obvious version makes the two
  directions disagree by one, and the parser's atomic-array shortcut hides
  it. `nested_json()`/`nested_list()` in `helper-expect.R` are what pin this
  down.
- **`zu_mkchar()` is the only place a CHARSXP is made, and it must stay that
  way.** Both guards live there, the `INT_MAX` length check and the
  embedded-NUL check, so string values and object keys cannot drift apart.
  The NUL one is not theoretical: `"\u0000"` is valid JSON, and letting it
  reach `Rf_mkCharLenCE` raises a bare `simpleError` from the R internals
  that escapes the `zujson_error` contract entirely. That is the single most
  important thing not to regress, because `zuhttp`'s error handling is built
  on that contract.
- **A data frame emits two container levels and must be charged for both.**
  It is the only value that does. Charging it one lets `json_write()` emit
  JSON that `json_parse()` then rejects: output the package will not read
  back, which is the worst bug shape available here. Both halves were once
  off by one in *opposite* directions, so test the two things that actually
  catch it: parsing, that the row objects are charged even though they never
  reach `zu_to_sexp()` (`zu_arr_df()` checks `depth + 1` itself and hands
  cells `depth + 2`); writing, that a *cell* holding a container is charged
  once and not twice (`zu_df_row()` passes its own level to `zu_w_elt()`,
  which adds the level itself). A frame nested inside lists is charged by the
  ordinary list recursion and stays correct either way, so it tests nothing
  here; the case that matters is a nested value in a cell. `test-write.R` and
  `test-parse.R` pin both.
- **The cell budget is per document, not per frame.** `zu_df_left` is reset
  from the call's budget by `zu_finish()` and by the NDJSON driver (once per
  body), and each frame is charged as soon as its columns are known, before
  its cells are built, so a frame nested in a cell draws on what its parent
  left. Do not go back to handing each frame `df`: forty frames each under the
  cap then built forty times it.
- **The key index hash is seeded per call** (`zu_hash_reseed()` beside the
  budget reset) and finished with a full 64-bit mix. Unseeded FNV-1a let a
  body choose colliding keys; the seed is what makes the "linear" claim below
  hold for adversarial input, not only for typical input. Column order is by
  first appearance, never by hash, so the seed changes no result.
- **A data frame's size comes from the union of the keys, not from the
  input.** Records that share no keys ask for one column per record, so 72 kB
  of JSON becomes a 5000 x 5000 frame. `ZUJSON_MAX_DF_CELLS` (5e7, the
  default) caps rows x columns and `zujson_limit_error` fires as the
  offending column appears, before the allocation. A body-size limit upstream
  cannot replace it, since the growth is quadratic in the body, and leaving
  it uncapped degrades to R's allocator raising a bare `simpleError`. It is
  the one limit here that is settable, through
  `options(zujson.max_df_cells = )`: unlike the depth cap it is a budget, not
  a property of the C stack.
  - **The option is resolved in R and threaded to C in place of the
    `data_frame` flag.** `df` is no longer a boolean but a cell budget where
    0 means off, so the recursion carries one value instead of two that must
    agree. `Inf` is refused in R, since a number larger than any frame that
    could be built says the same thing without asking C to convert something
    no integer type has a value for.
  - **Anything finite but enormous is clamped twice.** First in
    `zu_df_cells()`, against the `max_xlen` field `zujson_build_info()`
    carries (`R_XLEN_T_MAX` is `int` on a build without long vectors, so R
    cannot restate it), which is also what makes `zujson_info()` report the
    limit the parser will enforce rather than the one that was asked for.
    Again at the cast in `zu_df_arg()`, because an unclamped conversion past
    that range is undefined rather than merely wrong: it saturates on arm64
    but yields `INT64_MIN` on x86-64, leaving data frames on with a negative
    budget. Neither clamp is redundant, and a test that only asserts the
    result is finite does not catch either one going.
  - The two costs that are not capped are kept linear instead: the key union
    goes through the open-addressed index in `zu_collect_keys()`, and the
    cells are filled by one scattering pass, never by asking each record for
    each key, which is a scan of that record per cell and was 69 s on a
    4000 x 2000 frame.
- **`zu_w_str()` is the only place a CHARSXP's bytes are read**, as
  `zu_mkchar()` is the only place one is made. Both refuse `CE_BYTES`,
  because `Rf_translateCharUTF8()` answers an unknown encoding with a bare
  `simpleError` from the R internals: the same contract break as the NUL
  case, from the other direction. R-side argument checks
  (`zu_check_bytes()`) catch it on the input paths.
- **NDJSON framing rests on one fact: a raw newline cannot appear inside a
  JSON string.** That is why splitting on `\n` can never cut a record, and
  why `json_write_ndjson()` has no `pretty` argument: indented JSON contains
  newlines, so pretty-printed NDJSON is corrupt, not prettier. Do not add
  one. The reader is also deliberately stricter than
  `YYJSON_READ_STOP_WHEN_DONE`, which would accept newline-free concatenated
  JSON the content type does not promise.
- **The data frame plan's SEXPs are held in a keeper the caller allocates and
  protects**, and `zu_df_plan_init()` stores each into it on the line after
  it obtains it. Do not go back to protecting inside that function and
  unprotecting in the caller: the balance is then split across functions,
  which is what `rchk` reported as unprotecting more than was protected in
  *both* callers, and it is blocking now. The names attribute goes in the
  keeper for the same reason: it is reachable from the frame and so was never
  actually at risk, but reachability through an attribute is not something a
  static checker can see, and a protection nobody can verify is worth less
  than the stack slot it saves. It also retired the `PROTECT(R_NilValue)`
  that used to keep `zujson_write_lines()`'s two branches counting alike.
  `zu_from_sexp()` protects its own `nms` and `levels` on the stack for the
  same reason, and all three of its exits owe the matching `UNPROTECT(2)`:
  the unbox one after the `zu_w_elt()` call, not before it.
- **`zu_df_plan`/`zu_df_row()` are shared by `json_write()` and NDJSON** so
  the two cannot disagree about how a data frame row becomes an object. A
  change to row shape belongs there, not in either caller.
- **`ZUJSON_READ_FLAGS` is shared by every read path** so `json_parse()` and
  `json_validate()` cannot disagree about what the *reader* accepts. Add a
  read flag there or not at all. They still disagree where the R-tree builder
  imposes a limit the reader does not, which is deliberate and is exactly two
  classes: a string R cannot hold (NUL escape, or over `INT_MAX` bytes) and
  nesting past the depth cap. `json_validate()` returns `TRUE` for both. Do
  not "fix" the depth one: yyjson's reader is iterative and has no notion of
  depth, so validation is safe at any depth; the cap protects the tree
  builder, which validation never runs, and enforcing it would mean walking
  the document on every call to return `FALSE` for something RFC 8259 §9
  calls valid. NDJSON lines are read with `ZUJSON_NDJSON_LINE_FLAGS`, which is
  this set minus `ALLOW_BOM` (the body's one BOM is stripped before framing):
  a restriction of the shared set, never an addition to it.
- **`NA_INTEGER == INT_MIN`.** A JSON `-2147483648` must promote to `double`,
  or it comes back as `NA`. Same for anything above `INT_MAX`.
- **A number past double range is `Inf`, not a parse failure.** RFC 8259 caps
  no magnitude, so `1e309` is valid JSON; rejecting it would let one absurd
  value make a whole response body unreadable. `YYJSON_READ_BIGNUM_AS_RAW`
  delivers the token as `YYJSON_TYPE_RAW` and `zu_raw_dbl()` converts it: a
  finite one (an integer wider than uint64) by yyjson's correctly rounded
  `yyjson_read_number()`, and only one past double range by `R_strtod`, whose
  rounding is not correct and once put 1 in 1000 such integers 1 ulp off. Two
  traps: the overflow path must be **`R_strtod`, not `strtod`**, which reads the decimal
  point in the current C locale and would turn `1.5e400` into `1` under a
  comma-decimal locale; and **not `ALLOW_INF_AND_NAN`**, which also accepts
  the bare `Infinity`/`NaN` literals that are not JSON, and since the flags
  are shared, `json_validate()` would start calling those documents valid.
  Every "is this a number?" test goes through `zu_is_num()` so `NUM` and
  `RAW` cannot drift apart.
- **Whole doubles are written without a decimal point.** R has no integer
  literal, so `1` is a double and yyjson's real writer emits `1.0`, which a
  schema expecting an integer rejects. The bound is **int64's range, not
  2^53**: a double that is already whole *is* that integer at any magnitude,
  so converting is lossless; 2^53 is where consecutive integers stop being
  representable, which is a different question and the wrong test.
- **Every string crossing into JSON goes through `zu_utf8()`**, never
  `Rf_translateCharUTF8()` directly, wrapped in `vmaxget`/`vmaxset` so a long
  character vector does not accumulate one R_alloc buffer per element.
  `Rf_translateCharUTF8()` never fails: it rewrites a byte it cannot convert as
  the text `<xx>`, which sent `"caf<c3><a9>"` under the C locale and let
  invalid UTF-8 validate as `TRUE` (#42). `zu_utf8()` passes UTF-8 and ASCII
  through, refuses latin1's five undefined bytes, converts native text with a
  checked `Riconv`, and returns `NULL` on failure for the caller to raise. The
  same applies to the character inputs of `json_parse()`,
  `json_parse_ndjson()` and `json_validate()`. Every string coming back is
  marked `CE_UTF8`, accurate only because yyjson's UTF-8 validation is on.
- **`json_parse_file()` reads its bytes in R** (`zu_read_file()`) and parses
  them through `zujson_parse_raw`; there is no C file entry point. R opens the
  path in the encoding its own file functions use. Handing C a translated path
  opened the wrong file under the C locale (#50); do not move the read back.
- **`I()` is checked before the class dispatch**, because `I()` prepends to
  the class vector.
- **Partial names produce an array, not `{"a":1,"":2}`.** `zu_fully_named()`
  is the one place that decides object-vs-array; it requires every name
  present, non-`NA` and non-empty.
- **Conditions are built in C, not re-signalled in R.** `zu_stop()` attaches
  the class where the cause is known. R-side argument checks raise the same
  4-element class vector so the boundary is invisible to a caller.
  Everything inherits `zujson_error`, for example `zujson_depth_error`.
- **`json_parse()` takes raw as well as character** so `zuhttp` never needs
  a conversion step, and `json_write_raw()` returns bytes for the same
  reason. Do not let either direction acquire a mandatory string detour.

## Editing rules

**Prose is en-GB**, declared as `Language: en-GB` in DESCRIPTION, which is
what `R CMD check` spell-checks against. `Serialization` in the Title is
Oxford spelling and consistent with it. Domain terms live in
`inst/WORDLIST`; regenerate with `spelling::update_wordlist()` rather than
editing by hand, and do not Americanise prose to silence the checker.

## Testing

- **`expect_json()` asserts on exact output bytes**: that is what a
  serializer is for. **`expect_roundtrip()` uses `identical()`**, so an
  integer quietly becoming a double fails.
- Helpers in `helper-expect.R`: `expect_json()`, `expect_roundtrip()`,
  `nested_json()`, `nested_list()`.
- `test-conditions.R` interleaves failing and succeeding calls fifty times;
  that is what would catch the memory model above being wrong.
- **`test-interop-jsonlite.R` uses jsonlite as an oracle, not as a suite to
  port.** jsonlite's own tests are self-referential: 60 of 77 `fromJSON()`
  calls are `fromJSON(toJSON(x))` roundtrips, and the `toJSON()` side is
  saturated with arguments this package deliberately lacks, so there is
  nothing to import. The file instead pins two tables over JSON *text*: where
  the two packages agree, and a **divergence table** where they are meant not
  to (`[]` → `logical(0)`, `preserve` on `[1,"a"]`, no matrix detection, data
  frames only on request). The divergence table is the valuable half: it
  fires if a change makes zujson quietly more jsonlite-like than design §5
  says. Both tables assert zujson's own expected value, so a jsonlite change
  fails with the blame in the right place. jsonlite is `Suggests` only and
  every block opens with `skip_if_not_installed("jsonlite")`.
- **External conformance is `tools/jsontestsuite.R`**, against a pinned
  commit of `nst/JSONTestSuite`: 95/95 must-accept and 188/188 must-reject,
  with the implementation-defined set at 12 accepted / 23 rejected (all 23
  invalid UTF-8 or lone surrogates, which yyjson refuses because validation
  is on). That `i_` count is recorded in the script as a baseline and flagged
  when it moves, because moving it is how you tell a read-flag change apart
  from a conformance regression: enabling `BIGNUM_AS_RAW` moved exactly five
  `i_` files and no `y_`/`n_` answer. The script also re-derives the
  `json_parse()`/`json_validate()` divergence from the outside and finds
  exactly the two NUL-escape files, which is independent confirmation of the
  `zu_mkchar()` invariant above. It does **not** exercise the depth
  divergence, and cannot: the suite's only deep files are 500 levels (under
  the cap, so both accept) and 100,000 unterminated brackets (so both
  reject). `test-validate.R` covers that one.
- **A new C error path belongs in `tools/sanitizer-exercise.R` as well as in
  testthat.** That script uses nothing but base R and spends most of its
  effort on the error paths, where an R error longjmps past the explicit
  free. `test-fuzz.R` runs a smaller version of the same idea on every test
  run.
- **The suite must stay serial, and that is a CI constraint rather than a
  preference.** `Config/testthat/parallel` was removed from DESCRIPTION
  because testthat's parallel mode runs the test files in `callr`
  subprocesses, and neither `gctorture2()` nor `R CMD check --use-valgrind`
  follows a subprocess: the gctorture job would torture a parent that never
  enters this package's C at all, and valgrind would instrument the same one.
  Both would go green having checked nothing, which is the failure mode those
  jobs exist to rule out. It costs nothing: measured at 4.0 s parallel
  against 3.9 s serial, on two test processes.
- **CRAN budget: the suite finishes in a few seconds.** Keep it there.

### Definition of done, in addition to the shared one

- `devtools::check(cran = TRUE)` clean (0/0/0).
- `gctorture(TRUE)` clean over both directions if C changed, because
  everything in `native-checks.yaml` runs after the fact.
- New public surface has roxygen docs with runnable examples.
- Any mapping change updated in all three places it is written down:
  roxygen, `.agents/design-zujson.md`, tests.

## Continuous integration

- `R-CMD-check.yaml` calls r-actions' `r-cmd-check.yml@v1`.
- `coverage.yaml` calls `coverage.yml`, pinned to a commit (v1.18.0).
- `native-checks.yaml` calls r-actions' `sanitizers.yml` (UBSan over the
  suite, and `tools/sanitizer-exercise.R` under clang-asan and gcc-asan),
  `valgrind.yml`, `lto.yml`, `gctorture.yml` at step 100, `rchk.yml`
  (blocking, `fail-on-findings: true`), `vendor.yml` (the vendored-source
  guard) and `cran-special.yml`. It also has its own `fuzz` job, which fuzzes
  the parser through the R API with `ZUJSON_FUZZ=50000`.
- gctorture runs at step 100 rather than 20 because step 20 was not measured
  to completion: 3.9 s untortured, 86 s at step 500 and 473 s at step 100.
  The reasoning is in the comment above the job; re-measure rather than
  extrapolate if this is revisited.
- `pkgdown.yaml` (own, from r-lib/actions' example) builds and deploys the
  site.

## Vendored native code

yyjson 0.12.0, MIT (`src/vendor/yyjson/LICENSE`), from
<https://github.com/ibireme/yyjson> release tags. `src/vendor/yyjson/` is
yyjson verbatim and is **never edited in place**; there are no local patches.
Refresh with `Rscript tools/vendor-yyjson.R`, review the diff, and commit it
with the version bump in that script. Nothing is disabled at compile time:
UTF-8 validation and the reader's number handling are exactly what make it
safe to point at an untrusted body.

The version is asserted in two places that must move together:
`tools/vendor-yyjson.R` and the literal in `test-info.R`. The test carries a
literal because `tools/` is not installed. `vendor.yml`'s `must-update`
enforces this on pull requests.

There is no `src/vendor/PROVENANCE` and no checksum manifest yet, so
`vendor.yml` skips tree verification and only the pull-request guard runs.

Object files must never reach the tarball: `.Rbuildignore` excludes
`src/**/*.o`, `*.o.tmp` and `*.so`/`*.dll`. A stale `.o` is otherwise shipped
*and* relinked in preference to a fresh compile.
