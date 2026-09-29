# Spike: a shared document Core — Swift or C++?

**Status: evidence only. No decision is made here, and nothing in this folder is part of the app.** The macOS app
does not build, link or reference any of it (it lives outside the Xcode project's synchronized folders).

The question comes from [docs/multiplatform/windows-decisions.md](../../docs/multiplatform/windows-decisions.md) §1:
before moving the real document model anywhere, test whether a platform-independent Core written in Swift works on
Windows, and compare it with a C++ Core used from native UIs on each platform.

Both Cores implement the same small model — `Document`, `Layer`, `LayerGroup`, `Transform`, and undo/redo
`History` — with the same behavior and the same tests, and both expose the same C header, so one host program runs
against either.

## What's here

| Path | What it is |
|---|---|
| `swift/Sources/CoreModel/` | The Swift Core (391 lines). Swift standard library only. |
| `swift/Sources/CoreModelCABI/` | The Swift Core behind the C header (`@_cdecl`), built as `CompositorCore.dll` / `.dylib`. |
| `swift/Sources/WindowsAPIDemo/` | Swift calling Win32, shell and COM APIs directly, using the Core. |
| `swift/Tests/CoreModelTests/` | 17 XCTest cases. |
| `cpp/include`, `cpp/src/core.cpp` | The C++20 Core (443 lines). Standard library only. |
| `cpp/src/c_api.cpp` | The C++ Core behind the same C header, built as `CompositorCoreCpp.dll`. |
| `cpp/tests/core_tests.cpp` | The same cases for the C++ Core (no test framework). |
| `cpp/Package.swift`, `cpp/swift-interop/` | Swift using the C++ Core directly through Swift's C++ interoperability — how the macOS app would consume it. |
| `include/compositor_core.h` | The shared C boundary: what a Windows UI (WinUI via C# or C++/WinRT, or Win32) would call. |
| `hosts/cpp/host.cpp` | A stand-in UI that drives a Core only through the C header, including Korean names. Built against both Cores. |
| `CMakeLists.txt` | Builds the C++ Core, its tests and the host (against both Cores). |
| `../../.github/workflows/spike-core-model.yml` | CI for all of the above on Windows and macOS (runs only when the spike changes). |

## Build commands

Windows (Visual Studio 2022 Build Tools with the C++ workload and Windows SDK, Swift 6.4, CMake), from a
*x64 Native Tools* prompt, in `Spikes/CoreModel`:

```
swift test --package-path swift                                   # Swift Core tests
swift build --package-path swift && <bin>\WindowsAPIDemo.exe       # Swift calling Windows APIs
swift build --package-path swift -c release --product CompositorCore
cmake -S . -B build -DSWIFT_CORE_DIR=<swift release bin path>      # swift build -c release --show-bin-path
cmake --build build --config Release
ctest --test-dir build -C Release --output-on-failure             # C++ Core + host on both Cores
swift test --package-path cpp                                     # Swift using the C++ Core
```

macOS: the same commands, plus the Xcode build system on the Swift package:
`xcodebuild test -scheme CoreModelSpike-Package -destination 'platform=macOS'` (in `swift/`).

## Results

### Windows — run on this machine, 2026-09-29

Swift 6.4.0 (x86_64-unknown-windows-msvc), MSVC 19.44 (VS 2022 Build Tools), Windows SDK 10.0.26100, CMake 4.4.

| Check | Result |
|---|---|
| Swift Core: 17 tests | ✅ pass |
| Swift → Win32/COM demo (window + Swift message callback, UTF-16, `SHGetKnownFolderPath` + `CoTaskMemFree`, DPI) | ✅ pass |
| Swift Core as a DLL: exports all 12 C functions | ✅ (checked with `dumpbin`) |
| C++ Core: 11 test groups, MSVC `/W4 /permissive-` | ✅ pass, 0 warnings |
| Host program against the **C++** Core DLL | ✅ pass |
| Host program against the **Swift** Core DLL | ✅ pass — identical output, Korean names round-trip and are cut on character boundaries |
| Swift using the C++ Core (C++ interop), 2 tests | ✅ pass, after adding Swift-only accessors to the C++ Core (see below) |
| LLDB on the Swift code | ✅ breakpoints, backtrace, variables (Korean strings display correctly) |

### macOS — not run yet

There is no Mac here. `spike-core-model.yml` runs every command above on `macos-26` with Xcode 26.6, including
`xcodebuild` on the Swift package; it has not run because the spike hasn't been pushed. **Until it does, the macOS
column below is expectation, not evidence.** The Swift Core uses nothing macOS lacks; the only platform branch is
which C library provides `cos`/`sin` (`Darwin` vs `ucrt`).

The macOS app was not touched.

## The nine questions (Swift Core)

1. **Does a platform-independent Swift model compile reliably on Windows?** Yes, for this model: stock Swift 6.4,
   no changes for Windows except the C-library import for `cos`/`sin`. The toolchain itself warns about its own
   WinSDK module (`wchar_t … broken by a context change`) — harmless here, but a sign the Windows toolchain is less
   polished than Xcode's.
2. **Can a Windows UI consume it cleanly?** Through a C ABI, yes: a C++ program uses `CompositorCore.dll` exactly as
   it uses the C++ Core's DLL. A WinUI 3 app in C# (P/Invoke) or C++/WinRT would call the same header. *Not tested:*
   an actual WinUI 3 window — that needs the Windows App SDK (and the .NET SDK or C++/WinRT), which weren't installed.
   Writing the WinUI app itself in Swift (via the swift-winrt bindings) was not tested either.
3. **The actual interop boundary.** Swift → C ABI (`@_cdecl`, opaque handles, UTF-8 strings, status codes) → UI
   language. The C++ Core needs exactly the same boundary for a C# UI; only a C++/WinRT UI could skip it. So for a
   C#/WinUI front end, the boundary is the same size whichever Core is chosen (~125 lines each here). `@_cdecl` is
   an underscored attribute (widely used, but formally unofficial).
4. **Can Swift call Windows APIs without glue?** Yes. `import WinSDK` exposes Win32, the shell and COM functions
   directly; a Swift closure works as a `WNDPROC`. Rough edges: `BOOL` arrives as `Bool`, so `GetMessageW`'s `-1`
   error can't be told from `TRUE`; UTF-16 strings need small helpers. WinRT/WinUI APIs are *not* in WinSDK — they
   need generated bindings (swift-winrt), which is where glue would appear.
5. **Can one Swift Core build with Xcode and on Windows?** SwiftPM builds it on Windows (verified). On macOS it's a
   normal Swift package that Xcode opens and the app can depend on; the CI job checks this with `xcodebuild` (not yet
   run).
6. **Build system and dependencies.** Windows: Swift toolchain (~5 GB installed; winget also installed Python 3.10
   for LLDB) plus VS Build Tools (~3.4 GB). The app must ship the Swift runtime: the Core DLL (326 KB) needs only
   `swiftCore.dll` (5.9 MB) — because the Core avoids Foundation. Using Foundation would add ~50 MB (ICU alone is
   37 MB). C++ Core DLL: 42 KB, needs only the VC++ runtime.
7. **Can the Core stay free of UI/GPU frameworks?** Yes, and it's easy to check: both Cores import only their
   standard libraries. Keeping Swift free of Foundation is a rule to enforce (e.g. no `UUID`, `Data`, `Date`), not
   something the language does for us.
8. **Debugging and CI.** LLDB works on Windows from the command line (verified); Visual Studio's debugger can step
   Swift but doesn't understand Swift types (not verified here). VS Code with the Swift extension is the practical
   IDE. CI: `compnerd/gha-setup-swift` on `windows-latest`; Xcode on `macos-26`. The C++ Core gets the full
   Visual Studio debugger and sanitizers on Windows.
9. **Long-term risk for a Photoshop-class app** — see the recommendation.

## Swift Core vs C++ Core

| | Swift Core | C++ Core |
|---|---|---|
| macOS app uses it | Directly, as today's code does. The existing model is already Swift. | Through C++ interop: works, but needs Swift-specific accessors and must never throw (below). |
| Windows UI uses it | Through the C header (same as C++ for C#). A Swift WinUI app could use it directly (untested). | Directly from C++/WinRT; through the C header from C#. |
| Migrating today's model | Move and trim existing Swift code. | Rewrite the existing Swift model, mask and format code (several thousand lines: .comp, PSD, masks, history) — against AGENTS.md's "do not rewrite all Swift into C++". |
| Undo snapshots | Copy-on-write values: snapshots share unchanged data for free. | Copies are deep. Sharing needs explicit `shared_ptr<const …>` design. |
| Errors | `throws`, checked by the compiler. | Exceptions, which **crash the process** if they reach Swift (verified: `0xe06d7363`). Every Swift-facing call needs a non-throwing wrapper. |
| Tooling on Windows | Younger: needed MSVC anyway, long-path and symlink (Developer Mode) friction, toolchain warnings. | Mature: MSVC, Visual Studio debugger, sanitizers, profilers. |
| Ecosystem for imaging (codecs, color, GPU) | Small on Windows; most libraries are C/C++ reached through the C boundary anyway. | Large and native. |
| Runtime to ship on Windows | +6 MB Swift runtime. | None beyond VC++ runtime. |
| Hiring / contributors | Swift developers rarely know Windows. | Common for Windows imaging. |

C++ interop friction found (Swift using the C++ Core): C++ default arguments aren't imported; template types such as
`std::optional<uint64_t>` can't be named from Swift, so the C++ header needed typedefs; methods returning a
reference or a pointer into the object (`name()`, `layer()`) aren't imported at all, so the C++ Core needed copying
accessors (`nameCopy()`, `isGroupNode()`). All solvable, but each is C++ API bent for Swift.

## Recommendation (not a decision)

Neither option is ruled out by this spike. What it does show:

- **Swift Core is technically viable on Windows today** for model-type code: it compiled, tested, exported a C ABI
  and called Windows APIs without C/C++ glue. It keeps the existing Swift model and the macOS app's path unchanged,
  which is its main advantage.
- **The C++ Core is the lower-risk *Windows* choice but the higher-risk *migration*:** mature tooling, but the macOS
  app would consume it through an interop layer that crashes on exceptions and needs Swift-shaped accessors, and the
  existing Swift model would have to be rewritten.
- For a C#-based WinUI front end, **the boundary is a C ABI either way**, so the UI side doesn't decide between them.

Explicit risks of the Swift path:
1. Windows Swift tooling maturity (debugger, IDE, toolchain regressions) over a multi-year product.
2. Swift-on-Windows depends on a small set of maintainers; WinUI-from-Swift (swift-winrt) even more so.
3. Discipline required to keep Foundation and Apple frameworks out of the Core; a slip adds ~50 MB and Apple-only
   behavior.
4. Performance-critical imaging will still be C/C++ (as today's pixel code is) — the Swift Core must stay a model,
   not become the pixel engine.

Explicit risks of the C++ path:
1. A rewrite of the existing Swift model and formats, with two implementations during the transition.
2. Exception-safety and lifetime rules at the Swift boundary, in every call the macOS app makes.
3. Losing copy-on-write snapshots, which the current undo design relies on for memory.

Suggested next steps, still before choosing:
1. Push this spike so CI produces the macOS results.
2. A WinUI 3 window (C# or C++/WinRT) showing the layer outline from **both** DLLs — needs the Windows App SDK.
3. Put one real pixel buffer through both Cores (the image-buffer boundary from
   [inventory.md](../../docs/multiplatform/inventory.md)) to see copy-on-write vs. explicit sharing with real memory.

## Notes from this machine

Local-environment issues, not findings about the approaches: the session's working folder has a very long path, so
MSVC (260-character limit) and git needed short build folders or `core.longpaths`; SwiftPM warned it could not make
its `.build` symlinks and `swift run` failed to launch (Windows Developer Mode off), so executables were run directly;
`windows.h` defines `small` as a macro, which broke a variable name in the host.
