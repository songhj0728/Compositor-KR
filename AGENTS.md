# AI Agent Instructions

## Project

Compositor-KR is an open-source image editor derived from the original Compositor project by robbietilton. The current application is macOS-first and uses Swift, SwiftUI, AppKit, Core Image/Metal, and C/C-based pixel-processing code. The long-term product goal is a professional Photoshop alternative for macOS and Windows.

These instructions are vendor-neutral. They apply to Claude Code, Codex, Gemini, Copilot, Cursor, or any other coding agent.

## Non-negotiable principles

1. Preserve working behavior unless the task explicitly requires a behavior change.
2. Do not rewrite the whole application merely to make it cross-platform.
3. Do not replace Swift, Metal, or the current rendering/image-processing implementation wholesale without an explicit migration plan and approval.
4. Prefer incremental, reversible changes.
5. Before a structural change, inspect the current implementation and explain the affected files and risks.
6. Keep macOS builds working while Windows support is being introduced.
7. New platform-independent behavior belongs in shared/core code whenever practical.
8. OS-specific UI, windowing, filesystem integration, input APIs, and GPU backends belong behind platform boundaries.
9. Do not add Windows-only dependencies to the macOS application target.
10. Do not add macOS-only dependencies to the Windows application target.
11. Do not change the .comp project format without updating docs/project-format.md, the format version when required, validation, and round-trip tests.
12. Do not silently delete, disable, or replace existing features.

## Current implementation

The repository is currently a macOS application. The existing architecture already contains document/model, project/file format, rendering, UI, and native pixel-processing concerns. Treat the existing code as the reference implementation and migrate it gradually.

The project format is currently documented through version 11. Preserve backward compatibility unless a deliberate format migration is approved.

For .comp project authoring, read docs/writing-comp-files.md first.

## Target architecture

The desired end state is conceptually:

Shared Core
- document model
- layers/groups
- masks and selections
- history/undo
- adjustments/effects
- image data and algorithms
- project/PSD format logic
- platform-neutral math and validation

Rendering abstraction
- renderer interface/API
- macOS Metal/Core Image backend
- Windows GPU backend (DirectX 12 and/or Vulkan; decide based on measured requirements)

Platform layer
- macOS
- Windows

UI layer
- macOS
- Windows

The repository remains one source tree. Platform-specific implementations coexist in source control but are selected at build time. A macOS app package must not contain unused Windows implementation binaries/dependencies, and a Windows build must not require macOS frameworks.

## Development workflow

1. Read AGENTS.md and the relevant docs.
2. Inspect the current code before editing.
3. Identify whether the change is Core, Rendering, Platform, UI, Format, or Test work.
4. Make the smallest coherent change.
5. Build and test the affected target.
6. Check for regressions.
7. Report what changed, why, how it was verified, and any remaining risks.

## Build

Current macOS development remains Xcode/xcodebuild based. Do not remove the existing Xcode workflow.

When Windows development begins, introduce a reproducible Windows build workflow, preferably with CMake where it provides real value. CMake is a future cross-platform build layer, not a reason to rewrite the existing project today.

## Testing

Prefer deterministic tests. For image-processing and rendering behavior, build toward golden-image/reference-output tests so that macOS and Windows implementations can be compared within documented tolerances.

## Style

Match surrounding code style and naming. Use American English in code, comments, and UI text.

## AI safety rules

Never make a large architecture migration in one unreviewed step. For a migration, first produce a file-level plan, then execute it in small batches. Keep commits logically separated where practical so changes can be reviewed or reverted.

If a request conflicts with this file, protect existing functionality and explain the conflict before making a destructive change.
