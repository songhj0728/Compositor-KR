// Run on macOS, Linux or Windows with a C11 compiler; see docs/windows-patch-contract.md.
#include "../../Compositor/Core/StylePixels.h"
#include <assert.h>
#include <math.h>
#include <stdio.h>

int main(void) {
    enum { W = 17, H = 13, N = W * H };
    float shape[N], actual[N], reference[N];
    for (int kind = 0; kind < 3; ++kind) {
        for (int i = 0; i < N; ++i) shape[i] = kind == 0 ? 0 : kind == 1 ? 1 : ((i * 71 + i / W * 17) % 101) / 100.0f;
        assert(style_distances(shape, actual, W, H));
        for (int i = 0; i < N; ++i) {
            double nearest = W * W + H * H + 1;
            for (int j = 0; j < N; ++j) if ((shape[i] >= .5f) != (shape[j] >= .5f)) {
                double dx = i % W - j % W, dy = i / W - j / W;
                nearest = fmin(nearest, dx * dx + dy * dy);
            }
            float d = fmaxf(.01f, (float)sqrt(nearest) - 1 + fabsf(shape[i] - .5f));
            assert(fabsf(actual[i] - (shape[i] >= .5f ? d : -d)) < .0001f);
        }
    }
    for (int i = 0; i < N; ++i) shape[i] = (i % 37 - 18) / 7.0f;
    for (int horizontal = 0; horizontal <= 1; ++horizontal) for (int radius = 1; radius < 23; radius += 3) {
        style_box(shape, actual, W, H, radius, horizontal);
        for (int i = 0; i < N; ++i) {
            double sum = 0;
            for (int k = -radius; k <= radius; ++k) {
                int x = i % W + (horizontal ? k : 0), y = i / W + (horizontal ? 0 : k);
                if (x >= 0 && x < W && y >= 0 && y < H) sum += shape[y * W + x];
            }
            reference[i] = (float)sum / (2 * radius + 1);
            assert(fabsf(actual[i] - reference[i]) < .00001f);
        }
    }
    puts("Portable style distance and finite-support blur tests passed.");
    return 0;
}
