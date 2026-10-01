# Immutable resource ownership experiment

Run `SANITIZE=1 bash Spikes/RenderResources/run.sh` from the repository root.
Uses C++17 and threads already available for the other independent spikes. No
product target or renderer consumes these files. This selects no Core language.

`resources.hpp` defines a synthetic resource key (scope, ID, version, kind), owned
immutable lease, serialized owner and delivery provenance. `tests.cpp` checks
freeze isolation from mutable input, sharing between snapshots, replacement,
stale rejection without change, owner destruction, final release, four readers,
version exhaustion and mismatched provenance. `measure.cpp` compares copying a
payload once per snapshot with sharing the same frozen payload. `run.sh` uses
throwaway binaries outside the checkout and optionally ASan/UBSan.

A lease owns `shared_ptr<const Bytes>` constructed as an actually const allocation
from a copy. It does not convert a mutable shared_ptr and hope aliases disappear.
Snapshots copy leases; borrowed bytes live only while a lease is retained. Owner
replacement has one writer; it never changes published bytes. Readers each hold
their own lease. Weak observers in tests do not extend lifetime. Final release is
ordinary RAII, no document registry dependency. This is a retention model, not a
product ABI or image schema. Allocation failure remains a native allocation error,
not a validated product error contract.

The toy fixture assigns IDs/versions directly; uniqueness, persistent registry,
resource eviction/budgets, UUID allocation, and arbitrary-handle validation are
not implemented. Product keys must be unique within a non-reused instance scope.
Provenance scalar fields stand for explicit captured identities/parameters; they
are not a production hash or collision strategy. Exact-match tests distinguish
quality but do not implement a scheduler or progressive preview policy. There is
no path codec, image provider or GPU texture in this experiment.

## Local observation

Linux x86_64, GCC 14.2, `-O2`, one cold run, 2048×2048 RGBA8 synthetic bytes (16 MiB),
10 simultaneously retained snapshots:

| Strategy | Construction time | Unique payload in the 10 snapshots |
|---|---:|---:|
| Share frozen lease | 3.005 µs | 16 MiB |
| Copy for every snapshot | 856,944 µs | 160 MiB |

Both paths keep the same source allocation outside the table; shared timing
excludes the initial one-time freeze. Memory is exact payload accounting, **not**
RSS, peak heap or metadata/control-block overhead. Copies are read afterwards
(checksum 7,046,430,720) so they cannot be elided. Allocation/page faults and host
load dominate this single observation; no latency guarantee or language comparison
is supported. Sharing avoids the ten full copies structurally. Tiled native images
and compression/lazy providers need separate Mac measurements.

Tests passed optimized and ASan/UBSan; the lexical model boundary guard passed.
The Verify workflow now schedules this run with Apple Clang; that CI result is
pending. ASan/UBSan do not establish absence of data races; no ThreadSanitizer run
was performed. Concurrent immutable readers are exercised; concurrent owner calls
are intentionally outside the contract.

See [the resource audit](../../docs/multiplatform/render-resource-ownership.md)
for actual source ownership, main freshness, publication owner, color risks and
remaining Renderer API prerequisites. Synthetic success does not validate native
CGImage/CGPath lifetime, lazy color stability, or production publication capture.

Regression check: the unchanged RenderSnapshot runner also passed its four C++
semantic test groups and five transport tests. Product sources, CompositorTests,
and the Xcode project have zero diff against f6ce057. Full Mac builds/tests were
not run locally; no CI success is inferred from workflow configuration.
