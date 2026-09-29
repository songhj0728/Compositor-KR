# Notes for AI agents

Compositor is a macOS image editor for compositing and photo work, written in Swift (SwiftUI and AppKit, with some C for pixel work).

## Designing or editing a Compositor project

If you've been asked to make or change an image in a `.comp` project, you don't need the app's source code. Read [docs/writing-comp-files.md](docs/writing-comp-files.md): it covers the file format, the rules that make a project load, and how to write it safely while it's open, so the person can watch the canvas update as you work.

## Working on the app itself

- Build: open `Compositor.xcodeproj` and run the **Compositor** scheme, or
  `xcodebuild -project Compositor.xcodeproj -scheme Compositor -destination 'platform=macOS' build`.
- Tests: `CompositorTests` target (`xcodebuild ... test -only-testing:CompositorTests`). CI runs on every push.
- The C pixel code in `Compositor/Rendering` is shared with Windows: `CMakeLists.txt` builds and tests it there too
  (see [BUILD.md](BUILD.md)). Keep it plain C11 — no blocks or Grand Central Dispatch; use `PixelParallel.h`.
- Match the surrounding code: its naming, its comment style and density.
- American spelling in code, comments and UI ("color", not "colour").
- The project file format is described in [docs/project-format.md](docs/project-format.md). A change to what's saved means a format version bump there and in `ProjectManifest.current`.

## Multiplatform development

The long-term product goal is a professional Photoshop alternative for macOS and Windows.

These repository instructions are vendor-neutral and apply to Claude Code, Codex, Gemini, Copilot, Cursor, or any other coding agent. Follow the detailed rules in `ARCHITECTURE.md`, `BUILD.md`, `MULTIPLATFORM_MIGRATION.md`, and `AI_AGENT_GUIDE.md`.

### Non-negotiable rules

1. Preserve working behavior unless the requested change requires otherwise.
2. Do not rewrite the whole application just to make it cross-platform.
3. Keep macOS working throughout the migration.
4. Put platform-independent behavior in shared/core code when practical.
5. Isolate OS-specific UI/services and GPU backends.
6. Do not add Windows-only dependencies to macOS targets or macOS-only dependencies to Windows targets.
7. Do not change the `.comp` format without updating its documentation, validation, versioning when required, and tests.
8. Prefer small, reversible changes and inspect the code before editing.
9. For architecture migrations, plan first and execute in reviewable steps.
10. Do not silently remove or replace existing features.

The current macOS implementation is the reference implementation. Windows support should be added feature-by-feature using the same document semantics and tests, rather than by maintaining a second copy of the application.
