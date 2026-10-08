# Proteon branding and synchronization validation

Product name: **Proteon**, inspired by Proteus. This task synchronizes main and
changes presentation/packaging only. No Renderer API, mutation boundary, Windows
GPU, internal model rename or final Core language decision is added.

## Scope

- App Info.plist CFBundleName and Debug/Release CFBundleDisplayName are Proteon.
  Localized InfoPlist names are updated; standard App/About presentation derives
  its name from bundle metadata. Mac runtime presentation still needs Verify/manual
  launch confirmation; no custom About window exists to rename.
- Window name, Hide menu/shortcut title, language restart message, PSD conversion
  and project/PSD error wording now use Proteon. Catalog keys/translations are
  renamed without losing entries, including existing stale translations. Korean
  particles are adjusted for Proteon (프로테온).
- Project/layer type **descriptions** are Proteon; UTI identifiers/extensions stay
  unchanged. README identifies the name and keeps original Compositor attribution
  and historical release links. User format/writing document titles use Proteon.
- release.sh prepares `Proteon.app` and `dist/Proteon-<version>.dmg`, while archive
  output and executable remain Compositor-KR. The exported bundle is renamed for
  packaging; launch smoke check still invokes its real internal executable.
- publish.sh uses Proteon for release title/default notes/feed channel. Public
  asset remains **Compositor-KR.dmg**, preserving existing download links. Existing
  appcast changes **channel title only**; item URL, signature, length, date, build
  and version are unchanged. This explicitly requested display-only edit does not
  publish a new release or alter the protected update channel.

Intentionally unchanged: repository/branch names, source folders, Swift module
Compositor, CompositorApp/delegate/types, Xcode scheme/targets/CompositorTests,
built app/executable Compositor-KR, bundle identifiers, persisted UserDefaults and
.comp keys/UUIDs, UTI identifiers, Sparkle feed URL/public key, signing identities,
notary profile/cache path, existing release assets and historical audit baselines.
Internal symbols are not a second product brand to expose to users.

Version/build are main's **1.4.5(E)/45**, not a new release number. .comp current13
comes from main's optional layer locks; readers and lowest-required save rules
11/12/13 are preserved. The branding commit changes only one ProjectStore error
string and a format-document title; it changes no serializer or persisted values.
Older readers' rejection of unsupported v13 locks is preserved compatibility
behavior, not a claim that every old version reads v13.

## Executed local checks (Linux x86_64)

| Check | Actual result |
|---|---|
| Shared C Release CMake / CTest | pixels and portable_style: 2/2 pass; also saved setup's OpenMP variant passes |
| PortableCore Swift 6.2.1 | inherited locks/cycles/toggles, bevel cap/symmetry, circular Euclidean oracle, cancellation/narrow geometry, profiles/lighting, smooth/shadow checks pass |
| Portable style C | distance and finite-support blur harness passes optimized and ASan/UBSan |
| CoreBoundary | 3 groups pass optimized and ASan/UBSan |
| RenderSnapshot | 4 groups + 5 Python transport tests pass; sanitizer pass; measurement completes through 10,000 nodes |
| RenderResources | freeze/share/replacement/stale/lifetime/readers/provenance/overflow pass optimized and ASan/UBSan |
| Model boundary | All seven declarations/experiment headers pass; Swift Core files/FilterKind/TextAlignment standalone typecheck passes |
| Original CoreModel branch extracted to /tmp | Swift 18 XCTest cases pass; C++ core + host on C++ + host on Swift: 3/3 CTest pass; original boundary guard passes |
| Branding static preservation | Catalog entry count/translations, UTI/extensions, feed/signing keys, entire feed item, module/bundle/version/test-host values and serializer code preservation pass |
| Infrastructure | zsh -n for release/publish, YAML merged steps/serial scheduling, documentation links and git whitespace checks pass |

The CoreModel branch is unmodified and unmerged at e3bf3868; only source extraction
and Linux builds were used. WindowsAPIDemo built as a Linux stub is **not** a
Windows API execution result. WinUI/C# Windows, Windows Swift runtime, MSVC and
native macOS tests were not run locally. ASan/UBSan is not ThreadSanitizer proof.
An existing AdjustPixels indentation warning was left untouched.

Official Swift 6.2.1 Linux archive was signature-verified and installed outside the
checkout for portable validation. Default cache paths were read-only; writable
/tmp module/SwiftPM cache paths resolve that. The pure harness requires `-Xlinker
-lm` on this Linux toolchain. These are environment adjustments, not product
changes. Reusable environment installation/start instructions were prepared outside the
checkout. Configuration-draft saving returned stale_base (the environment changed
since the draft was created); persistence is unconfirmed. The complete proposal
is retained as /workspace/tooling/proteon-setup-proposal.json for transfer to a new
setup chat; no retry of the unchanged stale draft was made.
This installation supersedes earlier audit statements that Swift was unavailable;
Linux still has no Xcode/AppKit or Windows runtime.

## Final CI verification

For the final pushed SHA, check GitHub Actions **Verify → unit**:
`Check model boundary`, `Check render projection experiment`,
`Check render resource ownership experiment`, `Test portable core rules`,
`Build for testing`, `Run unit tests in parallel`, and
`Run window and preview tests serially`. The latter includes LayerStyleTests.
All new Mac read/projection tests remain included in CompositorTests by synchronized
membership/test-only bridging header. No app target executes the experiments.

Also check **Shared code → shared (windows-latest)** and **shared (macos-26)**,
including new portable_style. This task did not repeat previously Forbidden
Actions API calls; no final-SHA CI success is claimed. Release archive/notarization,
Sparkle upgrade from an existing installation, standard About/menu name, Finder
localized display and Proteon DMG installation need Mac release validation before
an actual authorized release. No release/publish script was executed.

See [main reconciliation](main-sync-2026-10-08.md) for category inventory,
conflicts and Renderer API/Windows GPU blockers. The completed sync removes the
main-freshness blocker; coherent product publication ownership, frozen native
resources/color, quality provenance and green final Mac CI remain required.
