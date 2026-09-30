// Tests for the shared pixel code, run the same way on macOS and Windows (see CMakeLists.txt). They check that
// the code gives the macOS app's results wherever it's built, and that sharing work out over the cores changes nothing.
#include "LiquifyPixels.h"
#include "ParallelFor.h"
#include "SmearPixels.h"
#include "LiquifySmearReference.h"
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int parallel_for_serial = 0;  // ParallelFor.h's test switch (PARALLEL_FOR_TESTING).
static int failures = 0;

#define CHECK(condition, ...)                                                   \
    do {                                                                        \
        if (!(condition)) {                                                     \
            ++failures;                                                         \
            fprintf(stderr, "FAIL %s:%d: ", __FILE__, __LINE__);                \
            fprintf(stderr, __VA_ARGS__);                                       \
            fputc('\n', stderr);                                                \
        }                                                                       \
    } while (0)

// The inputs: the same pseudo-random images, in the same order, as the ones the reference was made from.
static uint32_t rng;
static uint8_t next8(void) { rng = rng * 1664525u + 1013904223u; return (uint8_t)(rng >> 24); }

static uint8_t *make_image(size_t w, size_t h) {
    uint8_t *p = malloc(w * h * 4);
    for (size_t y = 0; y < h; ++y)
        for (size_t x = 0; x < w; ++x) {
            uint8_t *q = p + (y * w + x) * 4;
            uint8_t a = (uint8_t)(128 + (next8() >> 1));
            q[0] = (uint8_t)((x * 7 + (next8() & 15)) % (a + 1));
            q[1] = (uint8_t)((y * 5 + (next8() & 15)) % (a + 1));
            q[2] = (uint8_t)(((x + y) * 3) % (a + 1));
            q[3] = a;
        }
    return p;
}

// Four dabs of each tool but Reconstruct, travelling right and down.
static void warp_dabs(float *field, size_t w, size_t h, ptrdiff_t *dirty) {
    int k = 0;
    for (int mode = 0; mode <= LIQUIFY_PUSH_LEFT; ++mode) {
        if (mode == LIQUIFY_RECONSTRUCT) continue;
        double fx = (double)w * 0.3, fy = (double)h * 0.4;
        for (int i = 0; i < 4; ++i) {
            double tx = fx + (double)w * 0.05, ty = fy + (double)h * 0.03;
            liquify_dab(field, w, h, mode, fx, fy, tx, ty, (double)w * 0.6, 0.3, 0.8, dirty + 4 * k++);
            fx = tx; fy = ty;
        }
    }
}

static void reconstruct_dabs(float *field, size_t w, size_t h, ptrdiff_t dirty[4]) {
    for (int i = 0; i < 3; ++i)
        liquify_dab(field, w, h, LIQUIFY_RECONSTRUCT, (double)w * 0.4, (double)h * 0.5, (double)w * 0.45,
                    (double)h * 0.5, (double)w * 0.7, 0.2, 0.9, dirty);
}

// Two dabs, seeded 0 and 1 as the app's first two dabs are, so their rounding matches the reference.
static void smear_dabs(uint8_t *rgba, size_t w, size_t h, double sigma1, double sigma2) {
    smear_blur_dab(rgba, w, h, w * 4, (double)w * 0.5, (double)h * 0.45, (double)w * 0.35, 0.25, 0.9, sigma1, 0);
    smear_blur_dab(rgba, w, h, w * 4, (double)w * 0.3, (double)h * 0.6, (double)w * 0.2, 0.6, 0.5, sigma2, 1);
}

// Compilers and CPUs round sines, square roots and fused multiply-adds slightly differently, so results are compared
// within a tolerance: a pixel may be off by a level or two, or a displacement by a fraction of a pixel, where a value
// lands right on a threshold, but on average they must match to within a hundredth of a level — Smear 5% weaker
// already moves them by eight hundredths.
static void expect_bytes_near(const char *name, const uint8_t *actual, const uint8_t *expected, size_t n) {
    int worst = 0;
    double total = 0;
    for (size_t i = 0; i < n; ++i) {
        int d = abs((int)actual[i] - (int)expected[i]);
        if (d > worst) worst = d;
        total += d;
    }
    CHECK(worst <= 2, "%s: a value is off by %d levels", name, worst);
    CHECK(total / (double)n <= 0.01, "%s: values are off by %.4f levels on average", name, total / (double)n);
}

static void expect_floats_near(const char *name, const float *actual, const float *expected, size_t n) {
    double worst = 0, total = 0;
    for (size_t i = 0; i < n; ++i) {
        double d = fabs((double)actual[i] - (double)expected[i]);
        if (d > worst) worst = d;
        total += d;
    }
    CHECK(worst <= 0.02, "%s: a value is off by %g", name, worst);
    CHECK(total / (double)n <= 0.0001, "%s: values are off by %g on average", name, total / (double)n);
}

static void test_liquify_and_smear_match_reference(void) {
    rng = 12345;
    const size_t W = 24, H = 18;
    uint8_t *source = make_image(W, H);
    float *field = calloc(W * H * 2, sizeof(float));
    ptrdiff_t dirty[4 * 20];
    warp_dabs(field, W, H, dirty);
    CHECK(!memcmp(dirty, reference_dirty, sizeof dirty), "liquify: the changed rectangles differ");
    expect_floats_near("liquify field", field, reference_warped_field, W * H * 2);

    uint8_t *render = calloc(W * H * 4, 1);
    liquify_render(source, render, W, H, field, 0, 0, (ptrdiff_t)W - 1, (ptrdiff_t)H - 1);
    expect_bytes_near("liquify render", render, reference_render, W * H * 4);

    const size_t SW = W * 3 / 2, SH = H * 3 / 2;
    uint8_t *scaledSource = make_image(SW, SH), *scaled = calloc(SW * SH * 4, 1);
    liquify_render_scaled(scaledSource, scaled, SW, SH, field, W, H);
    expect_bytes_near("liquify scaled render", scaled, reference_render_scaled, SW * SH * 4);

    ptrdiff_t reconstructDirty[4];
    reconstruct_dabs(field, W, H, reconstructDirty);
    CHECK(!memcmp(reconstructDirty, reference_reconstruct_dirty, sizeof reconstructDirty),
          "liquify reconstruct: the changed rectangle differs");
    expect_floats_near("liquify reconstructed field", field, reference_reconstructed_field, W * H * 2);

    const size_t MW = 24, MH = 24;
    uint8_t *smear = make_image(MW, MH);
    smear_dabs(smear, MW, MH, 2.0, 1.2);
    expect_bytes_near("smear", smear, reference_smear, MW * MH * 4);

    free(source); free(field); free(render); free(scaledSource); free(scaled); free(smear);
}

// Big enough that Liquify and Smear share their rows out: those results must be exactly what one thread gets.
typedef struct {
    float *warped, *reconstructed;
    uint8_t *render, *scaled, *smear;
} big_results;

static big_results run_big(void) {
    rng = 777;
    const size_t W = 700, H = 500, SW = 1050, SH = 750, MW = 400, MH = 300;
    big_results r;
    uint8_t *source = make_image(W, H);
    float *field = calloc(W * H * 2, sizeof(float));
    ptrdiff_t dirty[4 * 20];
    warp_dabs(field, W, H, dirty);
    r.warped = malloc(W * H * 2 * sizeof(float));
    memcpy(r.warped, field, W * H * 2 * sizeof(float));
    r.render = calloc(W * H * 4, 1);
    liquify_render(source, r.render, W, H, field, 0, 0, (ptrdiff_t)W - 1, (ptrdiff_t)H - 1);
    uint8_t *scaledSource = make_image(SW, SH);
    r.scaled = calloc(SW * SH * 4, 1);
    liquify_render_scaled(scaledSource, r.scaled, SW, SH, field, W, H);
    reconstruct_dabs(field, W, H, dirty);
    r.reconstructed = field;
    r.smear = make_image(MW, MH);
    smear_dabs(r.smear, MW, MH, 6.0, 3.0);
    free(source); free(scaledSource);
    return r;
}

static void test_threads_change_nothing(void) {
    parallel_for_serial = 1;
    big_results serial = run_big();
    parallel_for_serial = 0;
    for (int run = 0; run < 3; ++run) {
        big_results parallel = run_big();
        CHECK(!memcmp(serial.warped, parallel.warped, 700 * 500 * 2 * sizeof(float)), "threaded liquify field differs");
        CHECK(!memcmp(serial.render, parallel.render, 700 * 500 * 4), "threaded liquify render differs");
        CHECK(!memcmp(serial.scaled, parallel.scaled, 1050 * 750 * 4), "threaded scaled render differs");
        CHECK(!memcmp(serial.reconstructed, parallel.reconstructed, 700 * 500 * 2 * sizeof(float)),
              "threaded reconstruct differs");
        CHECK(!memcmp(serial.smear, parallel.smear, 400 * 300 * 4), "threaded smear differs");
        free(parallel.warped); free(parallel.render); free(parallel.scaled); free(parallel.reconstructed);
        free(parallel.smear);
    }
    free(serial.warped); free(serial.render); free(serial.scaled); free(serial.reconstructed); free(serial.smear);
}

static void count_index(void *context, size_t index) { ((unsigned char *)context)[index] += 1; }

static void test_parallel_for_runs_each_index_once(void) {
    const size_t counts[] = { 0, 1, 2, 7, 1000, 100003 };
    for (size_t c = 0; c < sizeof counts / sizeof counts[0]; ++c) {
        size_t n = counts[c];
        unsigned char *seen = calloc(n ? n : 1, 1);
        parallel_for(n, seen, count_index);
        size_t wrong = 0;
        for (size_t i = 0; i < n; ++i) wrong += seen[i] != 1;
        CHECK(!wrong, "parallel_for(%zu): %zu indices not run exactly once", n, wrong);
        free(seen);
    }
}

int main(void) {
    test_parallel_for_runs_each_index_once();
    test_liquify_and_smear_match_reference();
    test_threads_change_nothing();
    if (failures) {
        fprintf(stderr, "%d check(s) failed\n", failures);
        return 1;
    }
    printf("All pixel tests passed\n");
    return 0;
}
