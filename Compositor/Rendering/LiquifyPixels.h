#ifndef LiquifyPixels_h
#define LiquifyPixels_h
#include <stdint.h>
#include <stddef.h>
// Liquify works on a displacement field rather than on pixels: two floats per pixel (dx, dy), rows top-down, and a
// pixel shows the source at (x + dx, y + dy). Strokes only change the field, so however many there are, the result
// is one resample of the untouched source: no blur builds up, and Reconstruct can take the field back to nothing.

// The tools, in `LiquifyMode`'s order.
enum { LIQUIFY_FORWARD_WARP = 0, LIQUIFY_RECONSTRUCT, LIQUIFY_TWIRL_CLOCKWISE, LIQUIFY_PUCKER, LIQUIFY_BLOAT,
       LIQUIFY_PUSH_LEFT };

// One dab of `mode` at (toX, toY), having travelled from (fromX, fromY), on a `width` × `height` field. `hardness`
// (0–0.98) is how far out the brush works fully; `strength` (0–1) how much. The rectangle of pixels changed is
// written to `dirty` as x0, y0, x1, y1 (inclusive); x1 < x0 when nothing changed. Returns -1 when memory runs out.
int liquify_dab(float *field, size_t width, size_t height, int mode, double fromX, double fromY, double toX, double toY,
                double diameter, double hardness, double strength, long dirty[4]);

// Renders the rectangle x0…x1, y0…y1 (inclusive) of `output` from `source` through `field`, all `width` × `height`
// premultiplied RGBA with `width * 4` bytes per row, bilinearly.
void liquify_render(const uint8_t *source, uint8_t *output, size_t width, size_t height, const float *field,
                    long x0, long y0, long x1, long y1);

// Renders the whole of a `width` × `height` `output` from `source` (same size) through a smaller `fieldWidth` ×
// `fieldHeight` field covering the same image, which is scaled up to fit it.
void liquify_render_scaled(const uint8_t *source, uint8_t *output, size_t width, size_t height,
                           const float *field, size_t fieldWidth, size_t fieldHeight);
#endif
