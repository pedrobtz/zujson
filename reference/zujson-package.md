# zujson: Lightweight JSON Parsing and Serialization

Converts between JSON text and ordinary R vectors and lists through a
small, predictable set of functions, backed by vendored 'yyjson'
<https://github.com/ibireme/yyjson> and requiring no system JSON
library. Parsing accepts character, raw and file input and reports
failures through structured conditions; serialization writes UTF-8 bytes
suitable for use directly as an HTTP request body. The type mapping is
deliberately narrow and fully documented, so what goes in and what comes
out are both predictable.

## Scope

zujson is the JSON an HTTP client needs: one document, or one NDJSON
body, in memory, to and from ordinary R vectors and lists. It leaves
out, on purpose:

- matrix and N-d array simplification: a JSON array of arrays stays a
  list, and a matrix is written as its values in column-major order;

- incremental streaming of a document that does not fit in memory;

- JSON Pointer, JSON Patch and schema validation;

- custom serializers for classes the type mapping does not name.

Data frame reconstruction is opt-in, through `data_frame = TRUE`, so
that the default mapping documented in
[`json_parse()`](https://pedrobtz.github.io/zujson/reference/json_parse.md)
is what you get unless you ask for something else. Use jsonlite when you
need one of the above.

## See also

The other packages of the `zu*` family:
[zukomp](https://github.com/pedrobtz/zukomp) for compression,
[zuxml](https://github.com/pedrobtz/zuxml) for XML,
[zuyaml](https://github.com/pedrobtz/zuyaml) for YAML, and zuhttp, the
HTTP client that uses them.

## Author

**Maintainer**: Pedro Baltazar <pedrobtz@gmail.com> \[copyright holder\]

Authors:

- Pedro Baltazar <pedrobtz@gmail.com> \[copyright holder\]

Other contributors:

- YaoYuan (author of the bundled yyjson library) \[contributor,
  copyright holder\]
