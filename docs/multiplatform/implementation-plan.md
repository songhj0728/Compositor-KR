# Implementation plan — Wave 0 and Wave 1

What gets built first, now that the architecture is decided ([windows-architecture.md](windows-architecture.md),
[architecture-questions.md](architecture-questions.md)). **Not started.** Each item is one reviewable change on
`Compositor-Multiplatform`; after each, `verify.yml` (macOS build + all tests) and `shared.yml` (shared code on Windows
and macOS) must pass, the macOS app must behave exactly as before, and `.comp` must not change.

The model does not move in Waves 0–1. Wave 2 — the C++ Core reaching parity with the Swift model, one area at a time,
proven by differential tests — starts only when every gate at the end of this page is green.

## Wave 0 — measure and pin down behavior (tests and fixtures only)

No product code changes.

| # | Item | Output | Runs on |
|---|---|---|---|
| 0.1 | **Golden tests for every C kernel** not yet covered: `AdjustPixels` (incl. 1.4.5's Camera Raw parametric curves and contrast), `DitherPixels` (all 11 styles incl. Scanlines, glow, dots), `LevelsPixels`, `WandPixels`, `HealPixels`, `BrushPixels`, `NoisePixels`, `LensPixels`, `ContentFill`, `PSDPixels` | references generated from the 1.4.5 code; tolerances documented as in `Tests/Pixels`; threaded = single-threaded checks | Windows (MSVC) + macOS (Clang), `shared.yml` |
| 0.2 | **`.comp` golden fixtures** covering every layer kind and field (image, folder, masks linked/unlinked, clipping, every adjustment kind, all effects, shape, text with color/font runs, guides, each color space) | fixtures under `CompositorTests/Fixtures/`; a Swift test that loads, saves and compares **semantically** (parsed JSON + image bytes) | macOS, `verify.yml` |
| 0.3 | **ICC profile export**: a macOS test writes `CGColorSpace.copyICCData()` for each `ColorSpaceID` | `Resources/ColorProfiles/*.icc` committed; hashes recorded | macOS |
| 0.4 | **Color reference set**: conversions (import from embedded profiles, CMYK JPEG export, document → display) computed with ColorSync on reference images | reference outputs + ΔE2000 tolerance ≤ 1 for the LittleCMS side (used in Wave 1) | macOS |
| 0.5 | **Renderer golden images**: the Metal/Core Image renderer's output for each blend mode, masks, clipping, each adjustment, each effect, at 8-bit | reference PNGs for the future D3D11 renderer | macOS |
| 0.6 | **Performance baselines** on the macOS app: add/duplicate/group/undo with 2,000 and 10,000 layers; layer-panel refresh; brush dab throughput (Smear's per-dab allocations, windows-architecture §2.1); open/save of a large project | numbers recorded in `docs/multiplatform/baselines.md` | macOS |
| 0.7 | **Model-file boundary check** (report-only): which files under `Compositor/Document`, `Compositor/IO` import UI or Apple imaging frameworks | CI step that prints the list; becomes blocking in Wave 1.4 | macOS + Windows |
| 0.8 | **Text reference set**: Latin and Korean samples laid out with Core Text (line breaks, advances, bounds) | fixtures for the DirectWrite comparison in Wave 1 | macOS |

## Wave 1 — the Core's shell, the macOS model's seams, the Windows skeleton

Language-neutral macOS refactors and new code beside the app; nothing replaces the Swift model yet.

### 1A — C++ Core skeleton (new code, not linked into the macOS app)

| # | Item |
|---|---|
| 1.1 | `Core/` C++20 library with CMake presets (Windows x64, macOS arm64/x64): Core types of core-api §2 (`Scalar`, `CorePoint`…`CorePath`, `LayerID`, `ColorSpaceID`, `ColorProfile`, `ImageRef` with tiled storage), status codes, fail-fast, hardened STL flags. |
| 1.2 | C ABI header v0 (`Core/include/compositor_core.h`): handles, IDs, status codes, image wrap/retain/release, snapshot handle and bulk row arrays — reviewed as the contract. |
| 1.3 | CI: Core unit tests, ASan (MSVC and Clang), UBSan (Clang), libFuzzer smoke over the C ABI (random operation sequences with invalid and duplicate IDs), on Windows and macOS. |
| 1.4 | Bindings: C# P/Invoke generated from the header (ClangSharp, pinned); Swift module map + thin wrapper built and tested in CI, **not** linked into the app. |
| 1.5 | Differential test harness: a small operation-script format run against the Swift model (from the macOS test target) and the C++ Core, comparing snapshots and manifests. First scripts: layer tree without pixels — create, duplicate, delete, move, group/ungroup, rename, visibility, opacity, blend mode, undo/redo. |

### 1B — macOS seams (moves and splits; behavior unchanged)

| # | Item |
|---|---|
| 1.6 | Inventory step 1: move `ImageLayer`/`CanvasDocument` to `Document/CanvasDocument.swift`; split `apply(CGImage)`/`path(in:)`/UI helpers out of model files (E6, E7); `FilterKind` to its own file. The boundary check (0.7) becomes blocking for the moved files. |
| 1.7 | **E5: policy, not dialog.** `deleteWithLiveMaskChoice` asks in the UI layer and calls a model function that takes `ClipPolicy` (`bake`/`unlink`); the model function never presents anything. Tests for both policies. |
| 1.8 | **Q25:** code that makes pixels takes the document's color space as a parameter where the Core will need it, leaving `WorkingColorSpace` in place for untouched macOS code. |

### 1C — Windows skeleton (no Compositor features)

| # | Item |
|---|---|
| 1.9 | Native DLL (`CompositorNative.dll`, static CRT): D3D11.1 device + Direct2D on the same device, flip-model swap chain in a WinUI 3 `SwapChainPanel`, drawing one `ImageRef` (tiles uploaded lazily) with pan/zoom; the canvas targets of Q17 measured on a synthetic document. |
| 1.10 | LittleCMS integration with the shipped profiles; the color reference set (0.4) passes with ΔE2000 ≤ 1. |
| 1.11 | DirectWrite text engine prototype; the text reference set (0.8) compared, differences recorded. |
| 1.12 | **Distribution skeleton:** WiX MSI (per-machine, UpgradeCode `15737362-8B12-4BF4-8314-16E529A0C200`, `MajorUpgrade`, downgrade blocked) of the skeleton app with an About box and **Check for Updates…** through WinSparkle against a test feed; `windows-release.yml` running build → test → package unsigned; upgrade from one test version to the next verified on a clean VM with settings preserved; signing steps wired but disabled until the cloud-signing account and EdDSA key exist. |
| 1.13 | Native AOT vs ReadyToRun measured for the C# shell (Q19); Windows App SDK component packages only (Q18); MSI size recorded. |

## Gates before model migration (Wave 2) begins

All must pass in CI, on the stated platforms:

| Gate | Where |
|---|---|
| macOS app: full `verify.yml` suite, unchanged behavior | macOS |
| Shared C kernels: all golden tests (0.1) within tolerance; threaded = single-threaded | Windows MSVC + macOS Clang |
| `.comp` golden fixtures (0.2): semantic round-trip | macOS |
| Core unit tests, ASan, UBSan, fuzz smoke (1.3) | Windows + macOS |
| Differential tests (1.5) for the layer-tree operations: Swift model and C++ Core produce identical snapshots and manifests | macOS (both implementations in one process) |
| C ABI boundary: no exception/trap escapes under fuzzing; `wrongThread` and `invalidHandle` returned, not crashed | Windows + macOS |
| Model boundary check (0.7) blocking for Wave 1.6's files | macOS |
| Color: LittleCMS vs ColorSync ΔE2000 ≤ 1 on the reference set | Windows |
| Performance: snapshot of 10,000 layers < 5 ms; single-layer `changes(since:)` < 0.1 ms; add layer < 50 µs at 2,000 layers (core-api §8.4) | Windows + macOS |
| Distribution skeleton: MSI major upgrade and downgrade refusal verified; WinSparkle check against the test feed | Windows |

## Wave 2 and after (for orientation only)

The C++ Core takes over one area at a time, in the dependency-map order ([migration-dependency-map.md](migration-dependency-map.md)):
layer tree and history → manifest codec → `ImageRef` in the macOS app (the Swift model keeps working through an
adapter) → selection/`CorePath` → operations. Each area switches only after its differential tests match, and each
switch is reversible until the Swift implementation of that area is deleted.
