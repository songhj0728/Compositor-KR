# Implementation status and future review units

**Current task: main synchronization + architecture refresh; stop before migration.** No Core language or
GPU backend is selected. The C++/D3D/WiX Wave 1 plan in `841d09c` is superseded as
an execution plan and retained in Git history. Semantic constraints and future
language-neutral order are in [Core contract](../core-api.md),
[inventory](document-model-inventory.md), [dependency map](migration-dependency-map.md)
and [open questions](architecture-questions.md).

## Already in the inspected branch

- Shared C pixel implementation, CMake build, Windows thread-pool adapter,
  Liquify/Smear reference tests and shared Windows/macOS workflow.
- macOS baseline synchronized through main `ccf062ed` (1.4.5(A), build 41) by
  merge `db268a2b`; v12 Layer Style, conditional 11/12 saves, clipping, shape and
  PSD changes are imported. Existing C/Windows portability paths are preserved.
- Model/format implementation remains Swift/macOS. No production Core module or
  Windows UI/renderer exists in this checkout.
- Both model/WinUI experiments remain on spike/core-model. Do not merge or delete
  them as part of an inventory/contract task.

## Evidence needed before future code work

1. Use the synchronized v12 baseline and recheck main before each affected
   migration. Review incoming shared semantics and preserve Windows portability.
2. Characterize affected behavior with existing tests and missing reference
   fixtures: parsed `.comp` records/decoded images, history/save races, grouping,
   identity remaps, masks, text spans and color, plus stored-default/disabled styles
   and Layer Style preview/save/Cancel. Do not pretend all golden tests exist.
3. Take one reversible data/helper seam (the dependency map proposes FilterKind)
   and verify the Mac reference before widening scope.
4. Prove image/path lifetime and equivalent bulk read semantics using actual model
   data before comparing implementation languages or publishing an ABI.

Existing CI is evidence infrastructure, not a pass claim for unrun work. Every
future code review needs the affected tests plus the Mac reference suite and shared
C suite where relevant. No installer or renderer prerequisite should force a
language-neutral enum split into a whole-app migration.

Earlier local tests/CI additions were archived outside the repository and excluded
from this sync. They are not completed baseline stages. Source changes in this task
are solely imported main changes; architecture refresh is a separate Markdown
commit. See [evidence ledger](repository-evidence.md).
