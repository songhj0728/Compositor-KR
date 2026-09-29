#ifndef PixelParallel_h
#define PixelParallel_h
#include <stddef.h>
// The one place the pixel code reaches for threads, so it builds the same on macOS and Windows: Grand Central
// Dispatch on Apple platforms, the system thread pool on Windows, one thread anywhere else.

// Runs `body(context, index)` for every index in 0..<count, shared out over the cores, and returns once all are done.
// The calls can run in any order and at the same time, so each must only write what its own index owns.
void pixel_parallel_for(size_t count, void *context, void (*body)(void *context, size_t index));

// Off, `pixel_parallel_for` runs everything in order on the calling thread. On by default; tests turn it off to check
// the threaded results against one thread's.
void pixel_parallel_set_enabled(int enabled);
#endif
