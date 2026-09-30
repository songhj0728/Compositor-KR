#!/usr/bin/env python3
"""Guard the first dependency-clean model declaration; run from any directory.

Like the spike guard, this is a lexical dependency check, not a Swift parser.
CI also typechecks the declaration on its own to detect undeclared dependencies.
"""
from pathlib import Path
import re
import sys

root = Path(__file__).resolve().parent.parent
path = root / "Compositor/Document/FilterKind.swift"
source = path.read_text(encoding="utf-8")
# Ignore literal strings and comments so documentation and raw values are not dependencies.
code = re.sub(r'"(?:\\.|[^"\\])*"|//[^\n]*|/\*.*?\*/', "", source, flags=re.S)
forbidden = re.compile(
    r"\b(?:import|SwiftUI|AppKit|LocalizedStringKey|Foundation|CoreGraphics|CoreImage|Metal|"
    r"NS\w*|CG\w*|CI[A-Z]\w*|MTL\w*|WinUI|Windows|WinSDK|HWND|HRESULT|D3D\w*|ID3D\w*)\b"
)
violations = sorted(set(forbidden.findall(code)))
if violations:
    print(f"BOUNDARY: {path.relative_to(root)}: {', '.join(violations)}", file=sys.stderr)
    sys.exit(1)
print("FilterKind uses no imports or platform/UI names")
