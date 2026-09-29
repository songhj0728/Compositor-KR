// The same cases as swift/Tests/CoreModelTests, for the C++ Core. No test framework, so no dependency.
#include "compositor/core.hpp"
#include <cmath>
#include <cstdio>
#include <functional>

using namespace compositor::core;

static int failures = 0;
#define CHECK(condition)                                                              \
    do {                                                                              \
        if (!(condition)) {                                                           \
            ++failures;                                                               \
            std::fprintf(stderr, "FAIL %s:%d: %s\n", __FILE__, __LINE__, #condition); \
        }                                                                             \
    } while (0)

static bool throwsCode(DocumentErrorCode code, const std::function<void()> &body) {
    try {
        body();
    } catch (const DocumentError &error) {
        return error.code == code;
    }
    return false;
}

static std::vector<LayerID> ids(const std::vector<LayerNode> &nodes) {
    std::vector<LayerID> result;
    for (const auto &node : nodes) result.push_back(node.id());
    return result;
}

static void addingStacksBottomToTop() {
    Document document(800, 600);
    auto background = document.addLayer("Background");
    auto top = document.addLayer("Top", {}, {}, 100, 50);
    CHECK(ids(document.layers()) == (std::vector<LayerID>{background, top}));
    CHECK(document.node(top)->layer()->width == 100);
}

static void groupingKeepsOrderAndTakesTopmostPlace() {
    Document document(10, 10);
    auto a = document.addLayer("A"), b = document.addLayer("B"), c = document.addLayer("C"), d = document.addLayer("D");
    auto group = document.group({c, a}, "Group");
    CHECK(ids(document.layers()) == (std::vector<LayerID>{b, group, d}));
    CHECK(ids(document.node(group)->group()->children) == (std::vector<LayerID>{a, c}));
    CHECK(document.location(c)->parent == group);
}

static void groupingNeedsSiblings() {
    Document document(10, 10);
    auto a = document.addLayer("A");
    auto group = document.addGroup("G");
    auto inside = document.addLayer("Inside", group);
    CHECK(throwsCode(DocumentErrorCode::notSiblings, [&] { document.group({a, inside}, "X"); }));
}

static void ungroupPutsChildrenBack() {
    Document document(10, 10);
    auto a = document.addLayer("A"), b = document.addLayer("B"), c = document.addLayer("C");
    auto group = document.group({a, b}, "G");
    document.ungroup(group);
    CHECK(ids(document.layers()) == (std::vector<LayerID>{a, b, c}));
    CHECK(document.node(group) == nullptr);
}

static void groupCantMoveIntoItself() {
    Document document(10, 10);
    auto outer = document.addGroup("Outer");
    auto inner = document.addGroup("Inner", outer);
    CHECK(throwsCode(DocumentErrorCode::wouldContainItself, [&] { document.move(outer, inner, 0); }));
    CHECK(throwsCode(DocumentErrorCode::wouldContainItself, [&] { document.move(outer, outer, 0); }));
    CHECK(document.location(inner)->parent == outer);
}

static void visibleLayersFollowGroups() {
    Document document(10, 10);
    auto group = document.addGroup("G");
    auto a = document.addLayer("A", group);
    auto hidden = document.addLayer("Hidden", group);
    auto b = document.addLayer("B");
    document.updateGroup(group, [](LayerGroup &g) { g.opacity = 0.5; });
    document.updateLayer(a, [](Layer &l) { l.opacity = 0.5; });
    document.updateLayer(hidden, [](Layer &l) { l.isVisible = false; });
    auto visible = document.visibleLayers();
    CHECK(visible.size() == 2 && visible[0].layer->id == a && visible[1].layer->id == b);
    CHECK(std::abs(visible[0].opacity - 0.25) < 1e-12);
}

static void outlineListsTopFirst() {
    Document document(10, 10);
    auto bottom = document.addLayer("Bottom");
    auto group = document.addGroup("G");
    auto inside = document.addLayer("Inside", group);
    auto outline = document.outline();
    CHECK(outline.size() == 3 && outline[0].node->id() == group && outline[1].node->id() == inside &&
          outline[2].node->id() == bottom);
    CHECK(outline[1].depth == 1);
}

static void transforms() {
    auto p = Transform::scale(2, 3).concatenating(Transform::translation(10, 20)).apply({1, 1});
    CHECK(p == (Point{12, 23}));
    auto r = Transform::rotation(std::acos(-1.0) / 2).apply({1, 0});
    CHECK(std::abs(r.x) < 1e-12 && std::abs(r.y - 1) < 1e-12);
    auto t = Transform::rotation(0.7).concatenating(Transform::scale(2, 0.5)).concatenating(Transform::translation(-3, 9));
    auto back = t.concatenating(*t.inverted()).apply({5, -7});
    CHECK(std::abs(back.x - 5) < 1e-9 && std::abs(back.y + 7) < 1e-9);
    CHECK(!Transform::scale(0, 1).inverted());
}

static void historyUndoRedo() {
    History history(Document(10, 10));
    auto a = history.perform("Add A", [](Document &d) { return d.addLayer("A"); });
    history.perform("Rename", [&](Document &d) { d.updateLayer(a, [](Layer &l) { l.name = "Renamed"; }); });
    CHECK(history.undoName() == "Rename");
    CHECK(history.undo() == "Rename");
    CHECK(history.document().node(a)->name() == "A");
    CHECK(history.undo() == "Add A");
    CHECK(history.document().layers().empty());
    CHECK(!history.undo());
    CHECK(history.redo() == "Add A");
    CHECK(history.redo() == "Rename");
    CHECK(history.document().node(a)->name() == "Renamed");
}

static void failedChangeLeavesNoTrace() {
    History history(Document(10, 10));
    history.perform("Add", [](Document &d) { d.addLayer("A"); });
    Document before = history.document();
    CHECK(throwsCode(DocumentErrorCode::noSuchLayer, [&] {
        history.perform("Bad", [](Document &d) { d.addLayer("B"); d.ungroup(999); });
    }));
    CHECK(history.document() == before);
    CHECK(history.undoName() == "Add");
}

static void limitDropsOldest() {
    History history(Document(10, 10), 3);
    for (int i = 0; i < 5; ++i) history.perform("Step " + std::to_string(i), [&](Document &d) { d.addLayer(std::to_string(i)); });
    std::vector<std::string> names;
    while (auto name = history.undo()) names.push_back(*name);
    CHECK(names == (std::vector<std::string>{"Step 4", "Step 3", "Step 2"}));
    CHECK(history.document().layers().size() == 2);
}

int main() {
    addingStacksBottomToTop();
    groupingKeepsOrderAndTakesTopmostPlace();
    groupingNeedsSiblings();
    ungroupPutsChildrenBack();
    groupCantMoveIntoItself();
    visibleLayersFollowGroups();
    outlineListsTopFirst();
    transforms();
    historyUndoRedo();
    failedChangeLeavesNoTrace();
    limitDropsOldest();
    if (failures) {
        std::fprintf(stderr, "%d check(s) failed\n", failures);
        return 1;
    }
    std::printf("All C++ core tests passed\n");
    return 0;
}
