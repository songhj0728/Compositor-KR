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
