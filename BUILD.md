# Build and Development

## Current macOS workflow

The current supported development environment is macOS with Xcode. Keep the existing Xcode project and scheme working while the architecture evolves.

The repository's existing AI instructions document the current xcodebuild commands. Agents should inspect the current project before assuming an exact project filename or target name.

Typical workflow:

```bash
xcodebuild -project <current-project>.xcodeproj -scheme <current-scheme> -destination 'platform=macOS' build
```

Tests:

```bash
xcodebuild -project <current-project>.xcodeproj -scheme <current-scheme> -destination 'platform=macOS' test
```

Use the actual project/scheme discovered in the checkout rather than copying stale command examples.

## Shared code (Windows and macOS)

`CMakeLists.txt` builds the code both apps share — today the C pixel algorithms in `Compositor/Rendering` — and its
tests in `Tests/`. It reads the same source files the Xcode project compiles; it does not build the macOS app.

On Windows (Visual Studio 2022 or its Build Tools, with CMake) or macOS (Xcode command-line tools and CMake):

```bash
cmake -S . -B build
cmake --build build --config Release
ctest --test-dir build --build-config Release --output-on-failure
```

CI runs this on Windows and macOS for every push (`.github/workflows/shared.yml`), next to the Xcode build and tests
(`.github/workflows/verify.yml`).

Rules for the shared C code: plain C11 that MSVC and Clang both compile — no Clang blocks (`^{ }`), no Grand Central
Dispatch, no Apple headers. Use `parallel_for` (`Compositor/Rendering/ParallelFor.h`) to spread work over the cores:
GCD on macOS, the system thread pool on Windows (`Platform/Windows/ParallelForWin32.c`). The test build compiles the
same sources with `PARALLEL_FOR_TESTING`, so the tests can compare threaded results with one thread's.

## Windows app workflow (planned)

Product language/toolchain, packaging and GPU choices remain open. The existing
shared-C workflow above is implemented; the separate `spike/core-model` branch
contains reproducible experimental Swift/C++/WinUI build commands, not a product
Windows app. See [repository evidence](docs/multiplatform/repository-evidence.md)
and [Windows boundary](docs/multiplatform/windows-architecture.md).

Windows support is not a reason to discard the current Xcode workflow.

When Windows implementation begins, establish:
- Visual Studio/MSVC or another supported Windows compiler toolchain;
- Windows SDK;
- CMake if useful as the shared build-generation layer;
- reproducible configure/build/test commands;
- CI coverage for the Windows target.

The Windows build should consume the same repository and shared core, but select Windows UI/platform/rendering implementations.

## Packaging

Platform packaging is separate.

macOS:
- build the macOS target;
- package only macOS resources, frameworks, and backends;
- sign/notarize according to the existing release process.

Windows:
- build the Windows target;
- package only Windows resources, runtimes, and backends.

Source files existing in the repository do not automatically become part of an application bundle. Target membership, compilation conditions, link dependencies, and packaging configuration determine what ships.

## CI direction

The long-term CI pipeline should have independent jobs for:
- macOS build/test
- Windows build/test

and shared tests where practical.

Image-processing reference tests should run on both platforms with documented numeric/image tolerances.
