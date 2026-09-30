#ifndef ParallelFor_h
#define ParallelFor_h
#include <stddef.h>
#if defined(__APPLE__)
#include <dispatch/dispatch.h>
#endif

// Runs `body(context, i)` for every i in 0..<count, shared out over the cores where the platform offers a way: Grand
// Central Dispatch on Apple platforms, OpenMP where the compiler has it switched on (MSVC's /openmp, Clang and GCC's
// -fopenmp), one after another otherwise. The iterations must not depend on each other. A plain function and context
// rather than a block, which only Clang with Apple's blocks runtime compiles, so the pixel code builds anywhere.
typedef void (*parallel_body)(void *context, size_t index);

#if defined(_WIN32) && !defined(__APPLE__)
// Windows: the process's system thread pool (Platform/Windows/ParallelForWin32.c) — no OpenMP runtime to ship, and
// it shares the pool the rest of the process uses rather than starting a thread team of its own.
void parallel_for_win32(size_t count, void *context, parallel_body body);
#endif

#if defined(PARALLEL_FOR_TESTING)
// Set by the shared-code tests (CMake's test build only) to run every loop in order on one thread and compare.
extern int parallel_for_serial;
#endif

static inline void parallel_for(size_t count, void *context, parallel_body body) {
#if defined(PARALLEL_FOR_TESTING)
    if (parallel_for_serial) {
        for (size_t i = 0; i < count; ++i) body(context, i);
        return;
    }
#endif
#if defined(__APPLE__)
    dispatch_apply_f(count, DISPATCH_APPLY_AUTO, context, body);
#elif defined(_WIN32)
    parallel_for_win32(count, context, body);
#elif defined(_OPENMP)
    // MSVC's OpenMP 2.0 wants a signed int loop; rows and columns are far below its limit.
    const int n = (int)count;
    #pragma omp parallel for schedule(dynamic)
    for (int i = 0; i < n; ++i) body(context, (size_t)i);
#else
    for (size_t i = 0; i < count; ++i) body(context, i);
#endif
}

#endif
