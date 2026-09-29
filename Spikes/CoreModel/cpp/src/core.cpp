#include "compositor/core.hpp"
#include <algorithm>
#include <cmath>

namespace compositor::core {

Transform Transform::rotation(double radians) {
    double cosine = std::cos(radians), sine = std::sin(radians);
    return {cosine, sine, -sine, cosine, 0, 0};
}

Transform Transform::concatenating(const Transform &n) const {
    return {a * n.a + b * n.c, a * n.b + b * n.d, c * n.a + d * n.c, c * n.b + d * n.d,
            tx * n.a + ty * n.c + n.tx, tx * n.b + ty * n.d + n.ty};
}

std::optional<Transform> Transform::inverted() const {
    double determinant = a * d - b * c;
    if (determinant == 0 || !std::isfinite(determinant)) return std::nullopt;
    return Transform{d / determinant, -b / determinant, -c / determinant, a / determinant,
                     (c * ty - d * tx) / determinant, (b * tx - a * ty) / determinant};
}

bool LayerGroup::operator==(const LayerGroup &other) const {
    return id == other.id && name == other.name && isVisible == other.isVisible && opacity == other.opacity &&
           isExpanded == other.isExpanded && children == other.children;
}

LayerID LayerNode::id() const { return std::visit([](const auto &n) { return n.id; }, value); }
const std::string &LayerNode::name() const {
    return std::visit([](const auto &n) -> const std::string & { return n.name; }, value);
}
bool LayerNode::isVisible() const { return std::visit([](const auto &n) { return n.isVisible; }, value); }

static const char *describe(DocumentErrorCode code) {
    switch (code) {
    case DocumentErrorCode::noSuchLayer: return "no such layer";
    case DocumentErrorCode::notAGroup: return "not a group";
    case DocumentErrorCode::notSiblings: return "layers are not siblings";
    case DocumentErrorCode::wouldContainItself: return "a group can't contain itself";
    case DocumentErrorCode::emptySelection: return "nothing selected";
    }
    return "document error";
}

DocumentError::DocumentError(DocumentErrorCode code) : std::runtime_error(describe(code)), code(code) {}

// MARK: Tree plumbing

static const LayerNode *find(LayerID id, const std::vector<LayerNode> &nodes) {
    for (const auto &node : nodes) {
        if (node.id() == id) return &node;
        if (auto *group = node.group())
            if (auto *found = find(id, group->children)) return found;
    }
    return nullptr;
}

LayerNode *Document::findMutable(LayerID id, std::vector<LayerNode> &nodes) {
    for (auto &node : nodes) {
        if (node.id() == id) return &node;
        if (auto *group = std::get_if<LayerGroup>(&node.value))
            if (auto *found = findMutable(id, group->children)) return found;
    }
    return nullptr;
}

static std::optional<Location> locate(LayerID id, const std::vector<LayerNode> &nodes, std::optional<LayerID> parent) {
    for (std::size_t index = 0; index < nodes.size(); ++index) {
        if (nodes[index].id() == id) return Location{parent, index};
        if (auto *group = nodes[index].group())
            if (auto found = locate(id, group->children, group->id)) return found;
    }
    return std::nullopt;
}

std::vector<LayerNode> &Document::childrenOf(std::optional<LayerID> parent) {
    if (!parent) return layers_;
    LayerNode *node = findMutable(*parent, layers_);
    if (!node) throw DocumentError(DocumentErrorCode::noSuchLayer);
    auto *group = std::get_if<LayerGroup>(&node->value);
    if (!group) throw DocumentError(DocumentErrorCode::notAGroup);
    return group->children;
}

void Document::insert(LayerNode node, std::optional<LayerID> parent, std::optional<std::size_t> index) {
    auto &children = childrenOf(parent);
    std::size_t at = std::min(index.value_or(children.size()), children.size());
    children.insert(children.begin() + static_cast<std::ptrdiff_t>(at), std::move(node));
}

// MARK: Adding and removing

LayerID Document::addLayer(std::string name, std::optional<LayerID> parent, std::optional<std::size_t> index,
                           std::optional<int> w, std::optional<int> h) {
    LayerID id = nextID_;
    Layer layer;
    layer.id = id;
    layer.name = std::move(name);
    layer.width = w.value_or(width);
    layer.height = h.value_or(height);
    insert(LayerNode{std::move(layer)}, parent, index);
    ++nextID_;
    return id;
}

LayerID Document::addGroup(std::string name, std::optional<LayerID> parent, std::optional<std::size_t> index) {
    LayerID id = nextID_;
    LayerGroup group;
    group.id = id;
    group.name = std::move(name);
    insert(LayerNode{std::move(group)}, parent, index);
    ++nextID_;
    return id;
}

LayerNode Document::remove(LayerID id) {
    auto spot = location(id);
    if (!spot) throw DocumentError(DocumentErrorCode::noSuchLayer);
    auto &children = childrenOf(spot->parent);
    LayerNode removed = std::move(children[spot->index]);
    children.erase(children.begin() + static_cast<std::ptrdiff_t>(spot->index));
    return removed;
}

// MARK: Arranging

void Document::move(LayerID id, std::optional<LayerID> parent, std::size_t index) {
    if (parent) {
        if (*parent == id) throw DocumentError(DocumentErrorCode::wouldContainItself);
        const LayerNode *moving = node(id);
        if (moving && moving->group() && find(*parent, moving->group()->children))
            throw DocumentError(DocumentErrorCode::wouldContainItself);
        const LayerNode *target = node(*parent);
        if (!target || !target->group()) throw DocumentError(DocumentErrorCode::notAGroup);
    }
    LayerNode moved = remove(id);
    insert(std::move(moved), parent, index);
}

LayerID Document::group(const std::vector<LayerID> &ids, std::string name) {
    if (ids.empty()) throw DocumentError(DocumentErrorCode::emptySelection);
    std::vector<std::size_t> indices;
    std::optional<LayerID> parent;
    for (std::size_t i = 0; i < ids.size(); ++i) {
        auto spot = location(ids[i]);
        if (!spot) throw DocumentError(DocumentErrorCode::noSuchLayer);
        if (i == 0) parent = spot->parent;
        else if (spot->parent != parent) throw DocumentError(DocumentErrorCode::notSiblings);
        indices.push_back(spot->index);
    }
    std::sort(indices.begin(), indices.end());
    auto &children = childrenOf(parent);
    LayerGroup made;
    made.id = nextID_++;
    made.name = std::move(name);
    for (auto index : indices) made.children.push_back(children[index]);
    for (auto it = indices.rbegin(); it != indices.rend(); ++it)
        children.erase(children.begin() + static_cast<std::ptrdiff_t>(*it));
    // Where the topmost member was, less the members that were below it.
    std::size_t at = indices.back() - (indices.size() - 1);
    LayerID id = made.id;
    children.insert(children.begin() + static_cast<std::ptrdiff_t>(at), LayerNode{std::move(made)});
    return id;
}

void Document::ungroup(LayerID id) {
    const LayerNode *found = node(id);
    if (!found) throw DocumentError(DocumentErrorCode::noSuchLayer);
    if (!found->group()) throw DocumentError(DocumentErrorCode::notAGroup);
    auto spot = *location(id);
    auto &children = childrenOf(spot.parent);
    std::vector<LayerNode> members = std::get<LayerGroup>(children[spot.index].value).children;
    children.erase(children.begin() + static_cast<std::ptrdiff_t>(spot.index));
    children.insert(children.begin() + static_cast<std::ptrdiff_t>(spot.index), members.begin(), members.end());
}

// MARK: Reading

const LayerNode *Document::node(LayerID id) const { return find(id, layers_); }

std::optional<Location> Document::location(LayerID id) const { return locate(id, layers_, std::nullopt); }

static void collectVisible(const std::vector<LayerNode> &nodes, double opacity, std::vector<VisibleLayer> &out) {
    for (const auto &node : nodes) {
        if (!node.isVisible()) continue;
        if (auto *layer = node.layer()) out.push_back({layer, opacity * layer->opacity});
        else collectVisible(node.group()->children, opacity * node.group()->opacity, out);
    }
}

std::vector<VisibleLayer> Document::visibleLayers() const {
    std::vector<VisibleLayer> result;
    collectVisible(layers_, 1, result);
    return result;
}

static void collectOutline(const std::vector<LayerNode> &nodes, int depth, std::vector<OutlineRow> &out) {
    for (auto it = nodes.rbegin(); it != nodes.rend(); ++it) {
        out.push_back({&*it, depth});
        if (auto *group = it->group()) collectOutline(group->children, depth + 1, out);
    }
}

std::vector<OutlineRow> Document::outline() const {
    std::vector<OutlineRow> result;
    collectOutline(layers_, 0, result);
    return result;
}

// MARK: History

History::History(Document document, std::size_t limit) : document_(std::move(document)), limit_(std::max<std::size_t>(1, limit)) {}

void History::commit(const std::string &name, Document edited) {
    if (edited == document_) return;
    undo_.push_back({name, std::move(document_)});
    if (undo_.size() > limit_) undo_.erase(undo_.begin(), undo_.begin() + static_cast<std::ptrdiff_t>(undo_.size() - limit_));
    redo_.clear();
    document_ = std::move(edited);
}

std::optional<std::string> History::undoName() const {
    if (undo_.empty()) return std::nullopt;
    return undo_.back().name;
}

std::optional<std::string> History::undo() {
    if (undo_.empty()) return std::nullopt;
    Step step = std::move(undo_.back());
    undo_.pop_back();
    redo_.push_back({step.name, std::move(document_)});
    document_ = std::move(step.document);
    return step.name;
}

std::optional<std::string> History::redo() {
    if (redo_.empty()) return std::nullopt;
    Step step = std::move(redo_.back());
    redo_.pop_back();
    undo_.push_back({step.name, std::move(document_)});
    document_ = std::move(step.document);
    return step.name;
}

}  // namespace compositor::core
