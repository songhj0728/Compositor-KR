# Document model inventory and migration plan

What the document model is made of today, what each part depends on, where it should end up under the Core
contract ([core-api.md](../core-api.md)), and the order in which it can be separated from macOS — file by file.
**Nothing here has been moved yet**, and no Core language is chosen; the first steps pay off either way. The order of
work is drawn in [migration-dependency-map.md](migration-dependency-map.md); open questions are in
[architecture-questions.md](architecture-questions.md).

Taken from Compositor-KR 1.4.2 and updated for **1.4.5** (build 40), now merged into `Compositor-Multiplatform`.
What 1.4.3–1.4.5 changed for this list: `ColorProfile.swift` and `LiquifyFilter.swift` were split by main (3672e7f)
into a Foundation-only core section and an Apple display layer — `DocumentColorProfile` moves from B to A; the split
also made visible `WorkingColorSpace`, a process-wide current profile (E8). 1.4.3's brush-engine and 1.4.5's
Camera Raw/Scanlines changes touch no type in this list.

**The Core is C++20** (decided — [windows-architecture.md](windows-architecture.md) §1). "Target" below is where a
type's counterpart lives in the C++ Core (`Core/…`) or which layer keeps it; the Swift type becomes a thin wrapper or
is removed when its area switches over in Wave 2 ([implementation-plan.md](implementation-plan.md)), after
differential tests show the two agree.

## How the list was made

Starting from the document's roots — `CanvasDocument`, `ImageLayer`, `ProjectManifest`, `ProjectSnapshot`,
`DocumentHistory` — every type reachable through stored properties or enum payloads: 47 types in 21 files
(8,180 lines). For each, the frameworks it touches were found by name and split into **stored** (the type's data
depends on it) and **methods** (only behavior does, which can move to an extension). Existing tests were found by the
type's name in `CompositorTests`; "indirect" means tests exercise it through the editor session without naming it.
Tool state, the editor session and view models are out of scope; they are UI.

Two facts decide most of the classification (both checked with Swift 6.4 on Windows):

- **`CGFloat`, `CGPoint`, `CGSize`, `CGRect` exist on Windows only in full Foundation** (ICU, ~63 MB of runtime), not
  in `FoundationEssentials`. **`CGAffineTransform`, `CGPath`, `CGImage`, `CGColorSpace` don't exist on Windows.**
- **`UUID` and `Codable`/JSON work with `FoundationEssentials`** (13.5 MB, no ICU), and `Observation` is in the
  Windows toolchain.

`CGFloat` is written to `.comp` as a JSON number, the same as `Double`, so replacing it with the Core's `Scalar`
doesn't change the file format — to be proven by golden-file tests first (step 0).

## Categories

| | Meaning | Count |
|---|---|---|
| **A** | Move to the shared Core as is (at most a file move) | 13 |
| **B** | Move after removing platform types (CoreGraphics geometry, UI helpers, `NSLock`) | 23 |
| **C** | Needs an adapter first: the `ImageRef` handle, `CorePath`, or operations taken out of the editor session | 8 |
| **D** | Stays in the renderer / platform layer, behind a Core boundary | 3 |
| **E** | Pieces *inside* the types above to remove or replace (listed separately) | 8 items |

Difficulty: **S** — mechanical, few call sites; **M** — many call sites or format-sensitive; **L** — needs a new
abstraction and touches the renderer and tools.

Target locations follow ARCHITECTURE.md's target structure (`Core/`, `Formats/`, `Rendering/`, `Platform/macOS/`).
They are destinations, not folders to create now.

## The 47 types

### A — move as is

| Type | Current file | Framework dependency | Target | Diff. | Existing tests |
|---|---|---|---|---|---|
| `CanvasGuide` | Document/Guides.swift | `UUID` only (guide *drawing* in the same file uses `CGColor`) | Core/Model | S¹ | GuideTests, PSDExportTests |
| `LayerSampling` | Document/LayerTransform.swift | — | Core/Model | S | indirect (TransformTests, CropTests) |
| `LayerBlendMode` | Document/LayerAppearance.swift | — (PSD key mapping is in IO/PSD) | Core/Model | S | LayerAppearanceTests, BlendShortcutTests, GPUCanvasTests |
| `LayerEffectKind` | Document/LayerEffects.swift | — | Core/Effects | S | indirect (OuterGlowTests, InnerGlowTests) |
| `FilterKind` | Document/Filters.swift | — (the file imports Core Image, AppKit, SwiftUI) | Core/Adjustments | S | CameraRawTests, FinishingFilterTests, ImageAdjustmentTests |
| `HueSaturationSettings` | Document/HueSaturation.swift | — | Core/Adjustments | S | HueSaturationTests, AdjustmentLayerTests, PSDExportTests |
| `ColorRange` | Document/HueSaturation.swift | — | Core/Adjustments | S | HueSaturationTests, PSDExportTests |
| `HueBand` | Document/HueSaturation.swift | — | Core/Adjustments | S | PSDAdjustmentTests |
| `RangeAdjustment` | Document/HueSaturation.swift | — | Core/Adjustments | S | HueSaturationTests, PSDAdjustmentTests |
| `AdjustmentColor` | Document/ImageAdjustments.swift | — | Core/Adjustments | S | ImageAdjustmentTests, FinishingFilterTests |
| `LayerTextFontRun` | Document/TypeTool.swift | — | Core/Text | S | TypeToolTests |
| `TextAlignment` | Document/TypeTool.swift | — | Core/Text | S | indirect (TypeToolTests) |
| `DocumentColorProfile` | Document/ColorProfile.swift (core section, Foundation only since 1.4.5) | — in the type; the `CGColorSpace` lookup is in the file's Apple layer | Core/Model as `ColorSpaceID`; lookup stays Platform/macOS | S | ColorProfileTests |

¹ Depends on the ID decision (architecture-questions.md Q1): with a stdlib-only Core, `UUID` becomes the Core's ID type.

### B — remove platform types, then move

| Type | Current file | Framework dependency | Target | Diff. | Existing tests |
|---|---|---|---|---|---|
| `LayerTransform` | Document/LayerTransform.swift | **stored** `CGPoint`, `CGSize`, `CGFloat` | Core/Geometry (as `LayerPlacement`) | M — most-used model type | 23 files: TransformTests, CropTests, DistortTests, BrushTests, … |
| `StrokeEffect` | Document/LayerEffects.swift | **stored** `CGFloat` (size, color) | Core/Effects | S | FinishingFilterTests, OuterGlowTests, PSDExportTests |
| `ShadowEffect` | Document/LayerEffects.swift | **stored** `CGFloat` | Core/Effects | S | OuterGlowTests, ProjectTests, GPUCanvasTests |
| `ColorOverlayEffect` | Document/LayerEffects.swift | **stored** `CGFloat` | Core/Effects | S | ProjectTests |
| `InnerShadowEffect` | Document/LayerEffects.swift | **stored** `CGFloat` | Core/Effects | S | ProjectTests |
| `OuterGlowEffect` | Document/LayerEffects.swift | **stored** `CGFloat` | Core/Effects | S | OuterGlowTests |
| `InnerGlowEffect` | Document/LayerEffects.swift | **stored** `CGFloat` | Core/Effects | S | InnerGlowTests |
| `LayerEffects` | Document/LayerEffects.swift | via its members | Core/Effects | S | InnerGlowTests, OuterGlowTests, FinishingFilterTests |
| `LayerShapeStyle` | Document/ShapeTool.swift | **stored** `CGFloat`, `CGPoint` | Core/Model (styles) | S | indirect (ShapeToolTests) |
| `ShapeKind` | Document/ShapeTool.swift | `CGPath` in `path(in:)` | Core/Model; path building → Rendering | S | indirect (ShapeToolTests) |
| `LayerTextStyle` | Document/TypeTool.swift | **stored** `CGFloat`, `CGSize` | Core/Text | S | TypeToolTests, InnerGlowTests |
| `LayerTextColorRun` | Document/TypeTool.swift | **stored** `CGFloat` | Core/Text | S | TypeToolTests |
| `PaletteColor` | Document/ColorPalette.swift | **stored** `CGFloat`; `NSColor` in methods | Core/Geometry as `CoreColor` (editor-color use stays UI) | M — 14 test files, color accessors of effects/styles | ColorPickerTests, ColorProfileTests, AdjustmentLayerTests, … |
| `AdjustmentKind` | Document/LayerAdjustment.swift | SF Symbol name (`symbol`, UI) | Core/Adjustments | S | AdjustmentLayerTests, ImageAdjustmentTests |
| `ExposureSettings` | Document/ImageAdjustments.swift | `apply(CGImage)` → shared C code | settings → Core/Adjustments; `apply` → Rendering | S | ImageAdjustmentTests, PSDExportTests |
| `GradientMapSettings` | Document/ImageAdjustments.swift | same | same | S | ImageAdjustmentTests, PSDExportTests |
| `GrainSettings` | Document/ImageAdjustments.swift | same | same | S | ImageAdjustmentTests |
| `BlackWhiteSettings` | Document/ImageAdjustments.swift | same | same | S | ImageAdjustmentTests |
| `ColorBalanceSettings` | Document/ImageAdjustments.swift | same | same | S | ImageAdjustmentTests, PSDExportTests |
| `LayerAdjustment` | Document/LayerAdjustment.swift | `apply(CGImage)`; file imports Core Image, AppKit, SwiftUI | Core/Adjustments; `apply` → Rendering | M | AdjustmentLayerTests, ImageAdjustmentTests, GPUCanvasTests, PSDExportTests |
| `LayerOrder` | Document/LayerGroups.swift | `NSLock` around a static cache | Core/Model, derived per snapshot (core-api §8) | S | indirect (GroupTests, GroupingSelectionTests) |
| `ProjectManifest` | IO/ProjectStore.swift | `UUID`; members' CG geometry | Formats/Comp | M — format-critical | ProjectTests, ExportTests, GroupTests, ExternalChangeTests, … (7) |
| `ProjectLayerRecord` | IO/ProjectStore.swift | `UUID`; members' CG geometry | Formats/Comp | M — format-critical | ProjectTests, ImageSizeTests, GroupTests, … (8) |

### C — adapter needed first

| Type | Current file | Framework dependency | Adapter | Target | Diff. | Existing tests |
|---|---|---|---|---|---|---|
| `CanvasDocument` | Document/EditorSession.swift (imports SwiftUI) | `UUID`; `selection` holds a `CGPath` | `CorePath` (via `DocumentSelection`) | Core/Model | M | CompositorTests, HistoryTests, PSDExportTests; nearly every test indirectly |
| `ImageLayer` | Document/EditorSession.swift | `ImportedImage` (`CGImage`), CG geometry; `==` compares `CGImage` identity; UI extension in UI/NativeLayerList | `ImageRef` | Core/Model | **L** | BrushTests, HistoryTests, GPUCanvasTests, MetalWarpTests, PSDAdjustmentTests, PSDExportTests; LayerTests indirectly |
| `LayerMask` | Document/LayerMask.swift | **stored** `ImportedImage`; `CGContext`/`CGImage` in methods | `ImageRef`; pixel helpers → Platform/shared C | Core/Model | M | LayerMaskTests, MaskTransformTests, BrushTests, … (12) |
| `ProjectSnapshot` | IO/ProjectStore.swift | **stored** `[UUID: ImportedImage]` | `ImageRef`; PNG codec → Platform | Formats/Comp | M | ProjectTests, ExportTests, ImageSizeTests, … (9) |
| `DocumentHistory` | Document/DocumentHistory.swift | Observation; byte accounting reads `CGImage` | `ImageRef` byte counts and identity | Core/History | M | HistoryTests |
| `DocumentSelection` | Document/Selection.swift | **stored** `CGPath`; Core Image/`CGContext` in `coverage` | `CorePath`; coverage → Rendering | Core/Model | **L** | SelectionFeatherTests, MagicWandTests, LevelsTests; SelectionTests indirectly |
| `LayerShape` | Document/ShapeTool.swift | **stored** style + `CGImage` | style stays; pixels leave (E1) | Core/Model (style) | M | indirect (ShapeToolTests) |
| `LayerText` | Document/TypeTool.swift | **stored** style + `CGImage` | style stays; pixels leave (E1); text layout per platform | Core/Text (style) | M–L | indirect (TypeToolTests) |

Operations are also C-category work though they aren't types: duplicate, delete, group, move and the rest live today
in `EditorSession` extensions (`SelectionClipboard`, `LayerGroups`, `LiveLayerMask`, …) mixed with selection and
panel state. They move to Core operations (core-api §5) with the UI state left behind.

### D — stays in the renderer / platform layer

| Type | Current file | Framework dependency | Target | Existing tests |
|---|---|---|---|---|
| `ImportedImage` | IO/ImageImporter.swift | **stored** `CGImage` ×2, `RasterSnapshot` | Platform/macOS/Imaging — the macOS implementation behind `ImageRef` | 47 files (AdjustmentLayerTests, BlurBrushTests, BrushTests, …; ImageImportTests indirectly) |
| `RasterSnapshot` | Rendering/RasterSnapshot.swift | `CGImage`, `CGContext` | Platform/macOS/Imaging | TiledLayerTests |
| `BrushPatch` | Document/BrushStroke.swift | `CGImage`, `CGRect` | Platform/macOS/Imaging | TiledLayerTests |

### E — remove or replace (pieces of the types above)

| # | Today | Replacement |
|---|---|---|
| E1 | `LayerShape.image`, `LayerText.image`: rendered pixels stored in the style | The pixel layer's `content`; each platform re-renders from the style |
| E2 | `ImportedImage.thumbnail`: a UI cache reachable from the model, counted in history bytes | Thumbnail cache in UI/renderer keyed by `ImageRef` identity |
| E3 | `ImageLayer ==` comparing `CGImage` object identity | `ImageRef` identity |
| E4 | `LayerOrder`'s process-wide static cache under `NSLock` | Hierarchy derived with each snapshot |
| E5 | `NSAlert` asking *bake or unlink* inside `deleteWithLiveMaskChoice` (Document/LiveLayerMask.swift) | Delete takes a clip policy; the UI asks first |
| E6 | UI helpers on model types: `AdjustmentKind.symbol`, `PaletteColor.nsColor` | UI extensions |
| E7 | Model files importing SwiftUI/AppKit only for convenience (`EditorSession.swift`, `LayerAdjustment.swift`, `Filters.swift`, …) | Model files import nothing but the Core's own types |
| E8 | `WorkingColorSpace` (Document/ColorProfile.swift): a process-wide current profile behind `NSLock`, read by buffer-making code on any thread | The document's `ColorSpaceID` passed to whatever makes pixels (core-api §9; architecture-questions Q25) |

## File-by-file migration plan

Each step is one reviewable change that keeps the macOS app behaving exactly as before; `verify.yml` (build and all
tests) must pass after each, and no step changes `.comp`. Steps 0–6 are needed whichever Core language is chosen;
their order and dependencies are drawn in [migration-dependency-map.md](migration-dependency-map.md).

### Step 0 — Safety net (tests only)
- Golden `.comp` fixtures covering every layer kind (image, folder, mask, each adjustment kind, effects, shape, text,
  guides, clipping), compared byte for byte on read → write.
- Files: `CompositorTests/ProjectFormatGoldenTests.swift` (new), fixtures under `CompositorTests/Fixtures/`.

### Step 1 — Separate model from UI files (moves only; A types, E6, E7)
- `Document/EditorSession.swift` → `ImageLayer`, `CanvasDocument` to `Document/CanvasDocument.swift`.
- `AdjustmentKind.symbol` → `UI/AdjustmentKind+UI.swift`; `PaletteColor.nsColor` → `UI/PaletteColor+AppKit.swift`.
- `FilterKind` → `Document/FilterKind.swift`.
- `HueSaturation.swift`, `ImageAdjustments.swift`, `LayerEffects.swift`, `ShapeTool.swift`, `TypeTool.swift`,
  `LayerAdjustment.swift` → split into settings/style types (no framework imports) and a `+Rendering.swift` extension
  holding `apply(CGImage)`, `path(in:)` and drawing.
- `ColorProfile.swift` — already split by 1.4.5 (3672e7f) into a Foundation-only core section and an Apple layer in
  the same file; moving the Apple layer to its own file is optional.
- Add a boundary check for the model files (like `check-core-boundaries.sh` on the spike branch) to CI.

### Step 2 — Core geometry (B types)
- New `Document/CoreGeometry.swift`: `Scalar`, `CorePoint`, `CoreSize`, `CoreRect`, `CoreTransform`, `CoreColor`
  (core-api §2) with conversions to and from CoreGraphics for the macOS side. (These Swift types mirror the C++ Core's, so the differential tests compare like with like.)
- Stored `CGFloat`/`CGPoint`/`CGSize` → Core types in `LayerTransform`, the six effects, `LayerShapeStyle`,
  `LayerTextStyle`, `LayerTextColorRun`, `PaletteColor`. Call sites convert at the edge (17 files outside
  Document/IO reference model types, ~94 lines).
- Step 0's golden tests prove `.comp` is unchanged.

### Step 3 — Identity and small platform types
- The ID decision (architecture-questions.md Q1); `.comp` keeps writing the same UUID strings either way.
- `LayerOrder`: drop the static cache/`NSLock` (E4). `DocumentColorProfile` → `ColorSpaceID`; `WorkingColorSpace`
  readers that the Core will replace take the color space as a parameter (E8).

### Step 4 — `ImageRef` (largest step; C types)
- New `Document/ImageRef.swift`: the handle of core-api §7.4 (size, format, byte count, identity). macOS
  implementation wraps `ImportedImage` + `RasterSnapshot` (D, unchanged inside).
- Touches `ImageLayer`, `LayerMask`, `ProjectSnapshot`, `DocumentHistory` (byte accounting), `ProjectStore` (PNG
  read/write behind a per-platform codec), `LayerShape`/`LayerText` (E1), `ImportedImage.thumbnail` (E2), `==` (E3).

### Step 5 — `CorePath` for selection and shapes
- `DocumentSelection.path: CGPath` → `CorePath` with a `CGPath` conversion on macOS; coverage and feathering stay in
  the renderer. `ShapeKind.path(in:)` builds a `CorePath`.

### Step 6 — Operations out of the editor session
- One function per core-api §5 operation, taking IDs and returning a status, implemented on `CanvasDocument` +
  `DocumentHistory`, called by today's `EditorSession` methods, which keep only UI state (selection in the panel,
  collapsed folders, dialogs — E5).

### Step 7 — Switch to the C++ Core (Wave 2)
- The C++ Core (built beside the app from Wave 1) takes over the areas prepared by steps 1–6, one at a time, in the
  dependency-map order. The macOS app calls it through the C ABI and a thin Swift wrapper (not Swift's C++ interop).
- An area switches only when its differential tests show the Swift model and the Core agree; until its Swift code is
  deleted, the switch can be undone.

### Not in this plan
Tools and the editor session's interaction code, the canvas and GPU rendering, Vision features, and all UI.
