# First S1 slice: FilterKind — 2026-10-01 (KST)

Status: data declaration dependency-clean; local source-parity/boundary/shared-C
validation passed. Mac build, standalone Swift typecheck and Swift regression tests
are pending CI evidence. No other type or Core language is selected by this change.
Implementation commit: `9bac5cfb3cb1e0c21b359ee1d76855118279e211`.

## Starting state and main drift

Started on clean Compositor-Multiplatform `88dfcd9`, matching origin. Both main-sync
`db268a2b` and architecture commit `88dfcd9` were present. Remote main advanced
from `ccf062ed` to `0be4fe6a6ba038385ab2b6c5f059376ed8a628f2`: `fcf8030` font
family/face controls and Korean-input shortcuts, `e420fc4` DMG generation, `0be4fe6`
release feed. Read all affected model/test/input diffs before editing.

LayerTextStyle gains fontNames/uniformFontFamily, including an NSFont dependency;
font/keyboard/type tests change. EditorCanvas changes key-event interpretation,
not pixel rendering. FilterKind, filter dispatch, .comp schema and shared C are
unchanged. Reported this drift and proceeded with the independent FilterKind seam;
**no main merge occurred**. The next text-related migration must review that delta.

## Observed FilterKind and real callers

Originally the enum lived in Document/Filters.swift, importing AppKit, CoreImage,
Observation and SwiftUI for many other types/operations. The enum itself had 17
String cases, CaseIterable, Sendable and synthesized Equatable/Hashable; no Codable
conformance. Its only direct UI dependency was displayName: LocalizedStringKey.
isAutomatic and isImageAdjustment are pure classification properties, retained.

| Caller inspected | Meaning preserved |
|---|---|
| CompositorApp Image/Filter command menus | Explicit Image-menu list; Filter-menu allCases filtered by classification, id: self and localized Text with ellipsis |
| UI/FilterSheet | Exhaustive kind switch chooses controls; automatic filters gate progress/OK |
| ContentView | Camera Raw panel placement and rawValue panel title |
| Document/Filters: PixelFilter.run | Exhaustive filter dispatch into existing C/Core Image/native implementations |
| Document/Filters: FilterEdit/FilterJob | Typed job/edit state, blur-margin partial switch and preview caching |
| Document/Filters: EditorSession | beginFilter, preview/commit, rawValue as asset/history name; existing undo grouping unchanged |
| Document/LayerAdjustment | Persisted AdjustmentKind maps to FilterKind for editing/blur-noise execution; FilterKind itself is not persisted |
| CameraRawTests/ImageAdjustmentTests/FinishingFilterTests | Existing classification and actual pixel processing coverage |

There is no FilterKind field in ProjectManifest/ProjectLayerRecord and no Codable
extension. Persisted AdjustmentKind is a separate enum and is unchanged. No v12
Layer Style linkage requires migration here. Raw names still matter for undo/panel
labels even though they are not .comp enum records.

## Minimal split

- Document/FilterKind.swift: same enum declaration, cases and pure properties,
  with no imports. This is not a new module or a Windows binding.
- UI/FilterKind+Display.swift: original exhaustive literal switch, same displayName
  API. Explicit nonisolated preserves access semantics under the app's default
  MainActor setting; the enum also retains its original nonisolated modifier.
- Filters.swift: only the old declaration was removed; all remaining source is
  byte-for-byte unchanged. All call sites and Localizable.xcstrings are unchanged.
- Xcode uses filesystem-synchronized Compositor/CompositorTests groups, so no
  project-file or target-membership edit is needed.

Direction: Mac presentation extension → FilterKind. The data file has no dependency
on its display extension. The current Mac app still compiles both; a future host
can compile the pure declaration independently with a compatible Swift compiler.
Windows compilation/integration was not performed, and this does not choose Swift
as the final Core implementation language.

Product diff: three files, 53 inserted/50 removed lines, almost entirely moved
source (27-line data file, 26-line presentation file). Tests add43 lines, boundary
script24, existing verify workflow5. No renderer/history/format operation changed.

## Validation

| Check | Result / scope |
|---|---|
| Original source comparison | Enum/cases/raw values/order/classifications exact; display switch exact except explicit nonisolated; remaining Filters.swift exact |
| Localization catalog | All17 original keys have Korean entries; entire catalog unchanged |
| New FilterKindTests | Three Swift tests: case/raw/order/round-trip/Hashable; classification/menu order; every display key. Added to existing Mac test target, not run on Linux |
| New lexical boundary guard | Passed locally; all imports and platform/UI type names prohibited in the data file |
| Guard failure-path checks | Six temporary injected dependencies (SwiftUI/AppKit imports, LocalizedStringKey, NSColor, CGPoint, HWND) rejected; comment-only names accepted |
| Standalone data typecheck | Added `xcrun swiftc -typecheck Compositor/Document/FilterKind.swift` to verify.yml; no local Swift compiler |
| Mac app/full tests | Existing verify.yml build-for-testing + parallel and serial suites retained; no local Xcode/macOS frameworks |
| Shared C | Existing Release/OpenMP build passed; CTest pixels1/1 passed (0.39 s) |
| Existing spike guard | Unchanged e3bf3868 extracted script passed; original spike not modified or merged |
| Live CI query | GitHub API returned403 Forbidden; no passing CI claim |

The guard follows the spike's simple lexical approach, scoped to the one migrated
file. It is not a Swift parser/security boundary; standalone compilation in CI
provides the stronger dependency check. No lint framework or new build module.

Run `python3 scripts/check-model-boundaries.py` locally. On Mac, run the existing
verify.yml build/test commands; the full suite includes FilterKindTests and the
existing filter/adjustment tests. No new serialization/golden fixture is needed
for a declaration move without a persisted FilterKind value or format change.

## Consequences and stop point

Inventory reclassifies FilterKind B→A; original47 totals become A7/B29/C8/D3.
S1 is only partially implemented, and runtime Mac validation remains pending.
core-api.md is unchanged because its semantic contract did not change.

This approach suits small enums whose only coupling is a display helper. It does
not demonstrate that image/geometry/history types can be moved the same way.
Potential later candidates: TextAlignment (review new main text helpers first),
ColorRange (preserve Codable dictionary keys and HueBand defaults), LayerEffectKind
(preserve nine-kind order and default-blend policy). None is migrated here.
