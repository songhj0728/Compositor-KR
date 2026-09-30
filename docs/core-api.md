# Core API contract

**Status: design, not implemented.** This defines the boundary between the document Core that macOS and Windows would
share and everything platform-specific around it. It deliberately does not choose the Core's language (Swift or C++;
see [windows-decisions.md](multiplatform/windows-decisions.md)) and changes nothing in the app today. Where it
describes behavior, that behavior is the macOS app's current behavior, which remains the reference.

Rules of this document:
- **Language-neutral.** Types are described by meaning, not by Swift or C++ declarations. The C ABI (§12) is the one
  concrete binding, because every UI language can call it.
- **The `.comp` format does not change.** Everything the Core stores maps onto
  [project-format.md](project-format.md) version 11 as it is.
- "Today" marks the current macOS implementation; "Contract" marks what the shared Core guarantees.

Evidence behind several rules: [spike-findings.md](multiplatform/spike-findings.md).

---

## 1. Parts and responsibilities

| Part | Owns | Must not |
|---|---|---|
| **Core** | Document state, IDs, validation of every change, history (undo/redo), document semantics (hierarchy, visibility, clipping, masks as data), `.comp` manifest meaning | Touch files, pixels' encodings, GPUs, windows, fonts, OS services |
| **Platform layer** (macOS / Windows) | File I/O, package layout, PNG/JPEG/PSD codecs, clipboard, fonts and text layout, color management, pixel buffers' memory | Change document state except through Core operations |
| **Renderer** | Turning a document snapshot into pixels (canvas, thumbnails, export) | Mutate the document |
| **UI** | Showing snapshots, turning user actions into Core operations, dialogs | Keep document state of its own that disagrees with the Core |

---

## 2. Core data types

The Core uses none of `CGFloat`, `CGPoint`, `CGSize`, `CGRect`, `CGAffineTransform`, `CGPath`, `CGImage`,
`CGColorSpace` (or any AppKit, SwiftUI, Metal, Core Image, WinUI, WinRT or Direct3D type). On Windows the first four
exist only with full Foundation and the rest not at all (spike finding 7). It uses these instead:

| Type | Meaning | Notes |
|---|---|---|
| `Scalar` | 64-bit IEEE float | Everything `CGFloat` is today. `.comp` writes both as JSON numbers, so the format doesn't change. Must be finite where stored. |
| `CorePoint` | `x`, `y` Scalars | Document pixels, origin top-left, y down. |
| `CoreSize` | `width`, `height` Scalars | |
| `CoreRect` | `origin: CorePoint`, `size: CoreSize` | Unrotated. |
| `CoreTransform` | Affine 2×3: `a b c d tx ty`, maps (x, y) → (a·x + c·y + tx, b·x + d·y + ty) | For renderers and hit-testing. Not what layers store. |
| `LayerPlacement` | `origin`, `size`, `rotation` (degrees, clockwise about the center), `flipX`, `flipY`, `sampling` (`Nearest` / `Smooth` / `High quality`) | What a layer stores today (`LayerTransform`) and what `.comp` writes. The Core derives its `CoreTransform`. |
| `CoreColor` | `red`, `green`, `blue`, `alpha` Scalars, 0–1, in the **document's color space** | Today colors are three `CGFloat`s plus an opacity. The Core never converts between color spaces; the platform does. |
| `ColorSpaceID` | One of `sRGB`, `Display P3`, `Adobe RGB (1998)`, `Rec. 709`, `Rec. 2020`, `CMYK` | A name only; profiles live in the platform layer. |
| `CorePath` | Elements `moveTo`, `lineTo`, `quadTo`, `cubicTo`, `close`, plus a fill rule (`nonZero` / `evenOdd`) | Replaces `CGPath` for selections and shapes. |
| `ImageRef` | An opaque, immutable reference to pixels: width, height, pixel format (`RGBA8 premultiplied` or `Gray8`), byte count, and an identity | The Core stores and compares these; it never reads their pixels except through the shared C pixel code. See §7.4. |
| `Text` | Unicode string | UTF-8 across the C ABI. **Text-run offsets are UTF-16 code units** (`location`, `length`), because `.comp` stores them that way. |
| `LayerID`, `DocumentID` | 128-bit identifiers | §6. Canonical text form: uppercase UUID string, as `.comp` writes. |
| `Revision` | Opaque token that changes on every committed change | For "has this changed?", saves and caches. §5.4. |

Limits come from the format and `DocumentLimits` and are part of the contract: 30,000 px per side, 10,000 layers,
group nesting ≤ 64, clipping chains ≤ 256, 1,000 guides, placement size 1–300,000 and origin within ±1,000,000.

---

## 3. Document

| Field | Contract | Today | Saved in `.comp` |
|---|---|---|---|
| `id: DocumentID` | Fixed for the document's life, including canvas resize, image resize, crop and merge | `CanvasDocument.id` | `documentID` |
| `width`, `height` | Whole pixels, 1–30,000; change only through canvas/image size operations | `let` fields, new value on resize | yes |
| `resolution` | Pixels per inch, 1–9,600, default 72 | yes | `resolution` (optional) |
| `colorSpace: ColorSpaceID` | The space all pixel values and `CoreColor`s are in | `DocumentColorProfile` | `colorSpace` |
| `layers` | Ordered collection, §4 and §8 | flat array, bottom to top, `parentID` links | `layers` |
| `activeLayerID` | The layer operations target by default; may be absent | kept in history snapshots | `activeLayerID` |
| `selection` | Optional: a `CorePath` + antialiased flag + feather (document px). Absent = no selection; an **empty** path = "select nothing", never "everything" | `DocumentSelection` (`CGPath`) | **no** — session only, but covered by undo |
| `guides` | List of `{id, axis: horizontal/vertical, position}` | `CanvasGuide` | `guides` (v8+) |
| metadata | Format version and identifier are the `.comp` layer's business; the Core exposes nothing else yet | — | `format`, `version` |
| `history` | §5 | `DocumentHistory` | **no** — session only |

Not part of the document (session / UI state): zoom and scroll, collapsed folders, which layers are selected in the
panel, the image-versus-mask editing target, tool settings, the editor's foreground/background colors.

---

## 4. Layer

Every layer has:

| Field | Contract |
|---|---|
| `id: LayerID` | §6 |
| `name: Text` | Any string. |
| `visible` | Own flag. Effective visibility also requires every ancestor folder visible; hiding a folder never rewrites children's flags. |
| `opacity` | 0–1. A folder's opacity multiplies into its descendants. |
| `blendMode` | One of the 24 names `.comp` uses (`Normal` … `Luminosity`). Folders are pass-through and stay `Normal`. |
| `placement: LayerPlacement` | Where the content sits in the document. |
| `parent: LayerID?` | Absent at the top level; otherwise an existing **folder**. Sibling order is bottom to top. |
| `kind` | Exactly one of: **pixel** (has `content`), **folder** (has children, no content), **adjustment** (has `adjustment`, no content). |
| `content: ImageRef?` | Pixel layers only; absent = blank layer (no pixels allocated yet). |
| `mask` | Optional raster mask: `ImageRef` (Gray8, white reveals), `enabled`, `linked`, and `placement` when unlinked. Allowed on pixel, adjustment and folder layers. |
| `clipTo: LayerID?` | Clipping mask (`maskSourceID`): a non-folder layer whose coverage limits this one. No self-links, no cycles, chain ≤ 256. |
| `adjustment` | Adjustment layers: `kind` (12 kinds) and that kind's settings, ranges as in `LayerAdjustment`. |
| `effects` | Optional: stroke, drop shadow, color overlay, inner shadow, outer glow, inner glow — each with its parameters and `enabled`. |
| `text` | Optional editable text style on a pixel layer (content, font name, size, `CoreColor`, alignment, tracking, leading, box size, color runs, font runs). |
| `shape` | Optional shape style on a pixel layer (kind, `CoreColor`, corner radius, line width, start/end). |

Invariants the Core enforces on every change (today spread over `LayerGroups`, `LiveLayerMask`, `ProjectStore`
validation): unique IDs; parents exist and are folders; no cycles; nesting ≤ 64; folders have no content and no
`text`/`shape`/`adjustment`; adjustment layers have no content and are not folders; clip targets valid; limits in §2.

**`text` and `shape` are styles, not pixels.** Today `LayerText`/`LayerShape` also carry the rendered image. In the
Core the pixel layer's `content` holds the pixels, the style is data, and re-rendering from the style is the
platform's job (fonts differ by OS — see architecture-questions.md).

---

## 5. Operations

### 5.1 General rules

- Every mutation is an **operation**: validated completely before anything changes, then applied atomically. A
  failed operation leaves the document and history exactly as they were and returns an error (§10).
- Every operation that changes the document is **one undo step** with a name ("Add Layer", "Duplicate Layers" …),
  unless it runs inside a transaction (§5.3).
- An operation that changes nothing records nothing and keeps redo (today's `DocumentHistory` rule).
- Operations take IDs, never positions in a list that may have changed.
- Operations over several layers take a **set of IDs** and are one step; duplicates in the set are an error, never
  ignored and never undefined (spike finding 3).

### 5.2 The operations

| Operation | Input | Result / rules |
|---|---|---|
| **Create document** | size, resolution, color space, optional background `CoreColor` | New `DocumentID`, empty history. |
| **Create layer** | kind (blank pixel / pixel from `ImageRef` / folder / adjustment / text / shape), name, parent, position among siblings, placement | New `LayerID` generated by the Core; becomes active. |
| **Duplicate** | set of layer IDs | Each duplicated layer and all its descendants get **new** IDs; `parent` and `clipTo` links *inside* the copied set are remapped to the copies, links *outside* it keep pointing at the originals. Pixels are shared, not copied (`ImageRef` is immutable). Layers inside a folder that is itself being duplicated aren't copied twice. One copy goes just above its original; several stack together, in their order, above the topmost original in its parent (today's `duplicateLayers`). Each copied root is named "<name> copy". Returns original → copy ID map. |
| **Delete** | set of IDs, **clip policy**: `bake` or `unlink` | Folders delete their descendants. If remaining layers clip to a deleted one, the caller must pass the policy; the Core never asks (today an `NSAlert` asks from inside the model — the UI asks, then calls). |
| **Move** | set of IDs, new parent, position | Rejects moving a folder into itself or its descendants, depth over 64, a non-folder parent. Clipping links that stop being contiguous are released, as today. |
| **Group / ungroup** | set of IDs / a folder ID | Group (today's `groupSelectedLayers`): members need not be siblings; a selected folder brings its whole subtree and its selected descendants aren't pulled out of it; the new folder goes into the members' deepest common parent, at the place of the topmost member's branch, named "Folder *n*" (first unused *n*). Ungroup puts the children in the folder's place. |
| **Rename** | ID, `Text` | |
| **Set visibility** | set of IDs, flag | |
| **Set opacity / blend mode** | set of IDs, value | Folders' blend mode stays `Normal`. |
| **Set placement** | ID → `LayerPlacement` (or a set with a `CoreTransform` applied to each) | Validated against §2 limits. Linked masks follow. |
| **Replace content** | ID, new `ImageRef`, optional new placement | How painting, filters and resampling commit their results (the pixel work happens outside the Core). Drops `text`/`shape` style if the pixels no longer come from it, as today. |
| **Mask** | add (solid reveal/hide or `ImageRef`), remove, enable/disable, link/unlink, set placement, replace pixels, apply | |
| **Clip** | set / release `clipTo` | |
| **Adjustment / effects / text / shape style** | ID, new settings | Validated against the ranges in the format document. |
| **Guides** | add, move, remove, clear | |
| **Selection** | set (`CorePath` + options), clear, invert, … | Undoable, not saved. The operations that turn pixels into paths (magic wand, color range, object selection) stay outside the Core and hand it a `CorePath`. |
| **Canvas / image size, crop** | new geometry and per-layer results | Keep the `DocumentID` and layer IDs. |
| **Undo / redo** | — | §5.4. |

### 5.3 Transactions

`begin(name)` … `end()` groups operations into one undo step, nested begins counting as one — today's
`DocumentHistory.begin/end` depth counter. Uses: a drag (many placement changes, one step), "duplicate then move".
While a transaction is open, undo/redo are unavailable. A transaction that ends with no net change records nothing.
An operation that fails inside a transaction fails alone; the caller decides whether to cancel the whole transaction
(`cancel()` restores the state at `begin`).

### 5.4 History

- Session-only; opening a document starts a clean history (as today and as `.comp` says).
- Undo/redo restore the **whole document state** of that step, including selection and `activeLayerID`.
- Limits: 100 steps and a 256 MiB budget of pixels retained only by history; the oldest steps drop first (today's
  values; the platform may tune them).
- `Revision` changes with every committed step and on undo/redo; `isModified` compares the current revision with the
  one last saved, so undoing back to the saved state is "unmodified" (today's behavior).
- Undo/redo names are for menus; the Core supplies them in English, the UI localizes.

---

## 6. IDs

| Question | Answer |
|---|---|
| Who creates IDs? | **The Core**, for every layer, guide and document it creates. The platform supplies IDs only when loading a `.comp` (they come from the file) or when a caller must match an external record — and then the Core validates them. |
| Unique within a document? | **Yes**, across all layers (and separately across guides). An operation that would duplicate one fails. |
| Does a duplicated layer get a new ID? | **Yes**, every copied layer and descendant (§5.2 Duplicate). |
| Kept across undo/redo? | **Yes.** Undo restores the previous state with the same IDs; redo brings back the same IDs it undid. An ID is never reused for a different layer within a session, even after its layer is deleted. |
| Kept across saving and loading? | **Yes.** `.comp` stores them (`id`, `documentID`, `<id>.png`), and a load uses them as they are. |
| Same ID in different documents? | **Allowed** in principle (IDs are only guaranteed unique within a document), and it happens when the same file is opened twice. Anything that moves layers between documents (paste, drag between tabs) **must remap** them to new IDs, as today, and must bake or drop `clipTo` links whose source didn't come along. |
| Representation | 128 bits. Generated as random UUIDs (version 4) for compatibility with existing files; compared as bytes; written as uppercase UUID strings. Whether the Core's implementation uses a platform UUID type or its own is an implementation choice (architecture-questions.md). |

---

## 7. Ownership and lifetime

### 7.1 Document
The Core owns each open document. Callers hold a **document handle** they got from `create`/`open` and give back
with `close`; after `close` the handle is invalid and any use is an error, not a crash (handles are checked, e.g. an
index plus generation counter, never raw pointers into Core memory).

### 7.2 Layers
Layers are owned by their document. **Callers never hold a pointer to a layer**; they hold its `LayerID` and read
its state from a snapshot. A `LayerID` can outlive its layer; using it then returns "no such layer".

### 7.3 Strings
- Into the Core: the caller's buffer, **borrowed for the duration of the call**, UTF-8. The Core copies what it keeps.
- Out of the Core: inside a snapshot (§8), owned by the snapshot and valid until the snapshot is released. No API
  returns a string the caller must free individually, and none writes into caller buffers row by row.

### 7.4 Images (`ImageRef`)
- Pixels are immutable once wrapped. The platform creates an `ImageRef` from a buffer it owns, with a release
  callback; the Core reference-counts it and calls the release when the last document, snapshot or history step
  lets go.
- The same `ImageRef` may be shared by many layers, snapshots and history steps (duplicates, undo) — this is what keeps
  undo memory small today (`CGImage` sharing), and the contract keeps it.
- Renderers may key caches on an `ImageRef`'s identity; identity never changes while it lives.
- Editing pixels means making a new `ImageRef` and committing it (§5.2 Replace content).

### 7.5 Snapshots
- A snapshot is an **immutable** view of a document at one `Revision` (§8). Taking one is cheap (no pixel copies,
  structural sharing where the implementation allows).
- The caller owns it until it calls `release`; it stays valid and unchanged however the document changes meanwhile.
- Everything reachable from a snapshot (rows, strings, `ImageRef`s) is **borrowed from the snapshot** and valid until
  the snapshot is released. To keep an `ImageRef` longer, the caller retains it explicitly.

### 7.6 Borrowed vs owned — summary

| Thing | Owner | Caller may keep it after… |
|---|---|---|
| Document handle | Core | until `close` |
| Snapshot | caller | until `release` |
| Row / string / array inside a snapshot | the snapshot | the snapshot's release — no longer |
| `ImageRef` from a snapshot | the snapshot | release, unless the caller retains it |
| Input strings and arrays | caller | Core copies during the call; never keeps the caller's pointer |
| Error message | Core (thread-local, last error) | the next Core call on that thread |

UI code may hold: document handles, snapshots, `LayerID`s, retained `ImageRef`s. It may **not** hold anything else
from inside the Core.

---

## 8. Reading the document: bulk first

**Prohibited as product API:** anything that makes the caller ask item by item while the Core rebuilds a collection
per call — `GetLayer(0)`, `GetLayer(1)`, … In the spike this made a 2,000-layer list cost up to ~490 ms instead of
microseconds (spike finding 2).

### 8.1 Document snapshot
`snapshot(document) → Snapshot` returns, in one call:
- the document fields (§3), the `Revision`, undo/redo availability and names;
- the **layer table**: one row per layer, in document (bottom-to-top) order, each row carrying every field of §4 by
  value (IDs, flags, numbers, `Text`, `ImageRef`s, the kind-specific records), plus derived values the UI and renderer
  all need and shouldn't each recompute: `depth`, `effectiveVisible`, `effectiveOpacity`, index of the parent row,
  first-child / next-sibling row indices;
- the guides and the selection.

Access to rows is by index into the table, **O(1) per row**; building the snapshot is **O(number of layers)** at most,
and may reuse unchanged rows from the previous snapshot.

### 8.2 Narrower bulk queries
For callers that don't need everything, each still returning a whole result in one call:
- `layerIDs(order: document | panel)` — IDs only; `panel` is top-first with folders before their contents.
- `layers(ids)` — rows for a set of IDs.
- `changes(since: Revision) → {added, removed, changed IDs, documentFieldsChanged}` — so a UI can update only what
  changed. If the Core can't answer for a revision that old, it says "everything".

### 8.3 Across the C ABI
A snapshot crosses as a handle plus accessors that read fields of row *i* from arrays laid out once when the snapshot
was built (or as one packed buffer). Reading row *i* never recomputes the table.

### 8.4 Performance targets (to verify when implemented)
10,000 layers (the format's limit): snapshot in < 5 ms, `changes(since:)` for a single-layer edit in < 0.1 ms, on the
spike's test machine. Adding a layer (one undo step) in < 50 µs with 2,000 layers present.

---

## 9. Threading

| Rule | Contract |
|---|---|
| Mutations | **One thread per document at a time** — the document's *owner thread*, by default the UI thread. The Core may check this and fail the call (never corrupt) if violated. |
| Undo/redo | Mutations; same thread. |
| Reading on the owner thread | Always allowed: snapshot or narrow queries. |
| Reading on other threads | **Only through snapshots.** Take a snapshot on the owner thread, hand it to any thread; snapshots are immutable and safe to read from several threads at once. |
| Reads during a mutation | Snapshots taken before the mutation stay valid and unchanged. There is no "live" reading of a document from another thread. |
| Renderer | Renders from a snapshot (its own thread, GPU queues, background exports). It never waits on the Core and the Core never waits on it; a newer snapshot simply replaces the old one. |
| Long operations (filters, liquify, resampling, baking, object selection) | Run off the owner thread **on a snapshot**, producing new `ImageRef`s or `CorePath`s; commit on the owner thread with an operation. If the document changed meanwhile, the commit validates against the current state (e.g. layer still exists) and fails cleanly otherwise. This is how the macOS app works today (`Task.detached` on value snapshots, applied on the main actor). |
| Several documents | Independent; each can have its own owner thread. |

When a snapshot is needed: whenever data leaves the owner thread, whenever something must stay consistent while the
document keeps changing (a save, an export, a render), and for every read across the C ABI.

---

## 10. Errors and failure

- Every operation returns a status: `ok` or an error code (`noSuchLayer`, `notAFolder`,
  `wouldContainItself`, `duplicateID`, `emptySelection`, `outOfRange`, `limitExceeded`, `invalidState`,
  `wrongThread`, `invalidHandle`, `outOfMemory`), with a message for logs.
- **Nothing propagates across the boundary**: no exceptions, no Swift errors, no traps for bad input. Every input is
  validated before use (spike finding 3). Bad input is an error code, always.
- A broken *internal* invariant (a Core bug) stops the process at once rather than continuing with corrupt data. Swift
  does this by default; a C++ Core must be built and written to do the same (assertions kept in release builds).
- Because a Core fault ends the app, the platform must keep crash recovery: autosave or journaling of open documents.
- The C ABI is fuzz-tested (random operation sequences, including invalid IDs and duplicates) on both platforms before
  any UI depends on it.

---

## 11. Boundaries with the rest of the app

| Boundary | Core does | Other side does |
|---|---|---|
| **`.comp` files** | Converts between documents and **manifest records** (every field of `project-format.md`), including version gating, range and reference validation, defaults for older versions, and the `<id>.png` / `<id>.mask.png` naming | Reads and writes the package: folders, atomic replace, PNG decode/encode with the embedded color profile, QuickLook preview, file watching for external edits, the 512 MiB / 4 MiB file limits |
| **Renderer** | Provides snapshots with everything compositing needs (order, effective visibility/opacity, blend, placement → `CoreTransform`, masks, clipping, adjustments, effects) | Compositing, GPU resources, previews, caching by `ImageRef` identity + `Revision`, text and shape rasterization |
| **UI** | Snapshots, `changes(since:)`, operations, undo names | Layout, input, localization, dialogs (e.g. asks *bake or unlink*, then calls Delete with the answer) |
| **Clipboard, import, export** | Accepts new layers from records + `ImageRef`s (remapping IDs, §6); provides snapshots to export | Pasteboard / Windows clipboard formats, image and PSD decoding/encoding, drag and drop, flattening for export |

The Core never calls into the platform, renderer or UI except to release `ImageRef`s through the callback they gave.

---

## 12. The C ABI shape (illustrative)

The concrete binding every UI language can call. **Illustrative only** — names and exact signatures get fixed when a
Core is implemented. It follows §7–§10: handles, borrowed inputs, snapshot-owned outputs, status codes.

```c
typedef struct cc_document  cc_document;   // checked handle
typedef struct cc_snapshot  cc_snapshot;   // immutable, caller-owned
typedef struct cc_image     cc_image;      // ImageRef, ref-counted
typedef struct { uint8_t bytes[16]; } cc_id;
typedef int32_t cc_status;                  // 0 = ok, else an error code

cc_status cc_document_create(const cc_document_desc *desc, cc_document **out);
void      cc_document_close(cc_document *doc);

cc_status cc_layers_duplicate(cc_document *doc, const cc_id *ids, size_t count, cc_id *out_copies);
cc_status cc_layers_delete(cc_document *doc, const cc_id *ids, size_t count, cc_clip_policy policy);
cc_status cc_begin(cc_document *doc, const char *name_utf8);
cc_status cc_end(cc_document *doc);
cc_status cc_undo(cc_document *doc);

cc_status cc_snapshot_take(cc_document *doc, cc_snapshot **out);
size_t    cc_snapshot_layer_count(const cc_snapshot *s);
const cc_layer_row *cc_snapshot_layers(const cc_snapshot *s);   // array of count rows, valid until release
void      cc_snapshot_release(cc_snapshot *s);

cc_status cc_image_wrap(const cc_image_desc *pixels, void (*release)(void *), void *context, cc_image **out);
void      cc_image_retain(cc_image *image);
void      cc_image_release(cc_image *image);

const char *cc_last_error_message(void);    // thread-local, valid until the next call
```

## 13. Versioning of this contract

Additive changes (new operations, new optional row fields) keep existing callers working. Anything else is a new
major version. The Core reports its contract version, and hosts check it at startup.
