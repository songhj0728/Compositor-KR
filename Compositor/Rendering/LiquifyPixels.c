#include "LiquifyPixels.h"
#include <dispatch/dispatch.h>
#include <math.h>
#include <stdlib.h>
#include <string.h>

// Rows are shared out over the cores once there are at least this many pixels to do.
static const size_t liquify_parallel_pixels = 65536;

static inline float liquify_weight(float u, float hardness) {
    if (u >= 1) return 0;
    if (u <= hardness) return 1;
    float t = (1 - u) / (1 - hardness);
    return t * t * (3 - 2 * t);
}

static inline long liquify_clamp(long v, long lo, long hi) { return v < lo ? lo : v > hi ? hi : v; }

// The columns of row `y` inside the brush's circle, within bx0…bx1; 0 when the row misses it.
static inline int liquify_span(long y, float cy, float cx, float radius, long bx0, long bx1, long *x0, long *x1) {
    float dy = (float)y - cy, reach = radius * radius - dy * dy;
    if (reach <= 0) return 0;
    float half = sqrtf(reach);
    *x0 = liquify_clamp((long)floorf(cx - half), bx0, bx1);
    *x1 = liquify_clamp((long)ceilf(cx + half), bx0, bx1);
    return *x0 <= *x1;
}

// Runs `body` for rows 0..<count, over the cores when `pixels` is worth it.
static void liquify_rows(size_t count, size_t pixels, void (^body)(size_t row)) {
    if (pixels < liquify_parallel_pixels || count < 8) {
        for (size_t row = 0; row < count; ++row) body(row);
        return;
    }
    dispatch_apply(count, DISPATCH_APPLY_AUTO, body);
}

int liquify_dab(float *field, size_t width, size_t height, int mode, double fromX, double fromY, double toX, double toY,
                double diameter, double hardness, double strength, long dirty[4]) {
    dirty[0] = 0; dirty[1] = 0; dirty[2] = -1; dirty[3] = -1;
    if (!width || !height || diameter <= 0) return 0;
    const float radius = (float)(diameter / 2), invR = 1 / radius, hard = (float)hardness, s = (float)strength;
    const float mx = (float)(toX - fromX) * s, my = (float)(toY - fromY) * s;
    const float cx = (float)toX, cy = (float)toY;
    // How far a displacement can reach past the rim, so the copy the dab samples from covers it.
    float reach = 0;
    const float pucker = 0.03f * s, turn = 0.04f * s, restore = 0.15f * s;
    switch (mode) {
    case LIQUIFY_FORWARD_WARP: case LIQUIFY_PUSH_LEFT: reach = fmaxf(fabsf(mx), fabsf(my)); break;
    case LIQUIFY_PUCKER: case LIQUIFY_BLOAT: reach = radius * pucker; break;
    case LIQUIFY_TWIRL_CLOCKWISE: reach = radius * turn; break;
    default: break;
    }
    const long r = (long)ceilf(radius), margin = (long)ceilf(reach) + 2;
    const long bx0 = liquify_clamp((long)floorf(cx) - r, 0, (long)width - 1), bx1 = liquify_clamp((long)ceilf(cx) + r, 0, (long)width - 1);
    const long by0 = liquify_clamp((long)floorf(cy) - r, 0, (long)height - 1), by1 = liquify_clamp((long)ceilf(cy) + r, 0, (long)height - 1);
    if (bx0 > bx1 || by0 > by1) return 0;
    const size_t rows = (size_t)(by1 - by0 + 1), columns = (size_t)(bx1 - bx0 + 1);

    if (mode == LIQUIFY_RECONSTRUCT) {
        // The field eases back toward nothing, all the way once it is under a hundredth of a pixel.
        liquify_rows(rows, rows * columns, ^(size_t row) {
            long y = by0 + (long)row, x0, x1;
            if (!liquify_span(y, cy, cx, radius, bx0, bx1, &x0, &x1)) return;
            for (long x = x0; x <= x1; ++x) {
                float dx = (float)x - cx, dy = (float)y - cy;
                float w = liquify_weight(sqrtf(dx * dx + dy * dy) * invR, hard) * restore;
                if (w <= 0) continue;
                float *f = field + ((size_t)y * width + (size_t)x) * 2;
                f[0] -= f[0] * w; f[1] -= f[1] * w;
                if (fabsf(f[0]) < 0.01f) f[0] = 0;
                if (fabsf(f[1]) < 0.01f) f[1] = 0;
            }
        });
    } else {
        // A copy of the field around the dab as it was before it, which the dab samples from.
        const long sx0 = liquify_clamp(bx0 - margin, 0, (long)width - 1), sx1 = liquify_clamp(bx1 + margin, 0, (long)width - 1);
        const long sy0 = liquify_clamp(by0 - margin, 0, (long)height - 1), sy1 = liquify_clamp(by1 + margin, 0, (long)height - 1);
        const size_t cw = (size_t)(sx1 - sx0 + 1), ch = (size_t)(sy1 - sy0 + 1);
        float *copy = malloc(cw * ch * 2 * sizeof(float));
        if (!copy) return -1;
        for (size_t y = 0; y < ch; ++y)
            memcpy(copy + y * cw * 2, field + ((size_t)(y + (size_t)sy0) * width + (size_t)sx0) * 2, cw * 2 * sizeof(float));
        liquify_rows(rows, rows * columns, ^(size_t row) {
            long y = by0 + (long)row, x0, x1;
            if (!liquify_span(y, cy, cx, radius, bx0, bx1, &x0, &x1)) return;
            for (long x = x0; x <= x1; ++x) {
                float dx = (float)x - cx, dy = (float)y - cy;
                float w = liquify_weight(sqrtf(dx * dx + dy * dy) * invR, hard);
                if (w <= 0) continue;
                // How the content under this pixel moves: it now shows what was `v` behind it.
                float vx, vy;
                switch (mode) {
                case LIQUIFY_FORWARD_WARP: vx = mx * w; vy = my * w; break;
                // To the left of the brush's travel (rows top-down: y points down).
                case LIQUIFY_PUSH_LEFT: vx = my * w; vy = -mx * w; break;
                case LIQUIFY_PUCKER: vx = -dx * w * pucker; vy = -dy * w * pucker; break;
                case LIQUIFY_BLOAT: vx = dx * w * pucker; vy = dy * w * pucker; break;
                case LIQUIFY_TWIRL_CLOCKWISE: {
                    float a = turn * w, c = cosf(a), n = sinf(a);
                    vx = dx * c - dy * n - dx; vy = dx * n + dy * c - dy;
                    break;
                }
                default: vx = 0; vy = 0; break;
                }
                // F'(p) = F(p - v) - v, sampling the old field bilinearly.
                float px = fminf((float)(cw - 1), fmaxf(0, (float)(x - sx0) - vx));
                float py = fminf((float)(ch - 1), fmaxf(0, (float)(y - sy0) - vy));
                size_t ix = (size_t)px, iy = (size_t)py;
                if (ix > cw - 2 && cw > 1) ix = cw - 2;
                if (iy > ch - 2 && ch > 1) iy = ch - 2;
                float fx = cw > 1 ? px - (float)ix : 0, fy = ch > 1 ? py - (float)iy : 0;
                const float *a00 = copy + (iy * cw + ix) * 2;
                const float *a10 = cw > 1 ? a00 + 2 : a00, *a01 = ch > 1 ? a00 + cw * 2 : a00, *a11 = cw > 1 ? a01 + 2 : a01;
                float *f = field + ((size_t)y * width + (size_t)x) * 2;
                for (int k = 0; k < 2; ++k) {
                    float top = a00[k] + (a10[k] - a00[k]) * fx, bottom = a01[k] + (a11[k] - a01[k]) * fx;
                    f[k] = top + (bottom - top) * fy - (k == 0 ? vx : vy);
                }
            }
        });
        free(copy);
    }
    dirty[0] = bx0; dirty[1] = by0; dirty[2] = bx1; dirty[3] = by1;
    return 0;
}

// The source at (x, y), bilinearly, clamped to its edge.
static inline void liquify_sample(const uint8_t *source, size_t width, size_t height, float x, float y, uint8_t *out) {
    x = fminf((float)(width - 1), fmaxf(0, x));
    y = fminf((float)(height - 1), fmaxf(0, y));
    size_t ix = (size_t)x, iy = (size_t)y;
    size_t ix1 = ix + 1 < width ? ix + 1 : ix, iy1 = iy + 1 < height ? iy + 1 : iy;
    float fx = x - (float)ix, fy = y - (float)iy;
    const uint8_t *p00 = source + (iy * width + ix) * 4, *p10 = source + (iy * width + ix1) * 4;
    const uint8_t *p01 = source + (iy1 * width + ix) * 4, *p11 = source + (iy1 * width + ix1) * 4;
    for (int k = 0; k < 4; ++k) {
        float top = p00[k] + (p10[k] - p00[k]) * fx, bottom = p01[k] + (p11[k] - p01[k]) * fx;
        float v = top + (bottom - top) * fy + 0.5f;
        out[k] = (uint8_t)(v < 0 ? 0 : v > 255 ? 255 : v);
    }
}

void liquify_render(const uint8_t *source, uint8_t *output, size_t width, size_t height, const float *field,
                    long x0, long y0, long x1, long y1) {
    if (!width || !height) return;
    x0 = liquify_clamp(x0, 0, (long)width - 1); x1 = liquify_clamp(x1, 0, (long)width - 1);
    y0 = liquify_clamp(y0, 0, (long)height - 1); y1 = liquify_clamp(y1, 0, (long)height - 1);
    if (x0 > x1 || y0 > y1) return;
    const size_t rows = (size_t)(y1 - y0 + 1), columns = (size_t)(x1 - x0 + 1);
    liquify_rows(rows, rows * columns, ^(size_t row) {
        size_t y = (size_t)y0 + row;
        for (size_t x = (size_t)x0; x <= (size_t)x1; ++x) {
            const float *f = field + (y * width + x) * 2;
            uint8_t *out = output + (y * width + x) * 4;
            if (f[0] == 0 && f[1] == 0) { memcpy(out, source + (y * width + x) * 4, 4); continue; }
            liquify_sample(source, width, height, (float)x + f[0], (float)y + f[1], out);
        }
    });
}

void liquify_render_scaled(const uint8_t *source, uint8_t *output, size_t width, size_t height,
                           const float *field, size_t fieldWidth, size_t fieldHeight) {
    if (!width || !height || !fieldWidth || !fieldHeight) return;
    const float sx = (float)fieldWidth / (float)width, sy = (float)fieldHeight / (float)height;
    liquify_rows(height, width * height, ^(size_t y) {
        // Pixel centers line up between the two grids.
        float qy = fminf((float)(fieldHeight - 1), fmaxf(0, ((float)y + 0.5f) * sy - 0.5f));
        size_t iy = (size_t)qy, iy1 = iy + 1 < fieldHeight ? iy + 1 : iy;
        float fy = qy - (float)iy;
        for (size_t x = 0; x < width; ++x) {
            float qx = fminf((float)(fieldWidth - 1), fmaxf(0, ((float)x + 0.5f) * sx - 0.5f));
            size_t ix = (size_t)qx, ix1 = ix + 1 < fieldWidth ? ix + 1 : ix;
            float fx = qx - (float)ix;
            const float *a00 = field + (iy * fieldWidth + ix) * 2, *a10 = field + (iy * fieldWidth + ix1) * 2;
            const float *a01 = field + (iy1 * fieldWidth + ix) * 2, *a11 = field + (iy1 * fieldWidth + ix1) * 2;
            float d[2];
            for (int k = 0; k < 2; ++k) {
                float top = a00[k] + (a10[k] - a00[k]) * fx, bottom = a01[k] + (a11[k] - a01[k]) * fx;
                d[k] = top + (bottom - top) * fy;
            }
            uint8_t *out = output + (y * width + x) * 4;
            if (d[0] == 0 && d[1] == 0) { memcpy(out, source + (y * width + x) * 4, 4); continue; }
            // The field is in its own pixels; in the full-size image a pixel of it spans 1 / scale.
            liquify_sample(source, width, height, (float)x + d[0] / sx, (float)y + d[1] / sy, out);
        }
    });
}
