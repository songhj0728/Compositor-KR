#ifndef COMPOSITOR_STYLE_PIXELS_H
#define COMPOSITOR_STYLE_PIXELS_H
#include <stddef.h>
#include <stdint.h>
// Plain C buffers, RGBA float order; no platform or vector ABI dependencies.
int style_distances(const float *alpha, float *distance, int width, int height);
void style_box(const float *source, float *target, int width, int height, int radius, int horizontal);
void style_unpack(const uint8_t *bytes, size_t stride, float *rgba, float *alpha, int width, int height);
void style_pack(const float *rgba, uint8_t *bytes, size_t count);
void style_over(float *target, const float *source, float fill, size_t count);
// mode: 0 normal, 1 multiply, 2 screen.
void style_color(float *target, const float *coverage, float opacity, float red, float green, float blue, int mode, size_t count);
// profile: 0 inner, 1 outer, 2 emboss, 3 pillow.
void style_height(const float *distance, float *height, size_t count, float size, int profile, int smooth);
void style_light(const float *height, float *highlight, float *shadow, int width, int rows, float lift, float lx, float ly, float lz);
void style_clip(float *highlight, float *shadow, const float *alpha, size_t count, int profile);
#endif
