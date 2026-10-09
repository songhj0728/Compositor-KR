// Portable checks for Rendering/DitherPixels.c (Dither, Scanlines, RAW rounding). Builds as plain C11 without Apple's
// blocks, which is what keeps it buildable on Windows:
//   cc -std=c11 -Wall -Wextra -Werror -fno-blocks -ICompositor/Rendering Compositor/Rendering/DitherPixels.c \
//      Tests/PortableCore/dither_pixels.c -lm -o dither-tests
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "DitherPixels.h"

static uint32_t seed = 7;
static uint32_t rnd(void) { seed = seed * 1664525u + 1013904223u; return seed >> 8; }

// Premultiplied pixels, a seventh of them clear.
static void fill(uint8_t *px, size_t pixels) {
    for (size_t i = 0; i < pixels; ++i) {
        uint8_t a = rnd() % 7 == 0 ? 0 : (uint8_t)(128 + rnd() % 128);
        for (int c = 0; c < 3; ++c) px[i * 4 + c] = (uint8_t)((rnd() % 256) * a / 255);
        px[i * 4 + 3] = a;
    }
}

// Alpha kept, clear pixels untouched, colors within their alpha.
static void check_kept(const uint8_t *before, const uint8_t *after, size_t pixels, const char *what) {
    for (size_t i = 0; i < pixels; ++i) {
        assert(before[i * 4 + 3] == after[i * 4 + 3]);
        if (!before[i * 4 + 3]) assert(!memcmp(before + i * 4, after + i * 4, 4));
        for (int c = 0; c < 3; ++c) assert(after[i * 4 + c] <= after[i * 4 + 3]);
    }
    printf("  %s keeps alpha and clear pixels\n", what);
}

int main(void) {
    const size_t w = 301, h = 97, pixels = w * h, bytes = pixels * 4;
    uint8_t *src = malloc(bytes), *a = malloc(bytes), *b = malloc(bytes);
    assert(src && a && b);
    fill(src, pixels);

    for (int style = DITHER_ATKINSON; style <= DITHER_PATTERNS; ++style) {
        DitherParams p = { style, 2, 0.9f, 0, 0, 6, 0.3f, 0, 0, {0, 0, 0}, {255, 255, 255}, 0, 0, NULL, NULL, 0 };
        memcpy(a, src, bytes); memcpy(b, src, bytes);
        assert(dither_apply(a, w, h, w * 4, &p) && dither_apply(b, w, h, w * 4, &p));
        assert(!memcmp(a, b, bytes)); // The same every time, however the bands are shared out.
        check_kept(src, a, pixels, "dither");
    }

    ScanlinesParams q = { 4, 0.7f, 0.4f, 3, 40, 0.1f, 2, 0, 0.2f, 0.15f, 0.6f, 0, {0, 0, 0}, {120, 255, 140} };
    memcpy(a, src, bytes); memcpy(b, src, bytes);
    assert(scanlines_apply(a, w, h, w * 4, &q) && scanlines_apply(b, w, h, w * 4, &q));
    assert(!memcmp(a, b, bytes));
    check_kept(src, a, pixels, "scanlines");

    // 16-bit RAW rounding: a mid-gray field stays mid-gray on average, its noise only a step either way.
    uint16_t *wide = malloc(pixels * 8);
    assert(wide);
    for (size_t i = 0; i < pixels; ++i) { wide[i * 4] = wide[i * 4 + 1] = wide[i * 4 + 2] = 32896; wide[i * 4 + 3] = 65535; }
    dither_quantize16(wide, a, w, h, w * 4);
    double sum = 0;
    for (size_t i = 0; i < pixels; ++i) { assert(a[i * 4] >= 127 && a[i * 4] <= 129 && a[i * 4 + 3] == 255); sum += a[i * 4]; }
    assert(sum / (double)pixels > 127.8 && sum / (double)pixels < 128.2);
    printf("  RAW rounding dithers within a step\n");

    free(src); free(a); free(b); free(wide);
    printf("Portable dither and scanlines tests passed\n");
    return 0;
}
