#!/bin/sh
# R -d passes only the R binary; append the arguments we want here.
exec env DYLD_INSERT_LIBRARIES=/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/lib/clang/17/lib/darwin/libclang_rt.asan_osx_dynamic.dylib ASAN_OPTIONS=detect_leaks=0 UBSAN_OPTIONS=print_stacktrace=1 "$@" --vanilla --no-echo -f "$ZU_SCRIPT" --args $ZU_ARGS
