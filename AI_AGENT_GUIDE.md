# AI Agent Guide

This file is for any AI coding agent working on Compositor-KR.

## Read first

1. AGENTS.md
2. ARCHITECTURE.md
3. BUILD.md
4. docs/project-format.md when changing persistence
5. docs/writing-comp-files.md when changing .comp project authoring

## How to work

Before changing code:
- inspect the relevant files and call graph;
- identify the owning architectural layer;
- check existing tests;
- state the smallest safe change.

After changing code:
- build the affected target;
- run relevant tests;
- inspect the diff;
- report verification and remaining risks.

## Cross-platform rule

The source repository is shared. The shipped applications are platform-specific.

Do not solve cross-platform support by duplicating the whole application. Share document semantics, data structures, algorithms, and file-format behavior where practical. Isolate OS UI, OS services, and GPU implementations.

## Change management

Prefer small, reversible commits. Avoid unrelated formatting changes. Never hide a migration behind a large automated rewrite.

If an architectural decision is uncertain, preserve the existing behavior and document the decision point rather than guessing.

## User-facing communication

The project owner is product-focused rather than a low-level programmer. Explain architecture and risk in plain language. Do not assume approval for destructive rewrites.

## Vendor neutrality

No tool or company is authoritative over this repository. These files are the source of project-specific rules. Agents may add vendor-specific helper files, but they must not contradict AGENTS.md or the documented architecture.
