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
- [docs/multiplatform/windows-decisions.md](docs/multiplatform/windows-decisions.md) — Windows choices still to be made

The documents describe the target architecture; they do not imply that every target directory or Windows implementation already exists.

Use `README.md` for the product and current feature documentation. Use the documents above for architecture and AI-assisted development.
