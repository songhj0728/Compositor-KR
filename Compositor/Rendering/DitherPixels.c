#include "DitherPixels.h"
#include <math.h>
#include <stdlib.h>
#include <string.h>
#include "ParallelFor.h"

// Compositor-KR: portable C11. The bands run through ParallelFor (Grand Central Dispatch on Apple platforms, OpenMP on
// Windows, serial elsewhere) as plain functions with a context, not blocks, which only Clang with Apple's blocks runtime
// builds; offsets that can go negative are ptrdiff_t, not long, which is 32-bit on Windows. The arithmetic is upstream's.

static inline float clamp01(float v) { return v < 0 ? 0 : v > 1 ? 1 : v; }

// One band's work: items start..<end, with whatever the caller packed into `context`.
typedef void (*band_body)(void *context, size_t start, size_t end);
typedef struct { size_t count, size; void *context; band_body body; } Bands;

static void run_band(void *bands, size_t band) {
    const Bands *b = bands;
    size_t start = band * b->size, end = start + b->size < b->count ? start + b->size : b->count;
    if (start < end) b->body(b->context, start, end);
}

// Runs `body` over `count` items split into a few runs per core, each a (start, end) range, all at once.
static void in_bands(size_t count, void *context, band_body body) {
    size_t bands = count < 64 ? 1 : 32;
    Bands b = { count, (count + bands - 1) / bands, context, body };
    parallel_for(bands, &b, run_band);
}

// Density darkens (positive) or lightens as a gamma, so black and white stay put; contrast pivots on mid gray.
static inline float adjust_tone(float v, float gamma, float contrast) {
    v = powf(clamp01(v), gamma);
    return clamp01((v - 0.5f) * contrast + 0.5f);
}

// One error-diffusion kernel: neighbors to the right on this row and below, with their weights over `divisor`.
typedef struct { int dx, dy, weight; } Tap;
typedef struct { const Tap *taps; int count; float divisor; } Kernel;

static const Tap atkinson[] = { {1,0,1}, {2,0,1}, {-1,1,1}, {0,1,1}, {1,1,1}, {0,2,1} };
static const Tap floyd[] = { {1,0,7}, {-1,1,3}, {0,1,5}, {1,1,1} };

// Atkinson passes on only six eighths of the error, which is what gives the Mac's crisp, contrasty look.
static Kernel kernel_for(int style) {
    return style == DITHER_ATKINSON ? (Kernel){ atkinson, 6, 8 } : (Kernel){ floyd, 4, 16 };
}

static inline float quantize(float v, int levels) {
    float steps = (float)(levels - 1);
    return roundf(clamp01(v) * steps) / steps;
}

// Diffuses each plane in serpentine order, so the error's drift doesn't streak to one side.
static void diffuse(float *plane, const uint8_t *alpha, size_t width, size_t height, const DitherParams *p) {
    Kernel k = kernel_for(p->style);
    for (size_t y = 0; y < height; ++y) {
        int reverse = (int)(y & 1);
        for (size_t i = 0; i < width; ++i) {
            size_t x = reverse ? width - 1 - i : i;
            size_t at = y * width + x;
            if (!alpha[at]) continue;
            float old = plane[at], q = quantize(old, p->levels);
            plane[at] = q;
            float error = (old - q) * p->diffusion / k.divisor;
            for (int t = 0; t < k.count; ++t) {
                ptrdiff_t nx = (ptrdiff_t)x + (reverse ? -k.taps[t].dx : k.taps[t].dx), ny = (ptrdiff_t)y + k.taps[t].dy;
                if (nx < 0 || nx >= (ptrdiff_t)width || ny >= (ptrdiff_t)height) continue;
                plane[(size_t)ny * width + (size_t)nx] += error * (float)k.taps[t].weight;
            }
        }
    }
}

static const uint8_t bayer8[64] = {
     0, 32,  8, 40,  2, 34, 10, 42, 48, 16, 56, 24, 50, 18, 58, 26,
    12, 44,  4, 36, 14, 46,  6, 38, 60, 28, 52, 20, 62, 30, 54, 22,
     3, 35, 11, 43,  1, 33,  9, 41, 51, 19, 59, 27, 49, 17, 57, 25,
    15, 47,  7, 39, 13, 45,  5, 37, 63, 31, 55, 23, 61, 29, 53, 21,
};

// The ordered threshold for a pixel, in [0, 1). Smaller Bayer matrices are the top-left corners of the 8 × 8 one,
// rescaled, which is how the recursive construction nests them.
static inline float ordered_threshold(int style, size_t x, size_t y) {
    switch (style) {
    case DITHER_BAYER_2: { static const uint8_t m[4] = { 0, 2, 3, 1 }; return ((float)m[(y & 1) * 2 + (x & 1)] + 0.5f) / 4; }
    case DITHER_BAYER_4: {
        static const uint8_t m[16] = { 0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5 };
        return ((float)m[(y & 3) * 4 + (x & 3)] + 0.5f) / 16;
    }
    default: return ((float)bayer8[(y & 7) * 8 + (x & 7)] + 0.5f) / 64;
    }
}

static inline float ordered(float v, float threshold, int levels) {
    float steps = (float)(levels - 1);
    float q = floorf(clamp01(v) * steps + threshold);
    return (q > steps ? steps : q) / steps;
}

// How much of a halftone cell a point must be covered by before it's marked, for each screen shape. `u` and `v`
// run from −0.5 to 0.5 across the cell; the shapes grow from its middle as coverage rises.
static inline float spot(int style, float u, float v) {
    float au = fabsf(u), av = fabsf(v);
    switch (style) {
    case DITHER_DOTS: return 3.14159265f * (u * u + v * v);
    case DITHER_LINES: return av * 2;
    default: return au + av;
    }
}

// Old Mac fill patterns, 8 × 8, one byte per row with the leftmost pixel in the top bit, from sparsest to fullest.
static const uint8_t patterns[][8] = {
    { 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 },
    { 0x80, 0x00, 0x00, 0x00, 0x08, 0x00, 0x00, 0x00 },
    { 0x88, 0x00, 0x22, 0x00, 0x88, 0x00, 0x22, 0x00 },
    { 0x80, 0x40, 0x20, 0x10, 0x08, 0x04, 0x02, 0x01 },
    { 0x88, 0x22, 0x88, 0x22, 0x88, 0x22, 0x88, 0x22 },
    { 0x00, 0xFF, 0x00, 0x00, 0x00, 0xFF, 0x00, 0x00 },
    { 0x11, 0x22, 0x44, 0x88, 0x11, 0x22, 0x44, 0x88 },
    { 0xAA, 0x00, 0xAA, 0x00, 0xAA, 0x00, 0xAA, 0x00 },
    { 0x88, 0x55, 0x22, 0x55, 0x88, 0x55, 0x22, 0x55 },
    { 0xFF, 0x80, 0x80, 0x80, 0xFF, 0x08, 0x08, 0x08 },
    { 0xAA, 0x55, 0xAA, 0x55, 0xAA, 0x55, 0xAA, 0x55 },
    { 0x81, 0x42, 0x24, 0x18, 0x18, 0x24, 0x42, 0x81 },
    { 0x77, 0xAA, 0xDD, 0xAA, 0x77, 0xAA, 0xDD, 0xAA },
    { 0xEE, 0xDD, 0xBB, 0x77, 0xEE, 0xDD, 0xBB, 0x77 },
    { 0x77, 0xFF, 0xDD, 0xFF, 0x77, 0xFF, 0xDD, 0xFF },
    { 0x7F, 0xFF, 0xFF, 0xFF, 0xF7, 0xFF, 0xFF, 0xFF },
    { 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF },
};
static const int patternCount = (int)(sizeof patterns / sizeof patterns[0]);

static inline void write_pixel(uint8_t *px, float r, float g, float b) {
    float a = (float)px[3] / 255.0f;
    px[0] = (uint8_t)lroundf(clamp01(r) * a * 255.0f);
    px[1] = (uint8_t)lroundf(clamp01(g) * a * 255.0f);
    px[2] = (uint8_t)lroundf(clamp01(b) * a * 255.0f);
}

typedef struct {
    const uint8_t *rgba; size_t width, stride, count;
    uint8_t *alpha; float *tone, *source;
    int originalColors; float gamma, contrast;
} ReadTones;

// Straight colors from premultiplied pixels, as adjusted tones (and, for Original colors, the colors themselves).
static void read_tones(void *context, size_t first, size_t last) {
    const ReadTones *c = context;
    for (size_t y = first; y < last; ++y) {
        const uint8_t *row = c->rgba + y * c->stride;
        for (size_t x = 0; x < c->width; ++x) {
            const uint8_t *px = row + x * 4;
            size_t at = y * c->width + x;
            c->alpha[at] = px[3];
            float r = 0, g = 0, b = 0;
            if (px[3]) {
                float scale = 1.0f / (float)px[3];
                r = px[0] * scale; g = px[1] * scale; b = px[2] * scale;
            }
            if (c->originalColors) {
                c->tone[at] = adjust_tone(r, c->gamma, c->contrast);
                c->tone[c->count + at] = adjust_tone(g, c->gamma, c->contrast);
                c->tone[2 * c->count + at] = adjust_tone(b, c->gamma, c->contrast);
                if (c->source) { c->source[at * 3] = r; c->source[at * 3 + 1] = g; c->source[at * 3 + 2] = b; }
            } else {
                c->tone[at] = adjust_tone(0.2126f * r + 0.7152f * g + 0.0722f * b, c->gamma, c->contrast);
            }
        }
    }
}

int dither_apply(uint8_t *rgba, size_t width, size_t height, size_t stride, const DitherParams *p) {
    size_t count = width * height;
    if (!count) return 1;
    int planes = p->originalColors ? 3 : 1;
    float *tone = malloc(count * sizeof(float) * (size_t)planes);
    uint8_t *alpha = malloc(count);
    // The image's own colors, unadjusted: halftone dots and glyphs take them in Original mode.
    float *source = p->originalColors ? malloc(count * sizeof(float) * 3) : NULL;
    if (!tone || !alpha || (p->originalColors && !source)) { free(tone); free(alpha); free(source); return 0; }

    float gamma = exp2f(p->density * 1.5f);
    float contrast = p->contrast >= 0 ? 1.0f / (1.0f - 0.95f * p->contrast) : 1.0f + p->contrast;
    ReadTones reading = { rgba, width, stride, count, alpha, tone, source, p->originalColors, gamma, contrast };
    in_bands(height, &reading, read_tones);

    float dark[3] = { p->dark[0] / 255.0f, p->dark[1] / 255.0f, p->dark[2] / 255.0f };
    float light[3] = { p->light[0] / 255.0f, p->light[1] / 255.0f, p->light[2] / 255.0f };
    int style = p->style;
    int levels = p->levels < 2 ? 2 : p->levels > 16 ? 16 : p->levels;

    if (style <= DITHER_BAYER_8) {
        // Diffusion and ordered dithering: each plane is quantized to `levels` tones, then mapped to colors.
        if (style <= DITHER_FLOYD_STEINBERG) {
            DitherParams local = *p;
            local.levels = levels;
            for (int c = 0; c < planes; ++c) diffuse(tone + (size_t)c * count, alpha, width, height, &local);
        } else {
            for (int c = 0; c < planes; ++c) {
                float *plane = tone + (size_t)c * count;
                for (size_t y = 0; y < height; ++y)
                    for (size_t x = 0; x < width; ++x) {
                        size_t at = y * width + x;
                        if (alpha[at]) plane[at] = ordered(plane[at], ordered_threshold(style, x, y), levels);
                    }
            }
        }
        for (size_t y = 0; y < height; ++y) {
            uint8_t *row = rgba + y * stride;
            for (size_t x = 0; x < width; ++x) {
                size_t at = y * width + x;
                if (!alpha[at]) continue;
                if (p->originalColors) {
                    write_pixel(row + x * 4, tone[at], tone[count + at], tone[2 * count + at]);
                } else {
                    float t = tone[at];
                    write_pixel(row + x * 4, dark[0] + (light[0] - dark[0]) * t, dark[1] + (light[1] - dark[1]) * t,
                                dark[2] + (light[2] - dark[2]) * t);
                }
            }
        }
    } else {
        // Marks (halftone shapes, patterns, glyphs) cover as much of each spot as the tone calls for. On light, they
        // stand for darkness and are drawn in the dark color; light on dark, the reverse.
        float *marks = p->originalColors ? malloc(count * sizeof(float)) : tone;
        if (!marks) { free(tone); free(alpha); free(source); return 0; }
        if (p->originalColors)
            for (size_t i = 0; i < count; ++i)
                marks[i] = 0.2126f * tone[i] + 0.7152f * tone[count + i] + 0.0722f * tone[2 * count + i];
        int cell = p->cell < 2 ? 2 : p->cell;
        float cosA = cosf(p->angle), sinA = sinf(p->angle);
        float *ink = p->lightOnDark ? light : dark, *paper = p->lightOnDark ? dark : light;
        // Glyphs: each cell shares one, picked from the cell's average tone, worked out once per cell.
        size_t gw = (size_t)(p->glyphWidth < 1 ? 1 : p->glyphWidth), gh = (size_t)(p->glyphHeight < 1 ? 1 : p->glyphHeight);
        size_t columns = (width + gw - 1) / gw, cellRows = (height + gh - 1) / gh;
        int *picked = NULL;
        if (style == DITHER_GLYPHS && p->glyphCount > 0) {
            picked = malloc(columns * cellRows * sizeof(int));
            if (!picked) { if (marks != tone) free(marks); free(tone); free(alpha); free(source); return 0; }
            for (size_t row = 0; row < cellRows; ++row)
                for (size_t column = 0; column < columns; ++column) {
                    float sum = 0; int n = 0;
                    for (size_t yy = row * gh; yy < (row + 1) * gh && yy < height; ++yy)
                        for (size_t xx = column * gw; xx < (column + 1) * gw && xx < width; ++xx) {
                            size_t i = yy * width + xx;
                            if (alpha[i]) { sum += marks[i]; ++n; }
                        }
                    float t = n ? sum / (float)n : 1;
                    float wanted = (p->lightOnDark ? t : 1 - t) * p->glyphCoverage[p->glyphCount - 1];
                    int best = 0;
                    float bestDistance = 2;
                    for (int g = 0; g < p->glyphCount; ++g) {
                        float d = fabsf(p->glyphCoverage[g] - wanted);
                        if (d < bestDistance) { bestDistance = d; best = g; }
                    }
                    picked[row * columns + column] = best;
                }
        }
        // Original colors: marks take the pixel's own color, on black (light on dark) or white.
        float paperOriginal = p->lightOnDark ? 0.0f : 1.0f;
        for (size_t y = 0; y < height; ++y) {
            uint8_t *row = rgba + y * stride;
            for (size_t x = 0; x < width; ++x) {
                size_t at = y * width + x;
                if (!alpha[at]) continue;
                float amount;
                if (picked) {
                    int glyph = picked[(y / gh) * columns + x / gw];
                    amount = p->glyphs[(size_t)glyph * gw * gh + (y % gh) * gw + x % gw] / 255.0f;
                } else if (style == DITHER_PATTERNS) {
                    float t = marks[at];
                    float coverage = p->lightOnDark ? t : 1 - t;
                    int index = (int)lroundf(coverage * (float)(patternCount - 1));
                    amount = (patterns[index][y & 7] >> (7 - (x & 7))) & 1;
                } else {
                    float fx = (float)x + 0.5f, fy = (float)y + 0.5f;
                    float u = (fx * cosA + fy * sinA) / (float)cell, v = (-fx * sinA + fy * cosA) / (float)cell;
                    u -= floorf(u) + 0.5f; v -= floorf(v) + 0.5f;
                    float t = marks[at];
                    amount = (p->lightOnDark ? t : 1 - t) > spot(style, u, v) ? 1 : 0;
                }
                if (p->originalColors) {
                    const float *s = source + at * 3;
                    write_pixel(row + x * 4, paperOriginal + (s[0] - paperOriginal) * amount,
                                paperOriginal + (s[1] - paperOriginal) * amount, paperOriginal + (s[2] - paperOriginal) * amount);
                } else {
                    write_pixel(row + x * 4, paper[0] + (ink[0] - paper[0]) * amount, paper[1] + (ink[1] - paper[1]) * amount,
                                paper[2] + (ink[2] - paper[2]) * amount);
                }
            }
        }
        free(picked);
        if (marks != tone) free(marks);
    }
    free(tone); free(alpha); free(source);
    return 1;
}

void dither_dots(uint8_t *rgba, size_t width, size_t height, size_t stride, int block, const uint8_t *gap) {
    if (block < 2) return;
    float radius = (float)block * 0.42f, middle = (float)block / 2;
    for (size_t y = 0; y < height; ++y) {
        uint8_t *row = rgba + y * stride;
        float dy = (float)(y % (size_t)block) + 0.5f - middle;
        for (size_t x = 0; x < width; ++x) {
            uint8_t *px = row + x * 4;
            if (!px[3]) continue;
            float dx = (float)(x % (size_t)block) + 0.5f - middle;
            float cover = clamp01(radius - sqrtf(dx * dx + dy * dy) + 0.5f);
            if (cover >= 1) continue;
            for (int c = 0; c < 3; ++c)
                px[c] = (uint8_t)lroundf((float)px[c] * cover + (float)gap[c] * (float)px[3] / 255.0f * (1 - cover));
        }
    }
}

typedef struct { uint8_t *rgba; const uint8_t *glow; size_t width, stride; float amount; } Glow;

static void glow_rows(void *context, size_t first, size_t last) {
    const Glow *g = context;
    for (size_t y = first; y < last; ++y) {
        uint8_t *row = g->rgba + y * g->stride;
        const uint8_t *light = g->glow + y * g->stride;
        for (size_t x = 0; x < g->width * 4; x += 4) {
            float a = row[x + 3];
            for (int c = 0; c < 3; ++c) {
                // The light eases in as the pixel nears full brightness rather than clipping there, so where the
                // picture is bright the gaps between lines glow without filling up to the lines.
                float v = row[x + c], added = (float)light[x + c] * g->amount * a / 255.0f, room = (a - v) * 0.7f;
                if (room > 0) v += room * (1 - expf(-added / room));
                row[x + c] = (uint8_t)lroundf(v > a ? a : v);
            }
        }
    }
}

void dither_glow(uint8_t *rgba, const uint8_t *glow, size_t width, size_t height, size_t stride, float amount) {
    Glow g = { rgba, glow, width, stride, amount };
    in_bands(height, &g, glow_rows);
}

// A fixed pseudo-random value in [0, 1) for each pixel and draw.
static inline float hash_noise(size_t x, size_t y, uint32_t draw) {
    uint32_t h = (uint32_t)x * 0x9E3779B1u ^ (uint32_t)y * 0x85EBCA77u ^ draw * 0xC2B2AE3Du;
    h ^= h >> 15; h *= 0x2C1B3C6Du; h ^= h >> 12; h *= 0x297A2D39u; h ^= h >> 15;
    return (float)(h >> 8) / (float)(1u << 24);
}

typedef struct { const uint16_t *wide; uint8_t *rgba; size_t width, stride; } Quantize16;

static void quantize16_rows(void *context, size_t first, size_t last) {
    const Quantize16 *q = context;
    for (size_t y = first; y < last; ++y) {
        uint8_t *out = q->rgba + y * q->stride;
        const uint16_t *in = q->wide + y * q->width * 4;
        for (size_t x = 0; x < q->width; ++x) {
            const uint16_t *p = in + x * 4;
            ptrdiff_t alpha = (ptrdiff_t)lroundf((float)p[3] * (255.0f / 65535.0f));
            for (uint32_t c = 0; c < 3; ++c) {
                // Two uniform draws added: noise that's strongest at zero and gone past one step.
                float value = (float)p[c] * (255.0f / 65535.0f) + hash_noise(x, y, c) + hash_noise(x, y, c + 3) - 1.0f;
                ptrdiff_t rounded = (ptrdiff_t)lroundf(value);
                // Premultiplied: the noise mustn't lift a color past its own alpha.
                out[x * 4 + c] = (uint8_t)(rounded < 0 ? 0 : rounded > alpha ? alpha : rounded);
            }
            out[x * 4 + 3] = (uint8_t)alpha;
        }
    }
}

void dither_quantize16(const uint16_t *wide, uint8_t *rgba, size_t width, size_t height, size_t stride) {
    Quantize16 q = { wide, rgba, width, stride };
    in_bands(height, &q, quantize16_rows);
}

typedef struct { float *lift; size_t width; ptrdiff_t radius; int failed; } SmoothAlong;

// Three box passes along each line, close to a Gaussian.
static void smooth_along(void *context, size_t firstLine, size_t lastLine) {
    SmoothAlong *s = context;
    size_t width = s->width;
    ptrdiff_t radius = s->radius;
    float *copy = malloc(width * sizeof(float));
    if (!copy) { s->failed = 1; return; }
    for (size_t line = firstLine; line < lastLine; ++line) {
        float *row = s->lift + line * width;
        for (int pass = 0; pass < 3; ++pass) {
            memcpy(copy, row, width * sizeof(float));
            float sum = 0;
            for (ptrdiff_t x = -radius; x <= radius; ++x) sum += copy[x < 0 ? 0 : x >= (ptrdiff_t)width ? width - 1 : (size_t)x];
            for (size_t x = 0; x < width; ++x) {
                row[x] = sum / (float)(2 * radius + 1);
                ptrdiff_t out = (ptrdiff_t)x - radius, in = (ptrdiff_t)x + radius + 1;
                sum += copy[in >= (ptrdiff_t)width ? width - 1 : (size_t)in] - copy[out < 0 ? 0 : (size_t)out];
            }
        }
    }
    free(copy);
}

typedef struct { const float *lift; float *spread; size_t width, lines; } SmoothAcross;

// One 1-2-1 pass across neighboring lines.
static void smooth_across(void *context, size_t firstLine, size_t lastLine) {
    const SmoothAcross *s = context;
    size_t width = s->width;
    for (size_t line = firstLine; line < lastLine; ++line) {
        const float *above = s->lift + (line ? line - 1 : 0) * width, *here = s->lift + line * width;
        const float *below = s->lift + (line + 1 < s->lines ? line + 1 : line) * width;
        for (size_t x = 0; x < width; ++x) s->spread[line * width + x] = (above[x] + 2 * here[x] + below[x]) / 4;
    }
}

typedef struct {
    uint8_t *rgba; size_t width, height, stride, lines, spacing, plane;
    const float *tone, *lift, *scan; const uint8_t *alpha;
    float middle, dots, threshold, displace, thickness, blackLevel;
    int rising, original;
    const float *screen, *phosphor;
    int failed;
} DrawColumns;

static void draw_columns(void *context, size_t first, size_t last) {
    DrawColumns *d = context;
    size_t width = d->width, height = d->height, lines = d->lines, plane = d->plane;
    const float *tone = d->tone, *lift = d->lift, *scan = d->scan, *screen = d->screen, *phosphor = d->phosphor;
    float middle = d->middle, dots = d->dots, threshold = d->threshold, displace = d->displace;
    float thickness = d->thickness, blackLevel = d->blackLevel;
    int rising = d->rising, original = d->original;
    float *cover = malloc(height * sizeof(float) * 4);
    if (!cover) { d->failed = 1; return; }
    float *color = cover + height;
    for (size_t x = first; x < last; ++x) {
        memset(cover, 0, height * sizeof(float));
        float along = fmodf((float)x + 0.5f, (float)d->spacing) - middle;
        // The edge of everything drawn so far in this column; lines further back show only beyond it.
        float horizon = rising ? INFINITY : -INFINITY;
        for (size_t step = 0; step < lines; ++step) {
            size_t line = rising ? lines - 1 - step : step;
            // Dots: darker than the Dots level, the line breaks into beads, one every line spacing, each lit in the
            // tone at its middle; just above it, into dashes that close up into the solid line.
            float beading = dots > 0 ? clamp01((dots - tone[line * width + x]) / 0.2f) : 0, across = along * beading;
            ptrdiff_t centered = (ptrdiff_t)lroundf((float)x - across);
            size_t at = centered < 0 ? 0 : (size_t)centered >= width ? width - 1 : (size_t)centered;
            size_t i = line * width + at;
            float t = tone[i];
            float lit = threshold > 0 ? clamp01((t - threshold) / 0.04f) : 1;
            if (lit <= 0) continue;
            // Drawn between this column's height and the last's, so a steep climb never breaks the line.
            float base = (float)line * (float)d->spacing + middle;
            float here = base - displace * lift[i], before = at > 0 ? base - displace * lift[i - 1] : here;
            float lo = fminf(here, before), hi = fmaxf(here, before);
            // Black Level: the line's least brightness, so it still shows where the picture is black.
            float level = blackLevel + (1 - blackLevel) * t, c[3];
            for (int k = 0; k < 3; ++k)
                c[k] = original ? blackLevel + (1 - blackLevel) * scan[(size_t)k * plane + i] : screen[k] + (phosphor[k] - screen[k]) * level;
            // Half the line's height: thinner where the picture is dim.
            float beam = middle * thickness * (0.29f + 0.71f * sqrtf(clamp01(level)));
            ptrdiff_t top = (ptrdiff_t)floorf(rising ? lo - beam - 1 : fmaxf(lo - beam - 1, horizon - 1));
            ptrdiff_t bottom = (ptrdiff_t)ceilf(rising ? fminf(hi + beam + 1, horizon + 1) : hi + beam + 1);
            if (top < 0) top = 0;
            if (bottom > (ptrdiff_t)height) bottom = (ptrdiff_t)height;
            for (ptrdiff_t y = top; y < bottom; ++y) {
                float yy = (float)y + 0.5f;
                float off = yy < lo ? lo - yy : yy > hi ? yy - hi : 0;
                float distance = sqrtf(off * off + across * across);
                float hidden = rising ? clamp01(horizon - yy + 0.5f) : clamp01(yy - horizon + 0.5f);
                float shown = clamp01(beam - distance + 0.5f) * lit * hidden;
                if (shown > cover[y]) {
                    cover[y] = shown;
                    color[y * 3] = c[0]; color[y * 3 + 1] = c[1]; color[y * 3 + 2] = c[2];
                }
            }
            if (lit > 0.5f) horizon = rising ? fminf(horizon, lo - beam) : fmaxf(horizon, hi + beam);
        }
        for (size_t y = 0; y < height; ++y) {
            if (!d->alpha[y * width + x]) continue;
            // The beam is driven brighter than the picture, making up for the dark screen between lines.
            float shown = cover[y];
            write_pixel(d->rgba + y * d->stride + x * 4, screen[0] + (color[y * 3] * 1.35f - screen[0]) * shown,
                        screen[1] + (color[y * 3 + 1] * 1.35f - screen[1]) * shown,
                        screen[2] + (color[y * 3 + 2] * 1.35f - screen[2]) * shown);
        }
    }
    free(cover);
}

// Draws the lines over the scanned tones, a column at a time. Displaced, they're a landscape seen from the front, after
// the Rutt-Etra video synthesizer: each line is lifted (or, displaced the other way, lowered) by the picture's
// brightness smoothed into hills, and hides whatever lies behind it, so nearer lines wrap over the shapes rather than
// crossing the ones beyond. Nearest line first: the bottom one when lines rise, the top one when they fall.
static int draw_lines(uint8_t *rgba, size_t width, size_t height, size_t stride, const ScanlinesParams *p,
                       const float *scan, const uint8_t *alpha, size_t lines, size_t spacing) {
    int original = p->originalColors;
    size_t plane = lines * width;
    float *tone = malloc(plane * sizeof(float)), *lift = malloc(plane * sizeof(float)), *spread = malloc(plane * sizeof(float));
    if (!tone || !lift || !spread) { free(tone); free(lift); free(spread); return 0; }
    for (size_t at = 0; at < plane; ++at)
        tone[at] = original ? 0.2126f * scan[at] + 0.7152f * scan[plane + at] + 0.0722f * scan[2 * plane + at] : scan[at];
    // The height: brightness blurred along each line (three box passes, close to a Gaussian) and then across its
    // neighbors, so a face rises as one rounded hill instead of a staircase of the pixels under it.
    float smoothness = clamp01(p->smoothness);
    ptrdiff_t radius = (ptrdiff_t)lroundf(smoothness * (float)spacing * 2);
    memcpy(lift, tone, plane * sizeof(float));
    if (radius > 0 && p->displace != 0) {
        SmoothAlong along = { lift, width, radius, 0 };
        in_bands(lines, &along, smooth_along);
        if (along.failed) { free(tone); free(lift); free(spread); return 0; }
        ptrdiff_t across = (ptrdiff_t)lroundf(smoothness * 2);
        SmoothAcross spreading = { lift, spread, width, lines };
        for (ptrdiff_t step = 0; step < across; ++step) {
            in_bands(lines, &spreading, smooth_across);
            memcpy(lift, spread, plane * sizeof(float));
        }
    }
    free(spread);

    float middle = (float)spacing / 2, dots = clamp01(p->dots), threshold = clamp01(p->threshold), displace = p->displace;
    float thickness = clamp01(p->thickness), blackLevel = clamp01(p->blackLevel);
    int rising = displace >= 0;
    float dark[3] = { p->dark[0] / 255.0f, p->dark[1] / 255.0f, p->dark[2] / 255.0f };
    float light[3] = { p->light[0] / 255.0f, p->light[1] / 255.0f, p->light[2] / 255.0f };
    if (original) dark[0] = dark[1] = dark[2] = 0;
    const float *screen = dark, *phosphor = light;
    DrawColumns drawing = { rgba, width, height, stride, lines, spacing, plane, tone, lift, scan, alpha,
                            middle, dots, threshold, displace, thickness, blackLevel, rising, original, screen, phosphor, 0 };
    in_bands(width, &drawing, draw_columns);
    free(tone); free(lift);
    return !drawing.failed;
}

typedef struct {
    const float *tone; const uint8_t *alpha; float *scan;
    size_t width, height, count, lines, spacing; int planes; float wobble;
} SampleLines;

// Each line's tone along it: the average of the rows it covers, sampled where its wobble moves it from.
static void sample_lines(void *context, size_t firstLine, size_t lastLine) {
    const SampleLines *s = context;
    size_t width = s->width, count = s->count, lines = s->lines;
    for (size_t line = firstLine; line < lastLine; ++line) {
        size_t top = line * s->spacing, bottom = top + s->spacing < s->height ? top + s->spacing : s->height;
        // A slow wave down the screen with a quicker one over it, as a CRT's picture wavers when its sync drifts.
        float wave = sinf((float)line * 0.45f) * 0.7f + sinf((float)line * 1.7f + 1.3f) * 0.3f;
        ptrdiff_t shift = (ptrdiff_t)lroundf(s->wobble * wave);
        for (size_t x = 0; x < width; ++x) {
            float sum[3] = { 0, 0, 0 }; int n = 0;
            ptrdiff_t sx = (ptrdiff_t)x - shift;
            if (sx >= 0 && sx < (ptrdiff_t)width)
                for (size_t y = top; y < bottom; ++y) {
                    size_t at = y * width + (size_t)sx;
                    if (!s->alpha[at]) continue;
                    for (int c = 0; c < s->planes; ++c) sum[c] += s->tone[(size_t)c * count + at];
                    ++n;
                }
            for (int c = 0; c < s->planes; ++c) s->scan[((size_t)c * lines + line) * width + x] = n ? sum[c] / (float)n : 0;
        }
    }
}

typedef struct { uint8_t *rgba; size_t width, stride; ptrdiff_t split; int failed; } ColorSplit;

// Red moved one way and blue the other, for colored fringes on the lines' edges.
static void split_rows(void *context, size_t first, size_t last) {
    ColorSplit *s = context;
    size_t width = s->width;
    uint8_t *copy = malloc(width * 4);
    if (!copy) { s->failed = 1; return; }
    for (size_t y = first; y < last; ++y) {
        uint8_t *row = s->rgba + y * s->stride;
        memcpy(copy, row, width * 4);
        for (size_t x = 0; x < width; ++x) {
            ptrdiff_t from = (ptrdiff_t)x - s->split, to = (ptrdiff_t)x + s->split;
            uint8_t a = row[x * 4 + 3];
            uint8_t r = from >= 0 ? copy[from * 4] : 0, b = to < (ptrdiff_t)width ? copy[to * 4 + 2] : 0;
            row[x * 4] = r > a ? a : r;
            row[x * 4 + 2] = b > a ? a : b;
        }
    }
    free(copy);
}

int scanlines_apply(uint8_t *rgba, size_t width, size_t height, size_t stride, const ScanlinesParams *p) {
    size_t count = width * height;
    if (!count) return 1;
    size_t spacing = (size_t)(p->spacing < 2 ? 2 : p->spacing);
    size_t lines = (height + spacing - 1) / spacing;
    int planes = p->originalColors ? 3 : 1;
    float *tone = malloc(count * sizeof(float) * (size_t)planes);
    uint8_t *alpha = malloc(count);
    // Each line's tone along it: the average of the rows it covers, sampled where its wobble moves it from.
    float *scan = malloc(lines * width * sizeof(float) * (size_t)planes);
    if (!tone || !alpha || !scan) { free(tone); free(alpha); free(scan); return 0; }

    float gamma = exp2f(p->density * 1.5f);
    float contrast = p->contrast >= 0 ? 1.0f / (1.0f - 0.95f * p->contrast) : 1.0f + p->contrast;
    // The same reading as Dither's, without keeping the colors themselves.
    ReadTones reading = { rgba, width, stride, count, alpha, tone, NULL, p->originalColors, gamma, contrast };
    in_bands(height, &reading, read_tones);
    SampleLines sampling = { tone, alpha, scan, width, height, count, lines, spacing, planes, p->wobble };
    in_bands(lines, &sampling, sample_lines);

    int drawn = draw_lines(rgba, width, height, stride, p, scan, alpha, lines, spacing);
    free(tone); free(alpha); free(scan);
    if (!drawn) return 0;

    // Color split: red moved one way and blue the other, for colored fringes on the lines' edges.
    ptrdiff_t split = (ptrdiff_t)lroundf(p->split);
    if (split > 0) {
        ColorSplit splitting = { rgba, width, stride, split, 0 };
        in_bands(height, &splitting, split_rows);
        if (splitting.failed) return 0;
    }
    return 1;
}
