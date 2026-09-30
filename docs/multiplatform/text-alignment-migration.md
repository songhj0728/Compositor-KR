# Second S1 slice: TextAlignment — 2026-10-01 (KST)

Implementation: `78cf0e90838875373a23897e46d8496cad8299af`. Status: dependency-clean
data declaration; local preservation/boundary/shared-C checks passed. Mac build,
standalone Swift typecheck and Swift tests remain pending CI evidence.

## Start and relevant main changes

Started on clean Compositor-Multiplatform `dfd4c9d`, identical to origin, with
FilterKind implementation `9bac5cf` and its documentation present. Latest main
remains `0be4fe6`, the same three unmerged commits seen during FilterKind work.
Re-read the text-related delta: fontNames/uniformFontFamily, NSFont lookup,
font-family UI/tests and keyboard input changes. It does not change TextAlignment,
alignment wire values, paragraph mapping or PSD alignment. Reported the related
changes before proceeding. No automatic main merge occurred.

## Source and callers inspected

The enum in Document/TypeTool.swift had three String cases in this order:
left="Left", center="Center", right="Right". Codable, CaseIterable and Sendable
are explicit; Equatable/Hashable are synthesized. displayName: LocalizedStringKey
was the sole direct Apple dependency. AppKit/SwiftUI imports elsewhere in TypeTool
serve the remaining text code; there is no native alignment conversion in the enum.

- LayerTextStyle stores alignment, default left. Codable ProjectLayerRecord.text
  includes the complete style; EditorSession+Projects maps live text to/from it.
  These strings are real `.comp` persisted values, unlike FilterKind's labels.
- UI/TypeControls enumerates allCases for the three icon buttons and localized
  help/accessibility text. It edits the draft through changeTextStyle; applyText
  records the existing text edit in document history. LayerText equality includes
  style, and document snapshots retain it.
- EditorSession.textAttributes sets NSMutableParagraphStyle.alignment to the
  corresponding NSTextAlignment. attributedText/textImage and native text layout
  consume it. That existing platform mapping already sits outside the enum and
  remains exactly where it was; no additional adapter is necessary.
- PSDText parses justification 0→left,1→right, 2→center; unsupported values fall back
  to left with a note. horizontalAnchor uses an exhaustive domain switch.
  PSDTextWriter uses the same PSD codes and alignment-dependent text origin.
  **PSD numeric order differs from enum iteration order**; never derive one from
  the other's index. All those functions are unchanged.
- SelectionClipboard duplicate/whole-layer copy and ProjectWorkspace cross-document
  copy preserve the LayerText value. Pixel-only copy/export keeps existing raster
  behavior. No clipboard, history, native layout or renderer operation was edited.
- TypeToolTests.saveReopenAndRasterize checks a right-aligned multilingual style;
  existing text raster tests and PSDRoundTripTests cover native/PSD consumers.

## Minimal implementation

Document/TextAlignment.swift now holds only the original enum data declaration
(three lines, no imports). UI/TextAlignment+Display.swift contains the original
literal display switch and explicit nonisolated access, following FilterKind.
Mac UI/presentation/text consumers → TextAlignment; the enum knows no UI helper.
Compositor module membership remains the same through Xcode's synchronized groups.
The rest of TypeTool.swift is byte-for-byte identical after removing the enum.

SwiftUI also defines a different TextAlignment. Tests explicitly name
Compositor.TextAlignment to avoid ambiguous imported names; no domain rename or
new alias/protocol is introduced. CoreText/AppKit/native paragraph/image handling
remains with the existing Mac text code. No Windows integration or Core language
choice is made.

Product diff: three files, 15 added/12 removed lines, almost entirely moved source.
Tests add 56 lines. Existing boundary script now checks two fixed files and reports
all violations; verify.yml adds one separate standalone typecheck command.

## Tests and verification

Added TextAlignmentTests with four tests: cases/raw/order/Hashable/display keys;
exact existing JSON strings and rejection of unknown values; LayerTextStyle JSON
alignment field and round trip for all three cases; existing renderer paragraph
mapping to NSTextAlignment for all cases. Full `.comp`/text raster/PSD tests remain
in the unchanged existing suite. No format version, codec or defaults changed.

| Verification | Result |
|---|---|
| Original declaration/Codable/raw order and display-switch comparison | Exact preservation except explicit nonisolated on the moved helper |
| Remaining TypeTool.swift, UI callers, PSD, format, history and translations | Unchanged; original three Korean localization keys present |
| Existing lexical guard extended to both enums | Passed; six injected dependency kinds rejected for each file, comment-only mentions accepted |
| Shared C build and pixels CTest | Passed, 1/1 (0.43 s), Linux Release/OpenMP |
| Original extracted spike boundary | Passed; spike remains unchanged/unmerged |
| Standalone Swift typechecks, four new tests, full Swift/Mac build/tests | Pending; Linux has no swiftc/Xcode/macOS frameworks |
| GitHub Actions query | Forbidden 403; no passing CI claim |

The current verify workflow runs both individual typechecks, app build-for-testing
and the complete parallel/serial test suites. Its trigger is not a test result.
The lexical guard is a small regression check, not a Swift parser or proof of a
compiled Windows host. Record actual Mac results when CI access is available.

## Pattern reuse and next-stage assessment

FilterKind's pattern worked for another enum, including one whose raw strings are
persisted: preserve semantics, split only presentation, test callers and wire data,
reuse the boundary guard and keep commits small. Inventory changes TextAlignment
B→A, giving original 47 totals A8/B28/C8/D3. core-api.md is unchanged.

This is not yet sufficient evidence to proceed directly to a product Core API/ABI
skeleton: both Mac validations are unverified, and these enums exercise none of
the document lifetime, bulk snapshot, threading, mutation/error or history resource
contracts. A separately scoped API prototype needs explicit operations and
acceptance evidence for those boundaries. No API skeleton or next type is started.
