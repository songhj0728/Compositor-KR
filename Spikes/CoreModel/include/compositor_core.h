// The document Core as plain C functions: the boundary a Windows UI (C++/WinRT, C#, Win32) calls. Both spike
// Cores implement it — the Swift one in swift/Sources/CoreModelCABI, the C++ one in cpp/src/c_api.cpp — so the same
// host programs run against either.
//
// Strings are UTF-8. Layer IDs are never 0; functions that make a layer return 0 when they fail. Functions that
// return int32_t return 1 on success and 0 on failure.
#ifndef compositor_core_h
#define compositor_core_h
#include <stddef.h>
#include <stdint.h>

#if defined(_WIN32) && defined(CC_BUILDING_DLL)
#define CC_API __declspec(dllexport)
#else
#define CC_API
#endif

#ifdef __cplusplus
extern "C" {
#endif

typedef struct cc_history cc_history;
typedef uint64_t cc_layer_id;

CC_API cc_history *cc_history_create(int32_t width, int32_t height);
CC_API void cc_history_destroy(cc_history *history);

// `parent` 0 adds at the top level. Each is one undoable step.
CC_API cc_layer_id cc_add_layer(cc_history *history, const char *name, cc_layer_id parent);
CC_API cc_layer_id cc_add_group(cc_history *history, const char *name, cc_layer_id parent);
CC_API cc_layer_id cc_group(cc_history *history, const cc_layer_id *ids, size_t count, const char *name);
CC_API int32_t cc_set_visible(cc_history *history, cc_layer_id id, int32_t visible);
CC_API int32_t cc_rename(cc_history *history, cc_layer_id id, const char *name);

CC_API int32_t cc_undo(cc_history *history);
CC_API int32_t cc_redo(cc_history *history);
// Copies the name of what Undo would take back into `buffer`, NUL-terminated and cut to fit. Returns the length of
// the whole name in bytes (without the NUL), or 0 when there is nothing to undo.
CC_API size_t cc_undo_name(const cc_history *history, char *buffer, size_t capacity);

// The layers panel's rows, top first. Fills the row at `index`; returns 0 when `index` is past the end.
CC_API size_t cc_outline_count(const cc_history *history);
CC_API int32_t cc_outline_row(const cc_history *history, size_t index, cc_layer_id *id, int32_t *depth,
                              int32_t *is_group, int32_t *is_visible, char *name, size_t name_capacity);

#ifdef __cplusplus
}
#endif
#endif
