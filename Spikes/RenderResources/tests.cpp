#include "resources.hpp"
#include <cassert>
#include <iostream>
#include <optional>
#include <thread>
using namespace resources;
int main() {
    Bytes source(1024, 7);
    std::optional<Lease> old, newer;
    std::weak_ptr<const Bytes> weak;
    {
        Owner document(Lease({1, 9, 1, Kind::raster}, source));
        old = document.snapshot();
        weak = old->observer();
        auto same = document.snapshot();
        assert(same.shares(*old));
        source[0] = 88;
        assert(old->bytes()[0] == 7);
        std::vector<std::thread> readers;
        for (int i = 0; i < 4; ++i) readers.emplace_back([copy = *old] {
            for (int n = 0; n < 10000; ++n) assert(copy.bytes()[0] == 7);
        });
        document.replace(old->key(), source);
        newer = document.snapshot();
        assert(newer->key().version == 2 && newer->bytes()[0] == 88);
        assert(!newer->shares(*old));
        try { document.replace(old->key(), source); assert(false); }
        catch (Error error) { assert(error == Error::staleResource); }
        assert(document.snapshot().shares(*newer));
        for (auto& reader : readers) reader.join();
    }
    assert(old->bytes()[0] == 7 && newer->bytes()[0] == 88); // owner destroyed
    assert(!weak.expired());
    old.reset();
    assert(weak.expired()); // no hidden registry retains retired resource
    Provenance accepted{1, 10, 2, 3, 4, 2, newer->key()};
    assert(accepted.matches(accepted));
    for (int field = 0; field < 9; ++field) {
        auto stale = accepted;
        switch (field) {
            case 0: ++stale.instance; break;
            case 1: ++stale.publication; break;
            case 2: ++stale.request; break;
            case 3: ++stale.color; break;
            case 4: ++stale.parameters; break;
            case 5: --stale.quality; break;
            case 6: ++stale.resource.version; break;
            case 7: ++stale.resource.scope; break;
            case 8: stale.resource.kind = Kind::mask; break;
        }
        assert(!accepted.matches(stale));
    }
    Owner exhausted(Lease({1, 9, UINT64_MAX, Kind::mask}, source));
    try { exhausted.replace(exhausted.snapshot().key(), source); assert(false); }
    catch (Error error) { assert(error == Error::exhaustedVersion); }
    std::cout << "PASS: freeze, sharing, replacement/stale atomicity, concurrent readers, owner/release lifetime, provenance, overflow\n";
}
