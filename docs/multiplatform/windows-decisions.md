# Windows: open decisions

Phase 4 of [MULTIPLATFORM_MIGRATION.md](../../MULTIPLATFORM_MIGRATION.md) asks for these to be evaluated, not assumed.
None is decided yet. Each lists the options, what they cost, and a suggestion; the project owner makes the call, and
the answer is recorded here.

## 1. What language the Windows app's shared logic is in

Most of Compositor's behavior — the document model, layers, masks, PSD and `.comp` reading and writing — is Swift.

| Option | What it means | Cost |
|---|---|---|
| **A. Swift on Windows** | The Swift toolchain runs on Windows. The shared Swift code compiles for both; each platform adds its own UI and renderer. | Apple-only APIs (`CGImage`, Core Image, ImageIO) must move behind boundaries first — the steps in [inventory.md](inventory.md). Windows tooling for Swift is younger than Xcode. |
| B. C++ Windows app | A C++ app that shares only the C pixel code. | The Swift document model, PSD and `.comp` code would be written a second time and kept in sync by hand — the "second copy" AGENTS.md rules out. |
| C. One cross-platform UI for both | Qt, Flutter or similar, for macOS as well. | Replaces the working macOS UI, against the migration's rules. |

**Suggestion: A.** It's the only option where one copy of the document semantics serves both apps.

## 2. The Windows UI toolkit (with option A)

| Option | Notes |
|---|---|
| WinUI 3 through Swift/WinRT bindings | Native Windows look and input (pen, touch, high DPI). Bindings exist and have shipped in a large app (Arc for Windows), but are a smaller ecosystem. |
| Win32 + a thin custom UI | Full control, most work. |
| Qt, called from Swift through C++ interop | Mature widgets and tablet input; a large dependency; not native-looking. |

**Suggestion:** a small WinUI 3 prototype (open a `.comp`, show the canvas, pan/zoom) before committing.

## 3. The Windows GPU backend

The macOS app uses Metal for the canvas, brush coverage, layer effects and warp, and Core Image for most filters.

| Option | Notes |
|---|---|
| Direct3D 12 | Native, best drivers and debugging tools on Windows, compute shaders for filters. |
| Vulkan | Portable, but macOS keeps Metal either way, so the portability buys little here. |
| Direct3D 11 | Simpler; enough for a canvas, weaker for heavy compute. |

**Suggestion:** Direct3D 12, decided once the renderer contract (`Rendering/API`) exists and shows what it needs.

## 4. Replacing Core Image's filters

About 75 uses of `CIFilter`/`CIImage` across 20 files have no Windows equivalent. Each filter the app uses needs a
Windows implementation (compute shader or C), checked against the macOS output with golden tests and documented
tolerances. This is the largest piece of Windows work and should be planned filter by filter.

## 5. Features that rely on Apple frameworks

- **Object Selection and subject removal** use Vision. Options: an ONNX segmentation model on Windows, or ship Windows
  without them at first. A product decision.
- **Updates** use Sparkle. Windows needs its own (WinSparkle, MSIX with App Installer, or similar).
- **Packaging and signing:** MSIX or a classic installer; a code-signing certificate for Windows.
