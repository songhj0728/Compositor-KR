#include "SmearPixels.h"
#include "ParallelFor.h"
#include <math.h>
#include <stdlib.h>

static inline float smear_weight(float u, float hardness) {
    if (u >= 1) return 0;
    if (u <= hardness) return 1;
    float t = (1 - u) / (1 - hardness);
    return t * t * (3 - 2 * t);
}

// A dab's two Gaussian passes: across the rows of `from` into `to`, then down the columns back. Five values a pixel.
typedef struct {
    float *from, *to;
    size_t w, h;
    const float *kernel;
    ptrdiff_t kr;
} smear_pass;

static void smear_across(void *context, size_t y) {
    const smear_pass *p = context;
    const size_t w = p->w;
    const ptrdiff_t kr = p->kr;
    for (size_t x = 0; x < w; ++x) {
        float acc[5] = {0, 0, 0, 0, 0};
        ptrdiff_t from = (ptrdiff_t)x - kr < 0 ? 0 : (ptrdiff_t)x - kr;
        ptrdiff_t to = (ptrdiff_t)x + kr > (ptrdiff_t)w - 1 ? (ptrdiff_t)w - 1 : (ptrdiff_t)x + kr;
        for (ptrdiff_t q = from; q <= to; ++q) {
            const float g = p->kernel[q - (ptrdiff_t)x + kr], *src = p->from + (y * w + (size_t)q) * 5;
            for (int c = 0; c < 5; ++c) acc[c] += g * src[c];
        }
        for (int c = 0; c < 5; ++c) p->to[(y * w + x) * 5 + c] = acc[c];
    }
}

static void smear_down(void *context, size_t x) {
    const smear_pass *p = context;
    const size_t w = p->w, h = p->h;
    const ptrdiff_t kr = p->kr;
    for (size_t y = 0; y < h; ++y) {
        float acc[5] = {0, 0, 0, 0, 0};
        ptrdiff_t from = (ptrdiff_t)y - kr < 0 ? 0 : (ptrdiff_t)y - kr;
        ptrdiff_t to = (ptrdiff_t)y + kr > (ptrdiff_t)h - 1 ? (ptrdiff_t)h - 1 : (ptrdiff_t)y + kr;
        for (ptrdiff_t q = from; q <= to; ++q) {
            const float g = p->kernel[q - (ptrdiff_t)y + kr], *src = p->to + ((size_t)q * w + x) * 5;
            for (int c = 0; c < 5; ++c) acc[c] += g * src[c];
        }
        for (int c = 0; c < 5; ++c) p->from[(y * w + x) * 5 + c] = acc[c];
    }
}

void smear_blur_dab(uint8_t *rgba, size_t width, size_t height, size_t stride, double cx, double cy, double radius,
                    double hardness, double strength, double sigma, uint32_t seed) {
    if (!width || !height || radius <= 0 || strength <= 0 || !(sigma > 0)) return;
    ptrdiff_t r = (ptrdiff_t)ceil(radius);
    ptrdiff_t x0 = (ptrdiff_t)floor(cx) - r, x1 = (ptrdiff_t)ceil(cx) + r, y0 = (ptrdiff_t)floor(cy) - r, y1 = (ptrdiff_t)ceil(cy) + r;
    if (x0 < 0) x0 = 0;
    if (y0 < 0) y0 = 0;
    if (x1 > (ptrdiff_t)width - 1) x1 = (ptrdiff_t)width - 1;
    if (y1 > (ptrdiff_t)height - 1) y1 = (ptrdiff_t)height - 1;
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
    const ptrdiff_t kr = (ptrdiff_t)ceil(3 * sigma);
    float *kernel = malloc((size_t)(2 * kr + 1) * sizeof(float));
    if (!a || !b || !k || !kernel) { free(a); free(b); free(k); free(kernel); return; }
    float sum = 0;
    for (ptrdiff_t i = -kr; i <= kr; ++i) { kernel[i + kr] = expf(-(float)(i * i) / (float)(2 * sigma * sigma)); sum += kernel[i + kr]; }
    for (ptrdiff_t i = 0; i <= 2 * kr; ++i) kernel[i] /= sum;
    const float invR = (float)(1 / radius), hard = (float)fmin(0.98, fmax(0, hardness)), s = (float)fmin(1, fmax(0, strength));
    for (size_t y = 0; y < h; ++y) {
        const uint8_t *row = rgba + (y + (size_t)y0) * stride + (size_t)x0 * 4;
        for (size_t x = 0; x < w; ++x) {
            float dx = (float)((ptrdiff_t)x + x0) - (float)cx, dy = (float)((ptrdiff_t)y + y0) - (float)cy;
            float weight = sqrtf(smear_weight(sqrtf(dx * dx + dy * dy) * invR, hard));
            size_t i = y * w + x;
            k[i] = weight;
            for (int c = 0; c < 4; ++c) a[i * 5 + c] = weight * row[x * 4 + c];
            a[i * 5 + 4] = weight;
        }
    }
    // Across the rows, a into b; then down the columns, b into a. Big dabs share the rows (or columns) over the cores.
    smear_pass pass = { a, b, w, h, kernel, kr };
    if (n * (size_t)(2 * kr + 1) >= 65536) { parallel_for(h, &pass, smear_across); parallel_for(w, &pass, smear_down); }
    else { for (size_t y = 0; y < h; ++y) smear_across(&pass, y); for (size_t x = 0; x < w; ++x) smear_down(&pass, x); }
    seed *= 2654435761u;
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
            uint32_t hash = (uint32_t)((ptrdiff_t)x + x0) * 73856093u ^ (uint32_t)((ptrdiff_t)y + y0) * 19349663u ^ seed;
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
