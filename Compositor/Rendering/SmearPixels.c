#include "SmearPixels.h"
#include <dispatch/dispatch.h>
#include <math.h>
#include <stdatomic.h>
#include <stdlib.h>

/// Counts dabs, so no two round alike, even one clicked again and again in the same place.
static _Atomic uint32_t smear_dab_count;

static inline float smear_weight(float u, float hardness) {
    if (u >= 1) return 0;
    if (u <= hardness) return 1;
    float t = (1 - u) / (1 - hardness);
    return t * t * (3 - 2 * t);
}

void smear_blur_dab(uint8_t *rgba, size_t width, size_t height, size_t stride, double cx, double cy, double radius,
                    double hardness, double strength, double sigma) {
    if (!width || !height || radius <= 0 || strength <= 0 || !(sigma > 0)) return;
    long r = (long)ceil(radius);
    long x0 = (long)floor(cx) - r, x1 = (long)ceil(cx) + r, y0 = (long)floor(cy) - r, y1 = (long)ceil(cy) + r;
    if (x0 < 0) x0 = 0;
    if (y0 < 0) y0 = 0;
    if (x1 > (long)width - 1) x1 = (long)width - 1;
    if (y1 > (long)height - 1) y1 = (long)height - 1;
    if (x0 > x1 || y0 > y1) return;
    const size_t w = (size_t)(x1 - x0 + 1), h = (size_t)(y1 - y0 + 1), n = w * h;
    // The pair (p, q) trades s·√w(p)·√w(q)·G(p − q) of their difference — the brush's weight between them, as the
    // geometric mean: a product of the two falls off twice as steeply toward the rim, and pulls what spreads toward the
    // brush's center. With v = √w, what p gets is
    //     s·v(p)·[G∗(v·I) − I·(G∗v)](p)
    // — two Gaussian blurs, of the weighted pixels and of the weights, each run as two one-dimensional passes. Past the
    // dab (and the canvas) the weight is nothing, so nothing is traded there.
    // Five values a pixel: its weighted color and alpha, then its weight.
    float *a = malloc(n * 5 * sizeof(float)), *b = malloc(n * 5 * sizeof(float)), *k = malloc(n * sizeof(float));
    const long kr = (long)ceil(3 * sigma);
    float *kernel = malloc((size_t)(2 * kr + 1) * sizeof(float));
    if (!a || !b || !k || !kernel) { free(a); free(b); free(k); free(kernel); return; }
    float sum = 0;
    for (long i = -kr; i <= kr; ++i) { kernel[i + kr] = expf(-(float)(i * i) / (float)(2 * sigma * sigma)); sum += kernel[i + kr]; }
    for (long i = 0; i <= 2 * kr; ++i) kernel[i] /= sum;
    const float invR = (float)(1 / radius), hard = (float)fmin(0.98, fmax(0, hardness)), s = (float)fmin(1, fmax(0, strength));
    for (size_t y = 0; y < h; ++y) {
        const uint8_t *row = rgba + (y + (size_t)y0) * stride + (size_t)x0 * 4;
        for (size_t x = 0; x < w; ++x) {
            float dx = (float)((long)x + x0) - (float)cx, dy = (float)((long)y + y0) - (float)cy;
            float weight = sqrtf(smear_weight(sqrtf(dx * dx + dy * dy) * invR, hard));
            size_t i = y * w + x;
            k[i] = weight;
            for (int c = 0; c < 4; ++c) a[i * 5 + c] = weight * row[x * 4 + c];
            a[i * 5 + 4] = weight;
        }
    }
    // Across the rows, a into b; then down the columns, b into a. Big dabs share the rows (or columns) over the cores.
    const int parallel = n * (size_t)(2 * kr + 1) >= 65536;
    void (^across)(size_t) = ^(size_t y) {
        for (size_t x = 0; x < w; ++x) {
            float acc[5] = {0, 0, 0, 0, 0};
            long from = (long)x - kr < 0 ? 0 : (long)x - kr, to = (long)x + kr > (long)w - 1 ? (long)w - 1 : (long)x + kr;
            for (long q = from; q <= to; ++q) {
                const float g = kernel[q - (long)x + kr], *src = a + (y * w + (size_t)q) * 5;
                for (int c = 0; c < 5; ++c) acc[c] += g * src[c];
            }
            for (int c = 0; c < 5; ++c) b[(y * w + x) * 5 + c] = acc[c];
        }
    };
    void (^down)(size_t) = ^(size_t x) {
        for (size_t y = 0; y < h; ++y) {
            float acc[5] = {0, 0, 0, 0, 0};
            long from = (long)y - kr < 0 ? 0 : (long)y - kr, to = (long)y + kr > (long)h - 1 ? (long)h - 1 : (long)y + kr;
            for (long q = from; q <= to; ++q) {
                const float g = kernel[q - (long)y + kr], *src = b + ((size_t)q * w + x) * 5;
                for (int c = 0; c < 5; ++c) acc[c] += g * src[c];
            }
            for (int c = 0; c < 5; ++c) a[(y * w + x) * 5 + c] = acc[c];
        }
    };
    if (parallel) { dispatch_apply(h, DISPATCH_APPLY_AUTO, across); dispatch_apply(w, DISPATCH_APPLY_AUTO, down); }
    else { for (size_t y = 0; y < h; ++y) across(y); for (size_t x = 0; x < w; ++x) down(x); }
    const uint32_t seed = atomic_fetch_add_explicit(&smear_dab_count, 1, memory_order_relaxed) * 2654435761u;
    for (size_t y = 0; y < h; ++y) {
        uint8_t *row = rgba + (y + (size_t)y0) * stride + (size_t)x0 * 4;
        for (size_t x = 0; x < w; ++x) {
            size_t i = y * w + x;
            if (k[i] <= 0) continue;
            const float *blurred = a + i * 5, share = s * k[i];
            float p[4];
            // Never more than it has to give (s·v·G∗v ≤ 1): each result lies between the colors it mixes.
            for (int c = 0; c < 4; ++c) p[c] = row[x * 4 + c] + share * (blurred[c] - row[x * 4 + c] * blurred[4]);
            // Rounded to 8 bits about a threshold that varies from pixel to pixel and dab to dab: always at a half, the
            // faint edge of what spreads rounds the same way every time, and a stroke gone over again and again loses
            // it. Kept within 0.05–0.95, a pixel the dab leaves as it was stays exactly so.
            uint32_t hash = (uint32_t)((long)x + x0) * 73856093u ^ (uint32_t)((long)y + y0) * 19349663u ^ seed;
            hash ^= hash >> 13; hash *= 0x5bd1e995u; hash ^= hash >> 15;
            const float threshold = 0.05f + 0.9f * (float)(hash & 0xffff) / 65535.0f;
            // Premultiplied: no color above its alpha.
            float alpha = floorf(fminf(255, fmaxf(0, p[3])) + threshold);
            if (alpha > 255) alpha = 255;
            for (int c = 0; c < 3; ++c) row[x * 4 + c] = (uint8_t)fminf(alpha, floorf(fmaxf(0, p[c]) + threshold));
            row[x * 4 + 3] = (uint8_t)alpha;
        }
    }
    free(a); free(b); free(k); free(kernel);
}
