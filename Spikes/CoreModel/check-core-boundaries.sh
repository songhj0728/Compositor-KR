#!/usr/bin/env bash
# Fails if either spike Core reaches for a platform, UI or GPU framework. Run from Spikes/CoreModel; CI runs it on
# every change. The Cores may use only their language's standard library (and, for Swift, the C library for math).
# Portable regular expressions only: macOS's BSD grep and sed know no \s, \w or \b.
set -u
cd "$(dirname "$0")"
failures=0
space='[[:space:]]'
word='[A-Za-z0-9_]'

fail() { echo "BOUNDARY: $*"; failures=$((failures + 1)); }

# Code lines only: drop whole-line comments, then anything after //.
code() { grep -rHnE "$1" "${@:2}" | grep -vE "^[^:]+:[0-9]+:$space*//" | sed -E 's#//.*$##'; }

# Swift Core: only these imports.
while IFS= read -r line; do
    module=$(sed -E "s/^.*import$space+([A-Za-z_]+).*\$/\\1/" <<<"$line")
    case $module in
        Darwin | ucrt | Glibc) ;;
        *) fail "Swift Core imports $module (${line%%:*})" ;;
    esac
done < <(code "^$space*(@_implementationOnly$space+|@preconcurrency$space+)?import$space" swift/Sources/CoreModel)

# C++ Core: only standard headers and its own.
while IFS= read -r line; do
    header=$(sed -E "s/^.*#$space*include$space*([<\"][^>\"]+[>\"]).*\$/\\1/" <<<"$line")
    case $header in
        \"compositor/*) ;;
        \<*.h\> | \<*/*\>) fail "C++ Core includes $header (${line%%:*})" ;;
        \<*\>) ;;
        *) fail "C++ Core includes $header (${line%%:*})" ;;
    esac
done < <(code "^$space*#$space*include" cpp/include cpp/src/core.cpp)

# Either Core: no framework type or module by name, even through a transitive import.
names="(NS[A-Z]$word+|CG[A-Z]$word+|CI[A-Z]$word+|MTL$word+|VN[A-Z]$word+|UI[A-Z][a-z]$word+|SwiftUI|AppKit|Metal|CoreImage|WinUI|winrt::|Microsoft::UI|ID3D$word+|D3D$word+|HWND|HRESULT|Vk[A-Z]$word+)"
while IFS= read -r line; do
    fail "framework name in a Core: $line"
done < <(code "(^|[^A-Za-z0-9_])$names([^A-Za-z0-9_]|\$)" swift/Sources/CoreModel cpp/include cpp/src/core.cpp |
         grep -E "(^|[^A-Za-z0-9_])$names([^A-Za-z0-9_]|\$)")

if ((failures)); then
    echo "$failures boundary violation(s)"
    exit 1
fi
echo "Both Cores use only their standard libraries"
