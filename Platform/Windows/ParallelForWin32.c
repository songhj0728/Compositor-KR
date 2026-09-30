// parallel_for on Windows (Compositor/Rendering/ParallelFor.h): the process's system thread pool. Every worker, the
// calling thread included, takes the next index until none are left — the same scheme as dispatch_apply on macOS.
// Built only by CMakeLists.txt on Windows; the macOS app never sees this folder.
#if defined(_WIN32)
#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>
#include "ParallelFor.h"

typedef struct {
    volatile LONG64 next;
    size_t count;
    void *context;
    parallel_body body;
} parallel_job;

static void parallel_drain(parallel_job *job) {
    for (;;) {
        LONG64 index = InterlockedIncrement64(&job->next) - 1;
        if ((size_t)index >= job->count) return;
        job->body(job->context, (size_t)index);
    }
}

static VOID CALLBACK parallel_worker(PTP_CALLBACK_INSTANCE instance, PVOID job, PTP_WORK work) {
    (void)instance; (void)work;
    parallel_drain((parallel_job *)job);
}

void parallel_for_win32(size_t count, void *context, parallel_body body) {
    if (count < 2) {
        for (size_t i = 0; i < count; ++i) body(context, i);
        return;
    }
    DWORD cores = GetActiveProcessorCount(ALL_PROCESSOR_GROUPS);
    size_t helpers = (cores > 1 ? (size_t)cores : 1) - 1;
    if (helpers > count - 1) helpers = count - 1;
    parallel_job job = { 0, count, context, body };
    PTP_WORK work = helpers ? CreateThreadpoolWork(parallel_worker, &job, NULL) : NULL;
    if (!work) {
        for (size_t i = 0; i < count; ++i) body(context, i);
        return;
    }
    for (size_t i = 0; i < helpers; ++i) SubmitThreadpoolWork(work);
    parallel_drain(&job);
    WaitForThreadpoolWorkCallbacks(work, FALSE);
    CloseThreadpoolWork(work);
}
#endif
