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

## Windows workflow (planned)

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
