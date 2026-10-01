#pragma once
#include <cstdint>
#include <limits>
#include <memory>
#include <stdexcept>
#include <vector>

// Synthetic ownership experiment. No product ABI or image format.
namespace resources {
using Bytes = std::vector<std::uint8_t>;
enum class Kind { raster, mask, path, style };
struct Key {
    std::uint64_t scope, id, version;
    Kind kind;
    bool operator==(const Key& b) const {
        return scope == b.scope && id == b.id && version == b.version && kind == b.kind;
    }
};
enum class Error { staleResource, exhaustedVersion };
class Lease {
    Key key_;
    std::shared_ptr<const Bytes> data_;
public:
    // Copy once at freeze: even a caller retaining a mutable alias cannot edit us.
    Lease(Key key, const Bytes& source): key_(key), data_(std::make_shared<const Bytes>(source)) {}
    Key key() const { return key_; }
    const Bytes& bytes() const { return *data_; } // borrowed only while lease lives
    std::weak_ptr<const Bytes> observer() const { return data_; }
    bool shares(const Lease& b) const { return data_ == b.data_; }
};
class Owner {
    Lease current_;
public:
    explicit Owner(Lease initial): current_(initial) {}
    Lease snapshot() const { return current_; }
    // Owner access is serialized by caller; readers use independent lease copies.
    void replace(Key expected, const Bytes& bytes) {
        if (!(current_.key() == expected)) throw Error::staleResource;
        if (expected.version == std::numeric_limits<std::uint64_t>::max()) throw Error::exhaustedVersion;
        ++expected.version;
        current_ = Lease(expected, bytes);
    }
};
struct Provenance {
    std::uint64_t instance, publication, request, color, parameters, quality;
    Key resource;
    bool matches(const Provenance& b) const {
        return instance == b.instance && publication == b.publication && request == b.request &&
            color == b.color && parameters == b.parameters && quality == b.quality && resource == b.resource;
    }
};
}
