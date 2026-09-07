# Maintainer-only: refresh src/vendor/yyjson from an upstream release.
# Needs network. Run from the package root:
#
#   Rscript tools/vendor-yyjson.R
#
# Then review the diff under src/vendor/yyjson/ and commit it together with
# the version bump here. Vendored sources are never edited in place: a local
# change belongs upstream or in a patch applied by this script.

version <- "0.12.0"
url <- sprintf(
  "https://github.com/ibireme/yyjson/archive/refs/tags/%s.tar.gz",
  version
)

tarball <- tempfile(fileext = ".tar.gz")
download.file(url, tarball, mode = "wb")

exdir <- tempfile("yyjson-")
untar(tarball, exdir = exdir)

root <- file.path(exdir, paste0("yyjson-", version))
dest <- "src/vendor/yyjson"

unlink(dest, recursive = TRUE)
dir.create(dest, recursive = TRUE, showWarnings = FALSE)
file.copy(file.path(root, "src", c("yyjson.c", "yyjson.h")), dest)
file.copy(file.path(root, "LICENSE"), dest)

# The version is asserted from R by zujson_info() and from the test suite, so
# a silent upstream bump cannot slip through.
cat("vendored yyjson", version, "into", dest, "\n")
cat("checksums:\n")
print(tools::md5sum(list.files(dest, full.names = TRUE)))
