#include "projection.hpp"
#include <cstdlib>
#include <iostream>
#include <limits>
#include <type_traits>
using namespace render_experiment;
#define CHECK(x) do { if (!(x)) { std::cerr << "FAIL line " << __LINE__ << ": " #x "\n"; std::abort(); } } while (false)
static_assert(std::is_const_v<std::remove_reference_t<decltype(std::declval<Snapshot>().read())>>);
InputNode layer(ID id, ID parent = "", std::string kind = "empty") {
    InputNode n; n.id = std::move(id); n.parent = std::move(parent); n.kind = std::move(kind); return n;
}
Input fixture(std::vector<InputNode> nodes) { return {{"instance", "state", 7}, "document", 100, 80, std::move(nodes)}; }
Snapshot capture(const Input& input) { auto r = project(input, "instance", 7); CHECK(!r.error && r.snapshot); return std::move(*r.snapshot); }
const Node& row(const Snapshot& s, const ID& id) {
    for (const auto& n : s.read().ordered) if (n.own.id == id) return n;
    std::abort();
}
void valuesAndOrder() {
    auto g = layer("group", "", "group"); g.opacity = .5; g.enabledMaskPresent = true;
    auto nested = layer("nested", "group", "group"); nested.opacity = .4;
    auto child = layer("child", "nested"); child.opacity = .3; child.fill = .2; child.blend = "Multiply";
    auto input = fixture({child, g, layer("sibling"), nested});
    auto s = capture(input);
    CHECK(s.read().drawn == std::vector<ID>({"child", "sibling"}));
    CHECK(s.read().ordered[0].own.id == "group" && s.read().ordered[1].own.id == "nested");
    CHECK(row(s, "child").depth == 2 && std::abs(row(s, "child").effectiveOpacity - .06) < 1e-12);
    CHECK(row(s, "child").own.opacity == .3 && row(s, "child").own.fill == .2);
    CHECK(row(s, "child").maskAncestors == std::vector<ID>({"group"}));
    input.nodes[1].visible = false;
    auto hidden = capture(input);
    CHECK(!row(hidden, "child").effectiveVisible && row(hidden, "child").own.visible);
    CHECK(row(s, "child").effectiveVisible && row(s, "child").own.blend == "Multiply");
}
void clipping() {
    auto base = layer("base"); auto child = layer("child"); child.source = "base";
    auto input = fixture({base, child}); auto s = capture(input);
    CHECK(row(s, "child").clipping == "stack" && row(s, "child").stackBase == "base");
    input.nodes[0].visible = false; auto hidden = capture(input);
    CHECK(!row(hidden, "child").effectiveVisible && row(hidden, "child").coverageChain == std::vector<ID>({"base"}));
    std::reverse(input.nodes.begin(), input.nodes.end()); auto reordered = capture(input);
    CHECK(row(reordered, "child").effectiveVisible && row(reordered, "child").clipping == "independent");
    auto group = layer("group", "", "group"); child.parent = "group"; base.visible = false;
    auto cross = capture(fixture({base, group, child}));
    CHECK(row(cross, "child").effectiveVisible && row(cross, "child").clipping == "independent");
    auto third = layer("third"); third.source = "child";
    auto chain = capture(fixture({base, child, third, group}));
    CHECK(row(chain, "third").coverageChain == std::vector<ID>({"child", "base"}));
}
void geometryAndLifetime() {
    auto n = layer("layer"); n.placement = {10, 20, 30, 40, 90, true, false, "Nearest"};
    auto input = fixture({n}); auto s = capture(input);
    const auto& m = row(s, "layer").unitToDocument;
    CHECK(std::abs(m.a) < 1e-10 && std::abs(m.b + 30) < 1e-10 && std::abs(m.c + 40) < 1e-10);
    const auto& b = row(s, "layer").axisBounds;
    CHECK(std::abs(b.width - 40) < 1e-10 && std::abs(b.height - 30) < 1e-10);
    input.nodes[0].visible = false; input.nodes[0].opacity = .2; input.nodes.push_back(layer("new"));
    std::reverse(input.nodes.begin(), input.nodes.end()); input.publication.generation = 8;
    auto newer = project(input, "instance", 8); CHECK(newer.snapshot);
    CHECK(s.read().publication.generation == 7 && s.read().ordered.size() == 1 && row(s, "layer").own.opacity == 1);
    CHECK(newer.snapshot->read().ordered[0].own.id == "new" && !row(*newer.snapshot, "layer").effectiveVisible);
    input.nodes.clear(); CHECK(row(s, "layer").own.placement.sampling == "Nearest");
}
void errors() {
    auto check = [](Input input, const std::string& code) {
        auto r = project(input, "instance", 7); CHECK(r.error && r.error->code == code && !r.snapshot);
    };
    check(fixture({layer("same"), layer("same")}), "duplicateID");
    check(fixture({layer("child", "missing")}), "missingParent");
    auto a = layer("a"); a.source = "missing"; check(fixture({a}), "invalidClippingBase");
    auto g = layer("group", "", "group"); a.source = "group"; check(fixture({g, a}), "invalidClippingBase");
    g.parent = "other"; auto h = layer("other", "group", "group"); check(fixture({g, h}), "parentCycle");
    a.source = "b"; auto b = layer("b"); b.source = "a"; check(fixture({a, b}), "clippingCycle");
    a.source.clear(); a.opacity = std::numeric_limits<double>::quiet_NaN(); check(fixture({a}), "invalidValue");
    auto input = fixture({layer("ok")}); input.publication.generation = 8; check(input, "stalePublication");
    input.publication = {"other", "state", 7}; check(input, "foreignInstance");
}
int main() {
    valuesAndOrder(); clipping(); geometryAndLifetime(); errors();
    std::cout << "PASS: 4 groups (hierarchy/values, clipping, geometry/lifetime, structured errors)\n";
}
