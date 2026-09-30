# Architecture inventory

Phase 1 of [MULTIPLATFORM_MIGRATION.md](../../MULTIPLATFORM_MIGRATION.md): what the code is today, what it depends on,
and which parts can be shared with a Windows build. Taken from Compositor-KR 1.4.1 on the `Compositor-Multiplatform`
branch. Counts are historical lines of source, including comments; they are not a current complete model count. The corrected [type inventory](document-model-inventory.md) and [branch evidence](repository-evidence.md) take precedence for this review.

## Summary

| Area | Size | Platform dependencies | Shareable today? |
|---|---|---|---|
| C pixel algorithms (`Compositor/Rendering/*.c`, `*.h`) | ~3,100 lines, 12 source files | None: C11 and the C library. Threads go through `ParallelFor.h` | **Yes.** Built for Windows and macOS by `CMakeLists.txt`, tested by `Tests/Pixels` |
| Swift, geometry and logic only | ~1,400 lines, 10 files | Foundation and CoreGraphics *geometry* (`CGRect`, `CGPoint`), available only through full Foundation in the recorded Windows Swift spike | Candidates after dependency review; no Core language selected (see [windows-decisions.md](windows-decisions.md)) |
| Swift, CoreGraphics images | ~3,600 lines, 14 files (PSD, masks, tiled renderer, resizers, history, guides) | `CGImage`, `CGContext`, `CGColorSpace` — Apple only | After an image-buffer boundary |
| Document model (`CanvasDocument`, `ImageLayer`) | in `EditorSession.swift` (1,008 lines) | The file imports SwiftUI; layers hold `CGImage`s | After it moves out and gets its own image type |
| Core Image filters and effects | 20 files, ~5,500 lines, 75 `CIFilter`/`CIImage` uses | Core Image — no Windows equivalent | Needs a renderer boundary and a Windows implementation |
| Metal | 5 files, ~1,500 lines (`GPUCanvas`, brush coverage, layer effects, warp, noise) | Metal | Behind the planned renderer boundary |
| Vision (object selection, subject removal) | 2 files, ~440 lines | Vision | Needs a Windows equivalent (e.g. an ONNX model) — a product decision |
| UI | AppKit in 83 files (~24,000 lines), SwiftUI in 72 (~22,000) | AppKit, SwiftUI | No: Windows needs its own UI layer |
| Updates | Sparkle, 2 files | macOS only | Windows needs its own updater |

Swift in total: ~36,600 lines. The macOS app remains the reference implementation.

## Shared now

`CMakeLists.txt` builds these straight from `Compositor/Rendering`, where the Xcode project also compiles them, so both
apps use one copy:

AdjustPixels, BrushPixels, ContentFill, DitherPixels, HealPixels, LensPixels, LevelsPixels, LiquifyPixels, NoisePixels,
PSDPixels, SmearPixels, WandPixels, with `ParallelFor.h` for threads (and `Platform/Windows/ParallelForWin32.c` on
Windows).

Clang blocks (`^{ }`) and Grand Central Dispatch, which MSVC can't compile, are gone from the pixel code: main's 1.4.5
portability cleanup introduced `ParallelFor.h` (GCD on Apple platforms, OpenMP or one thread elsewhere), and this
branch adds its Windows path — the system thread pool — and converts 1.4.5's Scanlines dither, which had reintroduced
blocks. Every conversion was checked byte for byte against the code before it, threaded and not.

Portability notes for this code:
- `long` is 32 bits on Windows. 1.4.5 moved Liquify and Smear to `ptrdiff_t`; the rest still use `long` for pixel
  coordinates and in-window offsets, which fits because `DocumentLimits.maxSide` is 30,000 (30,000² < 2³¹).
- `M_PI` needs `_USE_MATH_DEFINES` under MSVC; `CMakeLists.txt` defines it.
- Since 1.4.5, Smear takes each dab's rounding seed from its caller instead of a shared atomic counter, so no C11
  atomics (and no experimental MSVC switch) are needed.
- The sources contain UTF-8 comments; MSVC needs `/utf-8` or it reads them in the system code page (949 on Korean
  Windows).

## Swift files with no Apple-only framework

These import only Foundation, CoreGraphics geometry, or Observation, and use no `CGImage`/`CGContext`:
`ArithmeticExpression`, `Crop`, `DocumentLimits`, `EditorSession+Projects`, `LayerAppearance`, `LayerGroups`,
`ToolDefaults`, `PSDAdjustmentCoding`, `CanvasViewport`, `ProjectTabLayout`.

`EditorSession+Projects` extends `EditorSession`, so it can only move with the model.

## Main couplings to untangle

1. **The document model lives with the UI.** `CanvasDocument` and `ImageLayer` are in `EditorSession.swift`, which
   imports SwiftUI; layers carry `CGImage`s. Separating data from UI helpers is a useful boundary, but removing one file import does not remove the stored Apple types. The dependency map starts with a smaller enum/helper seam before the document types.
2. **Pixels are `CGImage`s everywhere.** Masks, PSD coding, the tiled renderer and the resizers read and write through
   `CGContext`. A small image-buffer type (width, height, row bytes, premultiplied RGBA) that the C code already
   speaks would let this logic run without CoreGraphics; the macOS side converts at the edge.
3. **The `.comp` format** (`ProjectStore.swift`) reads and writes PNGs through ImageIO. The manifest (`ProjectManifest`,
   Codable) is portable; the PNG coding needs a per-platform encoder behind one interface. The format itself does not
   change.
4. **Core Image and Metal** do the filters, effects and the canvas. These are the renderer boundary in
   ARCHITECTURE.md and the largest single piece of Windows work.
5. **File watching** (`ProjectWatcher`) uses `DispatchSource` with `O_EVTONLY`, which is macOS-only. Windows needs
   `ReadDirectoryChangesW` behind the same interface.

## Suggested order of boundaries

Smallest and safest first; each step keeps the macOS app building and its tests passing.

1. ✅ Shared C pixel code builds and is tested on Windows and macOS.
2. Golden tests for the rest of the C code (levels, adjust, dither, wand, heal), like `Tests/Pixels` has for Liquify
   and Smear.
3. Move `CanvasDocument`/`ImageLayer` into a UI-free file (no behavior change).
4. Introduce the image-buffer type and move mask and PSD logic onto it.
5. Define the renderer contract (`Rendering/API`), with Core Image/Metal as its first implementation.
6. Windows app shell, once the decisions in [windows-decisions.md](windows-decisions.md) are made.
