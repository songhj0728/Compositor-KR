# Windows: decisions

Phase 4 of [MULTIPLATFORM_MIGRATION.md](../../MULTIPLATFORM_MIGRATION.md) asked for these to be evaluated, not
assumed. They are now **decided** (2026-09-30, baseline 1.4.5); the full reasoning is in
[windows-architecture.md](windows-architecture.md) and, question by question, in
[architecture-questions.md](architecture-questions.md). This page keeps the short record, including where an earlier
suggestion on this page was revised and why.

## 1. The language of the shared logic — **C++20 Core, C11 kernels, C ABI**

Earlier suggestion here: Swift on Windows, to reuse the Swift model. **Revised** after the spike
([spike-findings.md](spike-findings.md)) was weighed against the project's priorities, Windows performance first:
C++ has no runtime to ship, explicit allocation and copying, and first-class Windows tooling (MSVC, debugger, PIX,
sanitizers, ARM64); Swift's advantages — memory safety and the existing model — are answered with fail-fast rules,
hardened standard libraries, sanitizers, fuzzing, and differential tests against the Swift model during the port. The
pixel kernels stay C; the macOS UI and renderer stay Swift. (windows-architecture §1, Q11)

## 2. The Windows UI toolkit — **WinUI 3 with a C# shell, confirmed by the Wave 1 prototype**

Stable Windows App SDK only, self-contained, component packages only. The canvas is native (Direct3D 11 in a
`SwapChainPanel`), so the UI language doesn't limit canvas performance. Final once the Wave 1 prototype meets the
canvas targets; the fallback is a Win32 host with C++/WinRT, with no Core or renderer change. (Q17, Q18, Q19)

## 3. The Windows GPU backend — **Direct3D 11.1 + Direct2D + DirectWrite + WIC**

Earlier suggestion here: Direct3D 12. **Revised**: the editor renders a few passes per frame on one queue, where D3D12's
explicit memory and synchronization cost code without saving CPU, and Direct2D/DirectWrite interoperate natively only
with D3D11. D3D11 has the compute shaders the filters and effects need. (windows-architecture §2.3, Q20)

## 4. Replacing Core Image's filters — **HLSL compute/pixel shaders matched by golden images**

Each Core Image filter the app uses gets an HLSL implementation on Windows, checked against the macOS output (Wave 0
reference images) with documented tolerances. Kernels that exist in the shared C code are used on both platforms
instead of being duplicated. Compositing stays in the document's encoded color space, as macOS does it.

## 5. Features that rely on Apple frameworks

| Feature | Windows |
|---|---|
| Object Selection, Subject Removal (Vision) | ONNX Runtime with DirectML (CPU fallback) and a permissively licensed model, behind a `SubjectSegmenter` interface; after editing parity; hidden until then (Q21) |
| Updates (Sparkle) | WinSparkle with a per-architecture appcast on GitHub, MSI payloads, EdDSA-signed (windows-architecture §3.3) |
| Packaging and signing | WiX MSI, per-machine, `MajorUpgrade`, UpgradeCode `15737362-8B12-4BF4-8314-16E529A0C200`; Authenticode through a cloud HSM from GitHub Actions (windows-architecture §3.2, §3.4) |
| Color management (ColorSync) | LittleCMS 2 with the macOS ICC profiles shipped identically (Q10) |
| Text (Core Text) | DirectWrite (Q9) |
| Document packages (`.comp` folders) | Opened as folders; shell verb for `*.comp` folders; no format change (Q24) |
