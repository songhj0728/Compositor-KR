#ifndef SmearPixels_h
#define SmearPixels_h
#include <stdint.h>
#include <stddef.h>
// One Blur dab over premultiplied RGBA (4 bytes per pixel, `stride` bytes per row, rows top-down), centered at
// (cx, cy) with `radius`. The dab diffuses: every pair of pixels under it trades the same share of their difference,
// a Gaussian of `sigma` pixels in how far apart they are, times the brush's weight at both (full out to `hardness`,
// easing to nothing at the rim) and `strength` (0–1). So color only ever spreads, never moves — over and over in one
// place, what's under the brush softens where it is, and a flat area stays flat. How far it spreads follows `sigma`
// alone, whatever the brush's size. `seed` varies how results round to 8 bits; give each dab its own (a count will do),
// or a spot dabbed over and over rounds the same way every time and loses the faint edge of what spreads.
void smear_blur_dab(uint8_t *rgba, size_t width, size_t height, size_t stride, double cx, double cy, double radius,
                    double hardness, double strength, double sigma, uint32_t seed);
#endif
