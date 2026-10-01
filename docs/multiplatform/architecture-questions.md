# Unresolved architecture questions and decision evidence

Status: refreshed after main-sync merge `db268a2b` (main `ccf062ed`) on 2026-09-30.
The semantic rules in [core-api.md](../core-api.md) are the current contract;
implementation choices formerly marked final in `841d09c` are superseded.
No language, GPU API, UI product architecture, synchronization primitive or product
ABI is chosen here. [Repository evidence](repository-evidence.md) distinguishes
observed implementation, archived test claims and pending verification.

## Questions to resolve before the corresponding migration

Stable Q numbers are kept so old references remain traceable. A semantic constraint
can be settled while its implementation remains open.

| ID | Open question / alternatives | Constraint already settled | Evidence needed; gate |
|---|---|---|---|
| Q1 | UUID representation/generator and session handle validation | Preserve file UUIDs; fresh copied IDs; no intentional deleted-ID reuse; qualify by open instance | Load/duplicate/undo/paste fixtures, stale handle tests; before identity adapter |
| Q2 | Swift stdlib vs FoundationEssentials vs platform JSON support; C++ dependencies if selected | Shared types contain no Apple/Windows UI, graphics or GPU objects | Build actual extracted values in both environments, measure runtime/dependency closure; before language choice |
| Q3 | JSON encoding in shared Formats or host adapters; codec/library | One validation/default policy; current reader 1–12, save11/12 based on stored v12 field presence; atomic package I/O outside Core | Cross-reader v1–12 fixtures including disabled styles/explicit defaults, version rejection and removal back to11; before format adapter |
| Q4 | Image formats, conversion guarantees and extension policy | Premultiplied RGBA and Gray8 cover current kernel/mask boundary; reject unsupported formats | Inspect import/export precision and profiles, test gray/uniform masks and stride; before image boundary |
| Q5 | Image storage owner, external buffer wrapping, tiles/patches, release context and accounting | Immutable shared resources; GPU memory is not model state; snapshots retain data | CGImage/RasterSnapshot adapter prototype, retained bytes/peak memory after brush/undo/close; before image migration |
| Q6 | Copy-on-write vs persistent/shared snapshots, lazy projections and delta retention | Bulk traversal cannot rebuild all rows per item; full-snapshot fallback for stale delta base | Comparable 500/2,000/10,000-layer bulk workloads, allocations and retained versions on named machines; before snapshot implementation |
| Q7 | Pull generation vs notification/callback transport | Notifications convey change, not mutable pointers; owner-context semantics; no reentrant mutation | UI/renderer/save handoff design and lifetime tests; before host binding |
| Q8 | CorePath representation, fill rules and optional future raster selection | Preserve absent vs empty, nonzero selection coverage, feather behavior | Selection/feather/holes/path conversion fixtures; before selection adapter |
| Q9 | Windows text engine and missing-font/fallback policy | Text data and UTF-16 spans in Core; saved pixels preserve appearance until edit | Korean/Latin/bidi/missing-font layout and re-edit tests; before Windows text work |
| Q10 | Color engine, profile distribution/licensing and comparison tolerance | Preserve six format IDs, CMYK's RGB working interpretation and profile metadata | Embedded-profile/ColorSync reference images and export tests; before color adapter |
| Q11 | Swift or C++ implementation language | Both spikes work; no winner from row-by-row performance | Decision factors and missing evidence below; no decision in this task |
| Q12 | C ABI or another host binding, opaque token layout, string/error lengths, generation/version fields, code generation tool | Explicit ownership, bulk results, checked domain input, no escaping language exceptions | Round-trip hosts, long Korean/embedded-NUL handling, invalid/duplicate inputs, failure atomicity, exception/OOM audit; before ABI publication |
| Q13 | In-process vs process isolation and fatal fault handling | C# catch cannot recover memory corruption/traps inside native Core | Failure injection, recovery requirements and IPC cost if considered; before production integration |
| Q14 | Autosave/recovery scheduling, retention and restore UX | Platform service consumes immutable state; failed save cannot replace good files | Existing external-edit and save race behavior, interrupted-write/recovery tests; separate behavior proposal |
| Q15 | Owner-context/thread-affinity enforcement and resource destruction | Mutations including undo/redo are serialized; background readers use retained snapshots | Same-instance concurrency and wrong-owner tests, release on background threads; spike did not test these |
| Q16 | Transaction previews/cancel/save and history accounting | Keep nested begin/end, no-op redo, restored StateID; separate Generation; Layer Style OK one entry, Cancel restore | Preview→save→Cancel/OK traces: current file gate does not exclude layerStyle; no guaranteed committed-only save today. Retained resource measurements; before S6 |
| Q17 | Windows product UI technology | WinUI 3 is a working experiment with both Cores, not a language discriminator | Accessibility/input/tablet/IME/high-DPI and real canvas integration evidence; outside this task |
| Q18 | Windows App SDK component packages vs metapackage, deployment mode | Spike packages and measured size are evidence only | Clean-machine dependency validation and measured trimmed payload; not yet demonstrated by spike |
| Q19 | .NET runtime mode and native CRT deployment | No allocator-owned object crosses an incompatible allocator boundary | Clean machine/runtime/update tests and AOT/R2R measurements if considered; outside Core contract |
| Q20 | Windows GPU API and renderer implementation | Core emits backend-independent data; current Metal/Core Image stays | Image parity, resource/latency/driver measurements after renderer boundary; no API selected |
| Q21 | Platform equivalents for Vision features | Services return semantic selection/content results | Product scope, model licensing, quality/performance evidence; no hidden feature removal |
| Q22 | Next main synchronization scope and cadence | This sync imports ccf062ed via db268a2b; frequent reviewed syncs preserve both platforms; no reset/rewrite | Before each migration, fetch refs/classify incoming A–F changes, review relevant semantics and record Mac/shared CI for resulting SHA |
| Q23 | Long-term spike archival/tag policy | Preserve branch and results; no product merge or freeze/tag action implied | Future experiment needs and reproducibility policy; no spike edits now |
| Q24 | Windows `.comp` folder UX and shell integration | Existing directory package format stays unchanged | Folder open/save/watch and safe-path tests; packaging design later |
| Q25 | Migration from global WorkingColorSpace | New shared operations receive document-specific color inputs | Two differently profiled documents editing/exporting concurrently; incremental Mac adapter plan |
| Q26 | Renderer capability/parity and PSD interchange of full Layer Style | Core retains nine effect records, Fill Opacity and pattern origin; legacy Metal/new CPU dispatch stays renderer; PSD fallback reports losses | All contour/pattern/technique outputs, disabled/default fields, mask/fill/order and tiled preview/export parity; supported vs unsupported PSD descriptors; before S3/S7/S8 |

## Additional gaps found in this audit

- **State vs publication:** current history restores revisions. A single monotonic
  revision cannot also represent returning to a saved state. Specify StateID and
  Generation separately; transaction previews/active context need explicit rules.
- **Current helpers vs product atomicity:** `duplicateLayers` may skip missing or
  limit-exceeding copies, while imports intentionally report partial success. A
  strict atomic Core batch must not accidentally erase these UI semantics; the
  application orchestrator selects atomic batches and reports individual failures.
- **Validation asymmetry:** `ProjectStore` does not validate every style equally.
  New stricter validators must not reject previously accepted documents without an
  explicit compatibility decision. Boundary safety and legacy decoding are distinct.
- **Color wording:** some adjustment code calls its colors sRGB while working-space
  APIs use document profiles. Preserve measured current output; do not assert that
  relabeling every scalar as document-space is a proven equivalent conversion.
- **Inventory closure:** the old 47-type list omits Levels/Curves children and
  hierarchy helpers. Seven v12 data declarations are now inventoried explicitly,
  with UI/renderer/format helpers separate; 47 is not the present full model count.
- **Style preview/save:** the imported LayerStyleEdit restores originals on Cancel
  and records one entry on OK, but preview mutates live state with the old history
  revision. File operation gating does not include the style editor. Preserve main
  in this sync; characterize save/Cancel/OK before selecting a transaction envelope.
- **Format gate vs render dispatch:** usesLayerStyle checks stored presence;
  needsStyleRenderer checks active rendering. Explicit default values/disabled
  effects can require v12 without requiring the new renderer. These predicates
  cannot be merged or inferred from one another.
- **Coverage:** imported LayerStyleTests exercises JSON/defaults, save11/12,
  rendering and dialog undo/redo; dedicated nested-style duplication, clipboard,
  grouping and malformed-v12 matrix tests are still missing evidence.
- **Error containment:** C++ spike entry points do not uniformly catch allocations
  and queries; Swift unsafe handles are retained object pointers, not validated
  generation handles. No claim of fuzzed production safety follows from happy-path CI.

## Core language decision criteria — no scoring or recommendation

| Factor | Swift evidence and cost to assess | C++ evidence and cost to assess | Missing comparable evidence |
|---|---|---|---|
| Existing model reuse | Existing value types, tests and Mac callers can potentially be retained after adapter work | Counterparts and Mac bindings need implementation; roughly 11,000 historical model/format lines are an estimate, not an approved rewrite | A small real extracted type and its callers, not the toy model |
| Value/history semantics | Array COW and immutable images already used; mutation can still copy metadata | Spike copies its tree; production sharing would need explicit design | Retained bytes and latency for nested groups, large pixel histories, undo/redo/no-ops |
| Windows tooling | Spike Swift 6.4 works; action version spelling, symlink/Developer Mode and WinSDK rough edges are recorded | MSVC toolchain and Windows debuggers are established; headers/interop still need discipline | Reproducible pinned setup, debugging and sanitizer coverage on clean hosts |
| Runtime/deployment | Measured swiftCore 5.8 MB; FoundationEssentials ~13.5 MB, full Foundation ~63 MB configurations in the report | Smaller experimental Core DLL; actual spike still ships VC++ runtime DLLs | Same optimized feature set and self-contained host, cold start and deployment inventory |
| Host boundary | C# calls C ABI; `_cdecl` export/tooling compatibility must be maintained | C# also needs C ABI; direct Swift interop hit exceptions, references, defaults and templates | Generated binding maintenance, ownership and versioning tests for the same bulk contract |
| Safety/faults | Bounds traps stop process; unsafe ABI pointers remain dangerous | Duplicate IDs previously caused heap corruption; catch does not catch UB | Domain error/fault-injection/fuzz corpus, no partial mutation, release-mode invariants |
| Performance | Bad O(n²) outline pattern measured hundreds of ms | Same bad pattern measured tens of ms | Same O(n) bulk workload and pixel ownership, including allocations and warm/cold runs |
| Format fidelity | Codable reuse possible with platform separation | JSON/default/number/UTF-16 span behavior must be reproduced | Bidirectional v1–12 fixtures and corrupt-input handling, without format change |
| Mac maintenance | Existing tests/tooling largely reusable; isolation work still substantial | Mac call sites need safe bindings while Swift UI/renderer continue shipping | Full Mac suite and feature-specific output parity after one reversible adapter |
| Platform services | CoreGraphics remains unavailable on Windows regardless of language | Same geometry/image/path/text/color boundaries still required | Image/path adapters, profile/text evidence; language does not supply these semantics |

Any later decision must cite these measurements and preservation costs, without
using the existing row-loop benchmark as a bulk-performance result. This task ends
with the contract and questions; it does not commission the measurements or select
a winner.

## CoreBoundary follow-up: partial evidence, not closed questions

The isolated [experiment](../../Spikes/CoreBoundary/README.md) partially validates
Q6 (bulk metadata copy/scaling), Q12 (owned domain errors), Q15 (serialized mutation,
concurrent readers, last snapshot release on a background thread), and Q16
(StateID restore with a new Generation). These synthetic checks do not close them.
Real resource lifetime/affinity, allocation instrumentation, host handles/ABI,
wrong-owner enforcement, full undo/redo and preview/save/Cancel remain unvalidated.
Q1 uses fixture integers only; Q5 image ownership and Q13 fatal fault handling are
unvalidated. Mac CI is still inaccessible. No language recommendation follows.

## Product metadata read surface follow-up

See [read-boundary evidence](product-read-boundary.md). Q1 reuses UUID layer values
and wraps instance/state UUIDs, but session allocation/close/reopen ownership remains
open. Q6 has a minimal bulk value shape and actual-model adapter, with Mac fixture
execution pending. Q12 has semantic error values only, no ABI or stable numeric codes.
Q15 confines model capture to MainActor; it does not implement a background owner
or prove host handoff. Q16 is still open: no DocumentHistory/publication manager
connection, previews, no-op publication policy or generation exhaustion recovery.

Synthetic spike validation must not be relabeled as product read-path runtime
validation. Foundation UUID is the only framework dependency in the new Core file;
future module/toolchain portability needs compilation evidence. Parent visibility,
clipping and effective opacity are deliberately absent from the minimal rows, so
this snapshot must not become a renderer contract by accident.

## Publication and renderer inventory follow-up

See [audit](render-data-inventory.md) for source-backed lifecycle, field matrix and
parity checklist. Q1/Q15 need an open-session epoch distinct from tab/persistent
document UUID: undoable canvas replacement differs from project replacement.
Q16 includes opacity gestures, Layer Style live previews, cancellation and
preview-save/reload gating; history alone cannot own visible Generation.
Q5/Q6 need immutable content plus hidden-source dependency closure, not just visible
metadata rows. Q25 remains blocked by front-tab WorkingColorSpace state.
Q26 needs full semantic style order/fill/pattern origin plus actual backend evidence.

Additional open distinctions: document publication vs viewport render request;
exact new-generation output vs seeded/previous cache presentation; accepted frozen
draft output vs render-time mutable preparation (gradient/pixel move). GPU tests
can return early without a device and mostly compare opaque RGB canvas output, so
suite success alone is not transparent-alpha or complete backend execution proof.
No questions are closed by unexecuted Mac tests or by this source analysis.
