#include "StylePixels.h"
#include <math.h>
#include <stdlib.h>

static float clamp(float v) { return fminf(1, fmaxf(0, v)); }
static void transform(double *field, int start, int stride, int count, double *values, int *sites, double *cuts) {
    for (int q = 0; q < count; ++q) values[q] = field[start + q * stride];
    int last = 0;
    sites[0] = 0; cuts[0] = -INFINITY; cuts[1] = INFINITY;
    for (int q = 1; q < count; ++q) {
        double crossing;
        do {
            int v = sites[last];
            crossing = ((values[q] + (double)q * q) - (values[v] + (double)v * v)) / (2.0 * (q - v));
            if (crossing > cuts[last]) break;
            --last;
        } while (last >= 0);
        ++last; sites[last] = q; cuts[last] = crossing; cuts[last + 1] = INFINITY;
    }
    last = 0;
    for (int q = 0; q < count; ++q) {
        while (cuts[last + 1] < q) ++last;
        double delta = q - sites[last];
        field[start + q * stride] = delta * delta + values[sites[last]];
    }
}
int style_distances(const float *alpha, float *distance, int width, int height) {
    if (width <= 0 || height <= 0) return 0;
    size_t count = (size_t)width * height;
    int length = width > height ? width : height;
    double *field = malloc(count * sizeof(double));
    double *values = malloc((size_t)length * sizeof(double));
    double *cuts = malloc(((size_t)length + 1) * sizeof(double));
    int *sites = malloc((size_t)length * sizeof(int));
    if (!field || !values || !cuts || !sites) { free(field); free(values); free(cuts); free(sites); return 0; }
    double limit = (double)width * width + (double)height * height + 1;
    for (int inside = 0; inside <= 1; ++inside) {
        for (size_t i = 0; i < count; ++i) field[i] = ((alpha[i] >= .5f) == inside) ? 0 : limit;
        for (int y = 0; y < height; ++y) transform(field, y * width, 1, width, values, sites, cuts);
        for (int x = 0; x < width; ++x) transform(field, x, width, height, values, sites, cuts);
        for (size_t i = 0; i < count; ++i) if ((alpha[i] >= .5f) != inside) {
            float d = fmaxf(.01f, (float)sqrt(field[i]) - 1 + fabsf(alpha[i] - .5f));
            distance[i] = inside ? -d : d;
        }
    }
    free(field); free(values); free(cuts); free(sites);
    return 1;
}
void style_box(const float *source, float *target, int width, int height, int radius, int horizontal) {
    int lines = horizontal ? height : width, length = horizontal ? width : height;
    int step = horizontal ? 1 : width, lineStep = horizontal ? width : 1;
    float scale = 1.0f / (2 * radius + 1);
    for (int line = 0; line < lines; ++line) {
        int base = line * lineStep;
        double sum = 0;
        for (int i = 0; i <= radius && i < length; ++i) sum += source[base + i * step];
        for (int i = 0; i < length; ++i) {
            target[base + i * step] = (float)sum * scale;
            if (i - radius >= 0) sum -= source[base + (i - radius) * step];
            if (i + radius + 1 < length) sum += source[base + (i + radius + 1) * step];
        }
    }
}
void style_unpack(const uint8_t *bytes, size_t stride, float *rgba, float *alpha, int width, int height) {
    for (int y = 0; y < height; ++y) for (int x = 0; x < width; ++x) {
        size_t i = (size_t)y * width + x;
        for (int c = 0; c < 4; ++c) rgba[4 * i + c] = bytes[y * stride + 4 * x + c] / 255.0f;
        alpha[i] = rgba[4 * i + 3];
    }
}
void style_pack(const float *rgba, uint8_t *bytes, size_t count) {
    for (size_t i = 0; i < count; ++i) {
        float a = clamp(rgba[4 * i + 3]);
        for (int c = 0; c < 3; ++c) bytes[4 * i + c] = (uint8_t)(fminf(a, fmaxf(0, rgba[4 * i + c])) * 255 + .5f);
        bytes[4 * i + 3] = (uint8_t)(a * 255 + .5f);
    }
}
void style_over(float *target, const float *source, float fill, size_t count) {
    for (size_t i = 0; i < count; ++i) {
        float a = source[4 * i + 3] * fill;
        for (int c = 0; c < 4; ++c) target[4 * i + c] = source[4 * i + c] * fill + target[4 * i + c] * (1 - a);
    }
}
void style_color(float *target, const float *coverage, float opacity, float r, float g, float b, int mode, size_t count) {
    float color[3] = {r, g, b};
    for (size_t i = 0; i < count; ++i) {
        float amount = clamp(coverage[i] * opacity);
        if (amount <= 0) continue;
        float a = target[4 * i + 3];
        for (int c = 0; c < 3; ++c) {
            float blended = color[c];
            if (mode && a > 0) {
                float backdrop = clamp(target[4 * i + c] / a);
                float mixed = mode == 1 ? backdrop * color[c] : backdrop + color[c] - backdrop * color[c];
                blended = color[c] * (1 - a) + mixed * a;
            }
            target[4 * i + c] = blended * amount + target[4 * i + c] * (1 - amount);
        }
        target[4 * i + 3] = amount + a * (1 - amount);
    }
}
void style_height(const float *distance, float *height, size_t count, float size, int profile, int smooth) {
    for (size_t i = 0; i < count; ++i) {
        float d = distance[i] / size;
        float h = clamp(profile == 0 ? d : profile == 1 ? 1 + d : profile == 2 ? .5f + d / 2 : fabsf(d));
        height[i] = smooth ? h * h * (3 - 2 * h) : h;
    }
}
void style_light(const float *h, float *highlight, float *shadow, int width, int rows, float lift, float lx, float ly, float lz) {
    for (int y = 0; y < rows; ++y) for (int x = 0; x < width; ++x) {
        int i = y * width + x;
        float dx = (h[y * width + (x + 1 < width ? x + 1 : x)] * lift - h[y * width + (x > 0 ? x - 1 : x)] * lift) / 2;
        float dy = (h[(y + 1 < rows ? y + 1 : y) * width + x] * lift - h[(y > 0 ? y - 1 : y) * width + x] * lift) / 2;
        float lit = (-dx * lx - dy * ly + lz) / sqrtf(dx * dx + dy * dy + 1);
        highlight[i] = lz < .9999f ? clamp((lit - lz) / (1 - lz)) : 0;
        shadow[i] = clamp((lz - lit) / (1 + lz));
    }
}
void style_clip(float *highlight, float *shadow, const float *alpha, size_t count, int profile) {
    for (size_t i = 0; i < count; ++i) {
        float region = profile == 0 ? alpha[i] : profile == 1 ? 1 - alpha[i] : 1;
        highlight[i] *= region; shadow[i] *= region;
    }
}
