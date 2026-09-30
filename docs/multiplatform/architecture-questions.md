# Open architecture questions

Decisions [core-api.md](../core-api.md) and the [migration plan](document-model-inventory.md) leave open, with what
each depends on and when it must be answered. None is answered here; each gets its answer recorded in this file when
the project owner makes it.

## Must be answered before the migration step that needs it

| # | Question | Options | Needed by | Notes |
|---|---|---|---|---|
| Q1 | **Core ID type.** Keep `UUID` (Swift: needs `FoundationEssentials` on Windows, +7.7 MB) or a Core-owned 128-bit ID? | platform UUID / own type | wave 4 (step 3) | Either writes the same uppercase UUID strings to `.comp`. |
| Q2 | **Foundation in the Core.** Standard library only, `FoundationEssentials`, or full Foundation? | stdlib 5.8 MB / Essentials 13.5 MB / full ~63 MB (Swift, Windows) | step 2 | Decides whether the Core may use `Data`, `Date`, JSON coders directly. C++ Core: equivalent question about third-party libraries. |
| Q3 | **Who encodes the manifest JSON?** The Core (needs a JSON coder) or the platform (the Core hands over records)? | Core / platform | wave 4 | core-api §11 puts manifest *meaning* in the Core; the byte encoding is open. Byte-for-byte compatibility is guarded by golden tests either way. |
| Q4 | **`ImageRef` pixel formats.** RGBA8 premultiplied + Gray8 only, or also 16-bit / float for future high-bit-depth editing? | 8-bit only now / reserve formats now | wave 5 (step 4) | `.comp` stores 8-bit PNGs today; adding formats later is additive if the field exists. |
| Q5 | **Who owns pixel memory on Windows?** Platform-allocated buffers wrapped by the Core, or a Core allocator both sides use? | platform-owned + release callback (core-api §7.4) / Core allocator | wave 5 | Affects GPU upload paths (D3D12 staging) later. |
| Q6 | **Snapshot implementation.** Persistent (structurally shared) data or copy-on-write arrays? | — | step 7 | Must meet core-api §8.4 targets at 10,000 layers. Swift gets copy-on-write free; C++ needs a design. |
| Q7 | **Change notification.** UI polls `changes(since:)`, or the Core calls back? | poll / callback / both | step 7 | core-api §11 says the Core never calls into the UI; a callback would change that rule. |
| Q8 | **Selection representation.** `CorePath` only (as today), or path + raster mask? Magic Wand, Color Range and Object Selection all work on pixels and hand back a `CGPath` today (the wand via `MaskTracing`, at 50% coverage). | path / path + mask | wave 6 (step 5) | Keeping path-only matches today exactly; a raster form would keep soft edges but needs its own `ImageRef` and undo cost. |
| Q9 | **Text on Windows.** Same font names may not exist; layout (wrapping, kerning) will differ between CoreText and DirectWrite. Accept differences, embed fonts, or rasterize on save? | accept / map fonts / keep pixels until edited | before Windows edits text | Today the PNG preserves appearance until the text is edited (`project-format.md`), which already limits damage. |
| Q10 | **Color management on Windows.** Which CMS (Windows WCS/ICM, LittleCMS, …) turns `ColorSpaceID` into profiles, and must results match ColorSync within a tolerance? | — | before Windows opens non-sRGB files | Core only carries names (core-api §2). |

## Must be answered before the Core is extracted (step 7)

| # | Question | Notes |
|---|---|---|
| Q11 | **Core language: Swift or C++.** | Evidence: `Spikes/CoreModel` (branch `spike/core-model`), [spike-findings.md](spike-findings.md). Steps 0–6 don't depend on it. |
| Q12 | **Is the C ABI generated or hand-written?** | Four places change per operation by hand (spike). Candidates: generate C# bindings from the header; generate header + exports from Core declarations. |
| Q13 | **Process model.** Core in-process (a Core fault ends the app) or out-of-process (isolation, IPC cost)? | Spike showed faults can't be caught in-process. In-process + fail-fast + autosave is the default in core-api §10. |
| Q14 | **Autosave / crash recovery design.** | Required by core-api §10 whatever Q13 decides. `.comp` itself is unchanged; recovery files are a separate concern. |
| Q15 | **Thread-affinity enforcement.** Check the owner thread on every call (small cost, clear errors) or only in debug builds? | core-api §9. |
| Q16 | **History budget per platform.** Keep 100 steps / 256 MiB, or scale with memory as `DocumentLimits` does? | core-api §5.4. |

## Must be answered before Windows UI work

| # | Question | Notes |
|---|---|---|
| Q17 | **Windows UI technology.** WinUI 3 is a candidate, not a choice. | WinUI 3 test: no fatal issue with either Core (`Spikes/CoreModel/winui-test.md`). UI choice waits for the Core boundary. |
| Q18 | **Windows App SDK deployment.** Self-contained (~155 MB folder, of which ~47 MB unused AI/ML) or framework-dependent (installs the Windows App Runtime); metapackage or component packages? | Spike finding 6. |
| Q19 | **.NET and VC++ runtimes.** Publish .NET self-contained? Ship VC++ runtime app-local or require the redistributable? | Spike finding 6. |
| Q20 | **Windows renderer.** Direct3D 12 / Vulkan / Direct3D 11 (windows-decisions.md §3), and how Core Image's filters are replaced (§4). | Out of scope until the Core boundary exists. |
| Q21 | **Vision-based features on Windows** (object selection, subject removal). | windows-decisions.md §5. |

## Process questions

| # | Question | Notes |
|---|---|---|
| Q22 | **Syncing main.** main is at 1.4.3 (brush engine fixes; no conflicts with the migration branch, checked with `git merge-tree`). Sync now, or with the next migration step? | AGENTS.md rules 11–20. Not merged in this step because this step changes documents only. |
| Q23 | **Where the spike lives long-term.** Keep `spike/core-model` as a branch, or archive its report under `docs/` and delete the branch? | It is evidence for Q11. |
