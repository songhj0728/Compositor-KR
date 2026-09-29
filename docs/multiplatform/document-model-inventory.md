# Document model inventory and migration plan

What the document model is made of today, what each part depends on, and the order in which it can be separated
from macOS — file by file. **Nothing here has been moved yet.** The plan is written so its first steps pay off
whichever Core language is chosen (see [windows-decisions.md](windows-decisions.md) and `Spikes/CoreModel` on the
`spike/core-model` branch).

Taken from Compositor-KR 1.4.2 on the `Compositor-Multiplatform` branch.

## How the list was made

Starting from the document's roots — `CanvasDocument`, `ImageLayer`, `ProjectManifest`, `ProjectSnapshot`,
`DocumentHistory` — every type reachable through stored properties or enum payloads: 47 types in 21 files
(8,180 lines). For each, the frameworks it touches were found by name (`CGImage`, `NSColor`, `CIImage`, `Color`, …)
and split into **stored** (the type's data depends on it) and **methods** (only behavior does, which can move to an
extension). Tool state, the editor session and view models are out of scope; they are UI.

Two facts decide most of the classification (both checked with Swift 6.4 on Windows):

- **`CGFloat`, `CGPoint`, `CGSize`, `CGRect` exist on Windows only in full Foundation**, which ships ICU (~63 MB of
  runtime). They are not in `FoundationEssentials`. **`CGAffineTransform`, `CGPath`, `CGImage` and `CGColorSpace` do
  not exist on Windows at all.** A type that *stores* CoreGraphics geometry needs its own geometry types (plain
  `Double`s) to be shared cheaply.
- **`UUID` and `Codable`/JSON work with `FoundationEssentials`** (13.5 MB runtime, no ICU), and `Observation` is in
  the Windows toolchain.

`CGFloat` is encoded in `.comp` manifests as a JSON number, the same as `Double`, so replacing it with `Double` does not
change the file format. (To be confirmed by a golden-file test before the change — step 2 below.)

## Categories

- **A — Shared Core candidate:** plain values; can move as is (at most a file move).
- **B — Refactor first:** belongs in the Core, but stores or requires something Apple-only.
- **C — Stays macOS platform:** the macOS implementation behind a Core boundary.
- **D — Replace / retire:** a macOS-specific shortcut inside the model that the Core should not carry.

## The 47 types

| Type | File | Depends on | Stored? | Category | What's needed |
|---|---|---|---|---|---|
| `CanvasDocument` | Document/EditorSession.swift | UUID; file imports SwiftUI | UUID | **B** | Move out of the SwiftUI file; `selection` needs step 5. |
| `ImageLayer` | Document/EditorSession.swift | UUID, `ImportedImage`, CG geometry | yes | **B** | The hub: pixel asset → image handle (step 4); `==` compares `CGImage` identity. Extensions in LayerGroups, LayerMask, ShapeTool, TypeTool, **UI/NativeLayerList** (UI; stays). |
| `ProjectManifest` | IO/ProjectStore.swift | UUID, Codable | UUID | **B** | The `.comp` manifest. Only UUID; carries `LayerTransform` etc. through records. |
| `ProjectLayerRecord` | IO/ProjectStore.swift | UUID, Codable | UUID | **B** | Follows its members. |
| `ProjectSnapshot` | IO/ProjectStore.swift | `ImportedImage` | yes | **B** | Images → image handles. |
| `DocumentHistory` | Document/DocumentHistory.swift | Observation, UUID; counts `CGImage` bytes | yes | **B** | Byte accounting through the image handle. `@Observable` works on Windows. |
| `LayerOrder` | Document/LayerGroups.swift | `NSLock` | static | **B** | `NSLock` → `Synchronization.Mutex` (or drop the cache). Pure logic otherwise. |
| `CanvasGuide` | Document/Guides.swift | UUID | UUID | **A** | (Guide *drawing* uses `CGColor`; that's a separate, UI part of the file.) |
| `LayerTransform` | Document/LayerTransform.swift | `CGPoint`, `CGSize`, `CGFloat` | yes | **B** | Core geometry types. Most-used type; biggest ripple. `LayerFlip.swift` extends it. |
| `LayerSampling` | Document/LayerTransform.swift | — | — | **A** | |
| `LayerBlendMode` | Document/LayerAppearance.swift | — | — | **A** | PSD blend-key mapping (IO/PSD) is format code; shareable. |
| `DocumentColorProfile` | Document/ColorProfile.swift | `CGColorSpace` | methods | **B** | Enum to Core; the color-space lookup to a macOS extension. Windows needs its own color management. |
| `DocumentSelection` | Document/Selection.swift | `CGPath`; `CIImage` in methods | **yes** | **B** | Needs a Core representation (path data or a mask raster). Hardest value type. |
| `ImportedImage` | IO/ImageImporter.swift | `CGImage` ×2, `RasterSnapshot` | yes | **C** | The macOS image representation. The Core gets an image-handle abstraction instead (step 4). |
| `RasterSnapshot` | Rendering/RasterSnapshot.swift | `CGImage`, `CGContext` | yes | **C** | macOS undo-memory optimization behind the handle. |
| `BrushPatch` | Document/BrushStroke.swift | `CGImage`, `CGRect` | yes | **C** | Part of `RasterSnapshot`. |
| `LayerMask` | Document/LayerMask.swift | `ImportedImage`; CG in methods | yes | **B** | Asset → image handle; mask *logic* is Core. |
| `LayerAdjustment` | Document/LayerAdjustment.swift | `apply(CGImage)` | methods | **B** | Settings are plain values; `apply` moves to the renderer/platform. |
| `AdjustmentKind` | Document/LayerAdjustment.swift | SF Symbol name (`symbol`) | methods | **B** | Move `symbol` (UI) to a macOS extension. |
| `HueSaturationSettings` | Document/HueSaturation.swift | — | — | **A** | |
| `ColorRange`, `HueBand`, `RangeAdjustment` | Document/HueSaturation.swift | — | — | **A** | |
| `ExposureSettings` | Document/ImageAdjustments.swift | `apply(CGImage)` → C pixel code | methods | **B** | Settings to Core; `apply` over an image buffer calls the already-shared C code. |
| `GradientMapSettings` | Document/ImageAdjustments.swift | same | methods | **B** | same |
| `GrainSettings` | Document/ImageAdjustments.swift | same | methods | **B** | same |
| `BlackWhiteSettings` | Document/ImageAdjustments.swift | same | methods | **B** | same |
| `ColorBalanceSettings` | Document/ImageAdjustments.swift | same | methods | **B** | same |
| `AdjustmentColor` | Document/ImageAdjustments.swift | — | — | **A** | |
| `LayerEffects` | Document/LayerEffects.swift | (members) | — | **B** | Follows its members. |
| `StrokeEffect`, `ShadowEffect`, `ColorOverlayEffect`, `InnerShadowEffect`, `OuterGlowEffect`, `InnerGlowEffect` | Document/LayerEffects.swift | `CGFloat` | yes | **B** | `CGFloat` → `Double` (format unchanged). Rendering stays in Core Image/Metal. |
| `LayerEffectKind` | Document/LayerEffects.swift | — | — | **A** | |
| `FilterKind` | Document/Filters.swift | — (file imports CoreImage) | — | **A** | Move out of the Core Image file. |
| `LayerShape` | Document/ShapeTool.swift | `CGImage` (rendered pixels) | yes | **B** + **D** | Style is Core; the stored rendered `image` is a cache → **D**, re-rendered per platform. |
| `LayerShapeStyle` | Document/ShapeTool.swift | `CGFloat`, `CGPoint` | yes | **B** | Geometry types. |
| `ShapeKind` | Document/ShapeTool.swift | `CGPath` in `path(in:)` | methods | **B** | Enum to Core; path building to the renderer. |
| `LayerText` | Document/TypeTool.swift | `CGImage` (rendered pixels) | yes | **B** + **D** | As `LayerShape`. Text layout and fonts differ per OS — a product risk (same text may wrap differently on Windows). |
| `LayerTextStyle` | Document/TypeTool.swift | `CGFloat`, `CGSize` | yes | **B** | Geometry types. |
| `LayerTextColorRun` | Document/TypeTool.swift | `CGFloat` | yes | **B** | `CGFloat` → `Double`. |
| `LayerTextFontRun` | Document/TypeTool.swift | — | — | **A** | Font *names* may not exist on Windows; mapping is a platform concern. |
| `TextAlignment` | Document/TypeTool.swift | — | — | **A** | |
| `PaletteColor` | Document/ColorPalette.swift | `CGFloat`; `NSColor` in methods | yes | **B** | Editor color (foreground/background), not document data; move with tools later. `nsColor` to a macOS extension. |

Totals: **A 12 · B 32 · C 3** (47), plus **3 D items** inside B/C types: the rendered-pixel caches in `LayerShape` and `LayerText`, and the
`thumbnail` stored in `ImportedImage`, which the handle design should drop from the model.

Nothing in the list depends on SwiftUI or AppKit *in its data*; the SwiftUI/AppKit exposure is files importing them
and a few UI helpers (`symbol`, `nsColor`) living on model types. The real dependencies are CoreGraphics geometry
(everywhere), `CGImage` (layers, masks, history), `CGPath` (selection) and `CGColorSpace` (profiles).

## File-by-file migration plan

Each step is one reviewable change that keeps the macOS app behaving exactly as before; `verify.yml` (build + all
tests) must pass after each. Steps 1–5 are needed whichever Core language is chosen: they define the Core's boundary.

### Step 0 — Safety net (tests only)
- Add golden `.comp` fixtures: write projects with every layer kind (image, group, mask, adjustment of each kind,
  effects, shape, text, guides, selection-less) and compare the manifest JSON byte for byte on read → write.
- Files: `CompositorTests/ProjectFormatGoldenTests.swift` (new), fixtures under `CompositorTests/Fixtures/`.

### Step 1 — Separate model from UI files (moves only)
- `Document/EditorSession.swift` → move `ImageLayer`, `CanvasDocument` to `Document/CanvasDocument.swift`
  (imports Foundation, CoreGraphics only).
- `Document/LayerAdjustment.swift` → `AdjustmentKind.symbol` to `UI/AdjustmentKind+UI.swift`.
- `Document/ColorPalette.swift` → `PaletteColor.nsColor` to `UI/PaletteColor+AppKit.swift`.
- `Document/Filters.swift` → `FilterKind` to `Document/FilterKind.swift` (no Core Image import).
- `Document/HueSaturation.swift`, `Document/ImageAdjustments.swift`, `Document/LayerEffects.swift`,
  `Document/ShapeTool.swift`, `Document/TypeTool.swift`, `Document/LayerAdjustment.swift` → split each into the
  settings/style types (no framework imports) and a `+Rendering.swift` extension holding `apply(CGImage)`,
  `path(in:)` and drawing.
- `Document/ColorProfile.swift` → `DocumentColorProfile` enum stays; `CGColorSpace` lookup to
  `Rendering/DocumentColorProfile+CoreGraphics.swift`.

Result: model files that import only Foundation/CoreGraphics — checkable with a script like
`Spikes/CoreModel/check-core-boundaries.sh`.

### Step 2 — Core geometry instead of CoreGraphics in stored data
- New `Document/Geometry.swift`: `DocPoint`, `DocSize`, `DocRect` (Doubles) with `init(_ cg:)`/`.cg` conversions for
  the macOS side.
- Change stored `CGFloat`/`CGPoint`/`CGSize` in `LayerTransform`, the six effect structs, `LayerShapeStyle`,
  `LayerTextStyle`, `LayerTextColorRun`, `PaletteColor`. Call sites convert at the edge (17 files outside
  Document/IO reference model types, ~94 lines).
- Step 0's golden tests prove the `.comp` format is unchanged.

### Step 3 — Identity and Foundation policy
- Decide: keep `UUID` (Core then needs `FoundationEssentials` on Windows, +7.7 MB) or a Core ID type that encodes
  to the same UUID strings. Either way manifests stay identical.
- `LayerOrder`: `NSLock` → `Synchronization.Mutex`.

### Step 4 — Image handle (largest step)
- New `Document/LayerImage.swift`: a protocol / opaque handle (size, byte count, identity) the Core stores instead of
  `ImportedImage`. macOS implementation wraps `ImportedImage` + `RasterSnapshot` (category C, unchanged inside).
- Touches `ImageLayer`, `LayerMask`, `ProjectSnapshot`, `DocumentHistory` (byte accounting), `ProjectStore` (PNG
  read/write moves behind a per-platform codec), `LayerShape`/`LayerText` (rendered caches leave the model — D).
- Pixel operations on handles go through the shared C code where it exists (`Compositor/Rendering/*.c`).

### Step 5 — Selection
- `DocumentSelection.path: CGPath` → a Core path representation (move/line/curve elements) with a `CGPath`
  conversion on macOS; feathering stays in the renderer.

### Step 6 — Extract the Core (decision point)
- With steps 1–5 done, the files below have no Apple-only types in their data and form the Core:
  `CanvasDocument.swift`, `Geometry.swift`, `LayerImage.swift`, `LayerTransform.swift`, `LayerAppearance.swift`,
  `LayerGroups.swift` (logic), `LayerMask.swift` (logic), `LayerAdjustment.swift`, `HueSaturation.swift`,
  `ImageAdjustments.swift`, `LayerEffects.swift`, `ShapeTool.swift` (style), `TypeTool.swift` (style),
  `Guides.swift` (model part), `Selection.swift` (model part), `ColorProfile.swift` (enum),
  `DocumentHistory.swift`, `ProjectStore.swift` (manifest and records), and the PSD reader/writer later.
- **Swift Core:** move them into a local Swift package (`Core/`) the Xcode app depends on; Windows builds it with
  SwiftPM. **C++ Core:** port these files; the macOS app calls them through C++ interop (see the spike for what that
  costs).
- The WinUI 3 window test does not wait for this plan: it runs against the spike's C boundary first. The final UI
  choice waits for the Core boundary (steps 0–5).

### Not in this plan
Tools and the editor session (`EditorSession`, brush/type/shape tools' interaction), the canvas and GPU rendering,
Vision features, and all UI. They are platform code or come after the Core boundary exists.
