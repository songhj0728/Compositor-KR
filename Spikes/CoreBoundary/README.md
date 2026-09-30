# Core boundary semantics experiment

Isolated synthetic C++17 experiment, not a product Core, language choice or ABI.
It follows the existing spike convention: outside Xcode synchronized folders,
unlinked to the app and root CMake. Original spike/core-model is untouched.
C++ is used only because GCC is available in this Linux workspace.

## Reproduce

From the repository root, with GCC, bash and pthread support:

```sh
bash Spikes/CoreBoundary/run.sh
SANITIZE=1 bash Spikes/CoreBoundary/run.sh
```

The script builds in a temporary directory and removes outputs. Tests use explicit
checks even with optimized builds. SANITIZE adds AddressSanitizer/UndefinedBehaviorSanitizer;
it is not a data-race detector. No new dependency or product target is introduced.

## Verification gate and baseline

Start: clean Compositor-Multiplatform/local and remote both
`9c8e4674aaaec0d0bdec30f8546406a327b9fcc7`. FilterKind `9bac5cf` and TextAlignment
`78cf0e9` are present. GitHub Actions query again returned Forbidden. Mac build,
full CompositorTests, FilterKindTests, TextAlignmentTests and CI boundary checks
remain **unverified**, not passed or known failed. Local enum boundary checks pass.
Linux has no Xcode/Swift compiler. This isolated experiment proceeds with that
explicit limitation; it does not clear the Mac integration gate.

Main remains `0be4fe6a6ba038385ab2b6c5f059376ed8a628f2`, unchanged since the prior
review. The three unmerged commits contain font family/style helpers and keyboard
UI/tests, packaging and feed changes. Re-read the LayerTextStyle helper delta;
it does not change this snapshot/identity/history experiment. No main merge.
Original spike ref remains `e3bf3868e49bddb6a5527318fa5b273b99001d00`.

## Model and implementation limits

Document owns mutable state: synthetic numeric document/instance/StateID/Generation
and layers containing numeric ID, name, visibility, opacity. Numeric IDs are test
fixtures, not a UUID design or product ID generator. add accepts fixture IDs and
rejects duplicates both within a batch and against existing layers, atomically.
There is no image, path, mask, style, codec, renderer or real document migration.

Each snapshot is one owned `shared_ptr<const Snapshot>` containing the entire
vector and copied strings. There is no mutable alias or GetLayer call. Traversal
is O(n); acquisition copies O(n) metadata while holding a mutex. Mutable document
state never escapes. Inputs are copied; later input changes cannot mutate state.
Retained snapshots survive mutation and document destruction; borrowed rows/strings
are valid only while their snapshot is retained. Last release on a background
thread is tested. No close-handle API or concurrent document destruction is tested.

A mutex serializes all operations and snapshot capture. This is a serialized
execution context, not proof of UI thread affinity or a permanent mutex choice.
Readers consume only immutable retained snapshots after synchronized acquisition.
Tests include four background readers plus a calling-thread UI-style reader,
four competing writers, and 100 further publications with readers checking that
generation and opacity always belong to the same complete version.

Meaningful mutations allocate a fresh StateID and advance Generation. A no-op
changes neither. A minimal undo test hook restores a historical StateID and data
but advances Generation. Thus A→B→A cannot accept work from the first A. Work is
checked under the mutation lock against both instance and Generation; two open
instances may have the same persistent document ID. This is not a full undo/redo,
saved-status, transaction, preview/cancel or history-budget implementation.

Errors are owned values with code, operation, field, ID and expected/actual tokens.
Duplicate ID, missing ID, invalid reorder (final index after removal), nonfinite or
out-of-range opacity, stale generation and foreign instance are recoverable with
no partial publication. Four writers using one source generation produce one
success and three stale errors. Internal invariant failures are bugs: do not map
them to domain errors or continue after corruption. The test harness aborts on
failed assertions; no fatal-invariant recovery or process isolation is implemented.
Allocations are staged before commit, but OOM/exception injection and integer token
exhaustion are unvalidated. No exception containment suitable for a C ABI is claimed.

## Measurement and results

Linux x86_64, AMD EPYC 9V74 (5 visible vCPUs), GCC 14.2.0, `-O2`, standard allocator.
Each layer has a 64-byte name; five warmups and 100 samples per size. Timer covers
one snapshot allocation/copy, excluding destruction, setup and traversal. No
concurrent contention in this micro-measurement and no language comparison.

| Layers | Median µs | p95 µs | Estimated owned bytes/snapshot |
|---:|---:|---:|---:|
| 10 | 0.130 | 0.140 | 1,266 |
| 2,000 | 28.682 | 92.796 | 242,056 |
| 10,000 | 145.764 | 275.245 | 1,210,056 |

Representative local run; reruns vary. Byte estimate uses sizeof(Snapshot), vector
capacity and each name capacity+1. Excludes allocator headers, shared_ptr control
block, document/history storage, executable and fragmentation; not RSS or an
allocation trace. This implementation allocates a vector, snapshot/control block
and non-small string storage for each row. Retaining K independent snapshots costs
approximately K times the table above. Deep-copy history is deliberately naive.
Snapshot acquisition is linear by inspection and measured scaling is consistent
with that; this is not a product latency budget, allocation profiler, or proof of
image/history scalability. Input setup uses a hash set for duplicate validation.

Three test groups pass in optimized and ASan/UBSan builds: errors/tokens,
ownership/release, and concurrency. ASan/UBSan report no issue in these runs.
ThreadSanitizer, Windows/macOS execution, real UI scheduling, sustained contention
latency and product CI remain unvalidated. Existing product code/build files are
unchanged.

## Future ABI ownership requirements (not implemented)

Use an owned immutable snapshot/result handle with a matching library release,
or caller-owned copied buffers. Return the entire layer table in one call. Borrowed
rows and string bytes must name their owning snapshot and lengths/encoding; they
expire on release, never on document mutation. A UI retaining a row must retain its
snapshot or copy the value. Specify retain/release concurrency and destruction
context. Never free library memory with the host allocator or expose vector/string
layout. Error storage needs the same explicit ownership. Validate open-instance and
generation tokens; a persistent document ID alone is insufficient. C++ exceptions
must be contained before any future foreign boundary; this spike exports none.

## What this permits next

Validated here means **synthetic model only**: immutable bulk data, copied string/
array lifetime, explicit release, serialized atomic mutation, concurrent snapshot
reads, StateID/Generation distinction and structured domain errors. See docs/core-api.md.
Unvalidated: actual model resources, UUID/handle lifecycle, complete history and
transactions, save/load, native adapters, host ABI, notifications, fatal errors,
allocation faults, and Mac migration CI. A separately scoped experimental API
skeleton could use these semantics; product integration is not justified by this
result alone. Stop here; no additional enum migration or renderer/API work.
