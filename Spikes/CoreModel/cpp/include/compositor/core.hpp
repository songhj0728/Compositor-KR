// The spike's document model in C++20, the same types and behavior as swift/Sources/CoreModel, for comparison.
// Standard library only.
#pragma once
#include <cstdint>
#include <optional>
#include <stdexcept>
#include <string>
#include <variant>
#include <vector>

namespace compositor::core {

struct Point {
    double x = 0, y = 0;
    bool operator==(const Point &) const = default;
};

// Maps (x, y) to (a·x + c·y + tx, b·x + d·y + ty), as CGAffineTransform does.
struct Transform {
    double a = 1, b = 0, c = 0, d = 1, tx = 0, ty = 0;

    static Transform identity() { return {}; }
    static Transform translation(double x, double y) { return {1, 0, 0, 1, x, y}; }
    static Transform scale(double sx, double sy) { return {sx, 0, 0, sy, 0, 0}; }
    // Clockwise on screen, where y points down.
    static Transform rotation(double radians);

    // This transform, then `next`.
    Transform concatenating(const Transform &next) const;
    Point apply(Point p) const { return {a * p.x + c * p.y + tx, b * p.x + d * p.y + ty}; }
    // Empty when the transform flattens everything onto a line.
    std::optional<Transform> inverted() const;
    bool operator==(const Transform &) const = default;
};

using LayerID = std::uint64_t;

enum class BlendMode { normal, multiply, screen, overlay, darken, lighten };

struct Layer {
    LayerID id = 0;
    std::string name;  // UTF-8
    bool isVisible = true;
    double opacity = 1;
    BlendMode blendMode = BlendMode::normal;
    Transform transform;
    int width = 0, height = 0;
    bool operator==(const Layer &) const = default;
};

struct LayerNode;

// Layers and groups inside a group, bottom to top.
struct LayerGroup {
    LayerID id = 0;
    std::string name;
    bool isVisible = true;
    double opacity = 1;
    bool isExpanded = true;
    std::vector<LayerNode> children;
    bool operator==(const LayerGroup &) const;
};

// One entry in the layer tree.
struct LayerNode {
    std::variant<Layer, LayerGroup> value;

    LayerID id() const;
    const std::string &name() const;
    // For Swift: it imports no method that returns a reference or pointer into the object (name(), group(),
    // layer()), so it needs copies.
    std::string nameCopy() const { return name(); }
    bool isGroupNode() const { return group() != nullptr; }
    bool isVisible() const;
    const LayerGroup *group() const { return std::get_if<LayerGroup>(&value); }
    const Layer *layer() const { return std::get_if<Layer>(&value); }
    bool operator==(const LayerNode &) const = default;
};

enum class DocumentErrorCode { noSuchLayer, notAGroup, notSiblings, wouldContainItself, emptySelection, duplicateLayer };

struct DocumentError : std::runtime_error {
    DocumentErrorCode code;
    explicit DocumentError(DocumentErrorCode code);
};

struct Location {
    std::optional<LayerID> parent;  // Empty at the top level.
    std::size_t index = 0;
};

struct VisibleLayer {
    const Layer *layer;
    double opacity;
};

struct OutlineRow {
    const LayerNode *node;
    int depth;
};

// A canvas and its layer tree. A value type; note that copying one copies the whole tree (no copy-on-write), unlike
// the Swift version.
class Document {
public:
    // Named so Swift can spell them: Swift has no syntax for a C++ template instantiation.
    using OptionalID = std::optional<LayerID>;
    using OptionalIndex = std::optional<std::size_t>;
    using OptionalSize = std::optional<int>;

    Document(int width, int height) : width(width), height(height) {}

    int width, height;
    const std::vector<LayerNode> &layers() const { return layers_; }

    LayerID addLayer(std::string name, std::optional<LayerID> parent = {}, std::optional<std::size_t> index = {},
                     std::optional<int> width = {}, std::optional<int> height = {});
    LayerID addGroup(std::string name, std::optional<LayerID> parent = {}, std::optional<std::size_t> index = {});
    LayerNode remove(LayerID id);
    void move(LayerID id, std::optional<LayerID> parent, std::size_t index);
    LayerID group(const std::vector<LayerID> &ids, std::string name);
    void ungroup(LayerID id);

    template <class Change> void updateLayer(LayerID id, Change change) {
        updateNode(id, [&](LayerNode &node) {
            auto *layer = std::get_if<Layer>(&node.value);
            if (!layer) throw DocumentError(DocumentErrorCode::noSuchLayer);
            change(*layer);
        });
    }
    template <class Change> void updateGroup(LayerID id, Change change) {
        updateNode(id, [&](LayerNode &node) {
            auto *group = std::get_if<LayerGroup>(&node.value);
            if (!group) throw DocumentError(DocumentErrorCode::notAGroup);
            change(*group);
        });
    }

    const LayerNode *node(LayerID id) const;
    std::optional<Location> location(LayerID id) const;
    std::vector<VisibleLayer> visibleLayers() const;
    std::vector<OutlineRow> outline() const;

    bool operator==(const Document &) const = default;

private:
    std::vector<LayerNode> layers_;
    LayerID nextID_ = 1;

    void insert(LayerNode node, std::optional<LayerID> parent, std::optional<std::size_t> index);
    std::vector<LayerNode> &childrenOf(std::optional<LayerID> parent);
    template <class Change> void updateNode(LayerID id, Change change) {
        LayerNode *found = findMutable(id, layers_);
        if (!found) throw DocumentError(DocumentErrorCode::noSuchLayer);
        change(*found);
    }
    static LayerNode *findMutable(LayerID id, std::vector<LayerNode> &nodes);
};

// Undo and redo by keeping whole Document values.
class History {
public:
    explicit History(Document document, std::size_t limit = 100);

    const Document &document() const { return document_; }

    // One undoable change. When `change` throws, the document is left as it was and nothing is recorded.
    template <class Change> auto perform(const std::string &name, Change change) {
        Document edited = document_;
        if constexpr (std::is_void_v<decltype(change(edited))>) {
            change(edited);
            commit(name, std::move(edited));
        } else {
            auto result = change(edited);
            commit(name, std::move(edited));
            return result;
        }
    }

    bool canUndo() const { return !undo_.empty(); }
    bool canRedo() const { return !redo_.empty(); }
    std::optional<std::string> undoName() const;
    std::optional<std::string> undo();
    std::optional<std::string> redo();

private:
    struct Step {
        std::string name;
        Document document;
    };
    Document document_;
    std::vector<Step> undo_, redo_;
    std::size_t limit_;
    void commit(const std::string &name, Document edited);
};

}  // namespace compositor::core
