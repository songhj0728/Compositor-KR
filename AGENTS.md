# Notes for AI agents

Compositor is a macOS image editor for compositing and photo work, written in Swift (SwiftUI and AppKit, with some C for pixel work).

## Designing or editing a Compositor project

If you've been asked to make or change an image in a `.comp` project, you don't need the app's source code. Read [docs/writing-comp-files.md](docs/writing-comp-files.md): it covers the file format, the rules that make a project load, and how to write it safely while it's open, so the person can watch the canvas update as you work.

## Working on the app itself

- Build: open `Compositor.xcodeproj` and run the **Compositor** scheme, or
  `xcodebuild -project Compositor.xcodeproj -scheme Compositor -destination 'platform=macOS' build`.
- Tests: `CompositorTests` target (`xcodebuild ... test -only-testing:CompositorTests`). CI runs on every push.
- The C pixel code in `Compositor/Rendering` is shared with Windows: `CMakeLists.txt` builds and tests it there too
  (see [BUILD.md](BUILD.md)). Keep it plain C11 — no blocks or Grand Central Dispatch; use `ParallelFor.h`.
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

### Main branch synchronization

11. `main` is the continuously developed macOS/reference branch. Do not freeze macOS development while Windows or multiplatform work is in progress.
12. The Windows/multiplatform branch must periodically synchronize with `main`. Do not allow the branches to diverge for a long period and then attempt one large catch-up merge.
13. When synchronizing, preserve the Windows/multiplatform work already completed. Do not discard, reset, or overwrite platform-specific work merely to resolve conflicts.
14. Before resolving a conflict, determine whether the changed code is:
    - shared/core behavior that should converge across platforms,
    - macOS-specific implementation,
    - Windows-specific implementation, or
    - project/build/documentation infrastructure.
15. Shared behavior should normally be reconciled into common code and tests. Platform-specific UI, OS integration, and GPU backend code may remain different.
16. If a `main` change is relevant only to macOS, do not force a Windows equivalent just to keep the branches textually identical.
17. If a `main` change changes shared document semantics, project format, image-processing behavior, or other cross-platform behavior, make an explicit plan for bringing the same semantics to Windows.
18. After synchronization, run the relevant tests/builds for the affected platform(s) and verify that both the macOS reference behavior and Windows work remain intact.
19. Prefer frequent, small synchronization steps over a large periodic rewrite. If synchronization reveals architectural duplication, fix the architecture rather than copying the macOS implementation into Windows.
20. Never merge or rebase `main` into the Windows branch blindly. Inspect the incoming changes, summarize conflicts, and verify the result before considering the synchronization complete.

The current macOS implementation is the reference implementation. Windows support should be added feature-by-feature using the same document semantics and tests, rather than by maintaining a second copy of the application.

The goal is not for the macOS and Windows branches to contain identical code. The goal is for them to share the same product behavior and core semantics wherever practical while keeping platform-specific implementations appropriately separate.
