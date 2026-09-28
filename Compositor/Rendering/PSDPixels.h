#ifndef PSDPixels_h
#define PSDPixels_h
#include <stdint.h>
#include <stddef.h>
// Splits premultiplied RGBA (4 bytes per pixel, `stride` bytes per row, rows top-down) into the four straight
// (un-premultiplied) planes Photoshop stores, each `width * height` bytes.
void psd_split_planes(const uint8_t *rgba, size_t width, size_t height, size_t stride,
                      uint8_t *red, uint8_t *green, uint8_t *blue, uint8_t *alpha);

// PackBits-compresses one row of `count` bytes into `output`, which must hold at least `count + count / 128 + 1`
// bytes. Returns the compressed length.
size_t psd_packbits(const uint8_t *row, size_t count, uint8_t *output);
#endif
