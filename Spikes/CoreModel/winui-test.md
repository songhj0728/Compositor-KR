# WinUI 3 window test

A C# WinUI 3 window calling each spike Core through the C boundary (`include/compositor_core.h`). **An experiment:**
it doesn't choose a Windows UI technology, isn't Compositor's Windows app, and doesn't choose a Core language. The
macOS app, the document model and the `.comp` format were not touched. No GPU or rendering work, no Experimental or
Preview API.

What it checks, from inside the WinUI process (`hosts/winui`, run with `selftest <folder>`):
the window activates; the Core is called from the UI thread with Korean names; the `ListView` renders what the Core
returned; buttons pressed through UI Automation change the Core and the list (add, undo, redo); a Core used on a
background thread hands its result back to the UI thread; which DLLs loaded from where; and a picture of the window.

Results from this machine are in `hosts/winui/results/`; CI runs the same on a fresh `windows-latest` runner.

## A. Versions

| | This machine | CI (`windows-latest`) |
|---|---|---|
| Visual Studio | Build Tools 2022 17.14.41 (MSVC 19.44, toolset 14.44), no IDE | VS 18 Enterprise (VC++ runtime 14.51) |
| Windows SDK | 10.0.26100 (and 10.0.22621) | runner image |
| .NET | SDK 10.0.401 (LTS), runtime 10.0.12 | .NET 10 via `actions/setup-dotnet` |
| Windows App SDK | **2.5.1** (stable, NuGet, 2026-09-16) | same |
| — resolved parts | WinUI 2.3.9 (Microsoft.UI.Xaml 3.2.3), Foundation 2.3.12, Runtime 2.5.1, Base 2.0.4, InteractiveExperiences 2.1.9, DWrite 2.1.0, AI 2.5.5, ML 2.1.94, Search 2.5.5, Widgets 2.0.5; Windows SDK BuildTools 10.0.26100.4654 | same |
| Swift (for the Swift Core DLL) | 6.4.0 | 6.4.0 |
| OS | Windows 11, build 26200 | Windows Server, build 26100 |

Every package version is a release (no `-experimental`/`-preview` suffix). APIs used: `Window`, `AppWindow.Resize`,
`ListView`, `Button`, `ButtonAutomationPeer`, `RenderTargetBitmap`, `DispatcherQueue` — all stable.

## B. The WinUI 3 window

✅ Builds with 0 warnings and runs, unpackaged and self-contained (nothing installed for the Windows App SDK), on this
machine and on CI. `results/window-swift.png` and `results/window-cpp.png` are the window as XAML rendered it.

## C. C# → C ABI → Swift Core DLL

✅ All checks pass, locally and on CI: UI-thread calls with Korean names, the rendered list, add/undo/redo through
buttons, background-thread use. `CompositorCore.dll` and `swiftCore.dll` loaded from the app folder, with Swift not on
`PATH`.

## D. C# → C ABI → C++ Core DLL

✅ The same checks pass, locally and on CI. `CompositorCoreCpp.dll` loaded from the app folder.

## E. Existing Core tests

All still pass after this test's one Core change (G4):

| | Result |
|---|---|
| Swift Core, XCTest | 18 passed (17 + 1 new) — local and CI (Windows, macOS, Xcode) |
| C++ Core tests | passed, MSVC 0 warnings — local and CI (both OSes) |
| C++ host on each Core / C# host on each Core | passed / passed |
| Swift using the C++ Core | 2 passed |
| Framework-boundary check | passed, both OSes |
| Shared C pixel tests (`Tests/Pixels`, MSVC) | passed |
| macOS app (`verify.yml`: build + all tests) | passed on both branches; app code unchanged |

CI: [run 36609111202](https://github.com/songhj0728/Compositor-KR/actions/runs/36609111202), every step green on
both OSes, including the WinUI self-test on both Cores.

## F. Runtime files to ship

What each Core adds next to the app (all verified to load from the app folder, not the system):

| | Swift Core | C++ Core |
|---|---|---|
| Core | `CompositorCore.dll` 326 KB | `CompositorCoreCpp.dll` 42 KB |
| Language runtime | `swiftCore.dll` 5.8 MB | — |
| VC++ runtime | `vcruntime140.dll`, `vcruntime140_1.dll`, `msvcp140.dll` (0.7 MB) — `swiftCore.dll` needs them too | same three |

The VC++ runtime is new with a Core: the Windows App SDK itself doesn't need it. Two ways to provide it: copy the three
files next to the app (done here; Microsoft allows it but then Windows Update doesn't patch them), or require the
VC++ Redistributable installer.

The rest of the app folder (~155 MB, the same for either Core): the Windows App SDK runtime, self-contained. About
47 MB of it is AI/ML/Search (`onnxruntime.dll`, `DirectML.dll`, …) that the metapackage brings and this window doesn't
use; referencing only the needed component packages should drop it (not tried here).

Still required on the machine: the **.NET 10 runtime** (the app is framework-dependent) — or publish .NET
self-contained, which adds it to the folder. Windows 10 1809 or later. The Windows App Runtime does not need to be
installed.

## G. Problems found and what fixed them

1. **XAML compiler fails on long paths.** WinUI's XAML compiler is a .NET Framework tool and couldn't open its own
   `obj\…\input.json` under this machine's working folder (virtualized path over 260 characters). Building from a
   short folder works; CI (short paths) builds from the repository as is. Lesson: keep the Windows project's paths short.
2. **`RuntimeInfo.AsString` throws in a self-contained app** — it loads `Microsoft.WindowsAppRuntime.Insights.Resource.dll`,
   which self-contained deployment doesn't ship. The self-test reads the runtime DLLs' file versions instead.
3. **Version strings came from the Korean `.mui`.** On Korean Windows, .NET read `Microsoft.ui.xaml.dll`'s version
   string from `ko-KR\Microsoft.ui.xaml.dll.mui`, which the Windows App SDK ships from an older build (3.2.0.2511 beside
   a 3.2.3.2609 DLL). Same binaries as CI (identical hash); the self-test now reports the numeric version.
4. **A bug inside a Core takes the whole WinUI process down; C# can't catch it.** Grouping the same layer twice (a
   real bug in both spike Cores) ended the process: Swift stopped at a bounds check (`0xC000001D`, illegal
   instruction, before anything was corrupted); C++ ran into undefined behavior and the heap was corrupted
   (`0xC0000374`). Both Cores now refuse it (`duplicateLayer`), with tests in both Cores and both hosts. The general
   point stands for any in-process Core: validate everything at the C boundary, test it hard (fuzzing the C functions
   is cheap), and plan crash reporting and document recovery.
5. **The boundary as written costs O(n²) for a layer list.** Each `cc_outline_row` call rebuilds the whole outline.
   2,000 layers: Swift Core 330–490 ms, C++ Core 24–34 ms (local and CI). A real UI needs one call that returns all rows
   (or a change set). The Swift Core is slower here because each rebuild copies layer values and strings; the fix is
   the same for both and is API design, not language.
6. **The VC++ runtime is a new deployment item** (F).
7. Not tested, by design: one document used from two threads at once. Neither Core locks; the UI must keep each
   document on one thread at a time.

## H. Swift Core and C++ Core, as this test saw them

Behind a C# WinUI app both behaved identically: same C#, same checks, both pass. The differences:

| | Swift Core | C++ Core |
|---|---|---|
| Adds to the app | 6.1 MB (Core + Swift runtime) + VC++ runtime | 42 KB + VC++ runtime |
| When the Core has a bug | stops at once, before corrupting memory (traps) | undefined behavior: may corrupt data silently, or crash later |
| This test's layer-list pattern | slower (value copies) — fixable by API design | faster |
| Windows build | Swift toolchain (5 GB), MSVC; community CI action | MSVC only; mature debugger and profilers |
| macOS side | the existing model's language; no interop | interop with sharp edges (exceptions end the process, APIs bent for Swift) |
| Migration | move and refactor the existing Swift model | rewrite ~11,000 lines of model and format code |

## I. Can the Core language be chosen from this test?

**No.** This test found no fatal problem with either Core behind a C# WinUI 3 window, and the Windows UI side treats
them the same — so it doesn't separate them. What decides it is outside this test: the cost of rewriting the existing
model (favors Swift), Windows toolchain and CI maturity (favors C++), and how failures behave (favors Swift). The next
evidence would come from the Core boundary itself (steps 0–5 of
[the migration plan](../../docs/multiplatform/document-model-inventory.md)), as agreed.

## Real changes vs. experiment

**Changed in product code: nothing.** No file under `Compositor/`, `CompositorTests/` or the Xcode project; no change to
the `.comp` format or the shared C layer in this step.

**Experiment only** (all under `Spikes/CoreModel`, branch `spike/core-model`, not merged anywhere):
- `hosts/winui/` — the WinUI 3 test window, its self-test, and this machine's results.
- Both spike Cores refuse duplicate layer IDs (G4), with tests; the C++ and C# hosts check it.
- `.github/workflows/spike-core-model.yml` — builds and runs the WinUI self-test on both Cores on `windows-latest`.

**On this machine only** (not in the repository): .NET SDK 10.0.401 installed; the Windows App SDK packages in the
NuGet cache; the crash probe used for G4; the short-path copy used to build locally (G1).
