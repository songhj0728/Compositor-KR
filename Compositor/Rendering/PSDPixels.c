#include "PSDPixels.h"

void psd_split_planes(const uint8_t *rgba, size_t width, size_t height, size_t stride,
                      uint8_t *red, uint8_t *green, uint8_t *blue, uint8_t *alpha) {
    for (size_t y = 0; y < height; ++y) {
        const uint8_t *p = rgba + y * stride;
        size_t row = y * width;
        for (size_t x = 0; x < width; ++x, p += 4) {
            size_t i = row + x;
            uint8_t a = p[3];
            alpha[i] = a;
            if (a == 0) { red[i] = green[i] = blue[i] = 0; continue; }
            if (a == 255) { red[i] = p[0]; green[i] = p[1]; blue[i] = p[2]; continue; }
            unsigned r = ((unsigned)p[0] * 255 + a / 2) / a, g = ((unsigned)p[1] * 255 + a / 2) / a,
                     b = ((unsigned)p[2] * 255 + a / 2) / a;
            red[i] = (uint8_t)(r > 255 ? 255 : r);
            green[i] = (uint8_t)(g > 255 ? 255 : g);
            blue[i] = (uint8_t)(b > 255 ? 255 : b);
        }
    }
}

size_t psd_packbits(const uint8_t *row, size_t count, uint8_t *output) {
    size_t i = 0, out = 0;
    while (i < count) {
        if (i + 1 < count && row[i] == row[i + 1]) {
            // A run of 2–128 equal bytes: a count of 1 - n, then the byte.
            size_t run = 2;
            while (i + run < count && row[i + run] == row[i] && run < 128) ++run;
            output[out++] = (uint8_t)(int8_t)(1 - (int)run);
            output[out++] = row[i];
            i += run;
        } else {
            // 1–128 literal bytes: a count of n - 1, then the bytes. Stops before the next run.
            size_t start = i++;
            while (i < count && i - start < 128) {
                if (i + 1 < count && row[i] == row[i + 1]) break;
                ++i;
            }
            output[out++] = (uint8_t)(i - start - 1);
            for (size_t k = start; k < i; ++k) output[out++] = row[k];
        }
    }
    return out;
}
