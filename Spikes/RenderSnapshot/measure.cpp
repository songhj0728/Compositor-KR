#include "projection.hpp"
#include <chrono>
#include <cstdlib>
#include <iostream>
#include <iomanip>
#include <sstream>
#include <new>
extern bool countAllocations;
extern std::size_t calls, allocated;
using namespace render_experiment;
static ID fixtureID(std::size_t i) {
    std::ostringstream s; s << "00000000-0000-0000-0000-" << std::hex << std::setw(12) << std::setfill('0') << i;
    return s.str();
}
int main() {
    std::cout << "workload,layers,median_us,p95_us,allocation_calls,requested_bytes\n";
    for (bool nested : {false, true}) for (std::size_t size : {10u, 2000u, 10000u}) {
        Input input{{"instance", "state", 1}, "document", 100, 100, {}};
        for (std::size_t i = 0; i < size; ++i) {
            InputNode n; n.id = fixtureID(i); n.opacity = .9;
            if (nested && i < 4) { n.kind = "group"; if (i) n.parent = fixtureID(i - 1); }
            if (nested && i >= 4) { n.parent = fixtureID(3); if (i % 2 == 1) n.source = fixtureID(i - 1); }
            input.nodes.push_back(std::move(n));
        }
        std::vector<double> times;
        for (int i = 0; i < 35; ++i) {
            calls = allocated = 0; countAllocations = true;
            auto start = std::chrono::steady_clock::now();
            auto result = project(input, "instance", 1);
            auto end = std::chrono::steady_clock::now();
            countAllocations = false;
            if (!result.snapshot || result.snapshot->read().ordered.size() != size) return 1;
            if (i >= 5) times.push_back(std::chrono::duration<double, std::micro>(end - start).count());
        }
        std::sort(times.begin(), times.end());
        std::cout << (nested ? "nested+clipping" : "flat") << ',' << size << ',' << times[15] << ',' << times[28]
                  << ',' << calls << ',' << allocated << '\n';
    }
}
