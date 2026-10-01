# RenderSnapshot semantic projection prototype

Independent C++17 experiment plus a **test-only** actual CanvasDocument adapter.
Implementation `acb92be730597b93d370feccc3532ba37acd2905`; hosted-test bridge
`ebc79d3` corrects the test execution approach for the existing App Sandbox.
No renderer API, app consumer, Core language choice, resource ownership or GPU work.
The app's Metal/Core Image/Core Graphics paths are untouched.

## Gate and source baseline

Start: clean Compositor-Multiplatform `79757d3d3dfb9dba3a34d3c5fa892cdda8ac53e8`,
matching origin. main remains `0be4fe6a6ba038385ab2b6c5f059376ed8a628f2` with the
same three reviewed font/text-helper/keyboard/packaging commits since prior work.
No new main delta or merge. CoreBoundary and both enum/product read migrations exist.

**Mac baseline gate passed by user evidence:** user directly confirmed Verify #59:
Xcode 26.6 selection, model boundary, package resolve, build-for-testing, unit tests,
window tests and entire job succeeded. The exact workflow-run SHA was not supplied;
this is explicitly user-reported evidence, not a successful API lookup or a claim
that the new prototype has already passed. Actions API remains Forbidden even
outside the sandbox. Official Swift toolchain download was also Forbidden. Thus
local C++ tests are executable, while new actual Swift fixture tests await Mac CI.

## Files and reproduction

| File | Purpose |
|---|---|
| projection.hpp | Pure numeric/UUID-string input, owned immutable snapshot and projection validator |
| transport.hpp / host.cpp | Shared private fixture codec and command-line runner; no product ABI/format |
| tests.cpp | Four executable semantic/error/lifetime test groups |
| transport-tests.py | Five end-to-end host transport tests |
| measure.cpp / allocations.cpp | Timings and operator-new allocation counters, experiment only |
| run.sh | Temporary build, tests, measurements and optional sanitizers |
| ../../CompositorTests/RenderSnapshotPrototypeTests.swift | Three Mac tests: 12 actual-model fixtures, source independence, graph/token errors |
| ../../CompositorTests/RenderProjectionFixture.h / .mm | Hosted-test-only Foundation adapter to the same projector |

```sh
bash Spikes/RenderSnapshot/run.sh
SANITIZE=1 bash Spikes/RenderSnapshot/run.sh
# macOS, selected Xcode compiler:
CXX=clang++ SANITIZE=1 bash Spikes/RenderSnapshot/run.sh
```

No dependency beyond C++17 compiler, bash and Python 3. Build outputs use a temporary
directory and are removed. Existing verify.yml runs the experiment separately; the
usual app suite picks up the new Swift test through the synchronized test folder.
The app uses App Sandbox and CompositorTests is hosted in that app. Mac tests
therefore call a tiny Objective-C++ adapter compiled into **the test target only**,
instead of launching a compiler/process from the sandbox. Test Debug/Release
configurations add a bridging header; app settings/entitlements stay unchanged.
The adapter converts scalar fixture text through Foundation strings and calls the
same projector/codec as the standalone host. No pixel or native object enters the
semantic snapshot. This internal test bridge is not a product C ABI, .comp field,
renderer service or selected interop strategy. Compile/fixture failures fail tests;
no fixture is silently skipped. C++17-or-newer settings already exist in Xcode.

## Snapshot structure and immutable ownership

Input publication: explicit instance UUID, state UUID and Generation, plus persistent
document UUID/dimensions and one bulk raw layer list. IDs are copied canonical UUID
strings by the Mac adapter; no identity redesign or generator. Input fields contain
node/content kind, own visibility/opacity, Fill Opacity, semantic blend/sampling
strings, numeric placement, parent and source links, style-present and enabled-mask
placeholder flags. No pixel or native pointer crosses this boundary.

Output Data contains publication/dimensions, hierarchy-ordered nodes and a visible
non-group draw-ID list. Every Node retains own values and separately stores depth,
effective visibility/opacity, unit-to-document matrix, axis-aligned logical bounds,
ancestor IDs, enabled-mask ancestor IDs, clipping-source chain and classification
(none/contiguous stack/independent alpha link) with explicit stack base. Hidden
sources/groups remain in ordered nodes; a backend never needs to revisit the live
document to resolve these relationships. The draw-ID list matches renderLayers,
which can include an empty layer that the actual drawOwn later skips for no content.

Snapshot owns copied Data; its read method returns const Data only. Borrowed row/
string references expire with the owner; copied values survive independently. Input
mutation or destruction cannot change old snapshots. This is metadata ownership,
not a physical image/path lifetime solution. Mutable model references are absent.

## Hierarchy representation alternatives

| Candidate | What it preserves / tradeoff |
|---|---|
| Flat ordered list + parent ID | Stable identity/sibling traversal; parent-only consumers would need repeated resolution |
| Flat list + depth | Efficient nesting iteration; cannot express arbitrary hidden/external clipping links alone |
| Explicit tree | Natural folder traversal; non-parent dependencies still require a second graph and extra ownership |
| Flat list + dependency edges | Keeps ordered nodes plus arbitrary source relationships, including hidden dependencies |

Prototype uses a flat hierarchy-ordered list with parent, depth, explicit ancestor
and clipping edges/chains. It is the smallest complete semantic form for this
scope, not a choice of GPU-friendly storage. Ancestor lists cost O(n*depth); depth
is bounded by the reference. A future compact index/range representation could
reduce copies without changing meaning. Full document state stays in the existing model.

## Projection algorithm

1. Check expected instance/Generation against supplied publication. Index all IDs
   once, reject duplicates, invalid opacity/fill/geometry or non-Normal group blend.
2. Validate parent existence/group kind, parent cycles/reference depth limits, and
   source existence/kind/cycles/256-node chain limit. Return structured error before
   publishing output. This is not a complete ProjectStore/style validator.
3. Bucket children in raw stored order. Traverse roots and folders once. Effective
   visibility = parent visibility AND own flag AND NOT hidden lower same-parent
   clipping base. Effective opacity = own times ancestor opacity. Groups are
   pass-through, never newly isolated composites.
4. Copy scalar placement; derive unit-square affine matrix and rotated axis bounds.
   Carry ancestor masks and full source chains, even for nondrawn hidden sources.
5. Resolve stacks in the visible nongroup order as LiveMaskRenderer.prepareStacks:
   a base has no source and is not adjustment; consecutive children must point at
   that base and share parent. Remaining source links are independent alpha dependencies.

Average hash-table work is O(n); validation/chain copying is O(n*D+n*C) with fixed
D<=64 ancestors and C<=256 source nodes. Stack scanning does not repeatedly scan
whole lists: only a successful contiguous run plus its terminating item per base.
No GetLayer operation or row-by-row Core crossing exists. Hash worst-case behavior,
large-depth memory and adversarial resource workloads are not performance guarantees.

## Clipping findings

The source ID is always retained. A hidden lower same-parent base suppresses its
clipped layer; an upper or external hidden source still supplies coverage. Group
boundaries prevent stack classification but do not forbid a valid independent
source relationship. Chain IDs are explicit, so a consumer can retain source-only
nodes without live graph discovery. Coverage pixels, base-alpha preservation and
stack blend execution are out of scope.

Reordering alone does **not** silently rewrite source links. The immutable input
records the model as captured: a previously lower base can become an independent
upper source. The actual-model fixture separately invokes existing
EditorSession.releaseDetachedClipping and projects that changed model. This
preserves the separation between model operation policy and read projection.

## Geometry, fill, styles and resources

Placement is copied as Double origin/size/clockwise degrees, flips and semantic
sampling name. The scalar affine maps a unit square to document pixels with y down;
it matches LayerTransform.unitToDocument/BrushRaster.pixelToDocument. Bounds are
rotated logical placement bounds, **not** final effect/crop/paint extents. No CGRect,
CGAffineTransform, CGFloat, UI or GPU type occurs in projection.hpp. This does not
migrate product geometry or add support for arbitrary shear/distortion corners.

Own opacity, effective opacity and Fill Opacity remain three separate values. Fill
never multiplies effective opacity in projection. Blend is a stable raw string,
not CGBlendMode/CI filter or shader code. Style presence is merely a copied flag;
there is no nine-effect descriptor or execution. Enabled-mask ancestry is metadata
only, not mask coverage ownership. Text/shape/pixel/adjustment/empty/group kinds are
copied; full payloads, imported profiles, image/path handles and glyphs are absent.

## Apple-specific adapter boundary

Only CompositorTests reads CanvasDocument/ImageLayer, Foundation UUID, CoreGraphics
placements and reference helpers. The Objective-C++ test wrapper uses NSString;
it is not part of the app target or semantic header. No Apple/native pointer is
stored in Input/Node/Snapshot. The existing Python boundary guard scans the semantic
header, and ten temporary forbidden UI/GPU/CG dependency probes were rejected.

## Publication consistency and limits

The Swift test adapter is MainActor, synchronous and reads one CanvasDocument value
without await/reentrant callbacks. It serializes complete fixture input before the
test adapter receives it. The C++ projector reads a controlled immutable input and copies
its token unchanged into the whole result. Expected instance/Generation mismatch
returns stale/foreign errors. Snapshot A remains unchanged after source visibility,
opacity and order changes; B is supplied a new explicit Generation and reflects them.

This does not authenticate that a caller's token truly belongs to its data. A forged
same-generation input is not detected; production lifecycle owner is still absent.
There are no concurrent writes to Input during project; unsynchronized mutation of
it would be invalid usage. Preview/commit/cancel/save envelopes, history integration,
async acceptance, resource freezing and result cache provenance remain unresolved.

## Parity fixtures and verification status

Mac fixture inventory: single layer, siblings, hidden folder/child, nested folder
opacity (0.5*0.4*0.3), clipping pair, hidden lower base, reordered upper source,
reordered model after existing unlink helper, cross-group source, Fill Opacity plus
normal opacity/Multiply, rotated/flipped/Nearest placement, chained source links.

The Mac tests compare actual LayerOrder hierarchy and renderLayers, effectiveVisibleIDs,
LayerHierarchy depth, effectiveOpacity, native unitToDocument/corner bounds, own IDs/
links/raw blend/sampling/fill and source chain. Stack classification oracle reproduces
the small private traversal rule inspected in both CPU/GPU canvas paths; it is not
a Metal draw or pixel comparison. Separate tests check old output after actual source
edits and actual-value fixtures with duplicate ID/missing parent/invalid base/cycles/
stale token. These three Swift tests are **authored, not locally executed**.

| Evidence | Result |
|---|---|
| Baseline Mac Verify #59 | Passed, user directly confirmed job steps; exact SHA not independently retrieved |
| C++ semantic tests | Four groups passed in optimized and ASan/UBSan builds |
| Test host transport | Five Python tests passed; structured errors are successful host results |
| Local boundary guard | Passed for pure projection.hpp; forbidden-dependency probes also checked |
| New actual CanvasDocument parity/lifetime/error tests | Pending new Mac CI; Linux lacks Swift/Xcode |
| New Verify workflow result | Not observed; API remains Forbidden |
| Pixel/Metal parity or complete render description | Not claimed; no renderer execution implemented |

## Performance observation

Linux x86_64, AMD EPYC 9V74 (5 visible vCPUs), GCC 14.2.0 `-O2`, canonical-length
36-byte UUID fixture strings. Five warmups, 30 measured captures per size. Timings
cover project/allocation, excluding source fixture setup, output destruction and
pipe transport. Allocation counters cover ordinary C++ operator-new calls/bytes
**including temporary validation/index storage**, not retained bytes, RSS, allocator
headers or all malloc/aligned allocations. No language comparison.

| Workload | Nodes | Median µs | p95 µs | Allocation calls | Requested bytes |
|---|---:|---:|---:|---:|---:|
| Flat | 10 | 6.219 | 6.539 | 165 | 13,778 |
| Flat | 2,000 | 1,228.53 | 1,399.09 | 30,043 | 2,693,712 |
| Flat | 10,000 | 7,664.44 | 8,190.44 | 150,053 | 13,918,352 |
| Four nested groups + clipping pairs | 10 | 12.659 | 50.104 | 388 | 25,457 |
| Four nested groups + clipping pairs | 2,000 | 2,916.4 | 4,293.75 | 89,968 | 6,064,156 |
| Four nested groups + clipping pairs | 10,000 | 19,143 | 25,733.7 | 449,978 | 30,788,796 |

Representative run; timing varies. Allocation totals scale roughly with n. Numeric
fields alone are cheap, but UUID/string/map/ancestor copies create substantial
allocation churn; this first simple implementation is not a product budget. The
algorithm has no per-row full-list rebuild. Actual Mac adapter/host timings and
real image/effect resource costs are unmeasured. No O(1) capture claim.

## Remaining blockers and next scope

- Execute the three actual-model Mac tests and new experiment step; Verify #59
  clears the baseline gate only. Exact new-commit CI success remains unobserved.
- Define publication owner, same-state token guarantees and preview envelopes.
- Replace resource flags with reviewed immutable image/path/mask/style descriptors,
  profile/format/alpha meaning, retain/release obligations and frozen draft tiles.
- Decide request/projection versus cache output provenance without live renderer edits.
- Add complete style/adjustment/mask dependency semantics and pixel parity before
  renderer integration; current logical bounds are not final padded render bounds.
- Reduce allocation churn only if later named workloads justify it; do not select a
  Core language or permanently adopt this container based on this experiment.

The result supports a draft discussion of renderer input responsibilities, not a
final Renderer API or Windows GPU implementation. Stop after the prototype.
