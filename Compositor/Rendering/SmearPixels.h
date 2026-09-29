#ifndef SmearPixels_h
#define SmearPixels_h
#include <stdint.h>
#include <stddef.h>
// One Blur dab over premultiplied RGBA (4 bytes per pixel, `stride` bytes per row, rows top-down), centered at
// (cx, cy) with `radius`. The dab diffuses: each pair of neighbors trades the same share of their difference, so
// color only ever spreads, never moves — over and over in one place, what's under the brush softens where it is, and a
// flat area stays flat. The share follows the brush's weight at both pixels (full out to `hardness`, easing to nothing
// at the rim) times `strength` (0–1), over `iterations` passes.
void smear_blur_dab(uint8_t *rgba, size_t width, size_t height, size_t stride, double cx, double cy, double radius,
                    double hardness, double strength, int iterations);
#endif
