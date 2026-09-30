# Multiplatform Migration Plan

## Goal

Evolve the existing macOS application into a macOS + Windows product without throwing away the working application.

## Status

- Phase 0: the branch carries Compositor-KR 1.4.5 (build 40) from main (synchronized per AGENTS.md rules 11–20). macOS build and tests run in CI (`verify.yml`).
- Phase 1: done — [docs/multiplatform/inventory.md](docs/multiplatform/inventory.md).
- Phase 2: first boundary — the C pixel code no longer depends on Grand Central Dispatch (`ParallelFor.h`, from main 1.4.5, with a Windows thread-pool path added here).
- Phase 4: first foundation — `CMakeLists.txt` builds and tests the C pixel code on Windows and macOS
  (`shared.yml`). The Windows app itself waits on [docs/multiplatform/windows-decisions.md](docs/multiplatform/windows-decisions.md).
- Phase 2, document model: Core API contract in [docs/core-api.md](docs/core-api.md); inventory, A–E classification and file-by-file plan in [docs/multiplatform/document-model-inventory.md](docs/multiplatform/document-model-inventory.md), order in [migration-dependency-map.md](docs/multiplatform/migration-dependency-map.md), open decisions in [architecture-questions.md](docs/multiplatform/architecture-questions.md). Nothing moved yet.
- Phase 4, decisions: made — C++20 Core, Direct3D 11.1 renderer, DirectWrite, LittleCMS, WiX MSI + WinSparkle
  ([docs/multiplatform/windows-architecture.md](docs/multiplatform/windows-architecture.md)); next work in
  [docs/multiplatform/implementation-plan.md](docs/multiplatform/implementation-plan.md) (Wave 0, not started).
- Phase 6: golden tests exist for Liquify and Smear (`Tests/Pixels`); the other algorithms still need them (Wave 0.1).

## Phase 0 — Baseline

- Keep main stable.
- Work on a dedicated migration branch.
- Record the current macOS build and test status.
- Do not change behavior during the baseline audit.

## Phase 1 — Architecture inventory

Classify existing files by responsibility:

- Core/domain
- Formats/IO
- Rendering
- macOS platform
- UI
- Tests
- native C/C pixel algorithms

Do not move files solely for aesthetics. Record platform dependencies and important call relationships first.

## Phase 2 — Establish boundaries

Create explicit boundaries where they provide value:
- shared document/model APIs;
- rendering contracts;
- platform services;
- testable image-processing APIs.

Prefer adapters around legacy code before rewriting it.

## Phase 3 — Mac reference stability

For every migrated area:
- keep the macOS implementation functional;
- add tests;
- compare output against the pre-migration behavior.

## Phase 4 — Windows foundations

Add Windows platform/build scaffolding without changing macOS behavior.

Evaluate:
- UI framework;
- GPU backend;
- image/compute interoperability;
- filesystem and clipboard services;
- keyboard/mouse/tablet input;
- color management;
- high-DPI/multi-monitor behavior.

Do not lock in a technology merely because it was suggested in an earlier conversation.

## Phase 5 — Shared feature parity

Implement Windows support feature-by-feature using the same document semantics and test cases.

Priority should be determined by product requirements and technical dependencies, not by convenience.

## Phase 6 — Cross-platform verification

Build golden/reference tests for:
- blend modes;
- masks;
- selections;
- adjustments;
- filters;
- transforms;
- brush behavior;
- layer effects;
- import/export.

Document expected tolerances where GPU implementations can differ numerically.

## What not to do

- Do not rewrite all Swift code into C++/Rust just to become cross-platform.
- Do not replace Metal before a Windows renderer boundary is needed.
- Do not create a second independent copy of the application.
- Do not fork the feature logic into permanently divergent Mac and Windows implementations.
- Do not break the existing .comp format casually.
- Do not remove existing features during architecture work.

## Definition of done for the migration

A feature is considered cross-platform-ready when its behavior is defined in shared/testable terms and its platform-specific implementation is isolated behind a clear boundary.
