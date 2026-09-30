#pragma once
#include <algorithm>
#include <atomic>
#include <cmath>
#include <cstdint>
#include <memory>
#include <mutex>
#include <optional>
#include <string>
#include <vector>
#include <unordered_set>

namespace experiment {
using ID = std::uint64_t;
struct Layer { ID id; std::string name; bool visible = true; double opacity = 1; };
struct Snapshot {
    ID document, instance, state, generation;
    std::vector<Layer> layers;
};
using Read = std::shared_ptr<const Snapshot>;
enum class Code { duplicateID, notFound, invalidReorder, invalidOpacity, stale, foreignInstance };
struct Error { Code code; std::string operation, field; ID id, expected, actual; };
using Result = std::optional<Error>;

// Synthetic model only. Lock acquisition is the owner execution context in this
// experiment, not a product thread-affinity or allocation policy.
class Document {
    inline static std::atomic<ID> nextInstance{1};
    std::mutex mutex;
    Snapshot model;
    ID nextState = 2;
    std::vector<Snapshot> past;
    Result failure(Code code, const char* op, const char* field, ID id = 0,
                   ID expected = 0, ID actual = 0) {
        return Error{code, op, field, id, expected, actual};
    }
    void publish(std::vector<Layer> candidate) {
        // Prepare everything that can allocate before installing the candidate.
        past.push_back(model);
        model.layers.swap(candidate);
        model.state = nextState++;
        ++model.generation;
    }
public:
    explicit Document(ID persistent) : model{persistent, nextInstance++, 1, 1, {}} {}
    Read snapshot() {
        std::lock_guard<std::mutex> lock(mutex);
        // No mutable alias escapes; vector and strings are deep value copies.
        return std::make_shared<const Snapshot>(model);
    }
    Result add(std::vector<Layer> layers) {
        std::lock_guard<std::mutex> lock(mutex);
        auto candidate = model.layers;
        std::unordered_set<ID> ids;
        for (const auto& layer : candidate) ids.insert(layer.id);
        for (const auto& layer : layers) {
            if (!ids.insert(layer.id).second)
                return failure(Code::duplicateID, "add", "id", layer.id);
            if (!std::isfinite(layer.opacity) || layer.opacity < 0 || layer.opacity > 1)
                return failure(Code::invalidOpacity, "add", "opacity", layer.id);
            candidate.push_back(layer);
        }
        if (!layers.empty()) publish(std::move(candidate));
        return {};
    }
    Result opacity(ID id, double value, ID instance, ID generation) {
        std::lock_guard<std::mutex> lock(mutex);
        if (instance != model.instance) return failure(Code::foreignInstance, "opacity", "instance", id, instance, model.instance);
        if (generation != model.generation) return failure(Code::stale, "opacity", "generation", id, generation, model.generation);
        auto it = std::find_if(model.layers.begin(), model.layers.end(), [&](const Layer& l) { return l.id == id; });
        if (it == model.layers.end()) return failure(Code::notFound, "opacity", "id", id);
        if (!std::isfinite(value) || value < 0 || value > 1) return failure(Code::invalidOpacity, "opacity", "opacity", id);
        if (it->opacity == value) return {};
        auto candidate = model.layers;
        candidate[static_cast<std::size_t>(it - model.layers.begin())].opacity = value;
        publish(std::move(candidate));
        return {};
    }
    Result reorder(ID id, std::size_t destination) {
        std::lock_guard<std::mutex> lock(mutex);
        auto it = std::find_if(model.layers.begin(), model.layers.end(), [&](const Layer& l) { return l.id == id; });
        if (it == model.layers.end()) return failure(Code::notFound, "reorder", "id", id);
        // Destination is the final index after removal.
        if (destination >= model.layers.size()) return failure(Code::invalidReorder, "reorder", "destination", id);
        if (destination == static_cast<std::size_t>(it - model.layers.begin())) return {};
        auto candidate = model.layers;
        auto layer = *it;
        candidate.erase(candidate.begin() + (it - model.layers.begin()));
        candidate.insert(candidate.begin() + destination, std::move(layer));
        publish(std::move(candidate));
        return {};
    }
    bool undoForTest() {
        std::lock_guard<std::mutex> lock(mutex);
        if (past.empty()) return false;
        auto restored = past.back();
        model.layers.swap(restored.layers);
        model.state = restored.state;
        ++model.generation;
        past.pop_back();
        return true;
    }
};
}
