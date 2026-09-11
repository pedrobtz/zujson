#!/usr/bin/env Rscript
#
# Conformance: run nst/JSONTestSuite against zujson.
#
# The suite is the standard external check on what a JSON parser accepts and
# rejects -- the question this package has to get right, because the input is
# an untrusted response body. Its files are named by what a parser must do:
#
#   y_*  must be accepted
#   n_*  must be rejected
#   i_*  implementation-defined; either answer conforms, and the counts are
#        reported so a change in them is visible rather than silent
#
# Current standing, for the pinned commit: 95/95 and 188/188 correct, and the
# i_ split is 12 accepted / 23 rejected. The 23 rejections are all invalid
# UTF-8 and lone surrogates, which yyjson refuses because its UTF-8 validation
# is on -- that is what makes marking parsed strings CE_UTF8 honest, so it is
# a deliberate strictness rather than a gap.
#
# The i_ split is also a useful regression signal in its own right. Turning on
# YYJSON_READ_BIGNUM_AS_RAW (so 1e309 reads as Inf instead of failing the whole
# document) moved exactly five files here -- i_number_huge_exp,
# i_number_neg_int_huge_exp, i_number_pos_double_huge_exp,
# i_number_real_neg_overflow and i_number_real_pos_overflow -- from reject to
# accept, and changed no y_ or n_ answer at all. That is the shape a safe
# change to the read flags has: it moves only what is free to move.
#
# Needs network on the first run. Run from the package root:
#
#   Rscript tools/jsontestsuite.R
#
# Set JSONTESTSUITE_DIR to a checkout to skip the download, which is also how
# a CI job avoids hitting GitHub on every build:
#
#   JSONTESTSUITE_DIR=~/src/JSONTestSuite Rscript tools/jsontestsuite.R
#
# Exits non-zero if any y_ or n_ file gets the wrong answer.
#
# Base R only, and deliberately so: this is the same constraint as
# tools/sanitizer-exercise.R, so the script can run anywhere the package
# builds without dragging in a test framework.

library(zujson)

# Pinned to a commit, not to master: a conformance result that changes because
# somebody added a file upstream is not a result about this package. Bump it
# deliberately and review what moved.
commit <- "1ef36fa01286573e846ac449e8683f8833c5b26a"

root <- Sys.getenv("JSONTESTSUITE_DIR", "")
if (!nzchar(root)) {
  url <- sprintf("https://github.com/nst/JSONTestSuite/archive/%s.tar.gz",
                 commit)
  tarball <- tempfile(fileext = ".tar.gz")
  cat("downloading JSONTestSuite", substr(commit, 1, 7), "\n")
  download.file(url, tarball, mode = "wb", quiet = TRUE)
  exdir <- tempfile("jsontestsuite-")
  untar(tarball, exdir = exdir)
  root <- file.path(exdir, paste0("JSONTestSuite-", commit))
}

parsing <- file.path(root, "test_parsing")
if (!dir.exists(parsing)) {
  stop("no test_parsing/ under '", root, "'", call. = FALSE)
}

# Every file is read as bytes and handed to the raw entry point. Reading them
# as text would be wrong twice over: the suite is full of deliberately invalid
# UTF-8, which a text read mangles or refuses, and of embedded NULs, which no
# R string can carry. Bytes are also what an HTTP response body actually is.
read_bytes <- function(path) {
  n <- file.info(path)$size
  if (is.na(n)) stop("cannot stat '", path, "'", call. = FALSE)
  if (n == 0) return(raw(0))
  readBin(path, "raw", n = n)
}

files <- sort(list.files(parsing, pattern = "[.]json$", full.names = TRUE))
if (!length(files)) stop("test_parsing/ is empty", call. = FALSE)

kind <- substr(basename(files), 1, 1)
kind[!kind %in% c("y", "n", "i")] <- "?"

accepted <- logical(length(files))
parsed <- character(length(files))

for (i in seq_along(files)) {
  bytes <- read_bytes(files[i])
  accepted[i] <- isTRUE(json_validate(bytes))
  # json_parse() is run as well as json_validate() because the two are allowed
  # to disagree on exactly one thing -- valid JSON that no R value can hold --
  # and that divergence is a documented part of the contract. Anything else
  # showing up here is a bug in one of them.
  parsed[i] <- tryCatch({
    json_parse(bytes)
    "ok"
  }, zujson_error = function(e) class(e)[1],
     error = function(e) paste0("bare:", conditionMessage(e)))
}

report <- function(label, idx, want) {
  wrong <- idx[accepted[idx] != want]
  cat(sprintf("%-28s %3d files, %3d wrong\n", label, length(idx), length(wrong)))
  for (f in basename(files[wrong])) cat("    ", f, "\n", sep = "")
  length(wrong)
}

cat("\n-- test_parsing ---------------------------------------------------\n")
bad <- report("y_ must be accepted", which(kind == "y"), TRUE) +
       report("n_ must be rejected", which(kind == "n"), FALSE)

# Free choices, so a change here is not a failure -- but it should be a
# deliberate one. Checking the count against a recorded baseline turns "diff 35
# lines of output by eye" into one line that either agrees or does not.
i_baseline <- 12L

i_idx <- which(kind == "i")
cat(sprintf("%-28s %3d files, %3d accepted, %3d rejected%s\n",
            "i_ implementation-defined", length(i_idx),
            sum(accepted[i_idx]), sum(!accepted[i_idx]),
            if (sum(accepted[i_idx]) == i_baseline) ""
            else sprintf("   <- CHANGED, baseline is %d accepted", i_baseline)))
for (j in i_idx[order(!accepted[i_idx], basename(files[i_idx]))]) {
  cat("    ", if (accepted[j]) "accept" else "reject", "  ",
      basename(files[j]), "\n", sep = "")
}

if (any(kind == "?")) {
  cat("unnamed by convention, skipped:",
      paste(basename(files[kind == "?"]), collapse = ", "), "\n")
}

# The one documented divergence: json_validate() answers "is this JSON", and
# json_parse() additionally has to build an R value. A string containing an
# escaped NUL is valid JSON that no R string can hold, so TRUE from one and a
# zujson_parse_error from the other is correct. Any *other* pairing is not.
cat("\n-- json_parse() against json_validate() ---------------------------\n")
split_ok <- accepted & parsed != "ok"
cat(sprintf("valid but unrepresentable in R: %d\n", sum(split_ok)))
for (j in which(split_ok)) {
  cat("    ", basename(files[j]), " -> ", parsed[j], "\n", sep = "")
}
odd <- which(!accepted & parsed == "ok")
if (length(odd)) {
  bad <- bad + length(odd)
  cat("INVALID BUT PARSED (must not happen):\n")
  for (j in odd) cat("    ", basename(files[j]), "\n", sep = "")
}
bare <- which(startsWith(parsed, "bare:"))
if (length(bare)) {
  bad <- bad + length(bare)
  cat("ESCAPED THE zujson_error CONTRACT (must not happen):\n")
  for (j in bare) cat("    ", basename(files[j]), " -> ", parsed[j], "\n", sep = "")
}

# Not pass/fail: these are inputs where the suite's author judged the *result*
# debatable rather than the accept/reject decision. Printed so a change in what
# this package produces is visible in a diff of the script's output.
transform <- file.path(root, "test_transform")
if (dir.exists(transform)) {
  cat("\n-- test_transform (informational) ---------------------------------\n")
  tf <- sort(list.files(transform, pattern = "[.]json$", full.names = TRUE))
  for (f in tf) {
    out <- tryCatch(
      paste(deparse(json_parse(read_bytes(f)), width.cutoff = 500),
            collapse = " "),
      zujson_error = function(e) paste0("<", class(e)[1], ">"))
    cat(sprintf("  %-42s %s\n", basename(f), substr(out, 1, 60)))
  }
}

cat("\n", length(files), " parsing files, ", bad, " wrong\n", sep = "")
if (bad > 0L) quit(status = 1L)
