# Repository and verification evidence — 2026-09-30

Follow-up 2026-10-01 (KST): the first S1 FilterKind seam is implemented in
`9bac5cf`, with a separate [migration record](filter-kind-migration.md). The ledger
below describes the preceding sync; its no-migration statement is historical.
Main now has three additional inspected commits through `0be4fe6`, not merged.

This audit uses repository contents, not prior Claude/ChatGPT conversations.
Remote heads were rechecked with `git ls-remote --heads origin` and fetched before
the requested synchronization. Main is now merged into the local named
`Compositor-Multiplatform` branch by **db268a2b4142cda0db5d8262227dce18036dabb9**.
No reset/rebase/history rewrite, spike merge/edit or Core migration was performed.
The synchronization and architecture refresh are separate commits; final refs and
publication status must be checked in Git rather than inferred from this ledger.

## Branches actually inspected

| Branch / SHA | Observed contents |
|---|---|
| Compositor-Multiplatform before sync / `841d09ce8011e56fcc8cd3d1885c8a2dfb951181` | Historical v11/macOS build40 baseline; portable C kernels/CMake/Windows threading, preserved by the merge. |
| Compositor-Multiplatform sync merge / `db268a2b4142cda0db5d8262227dce18036dabb9` | Contains main ccf062ed and every pre-existing multiplatform path. macOS 1.4.5(A) build41, reader1–12, conditional save11/12. No product Core/Windows UI implementation. |
| spike/core-model / `e3bf3868e49bddb6a5527318fa5b273b99001d00` | Both experimental Cores, C ABI, C++/C#/WinUI hosts, tests/workflow, text reports and two PNG captures under Spikes/CoreModel. Not in the current product checkout. |
| main / `ccf062ed3903c0b1b7dd61462ac8b79617e1e438` | Latest fetched reference: macOS 1.4.5(A), v12 styles, editable PSD text, clipping/shape improvements; fully included in the sync merge. |
| claude/compassionate-hawking-wcn4nz / `9cd0aa2cbe42243c5e52b49af2ede3321367dd5d` | Earlier point in the new Mac feature line, included in current main. Not another repository or a separate product Windows implementation. |

Before sync, merge base was `00cb37aacb69dd8d1fbda006320ef54caac698bb` and graph
count was 23 multiplatform-only / 10 main-only. After sync main ccf062ed is an
ancestor: **zero main-only commits**. Neither count is a feature count.

### Recent synchronization

- `7046a54` merges main through `00cb37a` (1.4.5 build 40). Its message documents
  inspected incoming 1.4.3/1.4.5 work and portability conflict resolution.
- `9e9fd17` completes files omitted from the preceding merge: ParallelFor's Windows
  path/testing switch, Windows thread-pool source, CMake and pixel tests, plain-C
  Scanlines callbacks. Read both commits; the merge message alone overstates what
  was present in the first commit.
- `841d09c` subsequently asserts a final C++20/D3D11 architecture **in documents**.
  This conflicts with the earlier language-neutral inventory and the requested
  scope. Current documents explicitly reopen those implementation choices; no
  historical commit is rewritten.
- `db268a2b` merges the latest main after A–F classification. There were **no merge
  conflicts**. All 47 incoming paths match main byte-for-byte (including deletion);
  all 24 pre-existing multiplatform paths match 841d09ce byte-for-byte in that
  merge. Architecture documents are subsequently refreshed separately. The local
  spike ref remains e3bf3868. See [sync record](main-sync-2026-09-30.md).

### Main changes imported in this sync

| Commit/area | Shared meaning to retain later | Tests / impact |
|---|---|---|
| `af24425`, shape and movement | Explicit shape size/style, editable text color and movement behavior | ShapeToolTests, TypeToolTests, TransformTests; split UI from value semantics |
| `d0c586c`, full Layer Style | EffectContour/Pattern, Bevel/Satin/PatternOverlay, fill opacity and extensions to older effects; version 12 | LayerStyleTests, PSDExportTests; update inventory and format fixtures together |
| `d0c586c`, clipping visibility | Hidden lower sibling clipping base hides clipped layers; arbitrary external/upper live-mask coverage is a different case | LiveMaskTests/LayerGroups; cache key now includes maskSourceID |
| PSD text/style export + `a8529e9` | Editable PSD text and row-vector text-matrix interpretation | PSDRoundTripTests, PSDExportTests; format adapter behavior |
| `8c1f9db` | Save v11 unless stored Layer Style fields require v12; `neededVersion` is 11/12, not a general minimal-version solver | ProjectStore and LayerStyleTests; presence and rendering predicates differ |
| `a9d9388`, `71d025d` | Selection outline outside Move tool; shape outside-stroke bounds and metadata | Renderer/UI vs shape geometry/format split |
| version/feed commits | Release labeling and payloads | macOS distribution only; no forced Windows counterpart |

Current contract/inventory describes the synchronized v12 source, including nine
effects, Fill Opacity, fixed style order and seven new data declarations. The
original 47-entry classification is retained for traceability, not completeness.
Main remains the evolving reference; recheck it before each affected migration.

## Documents and code reviewed

Read AGENTS, ARCHITECTURE, BUILD, MULTIPLATFORM_MIGRATION, AI_AGENT_GUIDE, CLAUDE,
CODEX, README_MULTIPLATFORM, docs/core-api, project-format, and every Markdown file
under docs/multiplatform, including the prior implementation-specific decisions.

Read the entire tracked Spikes/CoreModel source/configuration tree at `e3bf3868`:
Swift model/history/transform/C exports/Win32 demo/tests and Package.swift; C++
header/model/C exports/tests/Swift interop; both console hosts and C# binding;
WinUI XAML, code, self-test, project/manifest; boundary script/CMake; README and
WinUI report; selftest-cpp/swift text and both PNG captures. Read its workflow
from the same commit. Files were extracted under `/workspace/core-contract-audit`
for inspection/build, not merged into the product checkout.

Read current declarations and dependencies for every original inventory entry,
plus Levels/Curves children, hierarchy/opacity/link validators. Key behavioral
sources: EditorSession, EditorSession+Projects, DocumentHistory, LayerTransform,
LayerGroups, SelectionClipboard, ProjectWorkspace, Selection, LayerMask,
ColorProfile, RasterSnapshot, ProjectStore/Controller, renderer call sites, and
History/Project/Group/GroupingSelection/ExternalChange tests. Read main diffs for
the areas imported above, including LayerStyleTests, PSD style/text write/read,
preview commit/cancel, unchanged duplicate/clipboard/group/history paths. Evidence
links use symbols and pinned SHAs rather than
assuming current line numbers remain stable.

## What the spike establishes, and what it does not

- Both implementations can be called through the same C ABI by the same hosts.
- WinUI self-test exercises UI-thread operations and a **separate document created,
  used and destroyed on a background thread**. It does not test simultaneous access
  to one instance, snapshot sharing or owner-thread enforcement.
- `cc_outline_row` in both implementations rebuilds the list; C# calls it per row.
  The retained reports measure 334.7 ms Swift / 24.2 ms C++ at 2,000 rows on that
  machine. Both are an O(n²) boundary pattern, not a language decision.
- Duplicate grouping IDs are now rejected and covered in both Cores and hosts.
  Their toy tree still differs from Mac grouping across parents/empty selections.
- C ABI ownership is explicit but raw pointers, not checked generation tokens;
  full exception containment, arbitrary pointer safety, fuzzing and image ownership
  are not established. C++ allocations before `guarded` and undo/query paths need
  further audit before a product ABI claim.
- The 18 Swift tests and the C++ test executable cover toy-model cases. C++ invokes
  12 named test functions (some group multiple transform checks); do not invent an
  identical test-count claim. Swift→C++ interop has two tests.
- Runtime sizes, WinUI package size, framework/SDK versions and deployment caveats
  are measurements in the spike report. They are not promises for a full editor.

## CI and local validation provenance

| Evidence | Result and limitation |
|---|---|
| Stored spike README: [36595610253](https://github.com/songhj0728/Compositor-KR/actions/runs/36595610253) | Reports Windows/macOS Core/host/boundary success; historical report, not live reverified here |
| Stored WinUI report: [36609111202](https://github.com/songhj0728/Compositor-KR/actions/runs/36609111202) | Reports both WinUI Core variants and full spike jobs green; text self-tests also say all checks passed |
| Stored claim of macOS full app success | WinUI report says verify.yml passed on both branches; does not provide an exact app-run ID in that sentence, so do not attribute it to current main or this diff |
| Live GitHub Actions API | Read-only request to api.github.com failed: proxy tunnel 403 Forbidden. Latest head-run/job conclusions remain unverified; no token requested or substituted |
| Product workflow source | verify.yml: macos-26/Xcode 26.6, frozen package resolution, build-for-testing, parallel tests plus two serial window suites |
| Shared workflow source | shared.yml: Windows/MSVC and macos-26 CMake/CTest, one existing pixels test target at this baseline |
| Spike workflow source | Windows + macOS; pinned Swift version string, C++ and both hosts, C# and WinUI on Windows, Swift direct C++ interop; source path triggers and workflow_dispatch |
| Local shared code after sync | Linux GCC 14.2 Release + OpenMP, existing `pixels` CTest **1/1 passed** (0.35 s); pre-existing misleading-indentation warning in AdjustPixels.c:784 |
| Product boundary checks after sync | 26 shared C/header files contain no Apple graphics/UI imports; all24 existing multiplatform paths retained in merge, including workflows/CMake/Windows thread pool; new CPU renderer is outside shared C target |
| Original spike boundary after sync | Extracted unchanged e3bf3868 check-core-boundaries.sh passed. This checks experimental targets, not a product Core that does not yet exist |
| Earlier local spike copy | Existing C++ tests **2/2 passed** in the preceding contract task; not rerun as a new v12-model test and never represents Mac/Swift/WinUI validation |

No Windows, WinUI, Swift, Xcode or macOS tests were newly run in this Linux machine.
No CI workflow source was changed or manually dispatched. A push may trigger the
existing workflows; a definition or trigger is not proof that its run passed.
Live `gh api .../actions/runs` still returns Forbidden in this sync task. Latest
result remains unverified, not green by assumption.

## Worktree scope

Previous-turn uncommitted tests, CMake/CI edits and progress text were authored in
this session and saved intact to `/workspace/prior-windows-validation` (file copies
and tracked.patch), then excluded from this documentation-only worktree. They were
not pushed and must not be reported as committed baseline capabilities. The new
123,620-check suite is **not** part of this audit's product diff or current CTest.

The previous 15-file Markdown draft was archived under `/workspace/main-sync-audit`
and stashed before the merge, then reapplied intact. Main synchronization changes
47 incoming paths including product/test/format files; the following architecture
refresh changes only Markdown. No independent product edit or S1 migration occurs.
Builds use external output directories. The original spike branch is untouched.

New unresolved evidence: style preview mutates live document fields without a new
history state, while file gating omits layerStyle. Do not claim committed-only
saving is proven. Imported tests cover style JSON/save/render/dialog behavior;
dedicated v12 duplication/clipboard/grouping and preview-save-cancel matrices are
still needed before the corresponding migration (Q16/Q26).
