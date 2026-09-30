#include "boundary.hpp"
#include <chrono>
#include <iostream>
using namespace experiment;
int main() {
    std::cout << "layers,median_us,p95_us,estimated_owned_bytes\n";
    for (std::size_t n : {10u, 2000u, 10000u}) {
        Document d(1);
        std::vector<Layer> input;
        for (std::size_t i = 0; i < n; ++i) input.push_back({i + 1, std::string(64, 'x')});
        if (d.add(std::move(input))) return 1;
        std::vector<double> times;
        std::size_t bytes = 0;
        for (int iteration = 0; iteration < 105; ++iteration) {
            auto start = std::chrono::steady_clock::now();
            auto s = d.snapshot();
            auto end = std::chrono::steady_clock::now();
            if (iteration >= 5) times.push_back(std::chrono::duration<double, std::micro>(end - start).count());
            if (s->layers.size() != n || s->layers.back().id != n) return 2;
            bytes = sizeof(Snapshot) + s->layers.capacity() * sizeof(Layer);
            for (const auto& layer : s->layers) bytes += layer.name.capacity() + 1;
        }
        std::sort(times.begin(), times.end());
        std::cout << n << ',' << times[50] << ',' << times[94] << ',' << bytes << '\n';
    }
}
