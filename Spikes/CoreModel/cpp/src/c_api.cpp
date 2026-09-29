// The C++ Core behind include/compositor_core.h, the same functions the Swift Core exports. No C++ exception may
// cross into the caller, so every entry point catches.
#include "compositor_core.h"
#include "compositor/core.hpp"
#include <cstring>

using namespace compositor::core;

struct cc_history {
    History history;
};

namespace {
std::optional<LayerID> parentOf(cc_layer_id id) {
    if (id == 0) return std::nullopt;
    return id;
}

std::string text(const char *utf8) { return utf8 ? utf8 : ""; }

// Copies `value` into a C buffer, cut at a character boundary to fit. Returns the full length in bytes.
size_t copy(const std::string &value, char *buffer, size_t capacity) {
    if (!buffer || capacity == 0) return value.size();
    size_t count = std::min(value.size(), capacity - 1);
    // Don't end partway through a multi-byte UTF-8 character.
    while (count > 0 && count < value.size() && (static_cast<unsigned char>(value[count]) & 0xC0) == 0x80) --count;
    std::memcpy(buffer, value.data(), count);
    buffer[count] = 0;
    return value.size();
}

template <class Body> auto guarded(Body body, decltype(body()) failure) noexcept -> decltype(body()) {
    try {
        return body();
    } catch (...) {
        return failure;
    }
}

void setOnNode(Document &document, LayerID id, bool visible, const std::string *name) {
    const LayerNode *node = document.node(id);
    if (!node) throw DocumentError(DocumentErrorCode::noSuchLayer);
    if (node->layer())
        document.updateLayer(id, [&](Layer &layer) { name ? void(layer.name = *name) : void(layer.isVisible = visible); });
    else
        document.updateGroup(id, [&](LayerGroup &group) { name ? void(group.name = *name) : void(group.isVisible = visible); });
}
}  // namespace

extern "C" {

cc_history *cc_history_create(int32_t width, int32_t height) {
    return guarded([&] { return new cc_history{History(Document(width, height))}; }, nullptr);
}

void cc_history_destroy(cc_history *history) { delete history; }

cc_layer_id cc_add_layer(cc_history *h, const char *name, cc_layer_id parent) {
    if (!h) return 0;
    return guarded([&] { return h->history.perform("Add Layer", [&](Document &d) { return d.addLayer(text(name), parentOf(parent)); }); },
                   cc_layer_id{0});
}

cc_layer_id cc_add_group(cc_history *h, const char *name, cc_layer_id parent) {
    if (!h) return 0;
    return guarded([&] { return h->history.perform("Add Group", [&](Document &d) { return d.addGroup(text(name), parentOf(parent)); }); },
                   cc_layer_id{0});
}

cc_layer_id cc_group(cc_history *h, const cc_layer_id *ids, size_t count, const char *name) {
    if (!h || !ids || count == 0) return 0;
    std::vector<LayerID> members(ids, ids + count);
    return guarded([&] { return h->history.perform("Group Layers", [&](Document &d) { return d.group(members, text(name)); }); },
                   cc_layer_id{0});
}

int32_t cc_set_visible(cc_history *h, cc_layer_id id, int32_t visible) {
    if (!h) return 0;
    return guarded([&] {
        h->history.perform(visible ? "Show Layer" : "Hide Layer", [&](Document &d) { setOnNode(d, id, visible != 0, nullptr); });
        return int32_t{1};
    }, int32_t{0});
}

int32_t cc_rename(cc_history *h, cc_layer_id id, const char *name) {
    if (!h) return 0;
    std::string newName = text(name);
    return guarded([&] {
        h->history.perform("Rename Layer", [&](Document &d) { setOnNode(d, id, true, &newName); });
        return int32_t{1};
    }, int32_t{0});
}

int32_t cc_undo(cc_history *h) { return h && h->history.undo() ? 1 : 0; }
int32_t cc_redo(cc_history *h) { return h && h->history.redo() ? 1 : 0; }

size_t cc_undo_name(const cc_history *h, char *buffer, size_t capacity) {
    auto name = h ? h->history.undoName() : std::nullopt;
    if (!name) {
        if (buffer && capacity) buffer[0] = 0;
        return 0;
    }
    return copy(*name, buffer, capacity);
}

size_t cc_outline_count(const cc_history *h) { return h ? h->history.document().outline().size() : 0; }

int32_t cc_outline_row(const cc_history *h, size_t index, cc_layer_id *id, int32_t *depth, int32_t *is_group,
                       int32_t *is_visible, char *name, size_t name_capacity) {
    if (!h) return 0;
    auto outline = h->history.document().outline();
    if (index >= outline.size()) return 0;
    const auto &row = outline[index];
    if (id) *id = row.node->id();
    if (depth) *depth = row.depth;
    if (is_group) *is_group = row.node->group() ? 1 : 0;
    if (is_visible) *is_visible = row.node->isVisible() ? 1 : 0;
    copy(row.node->name(), name, name_capacity);
    return 1;
}

}  // extern "C"
