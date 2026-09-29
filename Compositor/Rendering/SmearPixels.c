#include "SmearPixels.h"
#include <dispatch/dispatch.h>
#include <math.h>
#include <stdlib.h>

static inline float smear_weight(float u, float hardness) {
    if (u >= 1) return 0;
    if (u <= hardness) return 1;
    float t = (1 - u) / (1 - hardness);
    return t * t * (3 - 2 * t);
}

void smear_blur_dab(uint8_t *rgba, size_t width, size_t height, size_t stride, double cx, double cy, double radius,
                    double hardness, double strength, int iterations) {
    if (!width || !height || radius <= 0 || strength <= 0 || iterations <= 0) return;
    long r = (long)ceil(radius);
    long x0 = (long)floor(cx) - r, x1 = (long)ceil(cx) + r, y0 = (long)floor(cy) - r, y1 = (long)ceil(cy) + r;
    if (x0 < 0) x0 = 0;
    if (y0 < 0) y0 = 0;
    if (x1 > (long)width - 1) x1 = (long)width - 1;
    if (y1 > (long)height - 1) y1 = (long)height - 1;
    if (x0 > x1 || y0 > y1) return;
    const size_t w = (size_t)(x1 - x0 + 1), h = (size_t)(y1 - y0 + 1), n = w * h;
    float *a = malloc(n * 4 * sizeof(float)), *b = malloc(n * 4 * sizeof(float)), *k = malloc(n * sizeof(float));
    if (!a || !b || !k) { free(a); free(b); free(k); return; }
    // Each pixel's share: the brush's weight there. 0.2 per pass keeps the four-way exchange stable (below 0.25).
    const float invR = (float)(1 / radius), hard = (float)fmin(0.98, fmax(0, hardness)), s = (float)fmin(1, fmax(0, strength));
    for (size_t y = 0; y < h; ++y) {
        const uint8_t *row = rgba + (y + (size_t)y0) * stride + (size_t)x0 * 4;
        for (size_t x = 0; x < w; ++x) {
            float dx = (float)((long)x + x0) - (float)cx, dy = (float)((long)y + y0) - (float)cy;
            k[y * w + x] = 0.2f * s * smear_weight(sqrtf(dx * dx + dy * dy) * invR, hard);
            for (int c = 0; c < 4; ++c) a[(y * w + x) * 4 + c] = row[x * 4 + c];
        }
    }
    for (int pass = 0; pass < iterations; ++pass) {
        // Rows are independent within a pass: shared out over the cores for big brushes.
        void (^row)(size_t) = ^(size_t y) {
            for (size_t x = 0; x < w; ++x) {
                size_t i = y * w + x;
                float kp = k[i];
                const float *p = a + i * 4;
                float *out = b + i * 4;
                out[0] = p[0]; out[1] = p[1]; out[2] = p[2]; out[3] = p[3];
                if (kp <= 0) continue;
                // A neighbor past the dab's area or the canvas trades nothing: its share there is the lesser of the two.
                size_t neighbors[4]; int count = 0;
                if (x > 0) neighbors[count++] = i - 1;
                if (x + 1 < w) neighbors[count++] = i + 1;
                if (y > 0) neighbors[count++] = i - w;
                if (y + 1 < h) neighbors[count++] = i + w;
                for (int j = 0; j < count; ++j) {
                    float share = fminf(kp, k[neighbors[j]]);
                    if (share <= 0) continue;
                    const float *q = a + neighbors[j] * 4;
                    for (int c = 0; c < 4; ++c) out[c] += share * (q[c] - p[c]);
                }
            }
        };
        if (n >= 16384) dispatch_apply(h, DISPATCH_APPLY_AUTO, row);
        else for (size_t y = 0; y < h; ++y) row(y);
        float *swap = a; a = b; b = swap;
    }
    for (size_t y = 0; y < h; ++y) {
        uint8_t *row = rgba + (y + (size_t)y0) * stride + (size_t)x0 * 4;
        for (size_t x = 0; x < w; ++x) {
            if (k[y * w + x] <= 0) continue;
            const float *p = a + (y * w + x) * 4;
            // Premultiplied: no color above its alpha.
            float alpha = fminf(255, fmaxf(0, p[3]));
            for (int c = 0; c < 3; ++c) row[x * 4 + c] = (uint8_t)(fminf(alpha, fmaxf(0, p[c])) + 0.5f);
            row[x * 4 + 3] = (uint8_t)(alpha + 0.5f);
        }
    }
    free(a); free(b); free(k);
}
