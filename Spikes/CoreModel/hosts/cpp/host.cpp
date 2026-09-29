// A stand-in for a Windows UI: drives a Core only through include/compositor_core.h, as a C++/WinRT or C# WinUI app
// would. Built twice, once against each Core's DLL; both must behave the same.
#include "compositor_core.h"
#include <cstdio>
#include <cstring>
#include <string>
#ifdef _WIN32
#include <windows.h>
#endif

static int failures = 0;
#define CHECK(condition)                                                              \
    do {                                                                              \
        if (!(condition)) {                                                           \
            ++failures;                                                               \
            std::fprintf(stderr, "FAIL %s:%d: %s\n", __FILE__, __LINE__, #condition); \
        }                                                                             \
    } while (0)

static std::string undoName(const cc_history *history) {
    char buffer[128];
    cc_undo_name(history, buffer, sizeof buffer);
    return buffer;
}

static void printOutline(const cc_history *history) {
    for (size_t i = 0; i < cc_outline_count(history); ++i) {
        cc_layer_id id;
        int32_t depth, isGroup, isVisible;
        char name[256];
        cc_outline_row(history, i, &id, &depth, &isGroup, &isVisible, name, sizeof name);
        std::printf("  %*s%s %s%s (#%llu)\n", depth * 2, "", isGroup ? "[G]" : "[L]", name, isVisible ? "" : " (hidden)",
                    static_cast<unsigned long long>(id));
    }
}

int main() {
#ifdef _WIN32
    SetConsoleOutputCP(CP_UTF8);
#endif
    cc_history *history = cc_history_create(1920, 1080);
    CHECK(history != nullptr);

    cc_layer_id background = cc_add_layer(history, "배경", 0);
    cc_layer_id sky = cc_add_layer(history, "하늘", 0);
    cc_layer_id people = cc_add_layer(history, "People", 0);
    CHECK(background && sky && people);
    CHECK(undoName(history) == "Add Layer");

    cc_layer_id members[] = {sky, people};
    cc_layer_id group = cc_group(history, members, 2, "보정 그룹");
    CHECK(group != 0);
    CHECK(cc_set_visible(history, sky, 0) == 1);
    CHECK(cc_rename(history, people, "인물 레이어") == 1);
    CHECK(cc_rename(history, 12345, "nothing") == 0);  // No such layer: fails, records nothing.
    cc_layer_id twice[] = {background, background};    // Once crashed both Cores; now refused.
    CHECK(cc_group(history, twice, 2, "twice") == 0);
    CHECK(undoName(history) == "Rename Layer");

    std::printf("Outline:\n");
    printOutline(history);
    CHECK(cc_outline_count(history) == 4);

    // A buffer too short for a Korean name is cut between characters, never inside one (3 bytes each).
    char shortName[7];  // Room for six bytes: "보정", not the space after it.
    cc_layer_id id;
    int32_t depth, isGroup, isVisible;
    CHECK(cc_outline_row(history, 0, &id, &depth, &isGroup, &isVisible, shortName, sizeof shortName) == 1);
    CHECK(id == group && isGroup == 1 && depth == 0);
    CHECK(std::strcmp(shortName, "보정") == 0);
    char cutName[5];  // Four bytes would end inside "정": only "보" fits.
    CHECK(cc_outline_row(history, 0, &id, &depth, &isGroup, &isVisible, cutName, sizeof cutName) == 1);
    CHECK(std::strcmp(cutName, "보") == 0);
    CHECK(cc_outline_row(history, 99, &id, &depth, &isGroup, &isVisible, shortName, sizeof shortName) == 0);

    CHECK(cc_undo(history) && cc_undo(history) && cc_undo(history));  // Rename, hide, group.
    CHECK(cc_outline_count(history) == 3);
    CHECK(undoName(history) == "Add Layer");
    CHECK(cc_redo(history) == 1);
    CHECK(cc_outline_count(history) == 4);

    cc_history_destroy(history);
    if (failures) {
        std::fprintf(stderr, "%d check(s) failed\n", failures);
        return 1;
    }
    std::printf("Host checks passed\n");
    return 0;
}
