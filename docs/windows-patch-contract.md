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
- Mask input on a bevel layer previews coverage without synchronous bevel work;
  effects rebuild after commit. Committed documents and exports retain all effects.
- UI adapters own lock icons, clipping-arrow direction and localized terminology.
  Localized labels never replace persisted enum identifiers.

When bringing this main patch into `Compositor-Multiplatform`, inspect its existing
CMake/shared C tests and platform boundaries first. Preserve Windows pixel/build
work, reconcile shared semantics and format 13 validation, and run macOS plus
Windows tests. Synchronizing that branch is a separate operation.

## Responsive bevel previews

- Canvas bevel previews first use a maximum side of 768 pixels (512 with a mask), still within the
  existing per-layer memory budget. After that result, 350 ms without a superseding
  request allows refinement to the existing preview limit (up to 1536 pixels).
- Only refined results enter the undo/redo result cache. Export is unchanged and
  always renders at full resolution. No saved preference or format field is added.
- Superseded work cooperatively cancels between distance-transform lines and bevel
  shading rows so it releases the single worker for newer requests. Cancellation
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
- Windows can implement the same worker and region contract with its existing image
  adapter. No Metal or Apple scheduler is required by the height/lighting core.
  Measure interactive performance in an optimized build, not a Swift -Onone build.
