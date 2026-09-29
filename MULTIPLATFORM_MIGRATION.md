# Multiplatform Migration Plan

## Goal

Evolve the existing macOS application into a macOS + Windows product without throwing away the working application.

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
