# Windows architecture — final decisions

The decisions that the Windows port is built on, with their reasons. They refine, and do not weaken,
[core-api.md](../core-api.md), which stays the source of truth for the Core boundary. Nothing here has been
implemented yet; [implementation-plan.md](implementation-plan.md) says in what order it will be. The 23 questions
that led here are answered one by one in [architecture-questions.md](architecture-questions.md).

Baseline: Compositor-KR 1.4.5 (build 40), merged into `Compositor-Multiplatform`. The macOS app remains the reference
behavior.

## Summary

| Area | Decision |
|---|---|
| Core language | **C++20** for the Core (model, history, operations, snapshots, `.comp` manifest, image store); pixel kernels stay **C11** (`Compositor/Rendering/*.c`); one **C ABI** as the boundary for every UI |
| Windows toolchain | MSVC (VS 2022 17.14 or later; CI uses the runner's current VS), C++20 `/permissive- /utf-8 /W4`, CMake, Windows SDK 10.0.26100, static CRT for our native DLLs |
| Architectures | **x64** first; **ARM64** native later from the same CMake presets (no ARM64EC) |
| Windows UI | WinUI 3 (Windows App SDK, stable only) with a C# shell, for Wave 1 prototyping; locked in when the prototype meets the canvas targets (Q17) |
| Renderer | **Direct3D 11.1** (feature level 11_0 minimum) compute + pixel shaders, **Direct2D** on the same device for overlays, DXGI flip-model swap chain in a `SwapChainPanel` |
| Text | Core holds text *data*; the platform lays it out: **DirectWrite** on Windows, Core Text on macOS |
| Color | Core holds color *identity* (`ColorSpaceID`, ICC bytes); **LittleCMS 2** on Windows, ColorSync on macOS; compositing in the document's encoded space, as today |
| Image memory | `ImageRef`: immutable, reference-counted, CPU-owned by the Core; tiled storage with shared tiles; GPU textures live in a renderer cache, never in `ImageRef` |
| Threading | One owner thread per document mutates; immutable snapshots everywhere else; worker pool (Windows thread pool) for CPU work; a render thread owns the D3D11 context; cancellable jobs |
| Installer | **WiX** MSI, per-machine, stable UpgradeCode `15737362-8B12-4BF4-8314-16E529A0C200`, `MajorUpgrade`, downgrades blocked |
| Updates | **WinSparkle** + per-architecture appcast on GitHub; MSI payloads; EdDSA-signed |
| Signing | Authenticode (cloud HSM signing from GitHub Actions via OIDC) + EdDSA for the feed; optional locally, mandatory for releases |
| CI/CD | build → test → package → sign → GitHub Release → appcast, on a version tag |

---

## 1. Core language: C++20 Core, C11 kernels, C ABI

### What was weighed

The spike built the same Core in Swift and in C++ and ran both on Windows and macOS, behind C++, C# and WinUI 3
hosts ([spike-findings.md](spike-findings.md)). Against the project's priorities, in order:

| Priority | Swift Core | C++ Core | Weight of the difference |
|---|---|---|---|
| 1. Windows performance | Swift runtime (5.8 MB `swiftCore.dll`), ARC retain/release traffic on every value copy; the spike's list rebuild was ~14× slower (330–490 ms vs 24–34 ms, 2,000 layers) because of value copies | Native MSVC code, no runtime, full control over allocation and layout | **Decisive** — the bulk API removes that particular rebuild, but the cost model remains: in Swift, copying and reference counting are implicit |
| 2. macOS performance | Native | Native (Clang), called from Swift through a C ABI at bulk granularity | Even |
| 3. Deterministic behavior | Deterministic; ARC release timing implicit | Deterministic; destruction explicit | Even |
| 4. Low-level pixel performance | Kernels are C either way | Kernels are C either way; C++ can call them with no bridging and add SIMD intrinsics where measured | Slight C++ |
| 5. Safe ownership/lifetime | Memory-safe; traps before corruption (spike: `0xC000001D`) | Undefined behavior possible (spike: heap corruption `0xC0000374`) | **Swift** — mitigated below |
| 6. C/C++ interop | Good with C; C++ interop has sharp edges (exceptions end the process, reference/pointer returns not imported) | Native | C++ |
| 7. Testability | XCTest; Windows test tooling young | CTest, sanitizers, fuzzers, same on both OSes | C++ |
| 8. Maintainability | Existing model is Swift | Rewrite of the model and formats (~11,000 lines) | Swift |
| 9. Minimal platform coupling | Needs Foundation-free discipline; `CGFloat`/`CGPath` absent on Windows | Standard library only | C++ |

Windows toolchain maturity decided the tie-breaks: MSVC, the Visual Studio debugger, PIX, WPA/ETW, MSVC AddressSanitizer
and ARM64 code generation are first-class; Swift on Windows needed a community CI action that broke on a version string,
Developer Mode for symlinks, and ships its own runtime.

### The decision

- **Core: C++20.** Model, IDs, history, operations, snapshots, `.comp` manifest semantics and the image store.
  Standard library only (plus vendored, pinned header-only libraries where named in this document).
- **Pixel kernels: C11, where they are.** `Compositor/Rendering/*.c` is already portable, byte-verified on both
  platforms, and called today by the macOS app. The C++ Core calls them directly; they are not rewritten.
- **Renderers: native per platform.** Metal/Core Image (Swift) on macOS as today; Direct3D 11 (C++) on Windows.
- **Boundary: one C ABI** (core-api §12). The macOS Swift app uses it through a thin Swift wrapper (a module map over
  the header — not Swift's C++ interop, whose exception and lifetime rules the spike found unsafe); the Windows C#
  shell uses it through P/Invoke bindings generated from the header; C++ code in the same native DLL (the Windows
  renderer) calls the Core's C++ API directly.
- **What does not move to C++:** macOS UI, AppKit/SwiftUI code, the Metal renderer, and Apple platform services stay
  Swift. AGENTS.md's "do not rewrite all Swift into C++" holds: only the Core crosses over.

### C++ safety rules (making up for priority 5)

- No exception crosses the C ABI; every entry point catches and returns a status. Invariant violations fail fast
  (`__fastfail` on Windows, `abort` elsewhere) so crash reports show the site — never continue on corrupt state.
- Value semantics for document state; immutable, reference-counted sharing (`std::shared_ptr<const T>` or intrusive
  equivalents) for snapshots, history and images. No raw owning pointers; no pointer is ever an ID.
- Hardened standard library in release (`_MSVC_STL_HARDENING`, libc++ `_LIBCPP_HARDENING_MODE_FAST`), assertions kept.
- CI on both OSes: AddressSanitizer (MSVC `/fsanitize=address`, Clang), UBSan (Clang), and libFuzzer over random
  operation sequences through the C ABI (including invalid and duplicate IDs — the spike's crash).
- **Differential tests** while both exist: the same operation scripts run against today's Swift model and the C++
  Core must produce identical snapshots and manifests.

**Reversibility:** low once the port starts (implementation-plan Wave 2). Until then — through Wave 1 — the C ABI,
the tests and the macOS refactors are language-neutral.

---

## 2. Windows Performance Architecture

### 2.1 CPU processing

- **Kernels stay contiguous-memory C.** Rows and tiles are processed in place, pointer-stride loops that MSVC and
  Clang auto-vectorize; explicit SIMD (SSE4.1/AVX2 on x64 with runtime dispatch, NEON on ARM64) only where a profile
  shows a kernel is the bottleneck.
- **Parallelism through `ParallelFor.h`.** Windows uses the process's system thread pool
  (`Platform/Windows/ParallelForWin32.c`): no OpenMP runtime to ship, no second thread team competing with the pool
  the rest of the process uses, work taken by atomic index with no locks. Parallel output is verified identical to
  single-threaded output (`Tests/Pixels`).
- **No per-pixel or per-row heap allocation.** Kernels allocate their working buffers once per call. Known exception to
  measure in Wave 0: `smear_blur_dab` allocates four buffers per dab (1.4.3 behavior); if dab throughput matters on
  Windows, a per-thread scratch arena is the fix — only after measuring.
- **Integer widths:** `size_t`/`ptrdiff_t` for sizes, indices and offsets; fixed-width types at every boundary; `long`
  never assumed pointer-sized (1.4.5 already moved Liquify and Smear to `ptrdiff_t`; the rest are bounded by the
  30,000 px limit and are migrated as they're touched).

### 2.2 Image memory

- **`ImageRef`** (core-api §7.4) is the only way pixels cross the boundary: immutable, atomically reference-counted,
  owned by the Core. Crossing to the UI or renderer passes the handle, never a copy.
- **Storage** behind an `ImageRef` is *tiled*: 256 × 256 tiles, each immutable and reference-counted; a derived image
  (a brush stroke, a filter on a region) shares every tile it didn't change. This is the same economy the macOS app
  gets today from `RasterSnapshot` base + patches, generalized; it keeps undo memory and upload bandwidth
  proportional to what changed. Empty (fully transparent) tiles are not allocated.
- **Allocation:** tile memory is 64-byte aligned (row stride a multiple of 64); large blocks come from a platform hook
  (`VirtualAlloc`/`mmap`), small ones from the heap. The Core never allocates per pixel.
- **Formats:** RGBA8 premultiplied and Gray8 now; RGBA16F premultiplied reserved (Q4).
- **Three separate things:**
  1. CPU storage — the tiles, owned by the Core.
  2. GPU resources — textures in the renderer's cache, keyed by (image identity, tile), created lazily on first
     draw, evicted least-recently-used against a VRAM budget from `IDXGIAdapter3::QueryVideoMemoryInfo`.
  3. Platform representations — `CGImage` on macOS, WIC bitmaps on Windows — made only at the edges (codecs,
     clipboard), wrapping tiles without copying where the API allows.
- **Synchronization:** CPU tiles are immutable once published, so a GPU copy can never be stale; a new image is a new
  key. A derived image records its parent and changed tiles, so the renderer copies the parent's textures GPU-side
  (`CopySubresourceRegion`) and uploads only the changed tiles. Normal editing never reads GPU data back; a GPU filter
  that produces a new image reads it back once, asynchronously (staging texture + query), to create its `ImageRef`.
- **Live painting:** during a stroke, the renderer and brush engine work on a mutable scratch surface outside the
  document; the stroke commits one new `ImageRef` (changed tiles only) at its end — one undo step, as today.

### 2.3 GPU rendering

**Direct3D 11.1**, feature level 11_0 minimum, with **Direct2D** on the same device and a **DXGI flip-model swap
chain** (`FLIP_DISCARD`, waitable, frame latency 1) in the WinUI `SwapChainPanel`.

Why not Direct3D 12: the editor draws a handful of passes per frame (composite visible tiles, effects, overlays) on one
queue; D3D12's explicit barriers, residency and descriptor management buy CPU savings for thousands of draw calls,
which this workload doesn't have, at a large cost in code and bugs. Direct2D and DirectWrite interoperate natively
only with D3D11 (with D3D12 they need D3D11On12 and cross-API synchronization). D3D11 has everything the renderer needs:
compute shaders (filters, effects, warp, brush coverage), UAVs, and tiled resources (11.2) if ever needed. It runs on
every D3D12-capable GPU and on ARM64 Windows. *Reversible* behind the renderer interface; no Core impact.

- **Compositing** happens in the document's encoded color space on `R8G8B8A8_UNORM` textures (not `_SRGB`, which would
  linearize), matching the macOS renderer (Core Image with the document profile as working space). Blend modes,
  masks, clipping, adjustments and effects are HLSL (Shader Model 5.0, compiled at build time with `fxc`), written to
  match the Metal/Core Image results within documented tolerances (Wave 0 golden images).
- **Display:** a final pass converts document space → monitor profile (3D LUT built with LittleCMS, §2.6); HDR/Advanced
  Color output (`R16G16B16A16_FLOAT`) is a later, additive step.
- **Only visible tiles** at the current zoom are composited; per-tile mip levels (as macOS's `DownsampleCache`) for
  zoomed-out views. Group results are cached per subtree `Revision`.
- **Threads:** a render thread owns the D3D11 immediate context; the UI thread never waits on the GPU. Uploads go
  through a ring of staging buffers so CPU work for frame N+1 overlaps GPU work for frame N.
- **Codecs:** WIC for PNG/JPEG/TIFF/HEIC/BMP (with the embedded ICC profile); PSD stays Compositor's own code; camera
  raw via WIC's raw codecs where installed, as a platform service.

### 2.4 Threading

Kept from core-api §9, optimized for Windows:

- **Owner thread** (the UI thread for an open document) performs every mutation. Core operations are metadata changes
  and tile-pointer swaps — microseconds — so they never need to leave it.
- **Readers** use immutable snapshots: the renderer, background saves, autosave, exports, thumbnails. Taking a snapshot
  is a pointer copy with structural sharing (Q6); handing it to another thread is an atomic reference.
- **Jobs** for expensive work (filters, liquify, resampling, baking, object selection): run on the worker pool against
  a snapshot, report progress, poll a cancellation flag per band/tile, and produce new `ImageRef`s/`CorePath`s. The
  owner thread commits the result with a normal operation, which re-validates against the current `Revision` and
  fails cleanly if the document moved on. Jobs are platform-layer objects; the Core only provides snapshots and
  operations.
- **No global locks in hot paths:** reference counts are atomics; snapshots are immutable; the texture cache belongs to
  the render thread; `parallel_for` shares work with one atomic counter. The macOS app's process-wide
  `WorkingColorSpace` (a global behind `NSLock`) does not exist in the Core — the color space is a per-document input.
- **CPU/GPU overlap:** workers prepare tiles while the GPU renders the previous frame; the render thread submits.
- The document is **never** concurrently mutable.

### 2.5 Text

- The **Core stores text data only**: content (UTF-8; run offsets in UTF-16 units, as `.comp` stores them), font
  request (PostScript name, size in px), color, alignment, tracking, leading, box size, color runs, font runs. No
  layout, no glyphs, no Core Text types.
- A **platform text engine** lays out and rasterizes: `layout(text, style, box) → lines, glyph runs, bounds,
  missing-font report`, then `rasterize → ImageRef`. **DirectWrite** on Windows (`IDWriteFactory7`: font sets matched
  by PostScript name, `IDWriteFontFallback` for missing glyphs, full shaping and bidi, variable-font axes via
  `IDWriteFontFace5`), drawn with Direct2D in grayscale antialiasing (never ClearType into document pixels). Core Text
  on macOS as today.
- **Korean:** a font map for Apple-only faces (e.g. Apple SD Gothic Neo → Malgun Gothic, Apple's system UI face →
  Segoe UI) is applied only when the named face is missing, and the substitution is reported to the UI.
- **Cross-platform consistency:** the layer's saved pixels stay authoritative until the text is edited (existing
  `.comp` rule), so a file opened on the other OS looks identical; only re-layout after an edit can differ, and golden
  tests bound the difference (line breaks identical for Latin and Korean samples, advance widths within 0.5 px).
  HarfBuzz/FreeType for identical layout was rejected for now (worse system-font and IME integration); the text-engine
  interface keeps it possible.

### 2.6 Color management

- **Core representation:** `ColorSpaceID` (the six `.comp` values), an optional `ColorProfile` = immutable ICC bytes
  with a content hash as identity, and `ColorEncoding` = `documentEncoded` (today's only value) with `linear`
  reserved. `CoreColor` values are document-space encoded values, like the pixels. Nothing in the Core converts.
- **Behavior preserved:** pixels and colors are numbers in the document's space; compositing is in that encoded space
  (Photoshop-compatible, as macOS does it); a `CMYK` document is edited in sRGB and converted only when exported as
  JPEG; imported images are converted into the document space on import; exports embed the document's profile.
- **Windows engine: LittleCMS 2** (MIT, vendored, pinned). The Windows Color System APIs are old and don't expose the
  transforms an editor needs; LittleCMS gives the same conversions on every machine, which ColorSync-matching tests
  need.
- **Profiles:** the exact ICC data macOS uses for each `ColorSpaceID` is exported once from `CGColorSpace` (Wave 0) and
  shipped with the Windows app, so both sides convert with identical profiles. Rendering intent and black-point
  compensation match macOS's defaults; tests require ΔE2000 ≤ 1 against ColorSync on reference images.
- **Display:** the monitor's ICC profile comes from the OS (the Windows color-profile APIs for the window's monitor,
  e.g. `ColorProfileGetDisplayDefault`; exact call chosen in Wave 1), converted into a 3D LUT on the GPU; profile
  changes (window moved to another monitor) rebuild it.

### 2.7 Large documents

Limits stay those of `.comp`: 30,000 px per side, 10,000 layers. A full 30,000² RGBA8 layer is 3.6 GB, so:
tiles are sparse (transparent tiles aren't stored) and shared across history and duplicates; rendering touches only
visible tiles at the needed mip level; kernels work on the dab's or selection's bounding region, not the canvas
(Liquify and Smear already do); brushes up to 2,100 px (1.4.3's `maxDiameter`) stay region-bound. Several open
documents are independent Cores; the texture cache has one VRAM budget across them.

### 2.8 Caching

| Cache | Key | Owner | Invalidation |
|---|---|---|---|
| Tile textures | image identity + tile | render thread | never stale (immutable); LRU by VRAM budget |
| Group / subtree composites | subtree `Revision` + zoom level | renderer | new revision |
| Mip levels | tile texture | renderer | with the tile |
| Thumbnails | image identity + size | UI | never stale; LRU |
| Effects previews | layer revision + effect parameters | renderer (serial worker, as macOS) | new revision |
| Layer table rows | snapshot `Revision` | Core | rebuilt only for changed layers |
| Display LUT | document profile + monitor profile | renderer | profile change |

### 2.9 Hot-path audit

Every decision above was checked for an unnecessary allocation, copy, lock, boundary call or CPU/GPU sync:

| Path | Allocation | Copy | Lock | Boundary calls | CPU/GPU sync |
|---|---|---|---|---|---|
| Layer panel refresh | table rows reused per revision | none (borrowed from snapshot) | none | 1 (`snapshot`) + `changes(since:)` | none |
| Canvas frame | none steady-state | only changed tiles uploaded | none (render-thread-owned) | 0 (C++ in-process) | waitable swap chain; no readback |
| Brush dab | kernel scratch per call (Smear: measure) | dab region only | none | 0 during stroke; 1 commit | scratch texture on render thread |
| Filter job | per job, not per pixel | output tiles only | none (atomic index) | 2 (snapshot, commit) | readback only for GPU filters, async |
| Undo/redo | none (snapshot swap) | none | none | 1 | textures already cached by identity |
| Save/autosave | encode buffers on worker | none of the document (snapshot) | none | 1 (`snapshot`) | none |

---

## 3. Windows Distribution

### 3.1 Shape

GitHub Releases hosts a signed **MSI**. The installed app checks a GitHub-hosted **appcast** with **WinSparkle**,
tells the user about a newer version with release notes, and on request downloads the new MSI and runs it; Windows
Installer performs a **major upgrade**; documents and settings are untouched. The updater lives in the application
shell. The Core knows nothing about GitHub, releases, appcasts, MSI, WinSparkle, Windows Installer or update URLs.

### 3.2 MSI (WiX Toolset)

- Built with the current **WiX Toolset** (the `WixToolset.Sdk` MSBuild SDK, version pinned in the repo), a real
  Windows Installer package — never a renamed executable.
- **Scope:** per-machine (`Scope="perMachine"`), installed with one elevation prompt; the application itself runs
  unelevated and never needs administrator rights. (A per-user variant is not offered: switching scopes breaks major
  upgrades between them.)
- **UpgradeCode:** `15737362-8B12-4BF4-8314-16E529A0C200` — fixed for the product's life, shared by x64 and ARM64
  packages. ProductCode is new for every build.
- **Versions:** MSI `ProductVersion` = the marketing version `X.Y.Z` (Windows Installer compares only the first three
  fields; X, Y ≤ 255, Z ≤ 65535). Every Windows release must have a higher marketing version than the last — CI
  refuses to publish otherwise. The build number is the fourth field of the file versions (`X.Y.Z.BUILD`, e.g.
  1.4.5.40), which WinSparkle compares.
- **`MajorUpgrade`**, scheduled `afterInstallInitialize` (the old version is removed before the new one installs;
  nothing of value lives in the install folder), `AllowSameVersionUpgrades="no"`, and a `DowngradeErrorMessage` so an
  older MSI refuses to install over a newer version.
- **Layout:**
  | What | Where |
  |---|---|
  | Application binaries | `%ProgramFiles%\Compositor-KR\` (`ProgramFiles64Folder`), read-only to the app |
  | Settings (small, roams) | `%APPDATA%\Compositor-KR\settings.json` |
  | Caches, autosave/recovery, logs | `%LOCALAPPDATA%\Compositor-KR\` |
  | Documents | wherever the user saves them; the default folder is Documents |
  | WinSparkle's own state | `HKCU\Software\Compositor-KR\Compositor-KR\WinSparkle` |
  The MSI never writes user data and uninstall leaves it. Nothing mutable is written next to the executable.
- **Settings schema:** `settings.json` carries a `schemaVersion`; the app migrates forward on first launch of a new
  version and never deletes unknown keys.
- **Contents:** app, native DLL(s) with static CRT (no VC++ redistributable needed), self-contained .NET and Windows App
  SDK (no prerequisites), WinSparkle.dll, the shipped ICC profiles. Start-menu shortcut; an "Open with
  Compositor-KR" verb for folders named `*.comp` (Q24).
- **ARM64 later:** the same WiX source built per platform (`-arch x64|arm64`), same UpgradeCode, separate MSI per
  architecture, separate feed (§3.3).

### 3.3 Updates (WinSparkle)

- **WinSparkle** (MIT), the Windows sibling of Sparkle, which the macOS app already uses. It supports appcast feeds,
  release notes, skip-this-version and remind-later, automatic background checks, EdDSA-signed updates and MSI
  payloads, which it downloads and launches. No custom updater.
- **Feeds**, one per architecture, committed to `main` next to `appcast.xml` and served from
  `https://raw.githubusercontent.com/songhj0728/Compositor-KR/main/…` exactly like the macOS feed:
  `appcast-windows-x64.xml` now, `appcast-windows-arm64.xml` later. Separate files (rather than one feed with
  per-OS enclosures) keep each updater from ever seeing another platform's payload, and keep the macOS feed unchanged.
- **Items:** `sparkle:version` = `X.Y.Z.BUILD`, `sparkle:shortVersionString` = `X.Y.Z`,
  `sparkle:releaseNotesLink` to the GitHub release, an enclosure pointing at the MSI on the GitHub release with its
  length and `sparkle:edSignature`, and `sparkle:installerArguments="/passive"` so the upgrade shows progress without
  questions.
- **App integration** (application shell only): `win_sparkle_set_appcast_url`, `win_sparkle_set_eddsa_public_key`,
  `win_sparkle_set_app_details` with `X.Y.Z.BUILD`, `win_sparkle_set_automatic_check_for_updates` (on by default,
  daily, user-controllable), a **Check for Updates…** menu item calling `win_sparkle_check_update_with_ui`, and the
  can-shutdown / shutdown-request callbacks: the app asks the user to save open documents, then quits so the
  installer can replace files. The About box shows the version and build.
- **macOS** keeps Sparkle and `appcast.xml`, unchanged.

### 3.4 Code signing

| Step | Local development | Production release (CI) |
|---|---|---|
| Authenticode on our `.exe`/`.dll` | optional (off by default) | **mandatory**, RFC 3161 timestamped |
| Authenticode on the `.msi` | optional | **mandatory**, timestamped |
| Third-party DLLs (WinSparkle, Windows App SDK, .NET) | as shipped by their vendors | as shipped by their vendors (verified signed) |
| EdDSA signature of the MSI in the appcast | not produced | **mandatory**; unsigned items are never published |
| Publishing to Releases / appcast | never | only after all of the above |

- **Authenticode** keys live in a cloud HSM (Azure Artifact Signing / Trusted Signing), reached from GitHub Actions by
  OIDC federation — no long-lived secret in the repo or in Actions. (Since 2023 new code-signing keys must be
  HSM-held, so an exportable PFX isn't an option.) Signing uses `signtool` with the provider's dlib; any HSM-backed
  provider with the same `signtool` interface can replace it.
- **EdDSA** (Ed25519): a **Windows-only** key pair, separate from the macOS Sparkle key, so a leak on one pipeline
  can't sign the other platform's updates. The private key is a GitHub Actions secret (`WINSPARKLE_EDDSA_PRIVATE_KEY`)
  in a protected `release` environment; the public key is compiled into the app. Order: Authenticode-sign the MSI
  first, then EdDSA-sign its final bytes.
- Nothing is hard-coded: certificate identity, endpoint and account names are repository variables; keys are never
  in the repository.
- Dev builds carry a different app identity for WinSparkle (no feed URL), so an unsigned local build can never offer
  or install an update.

### 3.5 CI/CD

A `windows-release.yml` workflow, triggered by a version tag (`vX.Y.Z`) after the macOS release of the same version:

1. **Build** (Windows runner, x64; ARM64 added as a matrix entry later): CMake + MSVC for the native DLL, `dotnet
   publish` (self-contained) for the shell.
2. **Test**: shared C tests, Core tests, C ABI fuzz smoke, differential tests; any failure stops the release.
3. **Package**: WiX builds `Compositor-KR-X.Y.Z-x64.msi`; CI checks the version is higher than the feed's latest.
4. **Sign**: Authenticode on binaries (before packaging) and on the MSI (after); verify with `signtool verify /pa`.
5. **Publish**: upload the MSI to the GitHub Release `vX.Y.Z` (the macOS DMG's release) with `gh release upload`.
6. **Feed**: EdDSA-sign the MSI, write the new item into `appcast-windows-x64.xml`, commit to `main` with a token scoped
   to contents only.

Steps 4–6 run only in the protected `release` environment. Pull requests and branch pushes run 1–3, unsigned.

---

## 4. Windows toolchain and platforms

| | Decision |
|---|---|
| Compiler | MSVC (VS 2022 17.14 or later locally; CI uses the runner image's current Visual Studio). Clang-cl optional for sanitizer coverage. |
| Language modes | C++20 (`/std:c++20 /permissive- /Zc:__cplusplus /utf-8 /W4`), warnings as errors in Core; C11 for kernels (`/std:c11 /utf-8`) |
| Build | CMake presets (`windows-x64-debug/release`, later `windows-arm64-*`); MSBuild/dotnet for the C# shell; WiX SDK for the MSI |
| Runtime | Static CRT (`/MT`) for our native DLLs — valid because no CRT object crosses the C ABI (core-api §7); self-contained .NET 10 and Windows App SDK |
| Windows versions | Windows 10 1809 (17763) or later, as the Windows App SDK requires; Windows 11 primary |
| x64 | primary; SSE2 baseline, AVX2 paths only with runtime dispatch and measurement |
| ARM64 | native ARM64 builds later (not ARM64EC, which exists for mixing with x64 plug-ins we don't have); NEON via the same kernels |
