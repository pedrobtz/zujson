# Assurance

How this package meets `.claude/shared/assurance.md`. CI checks this
file (r-actions `assurance.yml`), so keep the headings and table
columns as they are.

- **Statuses:** a cell is a fact, `gap #<issue>` or `n/a: <reason>`.

## Kinds

`compiled` `untrusted-input` `spec` `emits`

## Why these kinds

- `compiled`: `src/` holds the R bridge and vendored yyjson 0.12.0.
- `untrusted-input`: `json_parse()`, `json_parse_raw()`,
  `json_parse_file()`, `json_validate()` and `json_parse_ndjson()` read
  bodies that came from someone else.
- `spec`: RFC 8259 JSON, and NDJSON framing.
- `emits`: `json_write()`, `json_write_raw()` and the NDJSON writers produce
  request bodies that another program parses.

The package is not `lifecycle`, so it has no Objects table. Nothing it
returns outlives the call that made it. Each external pointer in
`zu_cond.c` (`zu_extptr_own_doc`, `_mut_doc`, `_buf`) owns a native buffer
for one `.Call` only. It is released eagerly on success, and it is never
returned to R. Its only job is to free the buffer when an R error longjmps
past the explicit free. `test-conditions.R` and `tools/sanitizer-exercise.R`
cover that, under ASan and valgrind.

## Required checks

`Where` names the workflow file under `.github/workflows/` that runs the
check. Add `(own)` when that workflow is the package's own rather than a
call to r-actions.

| Check         | Status    | Where              |
| ------------- | --------- | ------------------ |
| sanitizers    | done      | native-checks.yaml |
| valgrind      | done      | native-checks.yaml |
| rchk          | done      | native-checks.yaml |
| gctorture     | done      | native-checks.yaml |
| analyzers     | gap #25 |                    |
| alloc-failure | gap #26 |                    |
| mutation      | gap #27 |                    |
| fuzz          | gap #28 |                    |
| fuzz-reach    | gap #28 |                    |

`fuzz` is a gap even though `native-checks.yaml` has a `fuzz` job. That job
drives `json_parse()` from R with random bytes and JSON-alphabet soup
(`test-fuzz.R` at `ZUJSON_FUZZ=50000`). It is not coverage-guided, and its
oracle is the condition contract (a value or a `zujson_error`), plus raw and
character `json_validate()` agreeing. That is a contract check, not an answer
check.

## Boundaries

One row per boundary the package crosses. An oracle knows the answer:

- a conformance suite or test vectors;
- a reference implementation;
- a round trip;
- equivalent inputs compared;
- the bytes the other side received.

"No crash" is not an oracle.

<!-- markdownlint-disable MD013 -->
| Boundary                                         | Oracle                                                                                                                                                       | Carried by                                                                             |
| ------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------ | -------------------------------------------------------------------------------------- |
| JSON text accepted or refused (RFC 8259 reader)  | nst/JSONTestSuite at a pinned commit: 95/95 `y_`, 188/188 `n_`, and the `i_` split held to a recorded baseline                                                | tools/jsontestsuite.R, run by hand; in CI: gap #29                                   |
| JSON text → R values (type mapping)              | jsonlite as a reference reader: an agreement table, and a divergence table for what design §5 says differs                                                   | tests/testthat/test-interop-jsonlite.R; known answers in test-parse.R, test-simplify.R |
| JSON text → valid or not (`json_validate()`)     | JSONTestSuite through `json_validate()`; a differential against `json_parse()` that must differ on exactly two classes (NUL escape, depth)                     | tools/jsontestsuite.R; tests/testthat/test-validate.R                                  |
| Equivalent read routes (character, raw, file, NDJSON line) | the same bytes give the same value by every route                                                                                                  | raw and character `json_validate()` only, in test-fuzz.R; value differential: gap #30 |
| NDJSON body → records                            | known answers per framing case (blank lines, CRLF, no final newline); raw and text agree; round trip with the writer                                         | tests/testthat/test-ndjson.R                                                           |
| R values → JSON text (`json_write()`)            | exact output bytes; jsonlite reads back what was written; write/parse round trip with `identical()`                                                          | tests/testthat/test-write.R; test-interop-jsonlite.R; test-roundtrip.R                 |
| R doubles → JSON numbers                         | jsonlite reads back the identical double (pi, 1/3, 0.1, 1e-300, 2^53, `double.xmax`); whole doubles as exact integer text                                    | tests/testthat/test-interop-jsonlite.R; test-write.R                                   |
| `Date` and `POSIXct` → ISO 8601 text             | known answers at both ends of the range; differential against base R `format()` over random instants: gap #31                                              | tests/testthat/test-write.R                                                            |
| R strings in other encodings → UTF-8 JSON        | a latin1 and a UTF-8 spelling of one string give identical bytes; a `bytes` or invalid UTF-8 string is a classed error                                       | tests/testthat/test-write.R                                                            |
| Output under a hostile session                   | the same bytes under `LC_ALL=C` and `options(OutDec = ",", scipen = -5, digits = 3)`                                                                          | gap #32                                                                              |
| Data frame ↔ array of objects                    | jsonlite `fromJSON()` gives the same frame; NDJSON and `json_write()` write a row identically; round trip                                                   | tests/testthat/test-interop-jsonlite.R; test-ndjson.R; test-roundtrip.R                |
| records → NDJSON body                            | round trip; `json_write_ndjson_raw()` and `json_write_ndjson()` give identical bytes; a record never contains a raw newline                                  | tests/testthat/test-ndjson.R                                                           |
<!-- markdownlint-enable MD013 -->

## Limits

One row per limit the package enforces. "Straddled by" is the test of
`limit - 1`, `limit` and `limit + 1` on every path that reaches it.

<!-- markdownlint-disable MD013 -->
| Limit                                                    | Unit                                          | Straddled by                                                                                                                   |
| -------------------------------------------------------- | --------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------ |
| `ZUJSON_MAX_DEPTH` (1000), parse                         | containers, root = 1                          | tests/testthat/test-parse.R (`limit`, `limit + 1`; data frame cell at `limit - 1`, `limit`, `limit + 1`); test-fuzz.R           |
| `ZUJSON_MAX_DEPTH` (1000), write                         | containers, root = 1; a data frame counts two | tests/testthat/test-write.R (`limit`, `limit + 1`; data frame cell at emitted `limit`, `limit + 1`); test-roundtrip.R           |
| `ZUJSON_MAX_DEPTH` (1000), NDJSON, both directions        | containers per record                         | gap #33                                                                                                                      |
| `zujson.max_df_cells` (default 5e7)                      | cells, rows × union of keys                   | tests/testthat/test-simplify.R straddles 100 at 100 and 121 cells, not at 99 and 101, and never under NDJSON: gap #34         |
| int32 range on parse (`INT_MIN` is `NA`)                 | integer value                                 | tests/testthat/test-parse.R (±2147483647, ±2147483648); test-interop-jsonlite.R                                                |
| double range on parse (past it is `Inf`)                 | decimal magnitude                             | tests/testthat/test-parse.R at 1e308 and 1e309; at `DBL_MAX` and its rounding midpoint: gap #35                              |
| int64 range for whole doubles on write                   | double value, [-2^63, 2^63)                   | tests/testthat/test-write.R at 1e18 and 1e300 only; at ±2^63: gap #36                                                        |
| `Date` range on write                                    | days, 0000-01-01 to 9999-12-31                | tests/testthat/test-write.R (-719529, -719528, 2932896, 2932897)                                                               |
| `POSIXct` range on write                                 | seconds, 0000-01-01 to 9999-12-31             | tests/testthat/test-write.R upper end only; the lower end only at -1e300: gap #36                                            |
| `INT_MAX` bytes: a string value on parse, a document or NDJSON record on write | bytes                     | gap #37                                                                                                                      |
<!-- markdownlint-enable MD013 -->
