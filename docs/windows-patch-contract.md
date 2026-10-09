# Shared behavior for the Move, bevel and layer-lock patch

The current product remains the macOS reference. This patch does not choose the
Windows UI, GPU API or final Core language, and does not merge or overwrite the
existing `Compositor-Multiplatform` branch.

`Compositor/Core/BevelGeometry.swift` and `LayerLockRules.swift` use only the Swift
standard library. The macOS document and render adapters supply image coverage,
layer identities and parent links. No `CGImage`, `CGSize`, native event, view,
GPU resource or platform queue crosses these algorithm boundaries.

Run the portable tests with:

```
swiftc Compositor/Core/BevelGeometry.swift Compositor/Core/LayerLockRules.swift Tests/PortableCore/main.swift -o /tmp/compositor-core-tests
/tmp/compositor-core-tests
```

The same sources and harness are suitable for a Swift Windows toolchain. This
patch has been tested on macOS; a Windows build has not been executed. If the
final Core uses another language, preserve these semantics and fixtures rather
than copying the platform render/session code.

## Semantics to preserve when synchronizing the multiplatform branch

- Move Auto Select defaults on. With it enabled, clicking empty canvas clears
  selection; clicking another visible layer selects that layer. The alternate
  modifier temporarily toggles Auto Select; additive selection remains a separate
  input intent. Map Windows modifiers at the input adapter, not in Core.
- Locked layers remain selectable. Editing, painting, transform, opacity and
  destructive layer commands are disabled. A locked ancestor locks descendants.
  A multi-selection toggle locks all if any selected layer is unlocked; otherwise
  it unlocks all. History restores the flag.
- The `.comp` field is optional Boolean `isLocked`, default false. A project with
  any lock saves as version 13; Layer Style without locks saves as 12, other
  unlocked projects as 11. Files claiming versions below 13 cannot contain true
  locks. Readers through version 12 reject version 13 instead of losing locks.
- Bevel size is limited to one quarter of the true layer's shortest side, with a
  one-pixel minimum cap. Requested zero remains zero. Effect padding and dirty
  window size must not change that cap.
- Height slopes follow exact Euclidean distance to opposite coverage (coverage >=
  0.5 is inside). Two separable squared-distance transforms run in linear time;
  distance is sqrt(squaredDistance) - 1 + abs(coverage - 0.5), minimum 0.01.
  This avoids directional facets around circular holes. The portable tests compare
  every pixel of a circular hole against a brute-force Euclidean oracle.
- Mask input on a bevel layer renders immutable live regions on a worker.
  Committed documents and exports retain all effects.
- UI adapters own lock icons, clipping-arrow direction and localized terminology.
  Localized labels never replace persisted enum identifiers.

When bringing this main patch into `Compositor-Multiplatform`, inspect its existing
CMake/shared C tests and platform boundaries first. Preserve Windows pixel/build
work, reconcile shared semantics and format 13 validation, and run macOS plus
Windows tests. Synchronizing that branch is a separate operation.

## Responsive bevel previews

- Canvas bevel previews first use a maximum side of 768 pixels (including masks), still within the
  existing per-layer memory budget. After that result, 350 ms without a superseding
  request allows refinement to the existing preview limit (up to 1536 pixels).
- Only refined results enter the undo/redo result cache. Export is unchanged and
  always renders at full resolution. No saved preference or format field is added.
- Superseded work cooperatively cancels between rendering stages so it releases the single worker for newer requests. Cancellation
  is passed as a callback; the shared geometry contains no platform scheduling API.
- Distance-transform line buffers are reused; the Euclidean geometry is unchanged.

- After mask paint commits, effect previews sample immutable mask tiles directly
  at the bounded preview resolution. They must not assemble the original-size mask
  first. Placed masks are resampled on the preview worker, including their white or
  black exterior coverage; live distortion coverage remains a separate input.
- Both preview stages must leave the original sparse mask unmaterialized. Only an
  operation that actually needs full-resolution bytes (such as export) assembles it.

## Live bevel rendering and appearance

- Mask paint with Bevel & Emboss uses live region updates, not a mouse-up-only
  rebuild. A serial effect worker completes one snapshot while newer pointer
  samples replace a single pending snapshot. It must not cancel every sample:
  continuous input would otherwise prevent any result from reaching the screen.
- Compare changed immutable tile identities against the last rendered snapshot.
  Expand the output region by the effect reach, then expand the input window again
  for neighboring coverage. Reuse unaffected pixels from the current effects
  preview. Publish immutable results; never share a mutable render buffer with UI.
- Separate strokes own separate surfaces. Cancelled strokes must not seed painted
  effects into the committed canvas. On commit, finish pending live work before
  handing its result to the normal preview cache.
- The standard-library core defines four height profiles and diffuse lighting.
  Smooth rounds normalized height with h*h*(3-2*h), then filters pixel-scale
  distance fluctuations with sigma min(2, max(0.75, size/6)); Chisel Hard uses a
  straight distance ramp; Chisel Soft blurs the ramp (sigma 1.5). Depth scales
  height before normals, and gloss maps lit/shaded intensity after lighting.
- Soften blurs highlight/shadow planes (sigma = soften / 2), then clips them to the
  style's inside/outside coverage. It must not alter the height profile or expand
  an inner bevel into transparency. These are independently authored approximations
  of Adobe's documented controls, not claims of pixel-identical Photoshop output:
  https://helpx.adobe.com/africa/photoshop/desktop/create-manage-layers/apply-layer-effects/layer-style-effects-and-options-overview.html
- For Smooth, filter signed silhouette distances before constructing height
  (sigma min(4, max(1, size/4))). Keep original alpha for clipping. Normalize
  highlight by 1-flat and shadow by 1+flat, where flat is sin(altitude); shadow
  must retain gradation when a normal faces below the horizon rather than clipping.
- Windows can implement the same worker and region contract with its existing image
  adapter. No Metal or Apple scheduler is required by the height/lighting core.
  Validate the normal Xcode Debug build as well as optimized builds.

## Portable bulk pixel kernels

`Compositor/Core/StylePixels.c` implements exact signed distances, finite-support
box blur, height/normal lighting and common RGBA compositing using C11 buffers.
It has no Apple frameworks, dispatch, intrinsics or SIMD ABI dependency. The macOS
adapter calls it through the existing bridging header; the app target already
compiles C at `-O3` even when Swift debugging remains `-Onone`. Windows builds
should compile this translation unit with optimization too. Swift geometry remains
a reference oracle for the kernel tests. Cancellation is checked between stages.

Run portable bounds/geometry tests, also suitable for AddressSanitizer:

```sh
cc -std=c11 -O2 Compositor/Core/StylePixels.c Tests/PortableCore/style_pixels.c -lm -o style-pixels-tests
./style-pixels-tests
```

The output reach includes the profile width, the sum of the actual box radii for
signed-distance, height and soften filters, plus the normal derivative. Input
windows include this support again; never use a smaller halo than the filters.
On mouse-up, flush final tiles for both direct paint and masks. Completion must
finish cache handoff without another input event. If layer geometry is unchanged,
trim empty stroke-grid padding and, if its seed was full-resolution, adopt the result under the
committed image/mask identities, so another full render is unnecessary. If geometry
changes, retain the placed surface while a fresh preview is built.

## Upstream 1.4.7 and 1.4.8, as shared behavior

What a Windows build has to reproduce from these releases, and where the shared code lives.

- **Dither, Scanlines and RAW rounding** (`Rendering/DitherPixels.c`): portable C11. Upstream wrote it with Apple's
  blocks and Grand Central Dispatch; Compositor-KR runs the same arithmetic through `ParallelFor.h` (GCD on Apple
  platforms, OpenMP on Windows, serial elsewhere) as plain functions with a context, and uses `ptrdiff_t` for offsets
  that can go negative (`long` is 32-bit on Windows). The rewrite was checked byte for byte against upstream's kernel
  over 160 combinations of style, colors, displacement, color split, glow and 16-bit rounding. CI builds it with
  `-fno-blocks -Werror` and runs `Tests/PortableCore/dither_pixels.c` (alpha kept, clear pixels untouched, the same
  result however the bands are shared out). When merging upstream changes to this file, keep the portable form.
- **Scanlines** settings and their ranges are `ScanlinesSettings` (spacing 2–32 px, thickness 5–100 %, wobble 0–64 px,
  displace −100–100 px, split 0–16 px, threshold, dots, glow, black level, smoothness). Lines are drawn nearest first
  and hide the ones behind them; displacement smooths brightness along each line (three box passes, radius
  smoothness × spacing × 2) and then across lines (1-2-1 passes, smoothness × 2 of them).
- **Navigator** (`Core/NavigatorLayout.swift`): the document fitted and centered in the box; a picked point is held to
  the document's edges; centering pans so the picked pixel is in the middle at the same zoom and stops following Fit.
  It appears from 300 % zoom. `Rendering/NavigatorGeometry.swift` only adapts it to Core Graphics.
- **Last Filter** (⌃⌘F; Ctrl+Alt+F on Windows): repeats the last committed filter that `repeatsAsLastFilter`, with the
  same settings, as one undo step; nothing happens (a beep) when it can't apply.
- **Export As** (PNG, JPEG or a one-page PDF): the size scales both sides together; a PDF page is the image at its
  printed size (pixels ÷ resolution × 72 points) with lossless pixels. The PDF writer is platform code (Core Graphics
  here); Windows supplies its own with the same page size.
- **Fullscreen** is F (a menu item) and Escape leaves it when nothing else is in progress to cancel
  (`escapeHasNothingToCancel`); the command palette is ⌘F (Ctrl+F).
- **Layers panel**: layers selected on the canvas scroll into view; the panel grays out only for lasting states (a
  dialog, a pending transform, crop or gradient, a long operation), not for a stroke or a moment's work
  (`layersLookEditable`), while `canEditLayers` still guards every change, lock rules included.
