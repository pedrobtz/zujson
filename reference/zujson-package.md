# zujson: Portable JSON Parsing and Serialization

Converts between JSON text and ordinary R vectors and lists through a
small, predictable set of functions, backed by vendored 'yyjson' sources
and requiring no system JSON library. Parsing accepts character, raw and
file input and reports failures through structured conditions;
serialization writes UTF-8 bytes suitable for use directly as an HTTP
request body. The type mapping is deliberately narrow and fully
documented, so what goes in and what comes out are both predictable.

## See also

Useful links:

- <https://github.com/pedrobtz/zujson>

- <https://pedrobtz.github.io/zujson/>

- Report bugs at <https://github.com/pedrobtz/zujson/issues>

## Author

**Maintainer**: Pedro Baltazar <pedrobtz@gmail.com>

Authors:

- Pedro Baltazar <pedrobtz@gmail.com>

Other contributors:

- YaoYuan (author of the bundled yyjson library) \[contributor,
  copyright holder\]
