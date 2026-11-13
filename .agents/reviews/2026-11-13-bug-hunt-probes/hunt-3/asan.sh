#!/bin/sh
# usage: asan.sh script.R  -- runs under the sanitizer build in hunt-3/san/lib
H=$(cd "$(dirname "$0")" && pwd)
ASAN=/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/lib/clang/17/lib/darwin/libclang_rt.asan_osx_dynamic.dylib
RH=$(R RHOME)
ZULIB=$H/san/lib DYLD_INSERT_LIBRARIES=$ASAN ASAN_OPTIONS=detect_leaks=0 UBSAN_OPTIONS=print_stacktrace=1 R_HOME=$RH $RH/bin/exec/R --no-echo --no-restore --file="$1" 2>&1
