#!/usr/bin/env bash
# Fails if either spike Core reaches for a platform, UI or GPU framework. Run from Spikes/CoreModel; CI runs it on
# every change. The Cores may use only their language's standard library (and, for Swift, the C library for math).
set -u
cd "$(dirname "$0")"
failures=0

fail() { echo "BOUNDARY: $*"; failures=$((failures + 1)); }

# Swift Core: only these imports.
allowed_swift='^(Darwin|ucrt|Glibc)$'
while IFS= read -r line; do
    module=$(sed -E 's/^.*import ([A-Za-z_]+).*$/\1/' <<<"${line#*:}")
    [[ $module =~ $allowed_swift ]] || fail "Swift Core imports $module (${line%%:*})"
done < <(grep -rHnE '^\s*(@_implementationOnly\s+|@preconcurrency\s+)?import\s' swift/Sources/CoreModel)

# C++ Core: only standard headers and its own.
while IFS= read -r line; do
    header=$(sed -E 's/^.*#include\s*([<"][^>"]+[>"]).*$/\1/' <<<"${line#*:}")
    case $header in
        \"compositor/*) ;;
        \<*.h\> | \<*/*\>) fail "C++ Core includes $header (${line%%:*})" ;;
        \<*\>) ;;
        *) fail "C++ Core includes $header (${line%%:*})" ;;
    esac
done < <(grep -rHnE '^\s*#\s*include' cpp/include cpp/src/core.cpp)

# Either Core: no framework types by name, even through a transitive import.
frameworks='\b(NS[A-Z]\w+|CG[A-Z]\w+|CI[A-Z]\w+|MTL\w+|VN[A-Z]\w+|UI[A-Z][a-z]\w+|SwiftUI|AppKit|Metal|CoreImage|WinUI|winrt::|Microsoft::UI|ID3D\w+|D3D\w+|HWND|HRESULT|Vk[A-Z]\w+)\b'
while IFS= read -r line; do
    fail "framework name in a Core: $line"
done < <(grep -rHnE "$frameworks" swift/Sources/CoreModel cpp/include cpp/src/core.cpp | grep -vE ':\s*//')

if (( failures )); then
    echo "$failures boundary violation(s)"
    exit 1
fi
echo "Both Cores use only their standard libraries"
