#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
build=$(mktemp -d "${TMPDIR:-/tmp}/core-boundary.XXXXXX")
trap 'rm -rf "$build"' EXIT
compiler=${CXX:-g++}
flags=(-std=c++17 -Wall -Wextra -Werror -pthread)
"$compiler" "${flags[@]}" -O2 tests.cpp -o "$build/tests"
"$build/tests"
"$compiler" "${flags[@]}" -O2 measure.cpp -o "$build/measure"
"$build/measure"
if [[ ${SANITIZE:-0} == 1 ]]; then
    "$compiler" "${flags[@]}" -O1 -g -fsanitize=address,undefined -fno-omit-frame-pointer tests.cpp -o "$build/sanitized"
    "$build/sanitized"
fi
