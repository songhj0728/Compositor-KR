#include "PixelParallel.h"

static volatile int pixel_parallel_enabled = 1;

void pixel_parallel_set_enabled(int enabled) { pixel_parallel_enabled = enabled != 0; }

static void pixel_parallel_serial(size_t count, void *context, void (*body)(void *, size_t)) {
    for (size_t index = 0; index < count; ++index) body(context, index);
}

#if defined(__APPLE__)
#include <dispatch/dispatch.h>

void pixel_parallel_for(size_t count, void *context, void (*body)(void *context, size_t index)) {
    if (!pixel_parallel_enabled || count < 2) { pixel_parallel_serial(count, context, body); return; }
    dispatch_apply_f(count, DISPATCH_APPLY_AUTO, context, body);
}

#elif defined(_WIN32)
#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#include <windows.h>

// Every worker, the calling thread included, takes the next index until none are left — as `dispatch_apply` does.
typedef struct {
    volatile LONG64 next;
    size_t count;
    void *context;
    void (*body)(void *, size_t);
} pixel_parallel_job;

static void pixel_parallel_drain(pixel_parallel_job *job) {
    for (;;) {
        LONG64 index = InterlockedIncrement64(&job->next) - 1;
        if ((size_t)index >= job->count) return;
        job->body(job->context, (size_t)index);
    }
}

static VOID CALLBACK pixel_parallel_worker(PTP_CALLBACK_INSTANCE instance, PVOID job, PTP_WORK work) {
    (void)instance; (void)work;
    pixel_parallel_drain((pixel_parallel_job *)job);
}

void pixel_parallel_for(size_t count, void *context, void (*body)(void *context, size_t index)) {
    if (!pixel_parallel_enabled || count < 2) { pixel_parallel_serial(count, context, body); return; }
    DWORD cores = GetActiveProcessorCount(ALL_PROCESSOR_GROUPS);
    size_t helpers = (cores > 1 ? (size_t)cores : 1) - 1;
    if (helpers > count - 1) helpers = count - 1;
    pixel_parallel_job job = { 0, count, context, body };
    PTP_WORK work = helpers ? CreateThreadpoolWork(pixel_parallel_worker, &job, NULL) : NULL;
    if (!work) { pixel_parallel_serial(count, context, body); return; }
    for (size_t i = 0; i < helpers; ++i) SubmitThreadpoolWork(work);
    pixel_parallel_drain(&job);
    WaitForThreadpoolWorkCallbacks(work, FALSE);
    CloseThreadpoolWork(work);
}

#else

void pixel_parallel_for(size_t count, void *context, void (*body)(void *context, size_t index)) {
    pixel_parallel_serial(count, context, body);
}

#endif
