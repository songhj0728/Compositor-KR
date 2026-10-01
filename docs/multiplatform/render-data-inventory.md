# Publication lifecycle and renderer data inventory

Audit baseline: Compositor-Multiplatform `cd4a58a3a664e674938e5a16b6d6684b96a6c821`,
2026-10-01 (KST). This is source analysis and a semantic projection draft. No
publisher, render type, renderer API or mutation implementation is added.

## Verification and membership gate

Local/remote HEAD matched; working tree was clean. CoreSnapshot.swift and
CanvasDocument+CoreSnapshot.swift exist. `coreSnapshot` has two test call sites and
no application consumer. Main is still `0be4fe6`; its previously reviewed font/
keyboard/packaging delta has not advanced. No automatic merge occurred.

| Required Mac check | Actual evidence at this audit |
|---|---|
| App build | Unverified; Linux has no Xcode; Actions request Forbidden |
| Full CompositorTests | Unverified |
| CoreSnapshotTests (four new tests) | Unverified |
| FilterKindTests | Unverified |
| TextAlignmentTests | Unverified |
| CI boundary checks/standalone Swift typechecks | Unverified; local Python lexical guard passes |

`Compositor-KR.xcodeproj/project.pbxproj` has PBXFileSystemSynchronizedRootGroup
`8F311F9B` for Compositor, attached to app target `8F311F98`, and `8F311FA9` for
CompositorTests, attached to test target `8F311FA5`. There are no membership
exceptions excluding the new files. Thus the Core/adapter files and test file
belong to the intended targets by configuration. The shared Compositor scheme
builds both for testing and lists CompositorTests with skipped=NO. verify.yml
builds-for-testing, runs the suite except two window suites, then runs those two
serially; the new tests are not skipped. This is static membership evidence,
not successful compilation or execution evidence. No known Mac failure is visible.

## Publication lifecycle: observed behavior versus target

Sources: [DocumentHistory](../../Compositor/Document/DocumentHistory.swift),
[EditorSession](../../Compositor/Document/EditorSession.swift),
[project installation](../../Compositor/Document/EditorSession+Projects.swift),
[ProjectController](../../Compositor/IO/ProjectController.swift),
[external reload](../../Compositor/IO/ProjectController+ExternalChanges.swift),
[ProjectWorkspace](../../Compositor/Document/ProjectWorkspace.swift),
[Layer Style editing](../../Compositor/Document/LayerEffects.swift),
[appearance editing](../../Compositor/Document/LayerAppearance.swift),
[filter editing](../../Compositor/Document/Filters.swift).

There is currently **no DocumentInstanceID owner or DocumentGeneration publisher**.
DocumentHistory owns `revision`/`savedRevision` UUIDs; it does not own every visible
preview. ProjectTab.id is a tab identity; CanvasDocument.id is persisted content
identity. ProjectController.saveGeneration is a successful-save counter used to
re-read a file changed by save during open confirmation, not Core Generation.

| Event | Current behavior | Target StateID rule | Target Generation/publication rule |
|---|---|---|---|
| Session/tab construction | EditorSession/DocumentHistory initialized; history UUID initially marked saved; document may be nil | Initial no-document state identity if exposed | Establish owner and instance epoch; initialize sequence, not one per read |
| New project | createNewProject clears/reset history, then createDocument | New history epoch and meaningful new canvas state | Retire former open instance when replacing project; publish new instance/state |
| New/replacement canvas command | createDocument uses beginEdit/endEdit, may be undone back to prior canvas or nil | Fresh after-state UUID; retain before-state | Advance within same edit session, even if persistent CanvasDocument.id changes |
| Open successful | Validates whole package before installProject; assigns stored document/layer UUIDs; resets history | Fresh session state, marked saved | New open instance epoch; file UUID alone cannot validate jobs |
| Open/load failed or abandoned | Candidate not installed | Unchanged | No document publication; UI error/status may publish separately |
| Layer edit | beginEdit captures before; outer end compares document equality and creates revision if different | Fresh for meaningful committed change | Publish coherent changed state, once per externally visible publication |
| Grouped/nested edit | depth nesting; one before/after entry at outer end; interim live edits can be visible | One final meaningful StateID, not one per intermediate write | Each published visible intermediate view advances; coalesce unpublished writes |
| Opacity slider | beginOpacityEdit → repeated live writes → finishOpacityEdit/endEdit | One final state for gesture | Repeated visible changes advance even before history finishes |
| Undo | revision=entry.before.revision; EditorSession.restore installs optional document and active layer | Restore exact before StateID | Advance; never restore prior Generation |
| Redo | revision=entry.after.revision; restore installs after document/context | Restore exact after StateID | Advance; A→B→A still rejects first-A work |
| No-op edit | Document equality at outer end preserves revision and redo | Preserve StateID | No advance if entire observable publication unchanged; preview/context removal can still be a real publication |
| Transform/blend/filter preview | Pending transform/blend or generated filter pixels substitute in displayed helpers; normal filter preview need not change document | Retain committed StateID; mark preview explicitly | Advance when a new accepted preview becomes observable; stale jobs do not publish |
| Brush/gradient/pixel move/text/shape draft | Session transient state and raster/tile data contribute to display; tool-specific finish/cancel | Committed ID stays until meaningful finish | Publish coherent draft versions; no mutable stroke storage in a retained render description |
| Layer Style preview | applyLayerStyle directly edits live effects/opacity/blend; history stays at old revision | Target needs committed base plus explicit uncommitted preview | Advance per changed published preview, even though revision stays fixed |
| Cancel | Tool-specific removal/restore; Layer Style restores originals without history entry; undo first discards pending gradient | Restore committed base identity; no new committed state for pure cancellation | Publish restoration/removal with fresh Generation; do not rewind sequence |
| Commit/OK | Transform/filter use begin/end; Layer Style restores originals internally then reapplies final values in one edit | Fresh if changed, otherwise retain base | Publish final committed envelope with fresh Generation if data or preview/commit status differs; hidden temporary restore is not a publication |
| Save capture | prepareSave captures revision and ProjectSnapshot before save-panel await | Preserve state; identify captured StateID | Capture existing coherent publication; capture alone does not advance |
| Save success | Background write; markSaved(captured revision); URL and watcher bookkeeping update | Saved marker becomes captured state, even if current state changed | No new content state; advance shared publication only if exposed saved/context status changes, not for disk I/O alone |
| Save failure/export | Save failure preserves saved marker; export does not mark saved | Preserve StateID | No content publication; failure/UI progress handled in app status |
| Autosave/recovery | No autosave publisher/scheduler found in Compositor sources; watcher is external reload, Quick Look is save output | Future captured-state rule only | Unvalidated; do not invent existing autosave semantics |
| External same-project reload | Digest comparison; full load, reloadProject→installProject/reset; retains viewport/collapse and valid selection; rejected/mid-write load leaves old state | Fresh history epoch, marked saved | Candidate: same open instance, monotonically newer publication; invalidate old work. Different project replacement gets new instance |
| Close/clear | clearProject clears document/context and resets history; tab/window lifecycle owns teardown | Retire active state/history epoch | Invalidate instance; retained immutable snapshots remain alive independently |

### Owner candidates and unresolved edges

A. **DocumentInstanceID:** an open-document/session coordinator beside EditorSession
and ProjectController, with MainActor as the current Mac owner context. ProjectTab
may contain it but tab identity cannot substitute: a tab/session can replace its
project, while undoable canvas replacement may change persistent UUID within the
same session. New-project/open/close rotate or retire epochs; in-place reload can
retain the epoch while advancing Generation. Exact transition API is unimplemented.

B–D. **StateID:** history's committed revision is the natural compatibility source.
Fresh on meaningful outer commit; before/after IDs restore on undo/redo; load resets
history. Selection/guides in CanvasDocument are history data, unlike viewport.
Active-layer changes alone currently do not create a history revision.

E–H. **Generation:** the session publication coordinator must see committed data,
preview/draft, active edit context and exposed save status. History alone, property
observation alone, a draw counter, and the existing save counter are insufficient.
Snapshot reads/redraw requests/cache hits do not advance it. An accepted changed
preview and cancellation advance it. Same pixels with changed preview/committed
status are still distinct publications. Unchanged hidden writes need not publish.

I. Load/install changes the history epoch; save marks the captured state, not current
state indiscriminately. In-place reload must invalidate all old background results.
No token is persisted. Instance+Generation, not StateID alone, gates completion.

**Current/target gap:** canStartProjectOperation omits layerStyle, and the save
begin path cancels crop and commits transform, but does not resolve Layer Style
(textDraft instead prevents starting the file operation).
projectSnapshot reads current live values. Consequently a preview can be saved
with the old history revision; the target committed-only save contract is not
current behavior. External-change gating also uses this incomplete predicate.
Do not silently change this behavior in a projection task. Save→Cancel/OK traces
and reload-during-style traces need characterization before lifecycle integration.

## Rendering call chains inspected

- EditorCanvas.updateNSView → CanvasView.synchronizeDisplay builds private
  DisplayState from effective hierarchy/opacity, displayed transforms/blend/masks,
  image identities, text and brush revisions. It invalidates view regions; it is
  not a complete immutable render snapshot.
- CanvasView.draw → drawOnGPU/gpuFrame → GPU composite helpers → GPUPlacement,
  GPUBlend, GPUCanvasRenderer (Core Image graph, Metal textures/presentation).
  GPU failure/unsupported operations fall back to Core Graphics.
- CPU draw → drawDocumentPixels at crisp zoom or drawLayers → LayerRenderer /
  TiledLayerRenderer, AdjustmentSurface, SeparableBlend, LiveMaskRenderer and
  FolderMaskClip. Own masks are applied before effects; layer opacity afterwards.
- ImageExporter.render(ProjectSnapshot) → record validation → LayerHierarchy /
  LiveMaskRenderer / FolderMaskClip → LayerEffectsRenderer → LayerRenderer.
  Export uses full-resolution saved assets, no canvas chrome or session drafts.
- LayerEffectsRenderer.render → visible effects/margins/masked source → legacy
  MetalLayerEffects where possible, full floating-point LayerStyleRenderer for
  new styles/Fill Opacity/nonlegacy parameters, with CPU fallback.
- Text/shape committed raster is authoritative for ordinary compositing. Draft
  text/native layout and shape generation produce substituted content before draw.
  Overlay paths/selection, guides and handles are separate from document composite.

## Renderer data inventory

This table inventories semantic inputs and renderer-derived data across canvas,
export and overlay paths. References below are relative to Compositor/. P means
projection capture/derivation; B means backend execution; O means UI/overlay request.
Apple types are current adapters, not proposed shared fields.

| Data and source | Current raw/derived consumer | Parent/group effect | Proposed capture vs execution | Current Apple dependency |
|---|---|---|---|---|
| CanvasDocument.id; ImageLayer.id (Document/EditorSession.swift) | Raw UUID; DisplayState invalidation, by-ID lookup | Identity qualifies links | P retains stable IDs plus open instance/state/generation | Foundation UUID; no GPU identity |
| layers order; parentID/isGroup (EditorSession, LayerGroups.swift) | Raw bottom-to-top container; LayerOrder.resolve groups traversal, renderLayers filters folders/hidden nodes | Nested traversal changes paint order; collapse only panel | P computes ordered nodes and dependency-only sources once; preserve pass-through groups | NSLock hierarchy cache, model mixed Apple file |
| isVisible (LayerGroups/LayerOrder.hiddenClipping) | Raw own flag → effectiveVisibleIDs/visibleLayers | Ancestor suppression; hidden lower same-parent clipping base suppresses children | Core defines rule; P resolves effective flags; B consumes | IDs/bools portable; current record/model dependencies |
| opacity (LayerGroups/LayerOpacity) | Raw Double → product through ancestors | Folder opacity multiplies each descendant, not isolated folder composite | P derives effectiveOpacity once; B applies at correct compositing stage | Double portable |
| blendMode (LayerAppearance, SeparableBlend.swift, GPUCanvas.swift) | Raw plus session blendPreview; CG/CI mappings and custom blending | Pass-through folders Normal; clipping stack blends in base mode | P resolves displayed semantic mode; B implements formulas/alpha | CGBlendMode, CI filters/images |
| maskSourceID (LiveLayerMask, LiveMaskRenderer) | Raw directed graph → clipping stacks/coverage recursion | Contiguous same-parent lower-base stack differs from external/upper source | Core validates graph/meaning; P resolves stack vs independent link; B produces coverage | CGImage/CGContext/CIImage, C alpha kernels |
| Source coverage (LiveMaskRenderer.coverage; EditorCanvas GPU live helper) | Derived source alpha including own masks/opacity and source chain, independent of source visibility/color | Source may be hidden or outside visible traversal; folder context not identical to own-mask context | P retains dependency closure even for nondrawn source; B samples/composes coverage | CGImage/CIImage temporary surfaces |
| transform (LayerTransform; EditorSession.displayedTransform) | Raw origin/size/degrees/flips/sampling → displayed preview, affine placement | Group transform draft follows original placements; masks can move separately | P resolves semantic placement; B device-space mapping/resample | CGPoint/CGSize/CGFloat/CGAffineTransform |
| bounds (EditorCanvas.renderBounds, raster grids, effects margins) | Raw dimensions plus derived expanded/draft/render extents | Effects/crop/paint outside old layer; viewport clips work | P includes logical grid/origin/content/effect extents; B computes target/device clips and tile support | CGRect, CG paths |
| asset (ImportedImage; Rendering/RasterSnapshot.swift) | Immutable source image/thumbnail or base+patch raster, may flatten lazily | Drawable content; dependency sources need pixels even hidden | P retains logical immutable content reference; B uploads/rasterizes; ownership placeholder only | CGImage, pixel providers, native raster references |
| mask.asset/isEnabled/isLinked/placement (LayerMask.swift) | Raw mask fields → enabledImage, displayedMaskPlacement, resampled clipImage | Own mask before effects; independent placement; link affects editing | P records enabled coverage ref and placement; B coverage resampling | CGImage/LayerTransform/CGContext |
| Folder masks (LayerMask/FolderMaskClip; GPU folderMask) | Raw group masks → ancestor clip list/multiplication | Applies to descendants; not ordinary folder image | P retains ordered ancestor mask context; B applies coverage once | CGImage, CGContext, CIImage |
| adjustment (LayerAdjustment.swift, LiveMaskRenderer, GPUBlend.apply) | Raw LayerAdjustment kind/settings → transforms current lower composite | Folder masks/opacity; clipped adjustment operates on stack; source-linked nonstack behavior restricted | P captures settings, stack scope, region/scale requirements; B evaluates filter/mixes preserving alpha | CIImage, CGContext, color cubes/Data, C kernels |
| effects (LayerEffects.swift) | Raw nine optional slots + enabled flags → visible projection and isValid | Each effect blends within layer; composed result then layer/group opacity and external clipping | P preserves semantic effect description, enabled state and fixed order; B executes kernels | CGFloat/CGSize, CGImage/CGColor current helpers |
| fillOpacity (LayerEffects.fill/LayerStyleRenderer) | Optional raw field default 1 → source-only fade | Independent of layer opacity; effects remain visible at fill 0 | P resolves fill separately; B source/effect composition | Double value; current CPU floating raster |
| Full Layer Style (LayerStyleRenderer, MetalLayerEffects) | Bevel/Contour/Texture, Satin, Pattern Overlay, effect modes/spread/choke, stroke position → style dispatch | Local effect stack, not document blending; pattern anchored in original layer pixels | P retains semantic parameters/local origin; B chooses execution/fallback/margins | CGImage/CGPoint/Float arrays/Metal compute |
| text (TypeTool.swift; InlineTextEditor; EditorCanvas.editedText) | Stored LayerTextStyle and raster fallback; draft/native layout provides image+shown transform | Existing layer position/effects/masks; new draft insertion above active layer | P chooses committed or accepted preview content; layout service upstream; B composites pixels | NSAttributedString/AppKit text system/CoreText via native layout, CGImage |
| shape/path (ShapeTool.swift; EditorCanvas shapeDraft) | Editable style + saved raster; transform preview/draft raster generation | Inserted above active layer; outside-stroke changes bounds | P chooses versioned content/placement; platform raster service upstream | CGPath/CGImage/CGContext/NSBezierPath |
| selection (Selection.swift; TransformOverlay, brush/gradient preview) | Raw path/feather/AA → coverage for tool input and separate outline overlay | Not a global clip on entire document; lifted pixels/draft brushes use frozen selection | P associates accepted preview/overlay with same generation; B samples prepared coverage; O draws outlines | CGPath/CGImage/CGRect |
| filters (Filters.swift; EditorCanvas.drawOwn/own) | FilterEdit generated/prepared image/transform replaces asset; hue/levels similarly | Effects/masks/placement still apply; empty layer may show preview | P chooses accepted job output; no mutable FilterEdit in snapshot; B uses content | CGImage/CIImage/native settings helpers |
| brush/warp/gradient/pixel move (EditorSession+Brush, EditorCanvas) | Session live stroke grids/patches, sourceRect, selectionClip, revisions, warp result | Own masks/folder masks/effects still affect preview; paint beyond original bounds may be revealed | Freeze/retain accepted immutable preview upstream of P; B tile/update/gradient execution | CGImage/CGColor/CGRect/MTLTexture mutable stroke cache |
| Document dimensions/resolution/profile (EditorSession, ColorProfile.swift) | Raw width/height/resolution/profile; export render extent/profile; working space selected from current tab | No ancestor effect; profile affects all pixel/filter interpretation | P carries dimensions and document-specific color meaning; B color conversion/context; resolution primarily export metadata | CGColorSpace/CIContext; global WorkingColorSpace |
| Background (EditorCanvas.gpuFrame/draw; ImageExporter.render) | Checkerboard/shadow/dark chrome derived from viewport; actual Background is a normal layer | Composite alpha retained; JPEG matte is export option | Model content in P; O/request owns checkerboard/backdrop; export matte separate | NSColor/CIColor/CGColor |
| Guides/grid/handles/rulers (Guides.swift, CanvasLinesOverlay, TransformOverlay) | Guide model + viewport/tool settings → overlay geometry | Independent of layer composite; active context controls handles | Same-publication semantic overlay projection plus separate O/view request | CG paths/AppKit views/colors |
| Cache/display state (EditorCanvas.DisplayState, EffectsPreviewCache, DownsampleCache, TiledPieceCache, GPUCanvasRenderer) | Derived image identities, levels, recent results, seeds, strokes, textures, budgets and dirty rects | Keys must include relevant ancestry/mask/profile/preview context | B/platform owns caches; never authoritative domain snapshot data | ObjectIdentifier, NSLock, CGImage, CIImage, MTLTexture |

### Subtleties to preserve

- The visible render list alone is insufficient: hidden live-mask sources and their
  dependencies must be retained. Lower same-parent clipping-base visibility has a
  special suppression rule; an arbitrary external hidden source remains usable.
- Clipping stacks preserve the base alpha rather than source-over it repeatedly;
  child modes act within the stack and the whole stack uses its base mode.
- Group opacity is per-descendant, groups are pass-through; folder mask context
  cannot be replaced by drawing a flattened isolated group without parity evidence.
- Layer Style order: shadow, outer glow, outside stroke, source pixels, pattern
  overlay, color overlay, satin, inner glow, inner shadow, inside/centered stroke,
  bevel. Mask the source before effects; fade source by Fill Opacity independently;
  apply composed layer opacity later. Preserve pattern origin across padding/tiles.
- Adjustment layers read the already-composited lower surface; source pixels alone
  cannot describe their input. Preserve alpha and document-anchored noise/grain.
- DisplayState tracks redraw dependencies, not complete renderer ownership. Effects
  cache may return an older result while a request runs; this is presentation
  fallback, not proof the old pixels belong to the requested semantic generation.

## Model snapshot versus render snapshot

| Concern | Current CoreDocumentSnapshot / model reading | Candidate render projection |
|---|---|---|
| Purpose | Minimal domain metadata, IDs, own properties in stored order | Complete immutable description of one committed/preview publication for a named render purpose |
| Completeness | Omits hierarchy/content/dimensions/styles; cannot reconstruct rendering | Explicit ordered draw nodes plus dependency closure, masks, effects, transforms and color meaning |
| Visibility/opacity | Own values | Effective flags/opacity and ancestor mask context, with own values retained where composition needs them |
| Ordering | Physical bottom-to-top array | Hierarchy-resolved drawing/stack order; source-only nodes are not automatically drawn |
| Preview | Adapter records caller-supplied tokens, has no preview capture | Explicit committed base StateID, Generation and preview status/source; immutable accepted outputs |
| Cache | None | No textures/cache objects; result provenance and render request separate |
| Save/export | Not a save description | Committed full-resolution projection; canvas preview substitutions excluded unless explicitly requested |

CoreDocumentSnapshot stays unchanged. A conceptual RenderDocumentSnapshot would
carry instanceID, committed stateID, generation, committed/preview marker, document
pixel dimensions/color interpretation and ordered render nodes plus dependency-only
nodes. A RenderNode candidate carries stable layer ID/kind, effective visibility/
opacity, independent Fill Opacity, semantic blend mode, placement and logical
bounds, group/pass-through and parent/ancestor context, clipping relation/stack
membership, immutable content/mask references and semantic adjustment/effect/style
data. Text/path raster service outputs can stand in as immutable content; there is
no selected shared image/path handle layout or allocator. No Swift types are added.

A separate RenderRequest identifies canvas/export/thumbnail purpose, target scale,
viewport/output region, sampling/display-profile inputs and optional chrome/overlay.
Different zoom requests can use one model Generation; view changes alone need not
advance document Generation. Preview/active-context changes that alter the shared
publication do advance it. Final rendered results must match both publication and
request. Async cache completion for unchanged semantics does not create a new
domain Generation; retain result/request provenance or a presentation revision.
Do not present an old cached result as the exact new projection's output.

## Projection responsibility map (semantic draft)

| Responsibility | Core/domain | Render projection | Backend/service |
|---|---|---|---|
| IDs, hierarchy and clipping validity | Define/validate graph, stable identity and limits | Resolve traversal, effective flags and link classification once per publication | Consume; no policy reinvention every GPU frame |
| Parent visibility/opacity | Shared meanings and pass-through rules | Derive effective values in bulk, retain provenance/context | Apply numerically in documented stage |
| Clipping | Stable relationships and same-parent visibility meaning | Resolve stacks vs independent sources and dependency closure | Compute alpha coverage/stack blend surfaces |
| Masks | Enabled/link/placement semantics | Bind immutable refs and ancestor contexts | Resample/compose coverage; no ownership selected yet |
| Layer Style | Retain complete settings including disabled records | Project active style/order/fill/local origin without losing saved records | Execute CPU/GPU algorithms and fallback; Metal dispatch is backend policy |
| Adjustments | Validated settings and intended scope | Bind lower-stack dependency, region/coordinate meaning | Evaluate filter kernels/alpha mix |
| Draft/preview acceptance | Publication owner accepts current job and marks uncommitted | Select coherent content/geometry/style substitutions | Raster/layout services prepare immutable output; no live editing from draw |
| Color | Document-specific semantic inputs | Freeze color interpretation for all nodes | Conversion/profile implementation and device context |
| View/chrome/overlay | Relevant document selection/guides/context only | Separate overlay projection/request | Viewport mapping, checkerboard, device sampling, UI drawing |
| Cache/invalidation | Immutable resource identity, no cache storage | Generation and semantic dependency keys/provenance | Resource budgets, texture uploads, dirty regions, result retention |

These placements define responsibilities, not new modules or a GPU choice.
Shared projection rules should be backend-independent and tested before extracting
code. Numerical rasterization/coverage/padding work is not forced into domain Core.

## Mac renderer parity checklist and reusable evidence

Use the existing renderer as reference at the same model publication and named
request. Record dimensions, working/display profile, scale/viewport, preview mode,
content versions, alpha convention and backend availability. Compare semantic
projection first (IDs/order/visibility/opacity/links), then pixels/alpha. Never use
one blanket tolerance or compare a reduced preview to full-resolution export.

| Area | Existing suites/fixtures to reuse | Acceptance needed for projection integration |
|---|---|---|
| Ordering/group/visibility/opacity | GroupTests.hiddenParentOverridesChildrenAndExportOrderFollowsGroups; GroupingSelectionTests; LayerAppearanceTests; GPUCanvasTests.matchesCoreGraphicsCanvas | Same nested traversal, hidden parent/base, multiplied folder opacity, no collapse effect |
| Blend/alpha/clipping | LiveMaskTests; GPUCanvasTests.clippingStacksBlendInTheirBasesMode, softLightMatchesPhotoshop, softEdgedLayersBlendTheSame, matchesALiveMaskOutsideAClippingStack | Soft-alpha stack preservation/base mode, hidden/external source, source chains, special blend formulas |
| Masks/placement | LayerMaskTests, MaskTransformTests, MaskAloneTests; GPUCanvasTests.aNewMaskRevealsTheWholeLayer | Enabled/disabled, own/folder, linked/unlinked/independent placement and mask-only view |
| Transform/sampling/tiles | TransformTests, TiledLayerTests.tiledLayersDrawLikeOneImage/translucentStrokesDrawLikeOneImage; GPUCanvasTests.matchesWhileDistorting | Rotation/flips/nearest/shrink, pixel edges, odd dimensions, clipping/padding and no translucent seams |
| Adjustments | AdjustmentLayerTests, ImageAdjustmentTests, GPUCanvasTests.matchesEveryAdjustment/matchesAdjustmentsInABlendMode/patternsStayWithTheDocument | Lower-stack scope, alpha restoration, masks, folder opacity, noise/grain coordinate anchoring |
| Effects/Fill Opacity | LayerStyleTests.fillOpacityFadesThePixelsButNotTheOverlay/blendModesMixWithThePixelsUnderneath/innerBevelLightsOneSideAndShadesTheOther/satinAndPatternDrawOnlyInsideTheShape; FinishingFilterTests, OuterGlowTests, InnerGlowTests | Nine styles/order/defaults, fill independent of layer opacity, disabled data retained, tiled pattern origin and dispatch/fallback |
| Text/shape | TypeToolTests.saveReopenAndRasterize; ShapeToolTests; GPUCanvasTests.matchesWhileTyping/matchesWhileDrawingAShape | Saved raster and live draft placement, masks/styles, native layout output treated consistently |
| Preview/commit/cancel | GPUCanvasTests paint/move/smudge/gradient/distort/effects cases; HistoryTests; LayerStyleTests.layerStyleDialogIsOneUndoStepAndCancelPutsItBack | Coherent preview version, cancel restoration, no cache blink falsely counted as semantic change |
| Export/color | ExportTests, JPEGExportTests, ColorProfileTests, PSDExportTests | Full-resolution alpha/profile, transparent background vs matte, no canvas chrome or preview leakage |
| Publication/lifetime | CoreSnapshotTests authored; CoreBoundary synthetic tests | New actual-model same-generation capture, stale accepted/rejected jobs, close/reload, cache provenance tests still required |

GPUCanvasTests.compare generates patterned images, renders CPU CanvasView and GPU
frame, records PNG pairs, and compares RGB mean error and fraction of pixels with
maximum RGB error >12. matchesCoreGraphicsCanvas uses mean<1.5 and fraction<3%
when reduced, <1% otherwise. Other cases have their own thresholds. These compare
chrome-composited RGB, not a complete transparent-alpha golden corpus. Tests return
early when GPUCanvasRenderer.shared is nil; a green suite alone cannot prove GPU
execution. Retain actual device/backend evidence and test attachments. Other export/
mask/style tests directly sample alpha and pixels. Fixtures are mostly generated
in tests; Tests/Pixels/LiquifySmearReference.h is a C algorithm golden, not a whole
renderer golden. Current tests have not been executed in this Linux audit.

## Blockers and next gate

1. Mac compile/test/CI evidence remains unavailable, including new Core read tests.
2. Session instance epoch and coherent committed/preview publication owner remain
   unimplemented; history revision and saveGeneration cannot replace Generation.
3. Layer Style preview/save/reload behavior needs traced compatibility decisions.
4. CPU drawLayers invokes pixelMove.applyOffset/gradient.applyFill: render-time
   preparation is currently coupled to mutable edit objects. Retained projections
   require preparation/acceptance before capture, without changing tools silently.
5. Effects cache seeds/recent results and native text handoff need explicit output
   provenance; resource identities alone do not establish same-generation fidelity.
6. Image/path/raster resource lifetime, frozen stroke tiles, profile isolation and
   release context remain unresolved. Global WorkingColorSpace follows front tab;
   background projection must capture the target document's color inputs.
7. Coverage closure, folder masks and clipped adjustments cannot be represented by
   four metadata fields or only visible rows; prototype needs exact graph rules.

A separately scoped, unlinked projection prototype using synthetic immutable
resource placeholders and actual-model semantic fixtures is reasonable after this
analysis. Product RenderSnapshot linkage should wait for Mac evidence, publication
and ownership prerequisites above. No renderer, mutation or GPU implementation is
started by this audit.

## RenderSnapshot prototype follow-up

User directly confirmed Mac Verify #59 succeeded (boundary, package resolve, build,
unit/window tests and job). Treat the baseline verification gate as passed; earlier
unverified statements above describe the source-audit checkpoint. Exact run SHA
was not supplied and API lookup remains Forbidden.

The [prototype](../../Spikes/RenderSnapshot/README.md) implements pure numeric flat
nodes plus hierarchy/dependency metadata. Twelve actual CanvasDocument fixtures
are fed by a test-only adapter, with reference-helper parity tests pending new Mac
CI. Local C++/transport/sanitizer tests pass. Hidden dependency nodes are retained;
reorder classification never mutates source links; Fill Opacity stays independent.
No app renderer input/path changes or pixel parity claims are made. Resource
ownership, complete render descriptors and publication lifecycle remain blockers.
