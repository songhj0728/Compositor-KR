# Render resource ownership and publication decision

Audit baseline: `f6ce05721ee7ba962a5fc4878e708ceeb9fd9553` on
Compositor-Multiplatform. Initial tree clean and remote equal. This is an owner
**design decision**, source audit, and isolated synthetic ownership experiment;
no production coordinator, resource adapter, renderer API, or GPU change.

## Verification and main freshness

For baseline f6ce057, check GitHub Actions **Verify → unit**, especially
`Check model boundary`, `Check render projection experiment`, `Build for testing`,
`Run unit tests in parallel`, and `Run window tests serially`. The unit step covers
CoreSnapshotTests, FilterKindTests, TextAlignmentTests and RenderSnapshotPrototypeTests.
User-confirmed Verify #59 success is earlier baseline evidence, not proof for
f6ce057. Its Mac build/tests remain unconfirmed here. Actions API was previously
Forbidden; no repeated API requests were made. Linux cannot run Xcode.

Remote main is now `0db97a3789a18665b3c89899a2a04c7b3378986e`, advancing from
`0be4fe6`. The delta is 35 files, +1560/-362. It adds layer locking and optional
.comp v13 `isLocked`, portable BevelGeometry/LayerLockRules, corrected bevel
geometry/shading, sparse mask effect previews, cancellation and quick/refined
preview publication. `EffectsPreviewCache.Request` now captures mask raster,
thumbnail and owned-mask mode; only final results enter undo/redo recent cache.
`RasterSnapshot.preview` draws tiles without full materialization. Live bevel
regions and updated LayerStyleTests are additional parity requirements.
These changes were inspected with git diff; none merged. This document describes
checked-out behavior unless explicitly marked **incoming main**. Synchronize and
validate these changes before a production Metal adapter; the v12-only assumption
is no longer current for upstream. Existing branch format is unchanged.

## One publication owner: EditorSession

Choose **EditorSession**, with one future session-owned publication state per open
instance epoch. It owns the live document, history, transient tools and previews.
DocumentHistory alone misses previews; CanvasDocument is a persisted value and
cannot own open-instance lifetime; ProjectController owns file operations, not
all visible edits. Renderer/cache consumers must not mint document generations.
This narrows the earlier owner candidates; no coordinator is implemented.

Capture must execute synchronously on the session's MainActor, after draft
preparation and before handing immutable data to workers. ProjectController
reports successful install/reload to that owner. DocumentHistory supplies the
committed StateID (`currentRevision`). A publication records instance, generation,
committed StateID and explicit draft/committed status; preview pixels must not be
misrepresented as the committed history state. Do not use `saveGeneration`.

| Event | StateID | Session-owned Generation |
|---|---|---|
| Open/new project replacement | Fresh history epoch | New instance; initialize sequence, retire old jobs |
| Undoable new canvas | New meaningful state | Advance within current instance, even when document UUID changes |
| Committed edit / outer grouped edit | New revision if document changed | Advance on each externally published coherent view; batch unpublished writes |
| Preview/live slider/stroke/style change | Keep committed base, mark draft | Independent publication when accepted visible input changes |
| Cancel | Restore committed base | Fresh generation if a published draft is removed; never rewind |
| Commit | New meaningful history state | Fresh generation when content or draft/commit envelope changes |
| Undo/redo | Restore before/after revision respectively | Always fresh publication, not historical generation |
| True no-op | Preserve | Preserve if whole publication unchanged |
| Save/export/capture | Preserve; save marks captured revision saved | No content-generation change merely for disk I/O |
| Same-project reload | Fresh reset revision | New generation within retained instance; replacement-open rotates instance |
| Cache completion/quick→refined | Preserve | Same semantic generation, new quality/request delivery; not a model edit |
| Close | No further publication | Retire instance; retained snapshots/resources may outlive session |

Existing evidence: [DocumentHistory](../../Compositor/Document/DocumentHistory.swift)
compares documents at outer `end`, stores before/after revisions, restores them on
undo/redo, and tracks the revision actually saved. [LayerEffects](../../Compositor/Document/LayerEffects.swift)
`finishLayerStyle` restores originals before reapplying committed values inside
one history edit. Those internal writes must not produce intermediate publications.
[EditorSession](../../Compositor/Document/EditorSession.swift) `canStartProjectOperation`
does not exclude `layerStyle`; capture during that preview can contain uncommitted
values with an old revision. This needs an explicit capture policy, not a new
history implementation. EditorCanvas draw-time draft preparation also must be
moved behind a coherent capture boundary in a later task. No autosave publisher
was found; autosave remains a future captured-publication consumer.

## Resource inventory and ownership matrix

A = deep immutable value copy; B = shared immutable allocation; C = bare stable
handle; D = versioned reference. **B+D** means the reference owns a retention lease,
not a lookup into a document-owned table that disappears on close. C alone is
insufficient. Small metadata can use A while large payload uses B+D.

| Resource / source | Current owner and mutability | Apple / thread access today | Copy, retention, freeze and target |
|---|---|---|---|
| Raster: [ImportedImage](../../Compositor/IO/ImageImporter.swift) | Layer/history/export captures own immutable CGImage and thumbnail; raster optional | CGImage/CIContext/ImageIO; ImportedImage unchecked Sendable, importer actor | Full bytes O(pixels); retain native backing in adapter after freeze audit; B+D, small image descriptor A |
| Sparse raster: [RasterSnapshot](../../Compositor/Rendering/RasterSnapshot.swift), BrushPatch | Shared base/patch images; let geometry/patch array; `fill` is writable; materialized CGContext lazy under NSLock | CGImage/CGRect/CGContext; unchecked Sendable; provider reads can occur on workers | Share untouched tiles, freeze fill and color before exposure; B+D tile graph; never flatten on every publication |
| Mask: [LayerMask](../../Compositor/Document/LayerMask.swift) | Layer owns asset; value flags/placement replaced separately | Grayscale CGImage, CoreGraphics transform; enabledImage shared | B+D coverage; A enable/link/placement/background; 8-bit white reveal/black hide, no RGB conversion |
| Path/selection: [Selection](../../Compositor/Document/Selection.swift), ShapeTool | DocumentSelection holds CGPath; drafts construct CGMutablePath; coverage generated | CGPath/CGPoint, coverage CI blur; unchecked Sendable is not proof against mutable aliases | Freeze commands once O(commands), then B+D; A winding/AA/feather/coordinate convention; do not retain a mutable path alias |
| Text/layout: [TypeTool](../../Compositor/Document/TypeTool.swift) | LayerText holds value style + CGImage; liveText valid only while image identity matches; session owns TextDraft | NSFont/NSTextView/native layout stays platform side | A text/UTF-16 run/style metadata; B+D frozen raster fallback. Layout/glyph/font resource contract unvalidated; never share live text view |
| Adjustment: [LayerAdjustment](../../Compositor/Document/LayerAdjustment.swift) | Layer owns Codable value settings including curves/gradient/settings and noiseSeed | File mixes UI, CGFloat and execution; backend uses CI/C | A validated tagged parameters; larger tables may B+D. Preserve defaults, order, seed, sampling margin; no CIFilter/context in semantic data |
| Style: [LayerEffects](../../Compositor/Document/LayerEffects.swift) | Optional value effects; live style edits mutate document | CGFloat/native rendering helpers in same file | A normalized immutable semantic description; optional B+D for reuse. Preserve enabled flags, fill, contour/blend/size/colors; execution remains backend |
| Pattern/texture: EffectPattern, BevelEffect | Procedural enum and scale/colors/depth/inversion in style | Evaluation arithmetic; current file imports Apple UI/rendering | A descriptor, including noise semantics and origin; generated texture is cache. Current eight patterns are not external image assets |
| Color/profile: [ColorProfile](../../Compositor/Document/ColorProfile.swift) | DocumentColorProfile is document value; WorkingColorSpace is global locked front-tab state | CGColorSpace/NSColor; lock makes access safe but not publication-consistent | A explicit profile identity + immutable ICC bytes when needed (B+D); capture working/source/output distinctions, no worker global lookup |
| Preview/draft: BrushStroke, Filters, text/shape/transform session state | Mutable contexts/tiles/tool state; generated CGImages replaced; revision/request guards | MainActor tool ownership, filter workers, native image objects | Freeze accepted revision into A descriptors + B+D tiles/images; no mutable CGContext/StrokeTexture/CI graph lease |
| Cached intermediate: [EffectsPreviewCache](../../Compositor/Rendering/EffectsPreviewCache.swift), [DownsampleCache](../../Compositor/Rendering/DownsampleCache.swift), GPUCanvas | Cache owns native images/textures and retained sources; cancellation/eviction mutable | MainActor GPU/cache, serial effects worker, locked downsample map | Excluded from domain resource payload; backend retains its own source leases until work completes; provenance mandatory |

Read-only sharing can be safe after freeze; thread safety of each native provider
and release path still needs Mac validation. No blanket Sendable claim is made.

## Image strategy and actual backing behavior

Use immutable shared raster versions, with an owned lease on every referenced
base/tile/provider. A new resource version is created when bytes, dimensions,
format, alpha convention, color interpretation or sparse placement changes.
Unchanged tiles retain their versions. Undo can reuse an old resource version;
publication Generation still increases. IDs are scoped to an open resource epoch,
not layer UUIDs (one layer can own several resources). Never reuse a key/version
for different content. Persistent .comp IDs and format are unaffected.

ImportedImage's comment explicitly allows immutable CGImages to be shared.
BrushRaster.copy allocates/copies a mutable context for editing; Swift struct COW
does **not** make that context immutable. Brush patches use context.makeImage;
RasterSnapshot.replacing shares untouched tiles and crops replacements. Its
makeImage passes a retained self into CGDataProvider callbacks and releases on
releaseInfo. The image therefore retains the sparse source after document close.
`bytes()` serializes one-time materialization with NSLock and keeps its context.
This is concrete existing lifetime support, not proof for every native producer.

Two blockers prevent calling current sparse resources fully frozen:
`fill` is a mutable var (set at construction by replacing), and makeImage plus
later bytes()/BrushRaster.context can consult **different** WorkingColorSpace
values. A front-tab switch between image creation and lazy materialization could
change interpretation. Capture immutable color/fill with resource construction
before integrating; do not solve this by eager full-image copy on every snapshot.

CIImage is a deferred operation graph. GPUCanvas wraps a mutable stroke texture
in CIImage; retaining that CIImage cannot freeze its bytes. Neither belongs in the
shared semantic snapshot. Export consumes ProjectSnapshot and explicitly chooses
manifest profile at its root, may materialize full images and runs full effects;
canvas uses sparse/preview/downsample resources. Audit nested helpers for global
color even when the export root is explicit. Temporary previews get separate
immutable versions, never mutable aliases to ongoing brush buffers.

Existing RasterSnapshotTests check no mouse-up flatten, sharing through undo/redo,
old-image stability after more strokes, display/export equality and save/reopen.
ColorProfileTests cover saved profiles and RGB/CMYK export. These are reusable Mac
tests, not newly executed evidence. Add delayed materialization across tab/profile
switch, native provider lifetime after session destruction and concurrent native
reads before claiming adapter readiness.

## Path, style and adjustment strategies

Path candidate: immutable numeric commands (move, line, quadratic, cubic, close)
with finite coordinates, subpath order, coordinate convention, winding/fill rule,
AA and feather stored separately. Adapter copies/enumerates CGPath once on capture;
share/version the resulting command allocation. CGPath.copy alone is an Apple
adapter fallback, not the portable representation. Validate curve and selection
coverage parity; this experiment does not implement path serialization or geometry
migration. The existing selection API can accept a CGMutablePath through CGPath,
so declared reference type alone does not establish immutability.

Styles carry all enabled semantic records, overall versus fill opacity, local
blend modes, contour and procedural pattern parameters; preserve disabled settings
for history but derive an active render descriptor. LayerStyleRenderer/Metal/CI
objects are execution details. Adjustment descriptors preserve kind, scalar/curve/
gradient parameters, deterministic noise seed and spatial sampling/mapping. No
style GPU implementation is copied. Incoming main's clamped bevel size, smooth
profiles and continuous mask shading require explicit shared semantic/parity
criteria; a descriptor of the old v12 fields alone does not prove execution parity.

## Color ownership

Document owns intended profile. ProjectWorkspace sets global WorkingColorSpace
from the selected tab; GPUCanvas follows it and invalidates native caches;
ImageImporter and BrushRaster helpers also read it. Locking protects a read, not
consistency across an asynchronous job. Snapshot must explicitly identify working
profile, transfer/alpha interpretation and source resource profiles. Profile bytes
or a canonical known-profile identity must resolve without UI state. CMYK document
uses sRGB working pixels and CMYK JPEG output; PNG remains RGB. Output/display
profile, rendering intent and conversion parameters belong to the render/export
request and its cache key. Defaults must match current behavior before adoption.
Unchanged numeric bytes with different profile interpretation are a new resource
version or an explicit different conversion request, never an implicit tab effect.

## Cache provenance and stale rejection

Current GPUCanvas uses object identity + reduction level and retains the source
object, preventing identity reuse while cached. Mutable stroke uploads have a
separate tile identity map. DownsampleCache retains CGImage sources with a locked
map and pixel budget. EffectsPreviewCache matches image/mask identity, geometry,
effects and sideLimit; worker completion checks request UUID. It intentionally
shows previous/seeded results while new results render. None is a general shared
publication token. Incoming main distinguishes quick/refined results and keeps
only full-quality results for undo/redo cache hits.

Future *delivery* must match instance + publication Generation + render-request
identity, and all resource versions, explicit color, geometry/style/adjustment
parameters and requested quality. StateID alone permits ABA errors after undo.
A cache *content key* may omit publication to reuse immutable results across undo,
but acceptance into a current frame must validate current delivery provenance.
Quick results must not overwrite a refined result; track a monotonic quality rank
within a request. Previous-publication fallback can be deliberately displayed only
as labeled approximate content, not accepted as current exact output. Cancellation
is an optimization; provenance check is mandatory even if cancellation loses a race.
No cache rewrite or production hashing scheme is implemented; hashes require
canonical inputs and collision handling before serving as equality evidence.

## Experiment, evidence and readiness

[RenderResources](../../Spikes/RenderResources/README.md) uses synthetic byte
payloads and a retention lease. Validated locally: copy-on-freeze isolation,
unchanged A/B shared storage, version replacement, old snapshot after owner close,
last-lease release, four concurrent immutable readers during serialized replacement,
stale replacement atomic rejection, version overflow and provenance mismatches.
No CGImage, CGPath, real Document, GPU upload or production publisher is exercised.
C++ is only the installed experiment toolchain; this is not a Core language choice.

A future ABI would return an owned opaque snapshot/resource lease, with paired
release and borrowed views valid only while its owner is retained. No raw provider
pointer may outlive that lease; registry destruction must not invalidate it. Product
ABI, release-thread constraints and budget/backpressure remain unimplemented.

Renderer API **discussion** now has a concrete owner and resource-reference
candidate. Production Renderer API + Metal adapter is **not ready** until:

1. Synchronize reviewed main changes (including v13, locks, latest bevel tests)
   in a separate authorized task and confirm f6ce057/new Mac CI status.
2. Define coherent MainActor capture, all draft preparation, cancel/commit and
   save-during-style-preview policy; implement/test publisher separately later.
3. Freeze sparse fill/color and test delayed materialization, native lifetime,
   mutable provider exclusion and cross-thread native access on Mac.
4. Validate neutral path commands and text/font/raster fallback; complete image
   descriptor (stride, pixel format, alpha, coordinates, ICC) and resource budget.
5. Test delivery provenance with quality progression, out-of-order completion,
   undo/reload/close and explicit color across tabs. Decide retained resource limits
   separately from DocumentHistory's approximate image byte accounting.

Do not start a GPU or Renderer API implementation from synthetic lifetime success.
