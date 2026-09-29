# Spike: a shared document Core — Swift or C++?

**Status: evidence for a decision that has not been made.** Nothing in this folder is part of the app; the macOS app
does not build, link or reference it (it lives outside the Xcode project's synchronized folders). Swift is **not**
chosen as the Core language, and WinUI 3 remains a Windows UI candidate, not a choice. The Core's boundary is to be
settled before either — see [document-model-inventory.md](../../docs/multiplatform/document-model-inventory.md).

Both Cores implement the same small model — `Document`, `Layer`, `LayerGroup`, `Transform`, undo/redo `History` —
with the same tests, and both implement one C header, so the same host programs (C++ and C#) run against either.

## What's here

| Path | What it is |
|---|---|
| `swift/Sources/CoreModel/` | The Swift Core (391 lines). Swift standard library only. |
| `swift/Sources/CoreModelCABI/` | The Swift Core behind the C header (`@_cdecl`), built as `CompositorCore.dll` / `.dylib`. |
| `swift/Sources/WindowsAPIDemo/` | Swift calling Win32, shell and COM APIs directly, using the Core. |
| `swift/Tests/CoreModelTests/` | 17 XCTest cases. |
| `cpp/include`, `cpp/src/core.cpp` | The C++20 Core (443 lines). Standard library only. |
| `cpp/src/c_api.cpp` | The C++ Core behind the same C header, built as `CompositorCoreCpp.dll`. |
| `cpp/tests/core_tests.cpp` | The same cases for the C++ Core. |
| `cpp/Package.swift`, `cpp/swift-interop/` | Swift using the C++ Core directly (C++ interoperability) — how the macOS app would consume it. |
| `include/compositor_core.h` | The shared C boundary (12 functions). |
| `hosts/cpp/host.cpp` | A stand-in UI in C++ driving a Core only through the C header, Korean names included. |
| `hosts/csharp/` | The same in C#: the binding a C# WinUI 3 app would use (`CompositorCore.cs`) and its checks. |
| `check-core-boundaries.sh` | Fails if either Core imports or names a platform, UI or GPU framework. |
| `CMakeLists.txt` | Builds the C++ Core, its tests and the C++ host against both Cores. |
| `../../.github/workflows/spike-core-model.yml` | CI for all of the above on Windows and macOS. |

Build commands for each platform are the steps of `spike-core-model.yml`; locally on Windows they run from an
*x64 Native Tools* prompt with Swift 6.4 on `PATH`.

## Results

| | Windows | macOS |
|---|---|---|
| Swift Core — SwiftPM, 17 tests | ✅ local (Swift 6.4.0, MSVC 19.44) and CI (`windows-latest`) | ✅ CI (`macos-26`, Xcode 26.6) |
| Swift Core — **Xcode build system** (`xcodebuild test` on the package) | n/a | ✅ CI |
| Swift → Win32/COM directly (`WindowsAPIDemo`) | ✅ local and CI | n/a |
| Swift Core as a C-ABI library | ✅ `CompositorCore.dll`, 12 exports | ✅ `libCompositorCore.dylib` |
| C++ Core, tests | ✅ MSVC `/W4 /permissive-`, 0 warnings; CI | ✅ Apple Clang; CI |
| C++ host → Swift Core / → C++ Core | ✅ / ✅ identical output | ✅ / ✅ |
| C# host → Swift Core / → C++ Core | ✅ / ✅ local and CI (csc 4.8, C# 5) | n/a |
| Swift using the C++ Core (interop), 2 tests | ✅ after C++ changes for Swift (below) | ✅ CI |
| Boundary check (no framework in either Core) | ✅ | ✅ |
| LLDB on Swift code | ✅ local: breakpoints, backtrace, Korean strings | (Xcode, as today) |

CI evidence: [run 36595610253](https://github.com/songhj0728/Compositor-KR/actions/runs/36595610253) on `spike/core-model`, both jobs,
every step green, including the C# host on `windows-latest` and the boundary check on both. Getting there took three
fixes to the CI itself (below). The macOS app itself was not touched; `verify.yml` (build and all
tests) passes on both branches.

## Swift ↔ C# boundary: the actual code and what it costs

A C# WinUI 3 app can't call Swift (or C++) directly; it calls C functions. The chain is:

```
C# view model  →  CompositorCore.cs (DllImport + wrapper)  →  compositor_core.h  →  Swift @_cdecl functions  →  Core
```

| Layer | Lines here | Per new Core function |
|---|---|---|
| `compositor_core.h` | 49 (12 functions) | 1–2 lines |
| Swift exports (`CoreModelCABI.swift`) | 127 | ~8–12 lines: unwrap handle, convert strings, catch errors, return a status |
| C++ exports (`c_api.cpp`), for comparison | 122 | ~8 lines, same shape |
| C# binding (`CompositorCore.cs`) | 161 | 2 lines of `DllImport` + ~3–10 lines of wrapper |

What keeps it maintainable, and what it costs:
- **Mechanical, not clever.** Opaque handle, UTF-8 byte strings, status codes, caller-owned buffers. The C# side turns
  failures into exceptions and frees the handle through `SafeHandle`. Both Cores behave identically behind it.
- **Four places change per function** (header, export, C# import, C# wrapper). For a Core of hundreds of operations
  this should be **generated** (from the header, or from Swift/C++ declarations) rather than written by hand — a tool
  to build or adopt before the real migration, whichever Core language is picked.
- **Same cost for either Core.** A C# UI needs this C layer for C++ too; only a C++/WinRT UI could skip it for a C++
  Core. So the UI language, not the Core language, decides whether this layer exists.
- `@_cdecl` is widely used but formally unofficial (underscored); an official spelling has been proposed for Swift.
- Not covered: callbacks from Core to UI (change notifications), bulk pixel transfer, threading. Those need design
  before a real UI — likely "UI polls or receives a change token", and pixel data stays out of C#.

## C++ Core: results and what adopting it would mean

Both platforms ✅ (table above). On the macOS side, Swift using the C++ Core surfaced four frictions:
1. A C++ exception reaching Swift **terminates the process** (verified: `0xe06d7363`). Every Swift-facing C++ call
   needs a non-throwing wrapper.
2. Methods returning a reference or pointer into an object (`name()`, `layer()`) **aren't imported**; the Core
   needed copying accessors (`nameCopy()`, `isGroupNode()`).
3. C++ default arguments aren't imported.
4. Template types (`std::optional<uint64_t>`) can't be named in Swift; the Core needed typedefs.

### Moving the existing Swift model to C++: the work

From the [inventory](../../docs/multiplatform/document-model-inventory.md):
- **Model**: 47 types in 21 files, 8,180 lines of Swift (the files also hold related logic).
- **Formats**: PSD reader/writer 2,830 lines; `.comp` store 278 lines (+ controller 445, partly UI).
- **Tests**: 38 test files (7,726 lines) exercise these types from Swift; with a C++ Core they'd test it through
  interop or be rewritten in C++.
- **macOS call sites**: 17 files outside Document/IO use model types directly; each would go through the interop
  layer and its rules above.
- **Semantics to preserve**: copy-on-write undo snapshots (`DocumentHistory` shares unchanged images between steps);
  C++ would need an explicit shared-immutable design to match memory use.

Roughly 11,000 lines of model and format code rewritten in another language, with the macOS app switched over while
it keeps shipping — the kind of rewrite AGENTS.md rule 2 asks to avoid. The first five steps of the inventory's plan
(separating the model, geometry types, image handle) would be needed either way and don't commit to a language.

## Swift Core on Windows: toolchain and CI risks

Observed in this spike, not hypothetical:
- **CI setup broke once**: the Swift install action 404'd on a version string (`6.4` vs `6.4.0`). Windows Swift CI
  depends on a community action (`compnerd/gha-setup-swift`) and download naming.
- The other two CI fixes in this spike were not about Swift: a shell script using GNU-only regex (`\s`) behaved
  differently under macOS's BSD `grep`, and the old `csc.exe` misread forward-slash relative paths. Both are the kind
  of cross-platform CI friction any two-OS build will meet, whichever Core language.
- **Toolchain rough edges**: warnings from the toolchain's own WinSDK module; `swift run` couldn't launch without
  Developer Mode (symlinks); MSVC is still required; `BOOL` imports as `Bool`, losing `GetMessageW`'s `-1`.
- **Size**: the Windows toolchain is ~5 GB plus ~3.4 GB of VS Build Tools per developer machine.
- Longer-term: a small maintainer base for Swift-on-Windows (and more so for Swift/WinRT bindings); IDE support is
  VS Code + LLDB rather than Visual Studio; fewer Windows developers know Swift.

Mitigations: pin toolchain versions in CI (done); keep the Core's Windows build and tests in CI on every push (done);
keep the C boundary so the UI never depends on Swift tooling; keep pixel-heavy code in C (already shared).

## Working without Foundation in the Core

What it means day to day (Swift, Windows runtime sizes measured):

| Core uses | Runtime to ship on Windows | What you lose |
|---|---|---|
| Standard library only (this spike) | **5.8 MB** (`swiftCore.dll`) | `UUID`, `Data`, `Date`, `JSONEncoder`, `CGFloat`/`CGPoint`/`CGRect`, `URL`, `FileManager`, string formatting helpers |
| `FoundationEssentials` | **13.5 MB** — verified: `UUID`, `Data`, `Codable` JSON round-trip, no ICU | `CGFloat`/`CGPoint`/`CGRect`, locale-aware formatting, `URL` networking |
| Full `Foundation` | **~63 MB** (ICU alone 37 MB) | — |

Practical constraints of the stdlib-only Core:
- IDs need a Core type (the spike's `LayerID`), or `UUID` via FoundationEssentials. `.comp` stores UUID strings, so
  either must encode identically.
- **Geometry needs Core types**: on Windows, `CGFloat`/`CGPoint`/`CGSize`/`CGRect` exist only in full Foundation, and
  `CGAffineTransform`/`CGPath` not at all — so today's model, which stores them, must switch to its own (as the
  spike's `Point`/`Transform`). `CGFloat` encodes as a JSON number like `Double`, so `.comp` files don't change.
- `cos`/`sin` come from the C library (`Darwin` / `ucrt`) — a two-line `#if`.
- JSON (the `.comp` manifest) needs `Codable` encoders → FoundationEssentials, or the platform does the encoding.

When a feature needs Foundation, in order of preference:
1. **Keep it at the platform edge**: file access, URLs, dates for display — the app (Swift on macOS, C# on Windows)
   does it and hands the Core values.
2. **Use `FoundationEssentials`, not `Foundation`**: `#if canImport(FoundationEssentials) import FoundationEssentials
   #else import Foundation #endif` (Apple platforms have no separate FoundationEssentials module). +7.7 MB, no ICU.
3. **Full Foundation** only for something that truly needs ICU (locale-aware text), and preferably outside the Core.

## The Core stays free of platform, UI and GPU frameworks

Checked three ways:
1. `check-core-boundaries.sh` (CI, both platforms): Swift Core imports only `Darwin`/`ucrt`/`Glibc`; C++ Core
   includes only standard headers; neither names `NS*`, `CG*`, `CI*`, `MTL*`, `VN*`, SwiftUI, AppKit, Metal,
   Core Image, WinUI, WinRT, Direct3D, `HWND` or Vulkan types. Injected violations are caught.
2. **Link-level (Windows)**: `CompositorCore.dll` (release) depends only on `swiftCore.dll`, `KERNEL32.dll`, the VC++
   runtime and the CRT — no UI or GPU library.
3. Both Cores compile and pass their tests on each platform without any platform SDK in their sources.

## Recommendation (still not a decision)

- **Swift Core** is technically viable on both platforms and keeps the existing model and the macOS app's path. Its
  risks are Windows tooling and ecosystem, and the discipline to keep Foundation and CoreGraphics out of the Core.
- **C++ Core** has the stronger Windows tooling but means rewriting ~11,000 lines of model and format code and putting
  the macOS app behind an interop layer with sharp edges (exceptions, lifetimes).
- **For a C# WinUI front end, the C boundary exists either way** and should be generated, not hand-written.
- **Next, before choosing:** steps 0–5 of the inventory's plan. They're language-neutral, keep the macOS app unchanged
  in behavior, and turn today's model into something either Core could hold. Then the WinUI 3 window test against the
  real boundary.

## Notes from this machine

The session's working folder has a very long path, so MSVC (260-character limit) and git needed short build folders
or `core.longpaths`; SwiftPM couldn't make its `.build` symlinks (Developer Mode off), so executables were run
directly; `windows.h` defines `small` as a macro, which broke a variable name in the C++ host; winget installed
Python 3.10 alongside Swift (for LLDB).
