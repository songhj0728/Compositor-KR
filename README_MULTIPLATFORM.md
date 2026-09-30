# Multiplatform Development

## Multiplatform development

The long-term direction of Compositor-KR is a shared macOS + Windows codebase while preserving the existing macOS application.

This repository uses vendor-neutral AI development instructions:
- [AGENTS.md](AGENTS.md) — repository-wide rules
- [ARCHITECTURE.md](ARCHITECTURE.md) — target architecture and dependency boundaries
- [BUILD.md](BUILD.md) — build strategy for macOS and planned Windows support
- [MULTIPLATFORM_MIGRATION.md](MULTIPLATFORM_MIGRATION.md) — incremental migration plan
- [AI_AGENT_GUIDE.md](AI_AGENT_GUIDE.md) — instructions for any AI coding agent
- [CLAUDE.md](CLAUDE.md) and [CODEX.md](CODEX.md) — compatibility entry points for specific agents
- [docs/multiplatform/inventory.md](docs/multiplatform/inventory.md) — what the code depends on today and what is shared
- [docs/multiplatform/windows-architecture.md](docs/multiplatform/windows-architecture.md) — final Windows architecture: Core language, performance, renderer, text, color, distribution
- [docs/multiplatform/implementation-plan.md](docs/multiplatform/implementation-plan.md) — Wave 0 / Wave 1 and the gates before model migration
- [docs/multiplatform/windows-decisions.md](docs/multiplatform/windows-decisions.md) — the short record of the Windows decisions
- [docs/core-api.md](docs/core-api.md) — the Core API contract: what macOS and Windows would share, language-neutral
- [docs/multiplatform/document-model-inventory.md](docs/multiplatform/document-model-inventory.md) — the document model's types, dependencies and file-by-file migration plan
- [docs/multiplatform/migration-dependency-map.md](docs/multiplatform/migration-dependency-map.md) — what must move before what
- [docs/multiplatform/architecture-questions.md](docs/multiplatform/architecture-questions.md) — every architecture question and its decision
- [docs/multiplatform/spike-findings.md](docs/multiplatform/spike-findings.md) — findings from the Core-language spike and WinUI 3 test

The documents describe the target architecture; they do not imply that every target directory or Windows implementation already exists.

Use `README.md` for the product and current feature documentation. Use the documents above for architecture and AI-assisted development.
