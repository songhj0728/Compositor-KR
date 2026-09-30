#include "boundary.hpp"
#include <cstdlib>
#include <iostream>
#include <limits>
#include <thread>
#include <type_traits>
using namespace experiment;
#define CHECK(x) do { if (!(x)) { std::cerr << "FAIL line " << __LINE__ << ": " #x "\n"; std::abort(); } } while (false)
static_assert(std::is_const_v<Read::element_type>);
void errorsAndTokens() {
    Document d(7);
    CHECK(!d.add({{1, "한글 layer"}, {2, "second"}}));
    auto a = d.snapshot();
    auto reject = [&](Result r, Code c) {
        CHECK(r && r->code == c && !r->operation.empty() && !r->field.empty());
        auto now = d.snapshot();
        CHECK(now->state == a->state && now->generation == a->generation);
        CHECK(now->layers.size() == 2 && now->layers[0].opacity == 1);
    };
    reject(d.add({{3, "candidate"}, {1, "duplicate"}}), Code::duplicateID);
    reject(d.add({{3, "candidate"}, {3, "batch duplicate"}}), Code::duplicateID);
    reject(d.opacity(99, .5, a->instance, a->generation), Code::notFound);
    reject(d.reorder(1, 2), Code::invalidReorder);
    for (double v : {-1., 2., std::numeric_limits<double>::infinity(), std::numeric_limits<double>::quiet_NaN()})
        reject(d.opacity(1, v, a->instance, a->generation), Code::invalidOpacity);
    Document other(7);
    reject(d.opacity(1, .5, other.snapshot()->instance, a->generation), Code::foreignInstance);
    CHECK(!d.opacity(1, 1, a->instance, a->generation)); // No-op retains tokens.
    CHECK(d.snapshot()->generation == a->generation);
    CHECK(!d.opacity(1, .5, a->instance, a->generation));
    auto b = d.snapshot();
    CHECK(b->state != a->state && b->generation > a->generation);
    CHECK(a->layers[0].opacity == 1 && b->layers[0].opacity == .5);
    CHECK(d.undoForTest());
    auto restored = d.snapshot();
    CHECK(restored->state == a->state && restored->generation > b->generation);
    auto stale = d.opacity(1, .2, a->instance, a->generation);
    CHECK(stale && stale->code == Code::stale && stale->actual == restored->generation);
    CHECK(d.snapshot()->generation == restored->generation);
    CHECK(!d.reorder(1, 1));
    CHECK(d.snapshot()->layers[1].id == 1 && a->layers[0].id == 1);
}
void lifetime() {
    Read retained;
    std::weak_ptr<const Snapshot> weak;
    {
        Document d(1);
        std::vector<Layer> input{{1, std::string(100, 'x')}};
        CHECK(!d.add(input));
        input[0].name = "caller changed";
        retained = d.snapshot(); weak = retained;
        CHECK(retained->layers[0].name == std::string(100, 'x'));
    }
    CHECK(retained->layers[0].name.size() == 100); // Document destruction is independent.
    std::thread consumer([copy = retained] { CHECK(copy->layers[0].id == 1); });
    consumer.join();
    std::thread release([last = std::move(retained)]() mutable { last.reset(); });
    release.join();
    CHECK(weak.expired()); // No hidden owner retains the result.
}
void concurrency() {
    Document d(1);
    CHECK(!d.add({{1, "stable"}}));
    auto base = d.snapshot();
    std::atomic<int> ready{0}, accepted{0}, stale{0};
    std::atomic<bool> go{false};
    std::vector<std::thread> threads;
    for (int w = 0; w < 4; ++w) threads.emplace_back([&] {
        ++ready; while (!go.load()) std::this_thread::yield();
        auto result = d.opacity(1, .5, base->instance, base->generation);
        if (!result) ++accepted;
        else { CHECK(result->code == Code::stale); ++stale; }
    });
    for (int r = 0; r < 4; ++r) threads.emplace_back([&] {
        ++ready; while (!go.load()) std::this_thread::yield();
        for (int i = 0; i < 500; ++i) {
            auto s = d.snapshot();
            CHECK(s->layers.size() == 1 && s->layers[0].name == "stable");
            CHECK((s->generation == base->generation && s->layers[0].opacity == 1) ||
                  (s->generation == base->generation + 1 && s->layers[0].opacity == .5));
        }
    });
    while (ready.load() != 8) std::this_thread::yield();
    go = true;
    for (int i = 0; i < 500; ++i) { // UI-style reader on calling thread.
        auto s = d.snapshot(); CHECK(s->layers[0].id == 1);
    }
    for (auto& t : threads) t.join();
    CHECK(accepted == 1 && stale == 3);
    CHECK(base->layers[0].opacity == 1);
    CHECK(d.snapshot()->generation == base->generation + 1);
    // Sustained publication while background readers acquire complete versions.
    std::atomic<bool> done{false};
    std::atomic<int> started{0};
    threads.clear();
    for (int r = 0; r < 4; ++r) threads.emplace_back([&] {
        ++started;
        ID previous = 0;
        do {
            auto s = d.snapshot();
            CHECK(s->generation >= previous);
            CHECK(s->layers[0].opacity == (s->generation % 2 ? .5 : 1.));
            previous = s->generation;
        } while (!done.load());
    });
    while (started.load() != 4) std::this_thread::yield();
    for (int i = 0; i < 100; ++i) {
        auto s = d.snapshot();
        CHECK(!d.opacity(1, s->layers[0].opacity == .5 ? 1. : .5, s->instance, s->generation));
    }
    done = true;
    for (auto& t : threads) t.join();
}
int main() {
    errorsAndTokens(); lifetime(); concurrency();
    std::cout << "PASS: error/token, lifetime/release, concurrent readers/writers (3 test groups)\n";
}
