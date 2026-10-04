# Notes for AI agents

Compositor is a macOS image editor for compositing and photo work, written in Swift (SwiftUI and AppKit, with some C for pixel work).

## Compositor-KR fork: read this first

This repository is **Compositor-KR** (github.com/songhj0728/Compositor-KR), a Korean fork of robbietilton/Compositor ("upstream"). The rules in this section override anything below. When a request seems to need one of the things listed under "Never", stop and ask the owner instead.

### Never

- **Never sync the fork from upstream in a way that replaces history**: no GitHub "Sync fork ▸ Discard commits", no `git reset --hard upstream/main`, no force-push to `main`. If `origin/main` suddenly contains only upstream's history, stop and ask; the fork's work has to be restored from a local clone.
- **Never commit secrets**: GitHub tokens, the Sparkle private signing key (it lives only in the owner's login keychain), certificates, `.env`. Release scripts get `GITHUB_TOKEN` from `git credential fill` at run time; don't write it to a file or print it.
- **Don't touch the update channel**, except through the release scripts:
  - `Config/Info.plist`: `SUFeedURL` and `SUPublicEDKey`. Changing either cuts every installed copy off from updates.
  - `appcast.xml`: only `scripts/publish.sh` writes it.
  - `PRODUCT_BUNDLE_IDENTIFIER` values in the project file.
- **Don't lower or reuse version numbers.**
  - `MARKETING_VERSION` follows upstream's number. While upstream's number stays the same, each fork release adds a letter: 1.4.5, 1.4.5(A), 1.4.5(B)… When upstream moves to a new number, the version follows it and the letters start over. Never go above upstream's latest release.
  - `CURRENT_PROJECT_VERSION` goes up by exactly one per published release; Sparkle and `publish.sh` rely on it.
  - Only change versions when the owner asks for a release.
- **Don't publish releases** (`scripts/release.sh`, `scripts/publish.sh`, GitHub Releases) unless the owner asks for one in this conversation.
- **Don't break saved projects.**
  - `ProjectManifest.current` / `compatible` and `neededVersion` in `Compositor/IO/ProjectStore.swift`: a project is saved at the lowest format version that can hold it.
  - New fields are optional and additive. Never renumber, repurpose or remove an existing field or version.
  - Update `docs/project-format.md` alongside.
- **Don't delete or machine-overwrite Korean translations** in `Compositor/Localizable.xcstrings` / `InfoPlist.xcstrings`. Keys marked `stale` by Xcode are often still used through `String(localized: String.LocalizationValue(variable))`, so keep them.

### Fork features to protect when merging upstream or refactoring

- Filter ▸ Liquify dialog (it is not a Smear mode).
- The Smudge/Smear tool with diffusion blur (`smear_blur_dab`) and its Radius control.
- PSD import/export, including the embedded ICC profile (resource 1039) in both directions.
- New Canvas presets, background color and color profiles. The project's working color space is `WorkingColorSpace` in `Document/ColorProfile.swift`: don't hardcode sRGB for layer pixels or effects; use the layer image's own RGB space.
- Korean localization and keyboard shortcuts that work on a Korean input source (`NSEvent.shortcutCharacters`).
- The two-level font picker (family, then weight), the outside shape stroke, layer lock (`Core/LayerLockRules.swift`), Move-tool auto-select/deselect, the bevel kernels (`Core/BevelGeometry.swift`, `Core/StylePixels.c`), and the clipping-mask arrow symbol in the layer list.
- `ColorProfileRoundTripTests` and the other fork tests: fix the code, not the test, unless the owner agrees the behavior should change.

### How to work here

- **Project and tests.** The project is `Compositor-KR.xcodeproj` (scheme **Compositor**), not `Compositor.xcodeproj` as written further down.
  - CI runs `LayerStyleTests`, `FloatingPanelTests` and `SliderSnapTests` serially, after the parallel run. Locally they can time out when run in parallel with everything else; rerun them alone before calling them broken.
  - Tests must pass in both English and Korean system languages. Compare menu titles with `String(localized:)`, not English literals.
- **Branches.** Work on a branch (`claude/…`, `codex/…`, and so on) and open a pull request. Push to `main` only when the owner asks.
- **Upstream merges.**
  - Three-way merge each upstream release (`git merge-file`, with the previous upstream tag as the base). Take only what's needed, and keep the fork features above.
  - Leave upstream-owned files as close to upstream as possible; put fork code in its own files or clearly marked sections, so later merges stay clean.
- **Windows port in mind.**
  - Platform-neutral logic (Foundation / plain C) goes first in a file or in `Compositor/Core`, with an "Apple platform layer" section below it.
  - Fork C kernels use `Rendering/ParallelFor.h` (no blocks) and `ptrdiff_t`, not `long`. `Tests/PortableCore` checks them in CI.
  - See `docs/windows-patch-contract.md`.
- **Legal (the app may be sold later).**
  - Don't copy Adobe's (or anyone's) icons, artwork or documentation text.
  - Use generic or descriptive names, and system symbols for UI icons.
  - Photoshop file-format interoperability is fine.
- **Repository hygiene.** Scratch files in the repo root (`patch*.swift`, `*.diff`, `diff_*.txt`) are the owner's working notes. Don't commit, edit or delete them.
- **Language.** Reply to the owner in Korean. Code, comments and commit messages stay in English (American spelling).

## Designing or editing a Compositor project

If you've been asked to make or change an image in a `.comp` project, you don't need the app's source code. Read [docs/writing-comp-files.md](docs/writing-comp-files.md): it covers the file format, the rules that make a project load, and how to write it safely while it's open, so the person can watch the canvas update as you work.

## Working on the app itself

- Build: open `Compositor.xcodeproj` and run the **Compositor** scheme, or `xcodebuild -project Compositor.xcodeproj -scheme Compositor -destination 'platform=macOS' build`.
- Tests: the `CompositorTests` target (`xcodebuild ... test -only-testing:CompositorTests`). CI runs these on every push.
- Match the surrounding code: its naming, its comment style and density.
- American spelling in code, comments and UI ("color", not "colour").
- The project file format is described in [docs/project-format.md](docs/project-format.md). A change to what's saved means a format version bump there and in `ProjectManifest.current`.

## Windows portability

- Keep new document rules and pixel algorithms independent of AppKit, SwiftUI, Core Graphics, Metal and Windows UI/GPU APIs whenever practical. `Compositor/Core` holds small pure algorithms; existing platform sessions/renderers adapt them.
- Keep macOS working. Do not rewrite the app or choose a Windows UI/GPU/Core language as part of an unrelated feature patch.
- Document shared behavior and project-format changes with tests that a Windows implementation can reproduce. Preserve work on `Compositor-Multiplatform` when synchronizing it; inspect conflicts before merging.
