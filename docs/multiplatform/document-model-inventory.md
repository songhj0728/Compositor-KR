# Document model inventory and migration boundaries

Audited against main-sync merge **db268a2b** on `Compositor-Multiplatform`, containing
**main ccf062ed** (1.4.5(A), build 41), 2026-09-30. The original 47-entry inventory
is retained for traceability, with explicit v12 additions and changes below.
All current paths below are relative to `Compositor/`
and belong to the **Compositor macOS application module**; target paths are semantic
responsibilities, not new modules created here. No type was moved or rewritten.

**No Core language is selected.** A shared candidate means reusable meaning/data;
it does not authorize translating a Swift type to C++. Source methods using Apple
types must be separated even when their stored data is portable. Mere file imports
do not establish that the data itself depends on AppKit/SwiftUI.

The historical 47 types / 21 files / 8,180 lines and ~11,000 model/format lines are
scope estimates from the spike, not a current complete model count. This audit
found missing Levels/Curves/hierarchy types (below). The v12 Layer Style types are
now present after the reviewed main merge, not an unsynchronized future delta.
See [repository evidence](repository-evidence.md) and the
[synchronization record](main-sync-2026-09-30.md) for provenance and test limits.

Read [Core contract](../core-api.md), [dependency stages](migration-dependency-map.md)
and [open questions](architecture-questions.md) together with this inventory.

## Classification

| Category | Rule | Baseline entries |
|---|---|---|
| A | No direct Apple value/helper dependency in the data declaration; candidate after its dependencies and file boundary are available | 6 |
| B | Remove Apple values or convenience/rendering methods, or replace platform-dependent derived state first | 30 |
| C | Needs image/path/operation/lifetime adapter before integration | 8 |
| D | Keep native storage/rendering/platform implementation behind a boundary | 3 |
| E | Replace/separate responsibilities inside the above types; not additional model types | 8 items |

Seven former A entries are now B: LayerSampling, LayerBlendMode, LayerEffectKind,
FilterKind, ColorRange, AdjustmentColor and TextAlignment. Their data may be small,
but their actual declarations contain platform/helper dependencies. DocumentColorProfile's
base declaration is A; its Apple extensions and WorkingColorSpace remain outside it.
A does not mean all transitive dependencies are already portable.

Difficulty: S = small split/adapter, M = many call sites or format-sensitive,
L = image/path/lifetime integration. Existing test names are evidence of coverage,
not Mac tests rerun in this Linux synchronization task; indirect tests exercise callers.

## The original 47 types, reclassified

### A — Direct shared data candidates

| Type | Current file | Framework/helper dependency | Semantic target | Difficulty | Existing tests |
|---|---|---|---|---|---|
| `CanvasGuide` | Document/Guides.swift | `UUID` only (guide *drawing* in the same file uses `CGColor`) | Core/Model | S | GuideTests, PSDExportTests |
| `HueSaturationSettings` | Document/HueSaturation.swift | — | Core/Adjustments | S | HueSaturationTests, AdjustmentLayerTests, PSDExportTests |
| `HueBand` | Document/HueSaturation.swift | — | Core/Adjustments | S | PSDAdjustmentTests |
| `RangeAdjustment` | Document/HueSaturation.swift | — | Core/Adjustments | S | HueSaturationTests, PSDAdjustmentTests |
| `LayerTextFontRun` | Document/TypeTool.swift | — | Core/Text | S | TypeToolTests |
| `DocumentColorProfile` | Document/ColorProfile.swift (core section, Foundation only since 1.4.5) | — in the type; the `CGColorSpace` lookup is in the file's Apple layer | Core/Model as `ColorSpaceID`; lookup stays Platform/macOS | S | ColorProfileTests |

### B — Remove platform dependencies

| Type | Current file | Framework/helper dependency | Semantic target | Difficulty | Existing tests |
|---|---|---|---|---|---|
| `LayerSampling` | Document/LayerTransform.swift | methods: SwiftUI `LocalizedStringKey`, CoreGraphics `CGInterpolationQuality` | Core/Model | S | indirect (TransformTests, CropTests) |
| `LayerBlendMode` | Document/LayerAppearance.swift | methods: `CGBlendMode`, Core Image filter-name mapping | Core/Model | S | LayerAppearanceTests, BlendShortcutTests, GPUCanvasTests |
| `LayerEffectKind` | Document/LayerEffects.swift | nine cases; methods: SwiftUI localized names, creation-mode policy | Core/Effects with UI policy separate | S | LayerStyleTests; indirect OuterGlowTests, InnerGlowTests |
| `FilterKind` | Document/Filters.swift | methods: SwiftUI localized display names | Core/Adjustments | S | CameraRawTests, FinishingFilterTests, ImageAdjustmentTests |
| `ColorRange` | Document/HueSaturation.swift | methods: SwiftUI localized display names; data depends on HueBand | Core/Adjustments | S | HueSaturationTests, PSDExportTests |
| `AdjustmentColor` | Document/ImageAdjustments.swift | method initializer uses PaletteColor; clamp helper lives in Apple-bound ImageAdjustmentPixels | Core/Adjustments | S | ImageAdjustmentTests, FinishingFilterTests |
| `TextAlignment` | Document/TypeTool.swift | methods: SwiftUI localized display names | Core/Text | S | indirect (TypeToolTests) |
| `LayerTransform` | Document/LayerTransform.swift | stored: CGPoint/CGSize/CGFloat; methods: CGAffineTransform and BrushRaster | Core/Geometry (as `LayerPlacement`) | M — most-used model type | 23 files: TransformTests, CropTests, DistortTests, BrushTests, … |
| `StrokeEffect` | Document/LayerEffects.swift | **stored** `CGFloat` (size, color) | Core/Effects | S | FinishingFilterTests, OuterGlowTests, PSDExportTests |
| `ShadowEffect` | Document/LayerEffects.swift | **stored** `CGFloat` | Core/Effects | S | OuterGlowTests, ProjectTests, GPUCanvasTests |
| `ColorOverlayEffect` | Document/LayerEffects.swift | **stored** `CGFloat` | Core/Effects | S | ProjectTests |
| `InnerShadowEffect` | Document/LayerEffects.swift | **stored** `CGFloat` | Core/Effects | S | ProjectTests |
| `OuterGlowEffect` | Document/LayerEffects.swift | **stored** `CGFloat` | Core/Effects | S | OuterGlowTests |
| `InnerGlowEffect` | Document/LayerEffects.swift | **stored** `CGFloat` | Core/Effects | S | InnerGlowTests |
| `LayerEffects` | Document/LayerEffects.swift | nine records/Fill Opacity; CGFloat scaling, PaletteColor and UI creation helpers | Core/Effects; renderer dispatch/creation helpers separate | M | LayerStyleTests, PSDExportTests, InnerGlowTests, OuterGlowTests, FinishingFilterTests |
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
| `LayerAdjustment` | Document/LayerAdjustment.swift | stored settings include LevelsSettings/CurvesSettings; methods: CGFloat samplingMargin and apply(CGImage) | Core/Adjustments; `apply` → Rendering | M | AdjustmentLayerTests, ImageAdjustmentTests, GPUCanvasTests, PSDExportTests |
| `LayerOrder` | Document/LayerGroups.swift | NSLock/static cache; resolves ImageLayer values, not an independent stored layer field | Core derived hierarchy, per-snapshot ownership | S | indirect (GroupTests, GroupingSelectionTests) |
| `ProjectManifest` | IO/ProjectStore.swift | UUID and stored ProjectLayerRecord/CanvasGuide; codec/file APIs are elsewhere in same file | Formats/Comp | M — format-critical | ProjectTests, ExportTests, GroupTests, ExternalChangeTests, … (7) |
| `ProjectLayerRecord` | IO/ProjectStore.swift | UUID and stored geometry/styles/settings; no image object | Formats/Comp | M — format-critical | ProjectTests, ImageSizeTests, GroupTests, … (8) |

### C — Adapter required

| Type | Current file | Framework dependency | Adapter | Semantic target | Difficulty | Existing tests |
|---|---|---|---|---|---|---|
| `CanvasDocument` | Document/EditorSession.swift (imports SwiftUI) | `UUID`; `selection` holds a `CGPath` | `CorePath` (via `DocumentSelection`) | Core/Model | M | CompositorTests, HistoryTests, PSDExportTests; nearly every test indirectly |
| `ImageLayer` | Document/EditorSession.swift | `ImportedImage` (`CGImage`), CG geometry; `==` compares `CGImage` identity; UI extension in UI/NativeLayerList | `ImageRef` | Core/Model | **L** | BrushTests, HistoryTests, GPUCanvasTests, MetalWarpTests, PSDAdjustmentTests, PSDExportTests; LayerTests indirectly |
| `LayerMask` | Document/LayerMask.swift | **stored** `ImportedImage`; `CGContext`/`CGImage` in methods | `ImageRef`; pixel helpers → Platform/shared C | Core/Model | M | LayerMaskTests, MaskTransformTests, BrushTests, … (12) |
| `ProjectSnapshot` | IO/ProjectStore.swift | **stored** `[UUID: ImportedImage]` | `ImageRef`; PNG codec → Platform | Formats/Comp | M | ProjectTests, ExportTests, ImageSizeTests, … (9) |
| `DocumentHistory` | Document/DocumentHistory.swift | Observation; byte accounting reads `CGImage` | `ImageRef` byte counts and identity | Core/History | M | HistoryTests |
| `DocumentSelection` | Document/Selection.swift | **stored** `CGPath`; Core Image/`CGContext` in `coverage` | `CorePath`; coverage → Rendering | Core/Model | **L** | SelectionFeatherTests, MagicWandTests, LevelsTests; SelectionTests indirectly |
| `LayerShape` | Document/ShapeTool.swift | **stored** style + `CGImage` | style stays; pixels leave (E1) | Core/Model (style) | M | indirect (ShapeToolTests) |
| `LayerText` | Document/TypeTool.swift | **stored** style + `CGImage` | style stays; pixels leave (E1); text layout per platform | Core/Text (style) | M–L | indirect (TypeToolTests) |

### D — Keep in platform or renderer

| Type | Current file | Framework dependency | Semantic target | Existing tests |
|---|---|---|---|---|
| `ImportedImage` | IO/ImageImporter.swift | **stored** `CGImage` ×2, `RasterSnapshot` | Platform/macOS/Imaging behind `ImageRef` (M–L adapter difficulty) | AdjustmentLayerTests, BlurBrushTests, BrushTests, ImageImportTests indirectly |
| `RasterSnapshot` | Rendering/RasterSnapshot.swift | `CGImage`, `CGContext` | Platform/macOS/Imaging (L adapter difficulty) | TiledLayerTests |
| `BrushPatch` | Document/BrushStroke.swift | `CGImage`, `CGRect` | Platform/macOS/Imaging (M adapter difficulty) | TiledLayerTests |

## Per-type dependency, serialization/history/render relevance and order

The triplet is **serialization / undo-history / renderer**. Y = direct semantic
participation; mapping = participates through record conversion; shared = pixels
retained by history; N = not persisted/recorded. Renderer includes export/coverage
where named. Stage IDs refer to the dependency map. PaletteColor also has UI-only
foreground/palette use; that session state is not moved merely because model colors
use the same helper. Method dependencies are distinguished from stored values.

| Type | Other data/helper dependencies | Serialization / history / renderer | Migration stage |
|---|---|---|---|
| `CanvasGuide` | UUID, nested Axis | Y/Y/overlay | S2 |
| `LayerSampling` | none (helper mappings separated) | Y/Y/Y | S1 |
| `LayerBlendMode` | none (renderer mappings separated) | Y/Y/Y | S1 |
| `LayerEffectKind` | effect-kind enum and display helpers | derived/indirect/Y | S1 |
| `FilterKind` | none (command catalog, not saved layer state) | N/N/service | S1 |
| `HueSaturationSettings` | ColorRange, HueBand, RangeAdjustment | Y/Y/Y | S3 |
| `ColorRange` | HueBand through defaultBand, UI helper | Y/Y/Y | S1 |
| `HueBand` | scalar range endpoints | Y/Y/Y | S3 |
| `RangeAdjustment` | scalar adjustment values | Y/Y/Y | S3 |
| `AdjustmentColor` | PaletteColor helper, ImageAdjustmentPixels clamp | Y/Y/Y | S3 |
| `LayerTextFontRun` | string and UTF-16 span | Y/Y/Y | S3 |
| `TextAlignment` | UI display helper | Y/Y/Y | S1 |
| `DocumentColorProfile` | string identifier; Apple extension separate | Y/Y/Y | S1 |
| `LayerTransform` | LayerSampling, geometry, BrushRaster helper | Y/Y/Y | S2 |
| `StrokeEffect` | scalar fields, PaletteColor accessor | Y/Y/Y | S3 |
| `ShadowEffect` | scalar fields, CGSize/PaletteColor accessors | Y/Y/Y | S3 |
| `ColorOverlayEffect` | scalar fields, PaletteColor accessor | Y/Y/Y | S3 |
| `InnerShadowEffect` | scalar fields, CGSize/PaletteColor accessors | Y/Y/Y | S3 |
| `OuterGlowEffect` | scalar fields, PaletteColor accessor | Y/Y/Y | S3 |
| `InnerGlowEffect` | scalar fields, PaletteColor accessor | Y/Y/Y | S3 |
| `LayerEffects` | nine effect records, Fill Opacity; LayerEffectKind/PaletteColor helpers; presence-based v12 predicate | Y/Y/Y | S3/S7 |
| `LayerShapeStyle` | ShapeKind, geometry; PaletteColor helper | Y/Y/Y | S3 |
| `ShapeKind` | CGPath and UI helper methods | Y/Y/Y | S3/S4 |
| `LayerTextStyle` | TextAlignment, text runs, geometry; PaletteColor helper | Y/Y/Y | S3 |
| `LayerTextColorRun` | scalar color and UTF-16 span | Y/Y/Y | S3 |
| `PaletteColor` | scalar color; NSColor/working-space adapter | indirect/indirect/Y | S2 |
| `AdjustmentKind` | FilterKind, UI symbol/display helpers | Y/Y/Y | S1/S3 |
| `ExposureSettings` | numeric table; CGImage apply helper | Y/Y/Y | S3 |
| `GradientMapSettings` | AdjustmentColor; CGImage apply helper | Y/Y/Y | S3 |
| `GrainSettings` | values/seed; CGImage apply helper | Y/Y/Y | S3 |
| `BlackWhiteSettings` | numeric weights/tint; CGImage apply helper | Y/Y/Y | S3 |
| `ColorBalanceSettings` | numeric tonal shifts; CGImage apply helper | Y/Y/Y | S3 |
| `LayerAdjustment` | AdjustmentKind, HSV, Levels/Curves and five settings records | Y/Y/Y | S3 |
| `LayerOrder` | ImageLayer hierarchy projection, UUID, NSLock | N/N/Y | S5 |
| `ProjectManifest` | ProjectLayerRecord, CanvasGuide, UUID | Y/mapping/mapping | S7 |
| `ProjectLayerRecord` | LayerTransform, blend, adjustment, effects, shape/text styles | Y/mapping/mapping | S7 |
| `CanvasDocument` | ImageLayer, DocumentSelection, CanvasGuide, DocumentColorProfile | mapping/Y/Y | S5 |
| `ImageLayer` | ImportedImage, transform, blend, mask, adjustment, effects, shape/text | mapping/Y/Y | S5 |
| `LayerMask` | ImportedImage, LayerTransform | mapping/Y/Y | S4/S5 |
| `ProjectSnapshot` | ProjectManifest, ImportedImage maps for images and masks | Y/N/export | S7 |
| `DocumentHistory` | optional CanvasDocument, active UUID, StateID; asset accounting | N/owner/invalidates | S6 |
| `DocumentSelection` | CGPath, feather, CGImage coverage helper | N/Y/overlay and coverage | S4 |
| `LayerShape` | LayerShapeStyle, rendered CGImage | style plus pixels/Y/Y | S4/S5 |
| `LayerText` | LayerTextStyle, rendered CGImage | style plus pixels/Y/Y | S4/S5 |
| `ImportedImage` | CGImage/thumbnail, RasterSnapshot | asset codec/shared/Y | Mac adapter S4 |
| `RasterSnapshot` | CGImage base, geometry, BrushPatch, lazy CGContext cache | materialized pixels/shared/Y | Mac adapter S4 |
| `BrushPatch` | CGRect, CGImage | materialized pixels/shared/Y | Mac adapter S4 |

## Additional types omitted from the old 47-entry closure

These are additions to the inventory, not newly introduced code. Do not keep the
claim that the 47 entries exhaust stored-property reachability.

| Type | Current file / dependencies | Classification and target | Serialization / history / renderer | Tests, difficulty, order |
|---|---|---|---|---|
| `LevelRange` | Document/Levels.swift; Double fields and math | A, shared adjustment values | Y/Y/Y | LevelsTests, AdjustmentLayerTests; S, S3 |
| `LevelsChannel` | Document/Levels.swift; SwiftUI displayName | B, enum data + UI helper | Y/Y/Y | LevelsTests; S, S1/S3 |
| `LevelsSettings` | Document/Levels.swift; LevelsChannel and four LevelRange values | A data candidate after dependencies | Y/Y/Y | LevelsTests, PSDAdjustmentTests; S, S3 |
| `CurvePoint` | Document/Curves.swift; Double x/y | A, shared values | Y/Y/Y | ImageAdjustmentTests, PSDAdjustmentTests; S, S3 |
| `CurvesSettings` | Document/Curves.swift; LevelsChannel/CurvePoint; CGImage apply | B, shared values + renderer extension | Y/Y/Y | ImageAdjustmentTests, PSDAdjustmentTests; M, S3 |
| `CanvasGuide.Axis` | Document/Guides.swift; nested string enum | A, keep with guide semantic record | Y/Y/overlay | GuideTests; S, S2 |
| `LayerHierarchy` / `LayerOpacity` | Document/LayerGroups.swift; UUID and record/hierarchy projections | B responsibility split: Core hierarchy must not depend on format DTOs | validation/indirect/Y | GroupTests, GroupingSelectionTests; M, S5 |
| `LiveMaskGraph` | Document/LiveLayerMask.swift; ID/link validation over records | B validation candidate separated from pixel baking/dialogs | validation/indirect/Y | LiveMaskTests; M, S5 |

## v12 Layer Style additions now in the synchronized source

The original classification totals still describe those original 47 entries.
These **seven additional data declarations are B candidates**; they are not a
complete recount of the whole application. Current module is Compositor for every
entry; no file/module movement has occurred. Serialization/history/render relevance
is Y/Y/Y for each data entry. See core-api §2.1 for shared meaning.

| Type | Current file | Fields and dependencies | Target / dependency to remove | Tests | Difficulty / order |
|---|---|---|---|---|---|
| `EffectContour` | Document/LayerEffects.swift | 11 Codable string cases, pure Float falloff evaluator | Core/Effects data/math; SwiftUI displayName → UI | LayerStyleTests, PSDExportTests through styles | S; S1 helper, S3 data, S7 codec |
| `EffectPattern` | Document/LayerEffects.swift | eight Codable string cases, procedural Float/UInt32 sampling | Core/Effects pattern data; displayName → UI, numerical sampling ownership open | LayerStyleTests (checker), PSDExportTests (fallback) | S–M; S1/S3, renderer parity S8 |
| `BevelEffect.Style` | Document/LayerEffects.swift | four Codable cases | Core/Effects enum; SwiftUI displayName → UI | LayerStyleTests, PSDExportTests | S; S1/S3 |
| `BevelEffect.Technique` | Document/LayerEffects.swift | three Codable cases | Core/Effects enum; SwiftUI displayName → UI | LayerStyleTests round-trip | S; S1/S3 |
| `BevelEffect` | Document/LayerEffects.swift | CGFloat geometry/colors; Style/Technique, EffectContour/Pattern, LayerBlendMode; lighting, Contour/Texture enable and range/scale/depth | Core/Effects record; CoreScalar plus PaletteColor/native helpers separated | LayerStyleTests, PSDExportTests | M; S2 + enum dependencies → S3/S7 |
| `SatinEffect` | Document/LayerEffects.swift | CGFloat geometry/colors, EffectContour, LayerBlendMode; CGSize offset and PaletteColor helper | Core/Effects; geometry/color accessors → adapters | LayerStyleTests, PSDExportTests via records | S–M; S2 + contour/blend → S3/S7 |
| `PatternOverlayEffect` | Document/LayerEffects.swift | CGFloat ink/paper colors and scale; EffectPattern/LayerBlendMode; PaletteColor helpers | Core/Effects record; CoreScalar/color helpers separated | LayerStyleTests, PSDExportTests (fallback) | S–M; S2 + pattern/blend → S3/S7 |

### Existing data declarations changed by this synchronization

| Type / file | Added semantic data or behavior | Dependencies / migration consequence | Evidence |
|---|---|---|---|
| StrokeEffect / LayerEffects.swift | optional centered, blendMode | LayerBlendMode; preserve nil vs explicit false/Normal for version gate | LayerStyleTests round-trip/dispatch |
| ShadowEffect / LayerEffects.swift | spread, contour, blendMode | EffectContour/LayerBlendMode; light-angle convention unchanged | LayerStyleTests; PSDExportTests |
| InnerShadowEffect / LayerEffects.swift | choke, contour, blendMode | same contour/blend prerequisites | LayerStyleTests through JSON/settings |
| OuterGlowEffect / LayerEffects.swift | spread, contour, blendMode | same; numerical rendering remains outside model | LayerStyleTests/OuterGlowTests |
| InnerGlowEffect / LayerEffects.swift | choke, contour, fromCenter, blendMode | same; absent fromCenter retains legacy edge source | LayerStyleTests/InnerGlowTests |
| ColorOverlayEffect / LayerEffects.swift | blendMode | per-effect backdrop is local style stack | LayerStyleTests multiply/Fill Opacity |
| LayerEffects / LayerEffects.swift | bevel/satin/patternOverlay/fillOpacity; visible/scaled; usesLayerStyle vs needsStyleRenderer | separate serialized presence/version meaning from render dispatch; fixed nine-kind order | LayerStyleTests save11/save12/remove, defaults, render, cancel/undo |
| LayerShapeStyle / ShapeTool.swift | optional filled, strokeWidth/RGB, strokeOutside | CGFloat geometry/PaletteColor; additive format fields, old inside stroke preserved | ShapeToolTests style/undo/legacy stroke |
| LayerOrder / LayerGroups.swift | maskSourceID in cache key; lower-sibling hidden clipping | derived graph meaning belongs with hierarchy, not UI-only visibility | LiveMaskTests hidingTheClippingBaseHidesItsClippedLayers |
| ProjectManifest / ProjectStore.swift | current12/compatible11, neededVersion | depends on LayerEffects.usesLayerStyle, not rendered visibility | LayerStyleTests savesInTheOldestVersionThatHoldsTheProject |
| ProjectStore / ProjectStore.swift | presence-based v12 validation and conditional save version | Formats/Comp validation + native I/O adapter; no new migration | LayerStyleTests save/load and existing ProjectTests |
| PSDRecord / IO/PSD/PSDTypes.swift | optional LayerEffects | format DTO → Core settings; preserve unsupported-feature notes | PSDExportTests style/text round trips |

### New orchestration, renderer and format helpers (outside shared model)

| Type / current file | Classification / dependencies / target | Serialization, history and renderer relation | Tests / future order |
|---|---|---|---|
| `LayerStylePage` / Document/LayerEffects.swift | C application/UI adapter: blending/effect/Contour/Texture pages | N/N/UI; not persisted model or public Core page API | LayerStyleTests; stays UI |
| `LayerStyleEdit` / Document/LayerEffects.swift | C edit adapter: UUID, original optional effects, opacity, blend, page | N/original-values for commit-cancel/preview; retain future transaction intent, not dialog state in Core | LayerStyleTests; Q16 before S6 |
| `LayerStyleRenderer` / Rendering/LayerStyleRenderer.swift | D; CoreGraphics/Foundation, BrushRaster, effect settings | N/N/pixel output; CPU renderer remains renderer | LayerStyleTests; projection at S8 |
| `LayerStyleBlend` / Rendering/LayerStyleRenderer.swift | D numerical renderer helper; LayerBlendMode, SIMD | N/N/local blend output; potential shared pure algorithm separately assessed | LayerStyleTests; no move now |
| `PSDLayerStyle` / IO/PSD/PSDLayerStyle.swift | C Formats/PSD adapter: descriptor items, effects, PaletteColor/contours | PSD lfx2/iOpa, not .comp; procedural patterns/texture fall back to pixels | PSDExportTests; S7 service boundary |
| `PSDTextWriter` / IO/PSD/PSDTextWriter.swift | C native text/Formats adapter: Foundation/AppKit layout and geometry | PSD TySh/EngineData; UTF-16 text spans, raster fallback | PSDExportTests/PSDRoundTripTests; S7 + text adapter |

Duplication and whole-layer clipboard paths already copy `effects` by value;
ProjectWorkspace cross-document copy preserves them while remapping layer links.
History equality includes LayerEffects. Grouping retains child styles and is still
pass-through; styles are not newly supported on folders. Dedicated v12 tests for
duplicate/clipboard/group combinations remain a coverage gap, not a reason to
replace the existing implementations during this sync.

## E — responsibilities to separate or replace

| Item | Current coupling | Target boundary, not code change |
|---|---|---|
| E1 | LayerShape/LayerText retain rendered CGImage with style | Separate semantic style from immutable fallback content; retain live-style identity behavior |
| E2 | ImportedImage.thumbnail participates in history byte accounting | Platform/UI cache policy plus explicit resource accounting; measure before changing budget behavior |
| E3 | ImageLayer equality uses CGImage identity | Immutable content identity, preserving no-op/history semantics |
| E4 | LayerOrder global cache under NSLock | Snapshot/instance-owned derived hierarchy; not a selected container/locking design |
| E5 | NSAlert in deleteWithLiveMaskChoice | UI policy decision, pixel service preparation, atomic Core commit |
| E6 | Model UI/localization/NSColor/CGBlendMode helpers | Platform/UI/renderer extensions; includes seven reclassified entries |
| E7 | Model definitions mixed into EditorSession and rendering files | One small declaration seam at a time; no whole-file migration |
| E8 | Process-wide WorkingColorSpace | Explicit document/snapshot color context for migrated paths; existing Mac callers remain until separately adapted |

## Migration use

The dependency map owns stages, prerequisites, required tests and rollback points.
No automatic step converts the model to C++, removes Swift types, or merges the
spike. The smallest future code unit is FilterKind data/display-helper separation,
after baseline tests. This documentation task stops before that change.
