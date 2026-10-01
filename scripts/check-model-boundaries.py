#!/usr/bin/env python3
"""Guard the dependency-clean model declarations; run from any directory.

Like the spike guard, this is a lexical dependency check, not a Swift parser.
CI also typechecks the declaration on its own to detect undeclared dependencies.
"""
from pathlib import Path
import re
import sys

root = Path(__file__).resolve().parent.parent
forbidden = re.compile(
    r"\b(?:import|SwiftUI|AppKit|LocalizedStringKey|Foundation|CoreGraphics|CoreImage|Metal|"
    r"NS\w*|CG\w*|CI[A-Z]\w*|MTL\w*|WinUI|Windows|WinSDK|HWND|HRESULT|D3D\w*|ID3D\w*)\b"
)
failed = False
paths = [root / f"Compositor/Document/{name}.swift" for name in ("FilterKind", "TextAlignment")]
paths += sorted((root / "Compositor/Core").rglob("*.swift"))
paths.append(root / "Spikes/RenderSnapshot/projection.hpp")
paths.append(root / "Spikes/RenderResources/resources.hpp")
for path in paths:
    source = path.read_text(encoding="utf-8")
    # Ignore literal strings and comments so documentation and raw values are not dependencies.
    code = re.sub(r'"(?:\\.|[^"\\])*"|//[^\n]*|/\*.*?\*/', "", source, flags=re.S)
    if path.is_relative_to(root / "Compositor/Core"):
        # UUID value semantics are the sole allowed framework dependency.
        code = re.sub(r"(?m)^import Foundation\s*$", "", code)
    violations = sorted(set(forbidden.findall(code)))
    if violations:
        print(f"BOUNDARY: {path.relative_to(root)}: {', '.join(violations)}", file=sys.stderr)
        failed = True
    else:
        print(f"{path.relative_to(root)}: dependency boundary passed")
sys.exit(1 if failed else 0)
