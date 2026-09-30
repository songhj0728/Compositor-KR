# Windows architecture boundary — implementation choices open

This is a design boundary, not a final technology selection. On 2026-09-30 the
owner requested a language-independent Core contract and explicitly deferred Core
language, Windows UI and GPU choices. The implementation-specific proposal in
[841d09c](https://github.com/songhj0728/Compositor-KR/blob/841d09ce8011e56fcc8cd3d1885c8a2dfb951181/docs/multiplatform/windows-architecture.md)
is retained in Git history, **superseded as current guidance**. It was not an
implemented product. No scores or winner are carried into this contract.

## Boundaries that hold for either Core language

- Shared semantic state/operations: document, stable IDs, hierarchy, history,
  settings and immutable resources, as defined by [Core contract](../core-api.md).
- Existing C pixel algorithms stay shared and independently testable.
- UI/platform services own windows, input, dialogs, file I/O/codecs, clipboard,
  font resolution/text layout, color conversion, update and installation behavior.
- Renderer consumes immutable descriptions/snapshots. Existing Metal/Core Image
  remains the Mac implementation; Windows backend is undecided.
- Mac and Windows adapters translate geometry/path/image representations at the
  edge. No native image, window or GPU handle becomes a Core model field.
- Snapshot/history lifetime must preserve immutable pixel sharing; tiles, patch
  storage, allocator hooks, native CRT mode and persistent containers are options,
  not semantic requirements or completed work.
- One serialized owner context mutates an open instance; immutable views support
  background reads. No actor/queue/mutex implementation is selected.

## Evidence available

Both Swift and C++ toy Cores work behind the experimental C# WinUI host, including
Korean names and add/undo/redo. The bulk-query performance problem exists in both
C ABI implementations. Windows background test uses an independent document and
does not prove concurrent access to the same instance. See
[spike findings](spike-findings.md) and [repository evidence](repository-evidence.md).

Runtime footprint, interop exception/reference limitations, existing Swift history
semantics and rewrite cost are decision factors, not grounds for selecting a
winner without equivalent-boundary measurements. The full criteria are Q11 in
[architecture questions](architecture-questions.md).

## Deferred work

GPU API, native text/color engines, WinUI product adoption, Windows App SDK package
selection, AOT/R2R, installer/updater/signing, feature parity and recovery UX all
need separate evidence and scope. They are listed as Q9–Q26, not silently decided
by this document. In particular, a previous MSI UpgradeCode, sparse-tile layout,
60-fps target or provider choice in the superseded proposal is not a published
product commitment.

[Migration stages](migration-dependency-map.md) describe reversible future seams.
The current task synchronizes main's reference implementation and refreshes
documents; no product Core, Windows app/backend or model replacement is implemented.
