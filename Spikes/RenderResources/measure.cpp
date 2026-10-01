#include "resources.hpp"
#include <chrono>
#include <iostream>
using namespace resources;
using Clock = std::chrono::steady_clock;
int main() {
    constexpr std::size_t count = 10, size = 2048 * 2048 * 4;
    Bytes pixels(size, 42);
    Lease original({1, 1, 1, Kind::raster}, pixels);
    auto start = Clock::now();
    std::vector<Lease> shared(count, original);
    auto sharedUs = std::chrono::duration<double, std::micro>(Clock::now() - start).count();
    start = Clock::now();
    std::vector<Lease> copies;
    for (std::size_t i = 0; i < count; ++i) copies.emplace_back(Key{1, i + 2, 1, Kind::raster}, original.bytes());
    auto copyUs = std::chrono::duration<double, std::micro>(Clock::now() - start).count();
    std::uint64_t check = 0;
    for (const auto& copy : copies) for (auto byte : copy.bytes()) check += byte;
    std::cout << "10 snapshots, 2048x2048 RGBA8 synthetic payload; shared_us=" << sharedUs
        << " deep_copy_us=" << copyUs << " shared_unique_payload_bytes=" << size
        << " deep_unique_payload_bytes=" << count * size << " checksum=" << check << '\n';
}
