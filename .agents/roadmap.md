# zujson roadmap

**Status:** accepted, 2026-11-13.
**Owner:** this package, with the design. Changing either is a pull request
here; the RFC in `pedrobtz/packages` only points to them.
**Covers:** 0.2.0 to 1.0.0, and what is left for after.
**Does not cover:** 0.1.1, which is in flight under #17.

This is the plan for taking zujson from "the JSON an HTTP client needs" to
the JSON library the whole `zu*` family builds on, with the features the best
libraries in Go, Python and Rust have. It was written from four inputs:

- the design, `.agents/design-zujson.md`, §15 and §13 in particular;
- what vendored yyjson 0.12.0 offers that the package does not use;
- how the sibling packages call zujson today (GitHub code search,
  2026-11-13), and what they work around;
- the feature sets of Go `encoding/json` and `json/v2`, Python `json` and
  `orjson`, Rust `serde_json`, and in R `jsonlite`, `yyjsonr` and
  `RcppSimdJson`.

Near versions are planned in detail. Later ones are planned to the stage,
with their oracles named, and are planned again when they are entered:
`pkg-roadmap` re-reads this file at the start of each version.

## The rule that makes breadth safe

The design's framing is "a mapping you can hold in your head". This roadmap
keeps it, by one rule:

> **The defaults are the one-page mapping, and they stop changing at 0.2.0.
> Everything after is opt-in: a new argument value, or a new function.**

Ten sibling packages depend on the mapping. So:

1. **0.2.0 is the last release that changes what a default call returns.**
   Every breaking decision still open goes there, or is dropped.
2. **A new option is a row in a table.** It lands in the roxygen, the design
   and the tests in one pull request, as the mapping rows do today.
3. **A new option never changes another option's meaning.** Where two
   interact, the pull request states which wins, and tests both orders.
4. **Nothing reaches R as a bare error.** Every new path raises a
   `zujson_error` subclass, and joins `tools/sanitizer-exercise.R`.
5. **A feature needs an oracle before it needs code.** Each stage names the
   conformance suite, reference implementation or round trip that knows the
   answer. A stage with no oracle is not ready to plan.
6. **Scope is JSON text and R values.** A second format (CBOR, MessagePack,
   TOML, YAML) is another package's. So is a domain mapping (GeoJSON,
   ProtoJSON, JOSE): zujson supplies the options those packages need, not the
   mapping itself.

## Design amendments made with this roadmap

The design listed as non-goals "a `jsonlite` replacement, JSON Pointer,
Patch, Schema, custom serializer dispatch". This roadmap plans Pointer, Patch
and a narrow serializer fallback, and leaves Schema to a separate package.
The design is amended in the same pull request:

- [x] The non-goals line is replaced, and design §16 "Growth after v1"
      records the rule above, the options pattern (Stage 2.2) and what moved.
- [x] Design §13, §14.9 and §15: `zuhttp` is released and imports
      `zujson (>= 0.1.0)`, so the stream and the C API are no longer blocked
      on a caller. §15's list is closed and points here.
- [x] `CLAUDE.md` links this file and says the package owns both documents.
- [ ] `lifecycle` joins the package's kinds in `.agents/assurance.md`, with
      an Objects table, in the pull request that exports the stream (Stage
      3.1). Not before: CI checks that file against what exists.

Stage sub-issues are opened when this pull request merges. The v0.2.0 parent
is #60, and its six sub-issues are placed in stages below.

## What the siblings need (evidence)

<!-- markdownlint-disable MD013 -->
| Package | What it does today | What it is missing | Planned in |
| --- | --- | --- | --- |
| `zuhttp` | `streaming.Rmd` buffers NDJSON lines by hand in a chunk callback, through `rawToChar()` and `strsplit()` | a stream object fed raw chunks, with a capped tail | 0.3.0 |
| `zuhttp` | `zu_resp_json(resp, ...)` forwards `...` to `json_parse()` | a parse error that carries line, column and offset as fields, for its own error message | 0.2.0 |
| `zujose` | builds a JWK thumbprint by ordering members by hand, then `charToRaw(enc2utf8(json_write(x)))` | sorted keys and canonical JSON (RFC 8785); RFC 7515 §4 says duplicate header names must be rejected | 0.4.0, 0.5.0, 0.6.0 |
| `zulm` | `if (identical(json, "[]")) json <- "{}"` after writing a safetensors header | a way to say "this is an object" that survives being empty | 0.4.0 |
| `zugojson` | benchmarks minify and format as `json_write(json_parse(x))` | minify and format on text, with no R tree and no number change | 0.6.0 |
| `zugeo` | parses GeoParquet metadata with `simplify = FALSE`; writes coordinates at full precision | fixed digits on write; matrices for coordinate arrays | 0.4.0, 0.5.0 |
| `zuproto` | maps ProtoJSON through R values | 64-bit integers that survive a read; raw bytes as base64 | 0.4.0, 0.5.0 |
| `zupmxio`, `zusbml`, `zudedup` | `writeLines(json_write(x, pretty = TRUE), tmp)` | a file writer that writes bytes, not a locale-dependent string | 0.4.0 |
| `zucbor`, `zuarrow`, `zutoml` | would convert through R lists | a C API, so a native core can read and write JSON without the R tree | 0.8.0 |
<!-- markdownlint-enable MD013 -->

Re-run the search at each version entry
(`gh api -X GET search/code -f q='zujson:: user:pedrobtz'`). A workaround in
a sibling is the best evidence a feature is wanted, and its removal is the
best acceptance test.

## yyjson 0.12.0: used and unused

<!-- markdownlint-disable MD013 -->
| yyjson feature | Used now | Planned in |
| --- | --- | --- |
| `yyjson_read_opts`, `ALLOW_BOM`, `BIGNUM_AS_RAW`, UTF-8 validation | yes | |
| `yyjson_mut_write_opts`, `PRETTY_TWO_SPACES` | yes | |
| `yyjson_read_number` | yes (`zu_raw_dbl()`) | |
| `yyjson_locate_pos` (line, column, character of an offset) | no | 0.2.0 |
| `yyjson_read_max_memory_usage`, `yyjson_alc_*` (custom and pool allocators) | no | 0.2.0 (measure), 1.0.0 |
| `yyjson_incr_new/read/free` (one large document, progressively) | no | 0.3.0 (file reads only) |
| `STOP_WHEN_DONE` (concatenated documents) | no, deliberately | 0.3.0, opt-in |
| `WRITE_PRETTY` (4 spaces), `NEWLINE_AT_END`, `ESCAPE_UNICODE`, `ESCAPE_SLASHES` | no | 0.4.0 |
| `WRITE_FP_TO_FIXED(prec)`, `WRITE_FP_TO_FLOAT` | no | 0.4.0 |
| `WRITE_ALLOW_INF_AND_NAN`, `WRITE_INF_AND_NAN_AS_NULL` | no (done by hand) | 0.4.0 |
| `yyjson_mut_rawn` (a verbatim JSON fragment in the output) | no | 0.4.0 |
| `ALLOW_COMMENTS`, `ALLOW_TRAILING_COMMAS`, `ALLOW_INF_AND_NAN`, `READ_JSON5` and its parts | no | 0.5.0, opt-in |
| `NUMBER_AS_RAW` (every number as its token) | no | 0.5.0 |
| `ALLOW_INVALID_UNICODE` (both directions) | no | 0.5.0, opt-in, never default |
| `yyjson_val_write_opts` (serialise a subtree) | no | 0.6.0 |
| `yyjson_equals` | no | 0.6.0 |
| JSON Pointer: `yyjson_doc_ptr_get*`, `yyjson_mut_doc_ptr_add/set/replace/remove*` | no | 0.6.0 (get), 0.7.0 (edit) |
| `yyjson_patch`, `yyjson_merge_patch` | no | 0.7.0 |
| `yyjson_doc_mut_copy`, `yyjson_mut_doc_mut_copy` | no | 0.7.0, 0.8.0 |
| `READ_INSITU` | no | 1.0.0, if it measures |
| `yyjson_read_file`, `yyjson_write_file`, `*_fp` | no, and never | R opens files (#50) |
<!-- markdownlint-enable MD013 -->

yyjson has **no** JSONPath, diff, key sorting, canonical form, schema
validation or SAX reader. Those are first-party C, with their own oracles.

## Parity targets

What "best in class" means here, feature by feature. A dash is "not
planned"; the reason is under "Not planned".

<!-- markdownlint-disable MD013 -->
| Feature | Go | Python | Rust | zujson |
| --- | --- | --- | --- | --- |
| Error with line, column, offset | `SyntacticError.ByteOffset` | `JSONDecodeError.lineno/colno/pos` | `Error::line()/column()` | 0.2.0 |
| Streaming decode | `json.Decoder` | `ijson` | `StreamDeserializer` | 0.3.0 |
| Sorted keys | `Deterministic` | `sort_keys`, `OPT_SORT_KEYS` | default (`BTreeMap`) | 0.4.0 |
| Indent, final newline | `MarshalIndent`, `WithIndent` | `indent`, `OPT_APPEND_NEWLINE` | `PrettyFormatter` | 0.4.0 |
| ASCII-only output, `/` escaping | `EscapeForHTML` | `ensure_ascii` | | 0.4.0 |
| Non-finite policy | error | `allow_nan` | `null` | 0.4.0 |
| Verbatim fragment | `RawMessage`, `jsontext.Value` | `orjson.Fragment` | `RawValue` | 0.4.0 |
| Fallback for unknown types | `Marshaler` | `default=` | `Serialize` | 0.4.0 (`default =`) |
| Bytes | base64 | via `default` | via serde attr | 0.4.0 |
| Time formats | RFC 3339 nano | `OPT_OMIT_MICROSECONDS`, `OPT_UTC_Z` | via `chrono` | 0.4.0 |
| 64-bit and big integers | `int64`, `Number`, `StringifyNumbers` | `int` (arbitrary) | `arbitrary_precision` | 0.5.0 |
| Duplicate keys rejected | `RejectDuplicateNames` | `object_pairs_hook` | last wins | 0.5.0 |
| Comments, trailing commas | `hujson` | `json5`, `commentjson` | `json5`, `jsonc-parser` | 0.5.0 |
| Depth and size limits | v2: depth 10000 | recursion limit | `recursion_limit` 128 | have (1000); settable down in 0.5.0 |
| Minify, format, equal on text | `Compact`, `Indent` | | `to_writer` over `Value` | 0.6.0 |
| JSON Pointer | `jsontext.Pointer` | `jsonpointer` | `Value::pointer` | 0.6.0, 0.7.0 |
| Canonical JSON (RFC 8785) | `jsontext.Value.Canonicalize` | `rfc8785` | `serde_jcs` | 0.6.0 |
| JSON Patch, Merge Patch, diff | `evanphx/json-patch` | `jsonpatch` | `json-patch` | 0.7.0 |
| Document value, lazy access | `gjson` | `orjson` (no) | `Value`, `sonic-rs` lazy | 0.8.0 |
| Native API for other packages | | C extension API | crate | 0.8.0 |
| Typed decode | struct tags | `msgspec`, `pydantic` | `serde` derive | 0.9.0 |
| JSONPath (RFC 9535) | `ohler55/ojg` | `jsonpath-rfc9535` | `serde_json_path` | 0.9.0 |
| JSON Schema | `santhosh-tekuri/jsonschema` | `jsonschema` | `jsonschema` | separate package |
| SIMD parsing | `sonic` | `orjson`, `pysimdjson` | `simd-json` | — |
<!-- markdownlint-enable MD013 -->

## How stages are written

Each stage is one mergeable pull request, tracked as a sub-issue of its
version's parent, titled `Stage <v>.<n> — <title>`. Each has:

- **CI.** `quick` unless stated. `full` means the `full-ci` label and a green
  full run before merge (`.claude/shared/ci.md`).
- **Tests.** One row per behaviour: the behaviour, the oracle that knows its
  answer, and the test file. Each test is seen to fail once.
- **Exit.** What must be true to close the sub-issue, beyond the shared
  definition of done.

Every version ends with the same two stages, not repeated below:

- **`Full CI`**: dispatch the full profile on the last merge commit, fix
  what only it shows, re-run `tools/jsontestsuite.R`, update
  `.agents/assurance.md`.
- **`v<x> readiness`**: `pkg-critical-review`, then `pkg-cran-review`,
  reverse-dependency checks on every sibling in `CLAUDE.md`'s list, `NEWS.md`,
  `cran-comments.md`, submit.

Reverse-dependency checks matter more here than in most packages. From 0.2.0
on, a sibling test that changes result is a release blocker, not a note.

---

## v0.2.0 — the settled mapping

Parent: #60. **The last version that may change a default result.** It
closes the mapping decisions deferred from 0.1.1, builds the assurance that
every later version leans on, and lays the two foundations later versions
need: structured error positions, and the pattern options grow by.

### Stage 2.1 — Mapping decisions (#49, #51, #58)

The three open breaking changes, in one pull request so siblings are
re-checked once.

- **#49.** An empty key survives a round trip. `{"":1}` parses to a list
  named `""` and must write back as `{"":1}`. Two candidate rules, to be
  decided in design §6 before coding:
  (a) a list is an object when it has a `names` attribute with no `NA`, and
  an empty name is a key like any other, so only a list with *no* names
  attribute, or all names empty, is an array. `c(a = 1, 2)` then becomes
  `{"a":1,"":2}`, which design §6 rejected once;
  (b) the parser marks a list whose names came from JSON (an attribute or a
  class), and the writer trusts the mark. `c(a = 1, 2)` stays an array.
  Recommended: (b), with `json_object()` (Stage 4.4) as its public spelling.
  It changes no result for a value built in R.
- **#51.** `simplify = "coerce"` formats each number from its own token,
  independent of `OutDec`, `scipen`, `digits` and sibling values.
- **#58.** A matrix column in a data frame raises `zujson_unsupported_type`
  with a message that names the column.

**CI.** `full`: all three touch `zu_write.c` or `zu_parse.c` recursion.

**Tests.**

<!-- markdownlint-disable MD013 -->
| Behaviour | Oracle | File |
| --- | --- | --- |
| `{"":1}`, `{"":1,"a":2}`, `{"a":{"":[]}}` round-trip byte for byte | round trip, `expect_json()` | `test-roundtrip.R` |
| a frame with a `""` column writes and reads back | round trip, `identical()` | `test-roundtrip.R` |
| `c(a = 1, 2)`, and every other value built in R, writes the bytes 0.1.1 wrote | the 0.1.1 suite's `expect_json()` rows, unchanged | `test-write.R` |
| the mark survives `[`, `[[<-`, `c()` and `lapply()` or is documented as lost, one row each | known answer per operation | `test-roundtrip.R` |
| coerce strings equal the JSON token for integers, and yyjson's shortest form for reals | the input text itself; Python `json.loads` + `repr` over 2,000 seeded doubles | `test-simplify.R` |
| the same under `OutDec = ","`, `scipen = -5`, `digits = 3`, `LC_ALL=C` | differential across sessions | `test-session.R` |
| a matrix column is refused; a list column of matrices is not silently flattened | known answer, condition class | `test-write.R` |
<!-- markdownlint-enable MD013 -->

**Exit.** Design §5, §6 and both roxygen tables updated. Every sibling's
suite green against the branch. `NEWS.md` has a "Breaking changes" heading.

### Stage 2.2 — How options grow

No new behaviour. A decision and its scaffolding, so 0.4.0 and 0.5.0 do not
each invent one.

The headline arguments stay positional and few: `simplify`, `data_frame`,
`pretty`, `auto_unbox`. Everything else goes in one options object per
direction:

```r
json_parse(x, simplify = "preserve", data_frame = FALSE,
           options = json_read_options())
json_write(x, pretty = FALSE, auto_unbox = TRUE,
           options = json_write_options())
```

- `json_read_options()` and `json_write_options()` validate in R, once, and
  return a classed list. C receives one integer flag word and a small struct,
  not twenty `SEXP` arguments.
- The NDJSON, file and raw variants take the same object, so a new option
  reaches every route at once (family 3, "the class fixed as an instance").
- `options(zujson.max_df_cells = )` stays. No other global option is added:
  a global that changes a mapping changes it for every sibling at once.
- `zuhttp`'s `zu_resp_json(resp, ...)` forwards `...`, so `options =` reaches
  it with no change there.

Alternative considered: flat arguments, as `jsonlite::toJSON()` has. Rejected
because ten entry points times thirty arguments is where routes drift apart.

**Tests.**

<!-- markdownlint-disable MD013 -->
| Behaviour | Oracle | File |
| --- | --- | --- |
| a default options object changes no result on any route | the whole existing suite, run with `options = json_read_options()` injected | `helper-expect.R`, `test-options.R` |
| an unknown field, a wrong type, a length-2 value each raise `zujson_arg_error` | known answer, condition class | `test-options.R` |
| every entry point accepts `options` | a test that lists the exports and fails on one that does not | `test-options.R` |
<!-- markdownlint-enable MD013 -->

**Exit.** Design §16 "Options" updated from "decided" to what was built.
The two constructors exported with no fields
beyond the ones 0.2.0 uses (Stage 2.3 adds none; they are empty shells with
a tested contract).

### Stage 2.3 — Error positions as data

`zujson_parse_error` gains fields, not only a message:

```r
tryCatch(json_parse(x), zujson_parse_error = function(e) {
  e$offset   # byte offset, 0-based, as yyjson reports it
  e$line     # 1-based
  e$column   # 1-based, in characters
  e$record   # NDJSON only: the record number
  e$code     # yyjson's reason, as a stable lower_snake string
})
```

`yyjson_locate_pos()` supplies line and column. `zu_stop()` already builds
the condition in C, so the fields are attached where the cause is known.
`zujson_depth_error` and `zujson_limit_error` gain `$limit` and `$depth` or
`$cells`. The NDJSON writer error gains `$record` (#70 does the message in
0.1.1; this makes it a field).

**CI.** `full`: `zu_cond.c` allocates more in the error path.

**Tests.**

<!-- markdownlint-disable MD013 -->
| Behaviour | Oracle | File |
| --- | --- | --- |
| offset, line and column for an error at the start, middle and end, after a BOM, after CRLF, after a 2-, 3- and 4-byte character | Python `json.JSONDecodeError` (`pos`, `lineno`, `colno`) through a helper like zuhttp's `helper-python.R`; skipped without Python, with hand-computed answers that always run | `test-conditions.R` |
| the character and raw routes report the same position | differential | `test-conditions.R` |
| every `n_` file of JSONTestSuite gives an offset inside the file and a non-empty `code` | the corpus | `tools/jsontestsuite.R` |
| fields survive fifty interleaved failures | the existing interleave test | `test-conditions.R` |
| building the condition under `gctorture` and under allocation failure leaks nothing | ASan, `alloc-failure.yaml` | `tools/sanitizer-exercise.R`, `tools/alloc-exercise.R` |
<!-- markdownlint-enable MD013 -->

**Exit.** Design §7 lists the fields per class. `zuhttp` issue opened to use
them in `zu_resp_json()`'s message.

### Stage 2.4 — Coverage-guided fuzzing, with reach (#28)

A libFuzzer harness over the C entry points, not the R API, with oracles:

- reader: `parse → write → parse` gives an identical tree; `validate` agrees
  with `parse` except on the two documented classes;
- NDJSON: splitting and joining agree with per-line `json_parse()`;
- writer: a structure-aware harness builds an R value from the bytes, writes
  it, and requires yyjson to read the output back.

`zufuzz` is the family's harness package; use it if it can drive a `.Call`
target, and record why not if it cannot. Corpus seeded from JSONTestSuite
and `tests/`. `fuzz-reach` reports functions and branches of `zu_parse.c`
and `zu_write.c` the corpus never reaches, against a floor.

**CI.** `full`. Long runs wait for the weekly schedule.

**Exit.** `fuzz` and `fuzz-reach` are `done` in `.agents/assurance.md`. Each
later stage that adds a C entry point adds its harness in the same pull
request; that is an exit criterion from here on.

### Stage 2.5 — Mutation testing and the byte limits (#27, #37)

- #27: mutation run over `zu_parse.c`, `zu_write.c`, `zu_cond.c`. Survivors
  are read and either killed with a test or listed with a reason.
- #37: the `INT_MAX` byte limits straddled in both directions, on a runner
  with the memory for it, behind `R_ACTIONS_PROFILE=full`.

**Exit.** Both rows `done`. The survivor list is in the pull request.

### Stage 2.6 — Benchmarks and the vendor manifest

Two pieces of infrastructure every later version is judged against.

- `tools/bench.R`: parse and write, by route, over a fixed corpus (the
  `nativejson-benchmark` trio `canada.json`, `citm_catalog.json`,
  `twitter.json`, plus a wide data frame, a deep document and a 100k-line
  NDJSON body), against `jsonlite`, `yyjsonr` and `RcppSimdJson`. It records
  time and peak memory, and `yyjson_read_max_memory_usage()` against what was
  measured. Results go to `.agents/bench/<version>.md`. Nothing is gated; a
  later "performance claim needs evidence" points here.
- `src/vendor/PROVENANCE` and a checksum manifest, so `vendor.yml` verifies
  the tree rather than skipping. Check upstream for a release after 0.12.0
  and take it here if there is one, since 0.2.0 already re-checks siblings.
- `nm -u` guard on the built objects for the symbols CRAN refuses.

**Exit.** A baseline file exists. `vendor.yml` runs tree verification.

### Stage 2.7 — Close design §14.9

`zuhttp` is real. Add `tests/testthat/test-zuhttp.R`, skipped when `zuhttp`
is absent, that sends a body built by `json_write_raw()` through `zuhttp`'s
mock transport and parses what comes back, asserting on the bytes the other
side received. Add `zuhttp` to `Suggests`. Mark §14.9 done.

**Exit.** Acceptance criteria all closed. Design status line updated.

---

## v0.3.0 — streaming

The stream designed in §13, now that `zuhttp` hands out raw chunks through a
callback. It is first because it has a caller writing a workaround today,
and because it is small. It is also the package's first long-lived object.

### Stage 3.1 — `json_stream()`, `json_feed()`, `json_finish()`

```r
s    <- json_stream(simplify = "preserve", data_frame = FALSE,
                    max_record = 16 * 1024^2, options = json_read_options())
recs <- json_feed(s, chunk)   # raw in, list of completed records out
recs <- json_finish(s)        # the last record; error on a partial one
json_stream_info(s)           # bytes fed, records out, tail bytes, state
```

The five decisions of design §13 stand. Added here:

- **States.** `open → finished`, and `open → failed` on any error. A failed
  or finished stream refuses `json_feed()` with `zujson_stream_error`. It
  never resumes after an error: what was in the tail is unknown.
- **What the caller got before the error.** A chunk holding three good
  records and a bad fourth raises, and delivers nothing from that chunk.
  The good records are returned by the error's `$records` field, so a
  caller can choose; the stream is failed either way. State this in
  `?json_feed`.
- **Limits.** `max_record` bounds the tail in bytes, straddled at
  `limit - 1`, `limit`, `limit + 1`, with the newline inside and outside the
  chunk. The data frame cell budget is per `json_feed()` call.
- **Ownership.** The tail is owned by an external pointer with a finalizer.
  The object is not serialisable: a stream restored by `readRDS()` has a
  null pointer and raises `zujson_stream_error`, never a segfault. A stream
  used in a forked child after the parent fed it is refused by a PID guard.
- **BOM.** Stripped once, at the first byte of the stream, even when the
  three bytes arrive in three chunks.
- `\r\n` split across chunks is one line ending.

**CI.** `full`: a finalizer and a new lifetime.

**Tests.**

<!-- markdownlint-disable MD013 -->
| Behaviour | Oracle | File |
| --- | --- | --- |
| any chunking of a body gives the records `json_parse_ndjson()` gives | differential: 500 seeded bodies, each split at every byte, and at random points | `test-stream.R` |
| a chunk boundary inside a 4-byte character, an escape, a `\r\n`, a BOM | the same differential, with the split forced there | `test-stream.R` |
| `max_record` at `limit - 1`, `limit`, `limit + 1` | known answer, `zujson_limit_error` | `test-stream.R` |
| feed after finish, feed after error, finish twice, finish on a partial tail, finish on an empty stream | the documented terminal state | `test-stream.R` |
| a bad record delivers nothing from its chunk, and `$records` holds the good ones | known answer | `test-stream.R` |
| `readRDS(saveRDS(s))`, a forked child, a stream collected mid-record | classed error; ASan and valgrind clean | `test-stream.R`, `tools/sanitizer-exercise.R` |
| model-based fuzz: random sequences of feed, finish, error and drop against an R model of the state machine | the model | `fuzz/`, `test-fuzz.R` |
<!-- markdownlint-enable MD013 -->

**Exit.** `.agents/assurance.md` declares `lifecycle` and has an Objects row
with fork, unwind and owner guards. `zuhttp`'s `streaming.Rmd` rewritten on
it (a pull request there, linked).

### Stage 3.2 — NDJSON to and from files and connections

```r
json_parse_ndjson_file(path, ..., n = Inf, skip = 0)
json_read_ndjson(con, n = 1000, ...)      # the next n records of a connection
json_write_ndjson_file(x, path, append = FALSE, ...)
```

Built on the stream of 3.1, read in R in bounded chunks (#50's rule: R opens
the file). `json_read_ndjson()` is the batch iterator: call it until it
returns an empty list. `append = TRUE` adds records to an existing file and
never writes a BOM. gz, bz2 and xz arrive free through R connections.

**Tests.** File and in-memory routes give identical records (differential);
`n` and `skip` at 0, 1, the record count and one past; a file with no final
newline; a file larger than the read chunk at the chunk size ±1; appended
output read back (round trip); a `gzfile()` connection against the plain
file.

### Stage 3.3 — Other framings, opt-in

```r
json_stream(framing = "ndjson")   # default
            # "json-seq"     RFC 7464: RS (0x1E) before, LF after each text
            # "concatenated" values back to back, yyjson STOP_WHEN_DONE
```

`"concatenated"` is refused for a top-level scalar at a chunk end until more
bytes or `json_finish()` arrive (design §13, decision 1): `12` may be the
start of `123`. RFC 7464 §2.4 handles the same case with the trailing LF,
and a truncated text is skipped or raised by an option, as the RFC allows.
The same `framing` reaches `json_parse_ndjson()` under a new name,
`json_parse_seq()`, only if a sibling asks.

**Tests.** RFC 7464's own examples; concatenated bodies against
Python `json.JSONDecoder.raw_decode` in a loop; the scalar-at-boundary case
split at every byte.

### Stage 3.4 — A large array of records

The other streaming shape: one document, `[ {...}, {...}, ... ]`, too large
to hold as an R list of lists at once.

```r
json_parse_file(path, data_frame = TRUE)          # today: whole tree
json_read_array(con, n = 1000, pointer = "")      # the next n elements
```

A small first-party scanner finds element boundaries of the array at
`pointer` (string-aware bracket counting, validated by yyjson per element),
so memory is bounded by `n` elements, not by the file. `yyjson_incr_read` is
considered for `json_parse_file()` so the read can be interrupted, and taken
only if Stage 2.6's benchmark shows no loss.

**CI.** `full`: a new scanner over untrusted bytes, with its own fuzz
harness (oracle: the elements equal `json_parse()` of the whole document).

---

## v0.4.0 — writer controls

Everything a caller can ask of the output, as fields of
`json_write_options()`. Defaults reproduce 0.2.0 byte for byte.

### Stage 4.1 — Layout

<!-- markdownlint-disable MD013 -->
| Option | Values | yyjson |
| --- | --- | --- |
| `indent` | `0`, `2`, `4`; `pretty = TRUE` is `2` | `PRETTY`, `PRETTY_TWO_SPACES` |
| `final_newline` | `FALSE`, `TRUE` | `NEWLINE_AT_END` |
| `ascii` | `FALSE`, `TRUE`: non-ASCII as `\uXXXX`, with surrogate pairs | `ESCAPE_UNICODE` |
| `escape_slash` | `FALSE`, `TRUE`: `/` as `\/`, for JSON inside `<script>` | `ESCAPE_SLASHES` |
| `sort_keys` | `FALSE`, `TRUE`: members ordered by UTF-8 bytes, at every level | first-party, in `zu_from_sexp()` |
<!-- markdownlint-enable MD013 -->

`sort_keys` orders by bytes, not by the session's collation, and is stable
for duplicate names. NDJSON refuses `indent > 0`, as it refuses `pretty`.

**Tests.** Exact bytes per option; Python `json.dumps(sort_keys=True,
ensure_ascii=True, indent=…)` as a reference over a seeded corpus including
astral characters and keys that sort differently by code point, by UTF-16
unit and by locale; every option round-trips to the same R value as the
default; the hostile-session matrix of `test-session.R`.

### Stage 4.2 — Numbers and missing values

<!-- markdownlint-disable MD013 -->
| Option | Values | Notes |
| --- | --- | --- |
| `digits` | `NA` (shortest round trip), `1`–`15` fixed decimals | `WRITE_FP_TO_FIXED`; whole doubles stay integers |
| `non_finite` | `"null"` (default), `"error"`, `"string"` (`"NaN"`, `"Infinity"`, `"-Infinity"`), `"literal"` (bare `NaN`, not JSON) | `"string"` is ProtoJSON's rule; `"literal"` is refused by `json_validate()` and says so |
| `na` | `"null"` (default), `"error"`, `"string"` (`"NA"`) for character only | `NA_character_` only; numeric `NA` follows `non_finite` |
| `bigint` | `"number"` (default), `"string"`: an `integer64`, or a whole double past 2^53, as a JSON string | what JavaScript consumers need |
| `null` | `"null"` (default), `"drop"`: a `NULL` list member is omitted | Go's `omitempty`, the common request-body need |
<!-- markdownlint-enable MD013 -->

**Tests.** `digits` against `sprintf("%.*f")` only where the two are defined
to agree, and against Python `round`-then-`repr` otherwise (state the rounding
rule: yyjson's, half to even on the decimal expansion); straddle 2^53 and
±2^63 for `bigint`; each `non_finite` value at top level, in a vector, in a
data frame cell and in NDJSON (four routes, one answer); `null = "drop"` at
depth, in a data frame row (a missing cell omits the member) and never in an
array (positions matter).

### Stage 4.3 — Dates, times, factors, bytes

<!-- markdownlint-disable MD013 -->
| Option | Values |
| --- | --- |
| `time` | `"rfc3339"` (default, seconds, `Z`), `"rfc3339_ms"`, `"rfc3339_us"`, `"rfc3339_ns"`, `"epoch"`, `"epoch_ms"` |
| `time_zone` | `"utc"` (default), `"local"`: the vector's `tzone` as a numeric offset, never a zone name |
| `date` | `"iso"` (default), `"epoch_days"` |
| `factor` | `"string"` (default), `"integer"` |
| `raw` | `"error"` (default), `"base64"`, `"base64url"`, `"hex"`, `"array"` |
| `duration` | for `difftime` and `hms`: `"number"` (default, today's fall-through), `"seconds"` (unit-normalised), `"iso8601"` (`PT1H30M`) |
<!-- markdownlint-enable MD013 -->

`POSIXlt` stays refused. Fractional seconds are truncated, not rounded, so
an instant never moves to the next second (#41's lesson). An offset needs
the zone database; if that cannot be had from C without R's internals, the
offset is computed in R per distinct value and passed down.

**Tests.** `format(x, "%Y-%m-%dT%H:%M:%OS6Z")` is not an oracle (it rounds
and follows `digits.secs`); use integer arithmetic on the epoch in R and
Python `datetime.isoformat` over 2,000 seeded instants, both sides of each
second, and across a daylight-saving change for `"local"`; base64 against
RFC 4648 §10 vectors and `zucrypt`/`base64enc` over random lengths 0–100.

### Stage 4.4 — Saying what you mean: markers and fragments

```r
json_object(...)        # an object, even when empty or unnamed-looking
json_array(...)         # an array, even when fully named
json_scalar(x)          # never boxed, even under auto_unbox = FALSE
json_verbatim(text)     # already JSON: validated once, embedded as is
json_null()             # an explicit null where NULL would mean "absent"
```

- `json_object()` with no arguments is `{}`. This removes `zulm`'s
  `"[]" → "{}"` patch and gives #49 its explicit form.
- `json_verbatim()` is Go's `RawMessage`, `orjson.Fragment`, serde's
  `RawValue`: a string or raw vector checked with `json_validate()` at
  construction and at write time (the class can be forged), then written
  through `yyjson_mut_rawn`. It is refused in NDJSON if it holds a newline.
  It is charged for its own depth, measured when validated, so the depth cap
  still means "what `json_parse()` reads back".
- `I()` stays, and means what it means now.

**CI.** `full`: unvalidated bytes reaching the output is the worst bug shape
this version can have.

**Tests.** Exact bytes; a forged `json_verbatim` (class set by hand on
invalid text, on text with a trailing value, on text with a raw newline) is
refused; a fragment at depth `limit - d`, `limit - d + 1`; a fragment inside
a data frame cell; round trip `json_parse(json_write(json_verbatim(t)))`
equals `json_parse(t)` over JSONTestSuite's `y_` files.

### Stage 4.5 — Shapes: matrices and data frames

<!-- markdownlint-disable MD013 -->
| Option | Values |
| --- | --- |
| `matrix` | `"flat"` (default, today's), `"rows"` (array of row arrays), `"columns"`; an n-d array nests by `dim` |
| `data_frame` | `"rows"` (default), `"columns"` (object of arrays), `"values"` (array of row arrays, no names), `"split"` (`{"columns":[…],"data":[[…]]}`) |
| `row_names` | `FALSE` (default), `TRUE`, or a member name |
<!-- markdownlint-enable MD013 -->

A matrix column in a frame (#58) follows `matrix` once it is not `"flat"`.
Each shape is charged its real depth.

**Tests.** `jsonlite::toJSON(dataframe = , matrix = )` reads as the oracle
for shape, zujson's own table for bytes; pandas `to_json(orient=)` for
`"split"`, `"values"`, `"columns"`; depth straddled per shape; zero-row and
zero-column frames in every orientation (the #57 and #73 class).

### Stage 4.6 — `default =`, a fallback for what has no JSON form

```r
json_write(x, options = json_write_options(
  default = function(value) as.character(value)))
```

Called from C, only for a value that would otherwise raise
`zujson_unsupported_type` or that carries a class the writer does not know,
and only once per value: what it returns is written by the ordinary rules,
and a second unsupported value inside it raises. This is Python's `default`,
not S3 dispatch on every node; the design's non-goal "custom serializer
dispatch" stays a non-goal. The callback can longjmp or allocate; the owner
model (§8) already makes that safe, and the gctorture exercise proves it.

**CI.** `full`: R called back from inside the write recursion.

**Tests.** The callback sees the value unchanged (`identical()`); an error
inside it surfaces as `zujson_write_error` with the original as `$parent`,
and leaks nothing (ASan, alloc-failure); it is not called for supported
types (a counter); a callback that returns itself-unsupported raises rather
than recursing; `gctorture(TRUE)` over a callback that allocates.

### Stage 4.7 — `json_write_file()`

```r
json_write_file(x, path, ..., atomic = TRUE)
```

Writes the bytes of `json_write_raw()` with `writeBin()`, to a temporary
file in the same directory and then `file.rename()` when `atomic`. No
locale, no `writeLines()`, no BOM. Failure is `zujson_io_error`.

**Tests.** Bytes on disk equal `json_write_raw()`; a non-ASCII path under
`LC_ALL=C`; an unwritable directory; an existing target is intact when the
write fails mid-way (the target's bytes are asserted, not "it raised").

---

## v0.5.0 — reader controls

Fields of `json_read_options()`. The default reader stays strict RFC 8259,
and `json_validate()` stays strict whatever the options, unless it is given
the same options object.

### Stage 5.1 — Integers and numbers

<!-- markdownlint-disable MD013 -->
| Option | Values | Notes |
| --- | --- | --- |
| `bigint` | `"double"` (default), `"integer64"`, `"character"`, `"error"` | applies to an integer outside int32; `"integer64"` gives a `bit64`-classed vector with no `bit64` dependency, and one past int64 follows `bigint_overflow` |
| `number` | `"native"` (default), `"character"`: every number as its exact token | `NUMBER_AS_RAW`; serde's `arbitrary_precision`, Go's `UseNumber` |
| `non_finite` | `"error"` (default), `"string"`: `"NaN"`, `"Infinity"` strings in a numeric array become doubles | ProtoJSON's reading; pairs with the writer's |
<!-- markdownlint-enable MD013 -->

`"integer64"` changes the lattice: an array mixing int32 and int64 is one
`integer64` vector; one mixing `integer64` and a real is a double (stated,
tested, lossy and documented as such) unless `number = "character"`.

**Tests.** ±2^31, ±2^53, ±2^63 and one past each; `bit64::as.integer64()`
reads the same value where installed, and the raw bits are asserted where
not; write-then-read round trip with the writer's `bigint`; the token text
is byte-identical under `number = "character"` over
`nigeltao/parse-number-fxx-test-data` samples.

### Stage 5.2 — Duplicate keys, nulls, strictness

<!-- markdownlint-disable MD013 -->
| Option | Values |
| --- | --- |
| `duplicate_keys` | `"keep"` (default, today's), `"error"`, `"first"`, `"last"` |
| `null` | `"na"` in arrays (default, today's); `list_null = "null"` or `"drop"` for an object member |
| `max_depth` | `1`–`1000`; the cap can be lowered, never raised |
| `max_bytes` | refuse input over a size, before reading |
| `max_string_bytes`, `max_members` | per-value budgets, for a caller parsing a hostile body |
<!-- markdownlint-enable MD013 -->

`duplicate_keys = "error"` is what RFC 7493 (I-JSON) and RFC 7515 require,
and what `zujose` needs. It compares decoded keys, so `"a"` and `"a"`
are duplicates. It uses the seeded index `data_frame = TRUE` already has.

**Tests.** JSONTestSuite's `object_duplicated_key*` files under each value;
Go `json/v2` `RejectDuplicateNames` semantics table; escaped-equal keys;
100k distinct keys in linear time (the collision test of #44, reused);
every limit at `limit - 1`, `limit`, `limit + 1` on every read route.

### Stage 5.3 — Dialects: JSONC and JSON5

```r
json_read_options(dialect = "json")    # default, RFC 8259
                  # "jsonc"  comments and trailing commas
                  # "json5"  YYJSON_READ_JSON5
json_read_options(allow = c("comments", "trailing_commas", "inf_nan",
                            "single_quotes", "unquoted_keys",
                            "ext_number", "ext_escape", "ext_whitespace"))
```

For configuration files, not for response bodies. `ZUJSON_READ_FLAGS` stays
the shared base; a dialect is an addition made in one place and handed to
every route, so `json_validate(x, options)` and `json_parse(x, options)`
agree. A dialect is refused for NDJSON and for streams: a `/* */` comment
may hold a raw newline, which is the one thing line framing cannot survive.

`ALLOW_INVALID_UNICODE` is **not** exposed as a dialect. If a sibling shows a
need, it is `invalid_utf8 = "replace"` (U+FFFD), done by the package, so no
string marked `CE_UTF8` is ever invalid.

**Tests.** `json5/json5-tests` corpus (`.json5` accepted, `.txt` and `.js`
refused, with a recorded baseline as for JSONTestSuite's `i_`); every
JSONTestSuite `n_` file still refused under the default; the strict and
lenient readers agree on every `y_` file (differential).

### Stage 5.4 — Matrices and arrays on read

```r
json_parse(x, options = json_read_options(matrix = TRUE))
```

`[[1,2],[3,4]]` becomes a 2 × 2 matrix when every inner array has the same
length and one lattice type; deeper regular nesting becomes an n-d array.
Row-major JSON to column-major R, the inverse of the writer's
`matrix = "rows"`. Off by default, forever: the divergence table in
`test-interop-jsonlite.R` pins that.

**Tests.** Round trip with Stage 4.5; `jsonlite::fromJSON()` agreement table
for regular input; ragged, empty (`[[],[]]`), mixed-type and
`[[1],[null]]` cases as known answers; the cell budget applies.

### Stage 5.5 — Data frame options

- `flatten = TRUE`: a column of objects becomes columns named `a.b`
  (separator settable), within the cell budget.
- `columns = c("id", "name")`: build only these columns, others are skipped
  without being built (a real saving on wide API responses).
- `records = "/data/items"`: a JSON Pointer to the array to turn into the
  frame, so the envelope is not built at all. Shares the pointer code of
  0.6.0; if 0.6.0 is not in yet, this option waits for it.

**Tests.** `jsonlite::flatten()` as reference; selected columns equal the
same columns of the full frame (differential); a selected column that never
appears is all-`NA`.

---

## v0.6.0 — JSON as text

Operations that never build an R tree. They are faster, they preserve
numbers exactly, and they are what a proxy, a signer or a cache needs.

### Stage 6.1 — `json_minify()`, `json_format()`, `json_equal()`

```r
json_minify(x)                       # character or raw in, same type out
json_format(x, indent = 2, sort_keys = FALSE)
json_equal(x, y)                     # structural: key order ignored
json_type(x, pointer = "")           # "object", "array", "string", ...
json_length(x, pointer = "")
json_keys(x, pointer = "")
```

Numbers are copied as tokens (`NUMBER_AS_RAW`), so `1.0`, `1e2` and a
40-digit integer come out as they went in. `json_equal()` compares numbers
by value (`1.0 == 1`), and says so; duplicate keys make two documents
unequal unless identical in order.

**Tests.** `json_parse(json_minify(x))` is identical to `json_parse(x)` over
JSONTestSuite `y_` and the benchmark corpus; output of `json_format()` equals
Python `json.dumps(indent=2)` on documents with no floats, and round-trips
on all; minify is idempotent, and `minify(format(x)) == minify(x)`; a number
token is byte-identical before and after; `json_equal()` against
`jq -S`-normalised comparison and against `identical()` of sorted parses.
`zugojson`'s `bench-compare.R` gains a native column.

### Stage 6.2 — JSON Pointer, reading (RFC 6901)

```r
json_get(x, pointer, simplify = , data_frame = , options = )
json_get_text(x, pointer)            # the sub-document, as JSON text
json_has(x, pointer)
json_pointer("a/b", "c~d", 3)        # build one, escaping ~ and /
```

`pointer` may be a vector: one read of the document, one result per pointer.
A missing path is `NULL` from `json_get()` by default, or
`zujson_pointer_error` under `missing = "error"`. Only the selected subtree
is converted to R, by the same `zu_to_sexp()`, so §5 applies unchanged and
depth is counted from the selected value.

**Tests.** RFC 6901 §5's twelve examples, exactly; `json_get(x, p)` equals
walking `json_parse(x, simplify = "none")` by hand (differential, over
every path of a seeded corpus); `~0`, `~1`, `~01`, an empty key, a
leading-zero index, `-`, an index past the end; a duplicate key takes the
first, as yyjson does, and the documentation says so.

### Stage 6.3 — Canonical JSON (RFC 8785, JCS)

```r
json_canonical(x)        # JSON text in, canonical text out
json_write(x, options = json_write_options(canonical = TRUE))
```

Sorted by UTF-16 code units (not bytes: this differs from `sort_keys` for
astral characters), no whitespace, minimal string escapes, and numbers in
ECMAScript's `Number.prototype.toString` layout. yyjson supplies the shortest
round-trip digits; the layout (`1e+21`, `1e-7`, no exponent below 1e21) is
first-party. Input with a number outside double range, a duplicate key or a
lone surrogate is refused, as I-JSON requires. `canonical = TRUE` refuses
every other layout option.

**CI.** `full`. A canonical form that is wrong signs the wrong bytes.

**Tests.** RFC 8785 Appendix B number table; the `cyberphone/json-
canonicalization` test data, including a seeded sample of its
100-million-line number file checked by hash; Python `rfc8785` as a
reference over a seeded corpus; canonicalisation is idempotent; RFC 7638
§3.1's thumbprint example reproduces, and `zujose` drops its hand ordering.

---

## v0.7.0 — editing

### Stage 7.1 — Pointer edits

```r
json_set(x, pointer, value)       # add or replace; value is an R value
json_remove(x, pointer)
json_insert(x, pointer, value)    # RFC 6902 "add" semantics for arrays
```

Text in, text out, through a mutable copy
(`yyjson_doc_mut_copy`, `yyjson_mut_doc_ptr_*`). `value` goes through the
writer with the active options, or is a `json_verbatim()`.

### Stage 7.2 — JSON Patch (RFC 6902) and Merge Patch (RFC 7396)

```r
json_patch(x, patch)              # patch as JSON text or as an R list
json_merge_patch(x, patch)
```

`yyjson_patch` and `yyjson_merge_patch`. A failed `test` operation, a
missing `from`, an invalid operation each raise `zujson_patch_error` with
`$index`, the operation that failed. A patch is atomic: an error at
operation *n* returns nothing of operations 1 to *n* − 1.

**Tests.** `json-patch/json-patch-tests` (`tests.json`, `spec_tests.json`):
every case's document, error or not; RFC 7396 Appendix A's fifteen rows; a
failing patch leaves the input value untouched (asserted on the bytes).

### Stage 7.3 — `json_diff()`

```r
json_diff(x, y)                   # an RFC 6902 patch turning x into y
json_merge_diff(x, y)             # an RFC 7396 merge patch, where one exists
```

First-party (yyjson has no diff). Correctness is defined by a round trip,
not by a minimal patch: `json_equal(json_patch(x, json_diff(x, y)), y)`.

**Tests.** That property over 2,000 seeded document pairs made by mutating
one side; every pair of `json-patch-tests` documents; arrays with inserted,
removed and moved elements; `json_merge_diff()` refuses, with a classed
error, a pair no merge patch can express (a `null` member in the target).

### Stage 7.4 — The same verbs on R values

`json_get()`, `json_set()`, `json_remove()`, `json_patch()` and
`json_merge_patch()` accept a parsed R list as well as text, in R, so a
caller that already holds the tree does not re-serialise. Position, not
`x[[name]]`, for objects (the first-match trap in `correctness.md`).

**Tests.** Two routes, one value: the text route and the list route agree on
every case of the suites above, after `json_parse()`.

---

## v0.8.0 — documents and the C API

### Stage 8.1 — `json_doc()`: parse once, ask many times

```r
d <- json_doc(x, options = json_read_options())
json_get(d, "/data/items/0/id")
json_type(d); json_length(d, "/data/items"); json_keys(d)
json_write(d); format(d); as.list(d)
```

An immutable parsed document behind an external pointer. Every text verb of
0.6.0 accepts it. This is `serde_json::Value`, `gjson` and simdjson's
on-demand use in one object: a 50 MB response from which a caller wants
three fields builds three R values, not three million.

It is the second `lifecycle` object. It gets every guard the stream has:
owner and finalizer, a null-pointer check after `readRDS()`, no fork guard
needed for a read-only buffer (state why in the Objects row), and
`reg.finalizer` on exit. Its memory is reported by `json_doc_info()`, since
R's `object.size()` cannot see it.

**CI.** `full`.

**Tests.** Every `json_get()` test of 6.2 re-run through a document
(differential, text route against document route); out-of-order sequences
(use after `rm()` and `gc()` of the source vector, after `saveRDS()`,
`unserialize()`, in a forked child); model-based fuzz of the verbs against
the parsed R list.

### Stage 8.2 — Mutable documents

```r
m <- json_doc_edit(d)             # a mutable copy
json_set(m, pointer, value)       # by reference, returns m invisibly
json_write(m)
```

Reference semantics are un-R-like, so this is explicit: only `json_doc_edit`
objects mutate in place, and printing one says so. Skip this stage if no
sibling needs it by 0.8.0 entry; the text verbs of 0.7.0 cover the function.

### Stage 8.3 — C API through `LinkingTo: zujson`

`inst/include/zujson.h`, with `R_RegisterCCallable` entries following
`zukomp`'s pattern. No yyjson type crosses the boundary.

```c
/* bytes -> SEXP, by the R mapping, with a read-options word */
SEXP  zujson_c_parse(const char *buf, size_t len, const zujson_ropts *o);
/* SEXP -> bytes, in an R-owned raw vector */
SEXP  zujson_c_write(SEXP x, const zujson_wopts *o);
int   zujson_c_validate(const char *buf, size_t len, zujson_err *e);
/* an opaque, R-owned document and a cursor over it, for native readers */
SEXP  zujson_c_doc(const char *buf, size_t len, const zujson_ropts *o);
int   zujson_c_get(SEXP doc, const char *ptr, size_t n, zujson_ref *out);
/* a push writer, for native producers (CBOR, protobuf, Arrow -> JSON) */
zujson_writer *zujson_c_writer(SEXP owner, const zujson_wopts *o);
```

- The header carries `ZUJSON_API_VERSION`; a caller checks it at load.
- An options struct starts with its own size, so a field can be added
  without breaking a caller compiled against the old one.
- Every function that can fail returns a code and fills a `zujson_err`;
  none longjmps unless its name says `_or_stop`.
- The first caller is a real sibling pull request (`zuproto` or `zucbor`),
  open before this stage merges. A C API with no caller is not merged: that
  is design §15's rule, and it still holds.

**CI.** `full`. Plus an ABI probe workflow (own, gated by `changes.yml`)
that builds a tiny client package against the installed header.

**Tests.** The client package in `tests/` round-trips through the C API and
must equal the R API byte for byte (two routes, one value); a size-prefixed
struct from an "older" header is accepted; every error code is reachable and
tested; ASan over the client.

---

## v0.9.0 — typed parsing and queries

### Stage 9.1 — Parsing to a specification

Go decodes into a struct, Rust into a `serde` type, Python into `msgspec` or
`pydantic` models. The R form is a prototype:

```r
spec <- json_spec(
  id      = integer(),
  name    = character(),
  score   = double(),
  tags    = json_spec_array(character()),
  created = json_spec_time("rfc3339"),
  owner   = json_spec(id = integer(), login = character()),
  .extra  = "drop"                       # or "error", "keep"
)
json_parse(x, as = spec)                 # one object
json_parse(x, as = json_spec_array(spec), data_frame = TRUE)
```

- The result's types are the spec's, whatever the body holds: an all-`null`
  column is still `character`, and `[]` is `integer(0)` if the spec says so.
  This removes the type-instability that every lattice-based reader has.
- A mismatch raises `zujson_type_error` with `$path` (a JSON Pointer),
  `$expected` and `$actual`.
- Conversion happens in C during the build, so unselected members are never
  built.
- A spec can be inferred from an example: `json_spec_infer(x)`.
- Dates and times are parsed **only** here, by a named format, never
  guessed.

**CI.** `full`.

**Tests.** A spec built from a value parses that value's JSON back to it
(`identical()`); `vctrs::vec_ptype()` of the result equals the spec, for
empty, all-null and full inputs (the type-stability property); each mismatch
kind gives the right `$path`; timestamps against Python
`datetime.fromisoformat` over seeded inputs with offsets, fractions and leap
days; `msgspec`'s published strict/lax conversion table as the reference for
which coercions are allowed (integer to double yes, string to number no).

### Stage 9.2 — JSONPath (RFC 9535)

```r
json_query(x, "$.store.book[?@.price < 10].title")
json_query_paths(x, path)        # normalised paths of the matches
```

First-party, over a `json_doc`. The RFC's grammar, selectors, filter
expressions and function extensions (`length`, `count`, `match`, `search`,
`value`). `match` and `search` need I-Regexp (RFC 9485); use a small
first-party matcher for that subset, not R's regex engine, whose syntax
differs.

**CI.** `full`: a query language over untrusted documents, with its own fuzz
harness and a step budget so a filter cannot run unbounded.

**Tests.** `jsonpath-standard/jsonpath-compliance-test-suite` (`cts.json`):
every valid selector's result set, every invalid selector refused; RFC 9535's
own tables; Python `jsonpath-rfc9535` as a second reference on a seeded
corpus.

### Stage 9.3 — Schema inference and description

`json_structure(x)`: a compact description of a document's shape (types,
optional members, array element types), as an R value and as a JSON Schema
2020-12 fragment. This is the reading half of schema support and needs no
validator. It is what a person wants first from an unknown API.

---

## v1.0.0 — the stable release

No new features. The promise is the product.

- **Stage 10.1 — API freeze.** Every export reviewed against the naming
  table; anything deprecated since 0.5.0 removed; `lifecycle`-style badges
  dropped from what is stable. The options structs, condition classes and
  condition fields are declared stable, and the C API version is `1`.
- **Stage 10.2 — Performance pass.** Against Stage 2.6's benchmarks, with
  each change measured: a pool allocator sized by
  `yyjson_read_max_memory_usage()`; `READ_INSITU` on a private copy; a
  direct columnar build for `data_frame = TRUE` when keys repeat in order; a
  writer that skips the mutable document for atomic vectors and data frames
  and appends straight to the buffer (#78's idea, generalised); ALTREP lazy
  character vectors only if they measure and only if `rchk` can still see
  them. Target: no slower than `yyjsonr` on any corpus file, and stated
  where it is.
- **Stage 10.3 — Parity audit.** The parity table above, re-checked row by
  row against the then-current Go, Python and Rust libraries, with each row
  linked to its test.
- **Stage 10.4 — Documentation.** Articles: the mapping on one page; request
  bodies; reading a large response; streaming; configuration files; signing
  and canonical form; migrating from `jsonlite`; the C API.
- **Stage 10.5 — Assurance at zero gaps.** Every row of
  `.agents/assurance.md` is `done` or `n/a`. A second `pkg-bug-hunt`.

## Not planned, and why

- **JSON Schema validation.** A validator for 2020-12 is larger than this
  whole package, with its own test suite and its own release rhythm
  (`$ref` resolution, formats, vocabularies). It belongs in a sibling,
  `zujsonschema`, on the C API of 0.8.0. zujson supplies what it needs:
  documents, pointers, canonical equality, I-Regexp.
- **SIMD parsing (simdjson).** C++ and a second vendored parser. yyjson is
  within a small factor without it, and the R tree build dominates. Revisit
  only if Stage 10.2 shows the reader, not the builder, is the cost.
- **jq and JMESPath.** Second query languages after JSONPath. A sibling's
  job if anyone needs one.
- **`serializeJSON()`-style lossless R serialisation.** That is a format for
  R, not JSON for other programs. `saveRDS()` exists.
- **Guessing types on read**: dates from strings, numbers from strings,
  factors. Only by a spec (Stage 9.1).
- **S3 dispatch on every node when writing.** `default =` (Stage 4.6) is the
  fallback; a class that wants its own JSON converts itself before the call.
- **Global options that change a mapping.** One exists, for a budget. No
  more.
- **A raised depth cap.** It protects the C stack. Making the tree builders
  iterative would lift it, and is considered in Stage 10.2 only if a real
  document needs it.
- **`ALLOW_INVALID_UNICODE` as a switch.** Every string returned is marked
  UTF-8, and that mark must be true.
- **BSON, MessagePack, CBOR, YAML, TOML, GeoJSON, ProtoJSON.** Other
  packages, some already in the family.

## Risks that span versions

- **Argument and option drift between routes.** Ten entry points today, more
  later. Stage 2.2's "every export accepts `options`" test and the
  equivalent-routes test in `test-fuzz.R` are the guard; each new route
  joins both.
- **Lifecycle objects in a package that had none.** The stream (0.3.0) and
  the document (0.8.0) bring fork, serialisation and finalizer-order bugs
  the package has never had. Each gets a model-based fuzz target before it
  is exported.
- **First-party parsers next to yyjson.** The array scanner (3.4), the
  canonical number layout (6.3), diff (7.3), JSONPath and I-Regexp (9.2) are
  not yyjson's and do not inherit its testing. Each has a named external
  suite, and none merges on a round trip alone.
- **CRAN cadence.** Eight feature releases at CRAN's preferred spacing is
  well over a year. Versions may be combined (0.4.0 with 0.5.0, 0.6.0 with
  0.7.0) if the reverse-dependency load makes fewer, larger releases
  cheaper. The order within them stands.
- **Suite time.** The CRAN budget is a few seconds. Corpus-driven tests
  (JSON5, json-patch-tests, the JSONPath CTS, JCS numbers) run as `tools/`
  scripts and CI jobs with recorded baselines, like `tools/jsontestsuite.R`,
  with a small pinned sample inside testthat.
- **yyjson upgrades.** Each version entry checks for a new upstream release.
  A bump is its own pull request, with the `i_` baseline and the benchmark
  re-recorded.
