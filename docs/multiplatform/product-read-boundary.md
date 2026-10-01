# First product read boundary

Types: `97cff89`; adapter/tests: `74d1a49`. No write boundary, renderer API,
serialization, history replacement or Core language decision.

## Gate and scope

Started clean on Compositor-Multiplatform `a5adecf8a25b1989680a8b589333b1f47d3f0f57`,
matching remote. FilterKind, TextAlignment and CoreBoundary commits are present.
Main still points to `0be4fe6`; no new changes or automatic merge. Actions API
returns Forbidden. Mac app build, full CompositorTests, FilterKindTests,
TextAlignmentTests and CI boundary checks are individually **unverified**.
No CI failure was observable; this is not evidence of passing CI.

## Dependency and semantics

`CanvasDocument` (existing Mac owner context) → `CanvasDocument+CoreSnapshot`
→ `Compositor/Core/CoreSnapshot.swift` → Foundation UUID / Swift value types.
Core knows no Mac model, UI, GPU or adapter. Files remain internal to the existing
app module, included by synchronized Xcode folders. No new module or package.
Swift is used to connect the existing Swift model, not selected as the final Core
implementation language.

- Layer IDs remain the original UUID values, without a new alias or generator.
- Instance and State IDs are distinct UUID wrappers with explicitly supplied values.
  An instance is not CanvasDocument.id; reopening needs a different instance token.
  State UUID meaning matches DocumentHistory.revision, but history is not wired in.
- Generation wraps UInt64. `advanced()` produces the next value or nil at exhaustion;
  it never wraps. This value operation is not a mutation command or publisher.
- Snapshot fields are `let`, Sendable and Equatable. Bulk rows preserve existing
  bottom-to-top array order, Unicode names, own isVisible and own opacity.
- Only scalar/value metadata is copied. Swift array/string value semantics isolate
  retained snapshots from source edits. No CGImage, path, layer reference or cache.
- Errors carry IDs, field/operation or expected/actual generation. Recoverable
  domain cases are distinct from fatal invariant classification. Classification
  does not implement fault recovery, logging, ABI codes or validation enforcement.

The adapter requires caller-provided instance/state/generation captured for the
same document state on MainActor. It does not invent tokens per read, manage their
lifetime, validate stale work, check all source invariants or schedule publication.
Only tests call it today. There is no UI adoption or hidden history connection.
Snapshots omit persistent document identity, dimensions and other full-document
fields deliberately: this is a minimal metadata projection, not a complete save,
render or document representation. It must not be used as one.

## Evidence levels

| Level | Evidence |
|---|---|
| Validated in spike | C++ synthetic immutable bulk snapshot, release/lifetime, StateID/Generation restoration distinction, serialized mutation/read and structured errors; existing three groups rerun passed |
| Validated in product read-path | No runtime claim yet. Source inspection confirms one map of actual model rows, unchanged UUID/order/properties and explicit MainActor adapter; local lexical boundary and seven injected forbidden dependencies passed |
| Product tests authored, execution pending | Four CoreSnapshotTests: real blank-layer document projection/order/all properties/source mutation independence; empty collection; state restoration fixture/monotonic advancement/overflow; error payload and fatal/domain distinction |
| Not yet validated | Swift compilation and Mac execution, live publication lifecycle, multi-instance token ownership, actual history transactions, resource lifetime, background host handoff, stale commit enforcement and ABI |

verify.yml now typechecks all Core Swift files independently and retains its full
app build/test commands. Neither a workflow definition nor Sendable annotations
prove those checks passed. Linux has no swiftc/Xcode. Shared C existing pixels test
passed 1/1; no C code changed. Git diff/whitespace and dependency checks passed.

## Next gate

Before any mutation API: obtain Mac build/full tests and these fixture results,
define who owns instance/state/generation across open/close/no-op/undo/preview, then
scope one atomic operation with failure/stale tests and existing behavior parity.
Before renderer API: explicit immutable image/path ownership and release context,
complete hierarchy/effective-property projection and renderer parity fixtures.
This metadata-only surface validates none of those renderer responsibilities.
Rollback removes the new files and guard/workflow additions; no existing runtime
call site or stored data requires conversion. Stop here.

## Subsequent publication/render source audit

[Inventory](render-data-inventory.md) confirms app/test synchronized-group membership
without exclusions and test-only adapter call sites at cd4a58a. Mac build, full
tests, CoreSnapshotTests, FilterKindTests, TextAlignmentTests and CI boundary results
remain unverified (Actions Forbidden); local lexical guard passes. No product
read-path runtime validation is added by this audit.

The snapshot still carries own flags/opacity in stored order. Effective hierarchy,
clipping, masks, full style/fill, preview provenance and render resources require a
separate semantic projection. Lifecycle and render responsibility candidates are
now documented, not implemented. Existing product files remain unchanged.
