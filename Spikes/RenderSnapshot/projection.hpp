#pragma once
#include <algorithm>
#include <cmath>
#include <cstdint>
#include <functional>
#include <iterator>
#include <utility>
#include <optional>
#include <string>
#include <unordered_map>
#include <vector>

namespace render_experiment {
using ID = std::string; // Canonical UUID copied by the Mac test adapter; no ID generator.
struct Publication { ID instance, state; std::uint64_t generation; };
struct Placement {
    double x = 0, y = 0, width = 8, height = 8, degrees = 0;
    bool flipX = false, flipY = false;
    std::string sampling = "High quality";
};
struct Bounds { double x, y, width, height; };
struct Matrix { double a, b, c, d, tx, ty; }; // Unit square to document, y down.
struct InputNode {
    ID id, parent, source;
    std::string kind = "empty", blend = "Normal";
    bool visible = true;
    double opacity = 1, fill = 1;
    Placement placement;
    bool stylePresent = false, enabledMaskPresent = false;
};
struct Input { Publication publication; ID document; double width, height; std::vector<InputNode> nodes; };
struct Node {
    InputNode own;
    std::size_t depth;
    bool effectiveVisible;
    double effectiveOpacity;
    Matrix unitToDocument;
    Bounds axisBounds;
    std::vector<ID> ancestors, maskAncestors, coverageChain;
    std::string clipping = "none"; // stack vs independent live-alpha link.
    ID stackBase;
};
struct Data {
    Publication publication;
    ID document;
    double width, height;
    std::vector<Node> ordered; // Includes groups and hidden dependency sources.
    std::vector<ID> drawn;
};
class Snapshot {
    Data data;
public:
    explicit Snapshot(Data value) : data(std::move(value)) {}
    const Data& read() const { return data; } // Borrow valid only while this owner lives.
};
struct Error { std::string code, field; ID id; };
struct Result { std::optional<Snapshot> snapshot; std::optional<Error> error; };
inline Matrix matrix(const Placement& p) {
    const double r = std::fmod(p.degrees, 360.) * std::acos(-1.) / 180.;
    const double sx = p.flipX ? -1. : 1., sy = p.flipY ? -1. : 1.;
    const double a = std::cos(r) * p.width * sx, b = std::sin(r) * p.width * sx;
    const double c = -std::sin(r) * p.height * sy, d = std::cos(r) * p.height * sy;
    return {a, b, c, d, p.x + p.width / 2 - (a + c) / 2, p.y + p.height / 2 - (b + d) / 2};
}
inline Bounds bounds(const Matrix& m) {
    const double xs[] = {m.tx, m.tx + m.a, m.tx + m.c, m.tx + m.a + m.c};
    const double ys[] = {m.ty, m.ty + m.b, m.ty + m.d, m.ty + m.b + m.d};
    auto x = std::minmax_element(std::begin(xs), std::end(xs));
    auto y = std::minmax_element(std::begin(ys), std::end(ys));
    return {*x.first, *y.first, *x.second - *x.first, *y.second - *y.first};
}
inline Result project(const Input& input, const ID& expectedInstance, std::uint64_t expectedGeneration) {
    auto fail = [](std::string code, std::string field, ID id = "") -> Result {
        return {{}, Error{std::move(code), std::move(field), std::move(id)}};
    };
    if (input.publication.instance != expectedInstance) return fail("foreignInstance", "instance");
    if (input.publication.generation != expectedGeneration) return fail("stalePublication", "generation");
    if (!std::isfinite(input.width) || !std::isfinite(input.height) || input.width < 1 || input.height < 1 || input.width > 30000 || input.height > 30000)
        return fail("invalidValue", "documentSize");
    std::unordered_map<ID, std::size_t> index;
    for (std::size_t i = 0; i < input.nodes.size(); ++i) {
        const auto& n = input.nodes[i];
        if (n.id.empty() || !index.emplace(n.id, i).second) return fail("duplicateID", "id", n.id);
        const auto& p = n.placement;
        for (double v : {n.opacity, n.fill})
            if (!std::isfinite(v) || v < 0 || v > 1) return fail("invalidValue", "opacityOrFill", n.id);
        for (double v : {p.x, p.y, p.width, p.height, p.degrees})
            if (!std::isfinite(v)) return fail("invalidValue", "placement", n.id);
        if (p.width < 1 || p.height < 1 || p.width > 300000 || p.height > 300000 || std::abs(p.x) > 1000000 || std::abs(p.y) > 1000000) return fail("invalidValue", "size", n.id);
        if (n.kind == "group" && n.blend != "Normal") return fail("invalidGroup", "blend", n.id);
    }
    std::vector<std::vector<std::size_t>> children(input.nodes.size());
    std::vector<std::size_t> roots;
    for (std::size_t i = 0; i < input.nodes.size(); ++i) {
        const auto& n = input.nodes[i];
        if (n.parent.empty()) roots.push_back(i);
        else {
            auto at = index.find(n.parent);
            if (at == index.end()) return fail("missingParent", "parent", n.id);
            if (input.nodes[at->second].kind != "group") return fail("invalidParent", "parent", n.id);
            children[at->second].push_back(i);
        }
        if (!n.source.empty()) {
            auto at = index.find(n.source);
            if (at == index.end()) return fail("invalidClippingBase", "source", n.id);
            const auto& source = input.nodes[at->second];
            if (n.kind == "group" || source.kind == "group" || source.kind == "adjustment")
                return fail("invalidClippingBase", "kind", n.id);
        }
    }
    // Validate both graphs before constructing any output; bounded chains keep
    // worst-case work linear in n for the reference's fixed depth limits.
    for (const auto& n : input.nodes) {
        std::unordered_map<ID, bool> seen;
        ID current = n.id;
        std::size_t depth = 0;
        while (!current.empty()) {
            if (!seen.emplace(current, true).second) return fail("parentCycle", "parent", n.id);
            if (++depth > 65 || (n.kind == "group" && depth > 64)) return fail("depthLimit", "parent", n.id);
            current = input.nodes[index.at(current)].parent;
        }
        seen.clear(); current = n.id; depth = 0;
        while (!current.empty()) {
            if (!seen.emplace(current, true).second) return fail("clippingCycle", "source", n.id);
            if (++depth > 256) return fail("depthLimit", "source", n.id);
            current = input.nodes[index.at(current)].source;
        }
    }
    Data result{input.publication, input.document, input.width, input.height, {}, {}};
    result.ordered.reserve(input.nodes.size());
    std::function<void(std::size_t, bool, double, const std::vector<ID>&, const std::vector<ID>&)> visit;
    visit = [&](std::size_t i, bool parentVisible, double parentOpacity,
                const std::vector<ID>& ancestors, const std::vector<ID>& masks) {
        const auto& n = input.nodes[i];
        bool hiddenBase = false;
        if (!n.source.empty()) {
            auto at = index.at(n.source);
            const auto& source = input.nodes[at];
            hiddenBase = at < i && source.parent == n.parent && !source.visible;
        }
        auto m = matrix(n.placement);
        Node node{n, ancestors.size(), parentVisible && n.visible && !hiddenBase,
                  parentOpacity * n.opacity, m, bounds(m), ancestors, masks, {}, "none", ""};
        auto source = n.source;
        while (!source.empty()) {
            node.coverageChain.push_back(source);
            source = input.nodes[index.at(source)].source;
        }
        if (!n.source.empty()) node.clipping = "independent";
        if (node.effectiveVisible && n.kind != "group") result.drawn.push_back(n.id);
        result.ordered.push_back(node);
        auto nextAncestors = ancestors; nextAncestors.push_back(n.id);
        auto nextMasks = masks; if (n.enabledMaskPresent) nextMasks.push_back(n.id);
        for (auto child : children[i]) visit(child, node.effectiveVisible, node.effectiveOpacity, nextAncestors, nextMasks);
    };
    for (auto root : roots) visit(root, true, 1, {}, {});
    std::unordered_map<ID, std::size_t> outputIndex;
    for (std::size_t i = 0; i < result.ordered.size(); ++i) outputIndex.emplace(result.ordered[i].own.id, i);
    // Exact visible contiguous-stack interpretation of LiveMaskRenderer.prepareStacks.
    for (std::size_t i = 0; i < result.drawn.size(); ++i) {
        auto& base = result.ordered[outputIndex.at(result.drawn[i])];
        if (!base.own.source.empty() || base.own.kind == "adjustment") continue;
        for (std::size_t j = i + 1; j < result.drawn.size(); ++j) {
            auto& child = result.ordered[outputIndex.at(result.drawn[j])];
            if (child.own.source != base.own.id || child.own.parent != base.own.parent) break;
            child.clipping = "stack"; child.stackBase = base.own.id;
        }
    }
    return {Snapshot(std::move(result)), {}};
}
}
