# Spike findings (kept as evidence, not merged)

The Core-language spike and the WinUI 3 window test live on the `spike/core-model` branch, under `Spikes/CoreModel`
(last commit `e3bf386`). They are experiments: **not merged into product code, no `.comp` change, no macOS behavior
change, no Swift/C++ decision.** Full reports on that branch: `Spikes/CoreModel/README.md` and
`Spikes/CoreModel/winui-test.md`. This page keeps the findings that shape [core-api.md](../core-api.md).

## What was built

Two small Cores with the same model (document, layers, groups, transform, undo/redo) — one in Swift, one in C++ —
behind one C header, driven by C++, C# and a WinUI 3 window (Windows App SDK 2.5.1, .NET 10). Everything passed on
Windows and macOS, locally and in CI.

## Findings that the Core contract must answer

1. **Per-item queries that rebuild the whole collection.** The spike's C boundary returned the layer list one row at
   a time (`cc_outline_row(i)`), and each call rebuilt the entire outline. Reading all rows is O(n²).
2. **Measured cost, 2,000 layers, reading the list row by row** (WinUI self-test, Release builds):

   | | This machine | CI `windows-latest` |
   |---|---|---|
   | Swift Core | 327–366 ms | 487 ms |
   | C++ Core | 24–26 ms | 34 ms |

   500 layers: Swift ~20 ms, C++ ~2 ms. Adding 2,000 layers one undo step at a time: 50–105 ms in either. The
   difference between the Cores here is value copying in the rebuild, not the language; one bulk call removes the
   rebuild for both. → core-api.md §8 (bulk-first).
3. **Duplicate-ID bug in both Cores.** `group([a, a])` wasn't rejected. It ended the host process: Swift at a bounds
   check (`0xC000001D`, before corrupting anything), C++ with heap corruption (`0xC0000374`). C# could not catch
   either. Fixed in the spike with tests. → core-api.md §6 (ID rules), §10 (validation at the boundary).
4. **Ownership and memory safety across the boundary.** Found or confirmed:
   - A fault inside an in-process Core ends the whole app; exceptions and traps don't cross the C boundary.
   - C++ exceptions reaching Swift terminate the process; C++ methods returning references or interior pointers
     aren't usable from Swift (lifetime unknown).
   - Strings crossing the boundary need an explicit owner and encoding (UTF-8 bytes, cut on character boundaries).
   - Handles were retained objects freed by an explicit destroy call (`SafeHandle` on the C# side).
   - Neither Core locked; one document used from two threads at once was left undefined.
   → core-api.md §7 (ownership), §9 (threading), §10 (errors).
5. **WinUI XAML compiler and long paths.** The XAML compiler is a .NET Framework tool and failed under a working
   folder whose real path exceeded 260 characters. Short paths (as on CI) work. → keep Windows project paths short.
6. **Self-contained Windows App SDK specifics.**
   - `RuntimeInfo.AsString` throws: it loads `Microsoft.WindowsAppRuntime.Insights.Resource.dll`, which
     self-contained deployment doesn't ship.
   - On Korean Windows, file-version strings come from `ko-KR\*.mui`, which ships from an older build
     (3.2.0.2511 beside a 3.2.3.2609 `Microsoft.UI.Xaml.dll`); use numeric versions.
   - The app folder is ~155 MB, ~47 MB of it AI/ML/Search components the metapackage brings.
   - Both Cores add the VC++ runtime (`vcruntime140`, `vcruntime140_1`, `msvcp140`); the Swift Core also
     `swiftCore.dll` (5.8 MB). The app still needs the .NET 10 runtime unless .NET is published self-contained.
7. **Swift on Windows without Foundation.** `CGFloat`/`CGPoint`/`CGSize`/`CGRect` exist only in full Foundation
   (with ICU, ~63 MB runtime); `CGAffineTransform`, `CGPath`, `CGImage` don't exist. `FoundationEssentials` (13.5 MB,
   no ICU) has `UUID`, `Data` and JSON. → core-api.md §2 (Core types).

## What the findings decided (2026-09-30)

- **Core language: C++20** (with the C kernels kept and a C ABI) — findings 2, 4 and 7 weighed against the project's
  priorities, Windows performance first; the safety gap shown by finding 3 is closed by fail-fast rules, sanitizers,
  fuzzing and differential tests. [windows-architecture.md](windows-architecture.md) §1.
- **Bulk-first reads** (finding 1–2) are in core-api.md §8; **policies instead of dialogs** in §11.1.
- **Windows App SDK** self-contained with component packages only (finding 6); .NET self-contained; static CRT, so no
  VC++ runtime files ship.
- **Keep Windows project paths short** (finding 5) — the repository layout and CI already do.

Merging 1.4.5 added one more finding: its Scanlines dither brought back Clang blocks and GCD in shared C code — caught
at once because the shared code is built with MSVC in CI. Syncing after every `main` release (Q22) keeps such fixes
small.

