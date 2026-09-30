# Compositor-KR Architecture

## Status

This document describes the target architecture and the migration strategy. It is intentionally compatible with the current macOS-first implementation and does not claim that all target layers already exist.

## Current state

Compositor-KR is currently a macOS application using Swift, SwiftUI, AppKit, Metal/Core Image, and native pixel-processing code. The existing application is the reference implementation.

The repository also contains established document/project concepts and a versioned .comp project format. The current documented project format is version 11.

## Target structure

```
Compositor-KR/
├── Core/                 # platform-independent application/domain logic
├── Formats/              # PSD, .comp, import/export logic
├── Rendering/
│   ├── API/              # platform-neutral rendering contracts
│   ├── Metal/            # macOS GPU implementation
│   └── Windows/          # Windows GPU implementation
├── Platform/
│   ├── macOS/
│   └── Windows/
├── UI/
│   ├── macOS/
│   └── Windows/
├── Tests/
├── docs/
└── platform/build files
```

This is a target structure, not a requirement to move every existing file immediately.

## Dependency direction

Preferred dependency direction:

```
UI / Platform
      ↓
Rendering API
      ↓
Core
      ↓
pure algorithms / data
```

Format code may depend on Core data structures. Core should not depend on AppKit, SwiftUI, Metal, DirectX, Windows SDKs, or other OS UI frameworks.

When legacy code violates this direction, migrate it incrementally instead of performing a repository-wide rewrite.

## Rendering

The renderer abstraction exists to let the same document/model behavior use different GPU implementations.

Mac:
- Metal/Core Image as appropriate.

Windows:
- DirectX 12 and/or Vulkan after evaluating the actual rendering requirements.
  **Evaluated and decided (2026-09-30): Direct3D 11.1 with Direct2D, DirectWrite and WIC** — see
  [docs/multiplatform/windows-architecture.md](docs/multiplatform/windows-architecture.md) §2.3.

Do not choose a Windows GPU API solely for theoretical portability. Evaluate canvas compositing, filters, effects, masks, brush operations, compute workloads, texture formats, synchronization, memory management, and tablet/input requirements.

## Build products

One repository does not mean one universal binary.

macOS build:
- Shared/core code
- macOS platform/UI code
- Metal/Core Image implementation
- macOS dependencies

Windows build:
- Shared/core code
- Windows platform/UI code
- Windows renderer
- Windows dependencies

Build configuration and target membership must prevent irrelevant platform code and dependencies from being packaged into the other platform's application.

## Migration rule

Do not move a file simply because a new folder looks cleaner. Move or refactor code when doing so establishes a useful boundary, reduces platform coupling, improves testability, or enables the Windows implementation.

## Success criteria

The migration is successful when:
- existing macOS behavior remains stable;
- shared behavior has a clear home independent of OS APIs;
- rendering has a replaceable backend boundary;
- Windows can be added without copying the whole macOS application;
- both builds use the same source-of-truth for document semantics and file formats;
- platform-specific dependencies remain platform-specific;
- automated tests can compare important image-processing results across platforms.
