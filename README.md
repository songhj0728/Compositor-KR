# Attention!
한국어

이 작업은 robbietilton의 Compositor 프로그램을 기반으로 한 포크 버전입니다.

현재 한글화와 포토샵을 대체하기 위한 기능들을 준비하고 있습니다.

포토샵을 사용해 본 사용자라면 큰 어려움 없이 사용할 수 있도록 개발하고 있으며, 무료로 이용할 수 있습니다.

PSD로 내보내면 텍스트는 포토샵에서 편집 가능한 문자 레이어로, 레이어 효과는 포토샵의 레이어 스타일로 저장됩니다. 패턴 오버레이와 경사의 텍스처처럼 포토샵 라이브러리가 필요한 일부 효과는 픽셀로 병합됩니다.

원본 제작자의 설명과 링크는 아래 있습니다.

English

This project is a fork of Compositor by robbietilton.

We are currently working on Korean localization and additional features aimed at making the application a practical alternative to Adobe Photoshop.

The goal is to make the application familiar and easy to use for users who are already accustomed to Photoshop. It will be free to use.

Exported PSD files keep their layer structure in Photoshop; text is written as editable type and layer effects as Photoshop's own Layer Style. A few effects that need Photoshop's pattern library (Pattern Overlay, a bevel's Texture) are merged into pixels.


# Compositor

Adobe Photoshop costs too much and tools like GIMP don’t feel familiar enough for me to stay in flow. That’s why I built Compositor.

The goal was to create a full-featured image editor that is completely free and open source. I used to use Photoshop for compositing and post-processing, so Compositor is built around that workflow - with the tools needed to create a pixel-perfect final image.

Because it’s open source, you can download the Xcode project and add, remove, or modify any feature to fit your workflow.

## Installation

### Download
Download the latest Compositor-KR release from [GitHub Releases](https://github.com/songhj0728/Compositor-KR/releases/latest). The app checks this repository for updates on its own.

The original, English-only Compositor is at [robbietilton.com/compositor](https://robbietilton.com/compositor) and [github.com/robbietilton/Compositor](https://github.com/robbietilton/Compositor).

## Features

### Layers
- Layers and folders, with opacity and Photoshop's full set of blend modes in its order — a folder's opacity dims everything inside it
- Layer masks: paint, fill, invert, blur and feather them anywhere on the canvas, past the layer's own pixels; link or unlink them to transform a mask on its own
- Clipping masks and folder masks
- Adjustment layers: Hue/Saturation, Levels, Curves, Exposure, Gradient Map, Grain, Black & White, Color Balance, Invert, Gaussian Blur, Motion Blur and Noise
- Layer Style, as in Photoshop: Blending Options (blend mode, opacity, Fill Opacity), Bevel & Emboss with Contour and Texture, Stroke, Inner Shadow, Inner Glow, Satin, Color Overlay, Pattern Overlay, Outer Glow and Drop Shadow, each with its own blend mode, editable at any time in the Layer Style dialog (click the fx icon; its arrow adds a style directly)
- Clipping masks hide with their base, as in Photoshop
- Merge Down, Merge Layers and Merge Group (⌘E)
- Duplicate, rename inline, reorder and nest by drag and drop; Option-drag to duplicate; a right-click menu in the Layers panel
- Copy and paste whole layers and folders (⌘C/⌘V with no selection), within a project or between projects, or drag them between projects

### Move and transform
- Move tool (V): pick, move and flip layers, with the transform box's handles for scaling, rotating and distorting by hand; exact width, height, scale and angle are typed in the Shape tool's bar
- Non-destructive move, scale, rotate and flip — images keep their full resolution however small you make them
- Free distort (⌘-drag a handle), with Shift to lock to an axis
- Transform several layers, or a whole folder, together
- Snapping to canvas and layer edges and centers, with guides
- Exact values for position, size, scale and angle, stepped with the arrow keys
- Flip Layer and Flip Canvas, horizontal and vertical

### Selections
- Rectangle and Ellipse Marquee, Freehand and Polygonal Lasso, and the Magic tool — Wand selects by color, Object traces whatever you click (Tab switches)
- Select Subject, and Expand, Contract and Feather on any selection
- Add to and subtract from selections, move the outline, or move and duplicate the pixels inside
- Load a layer's pixels or a mask as a selection
- Content-Aware Fill, which can also extend an image past its edges

### Painting and retouching
- Brush with size, hardness, opacity and smoothing, in Paint or Erase mode (B and E), and Shift for straight lines
- Spot Healing Brush (content-aware)
- Clone Stamp, aligned or not, sampling one layer or all of them
- Blur tool, on pixels or masks
- Gradient tool and Shape tool (rectangles, rounded rectangles, ellipses and lines), which stay editable rather than being rasterized: a fill, an outline and a line width of their own, remembered for the next shape and changed on a selected shape; click instead of dragging to type a size, around the click or From Center
- Type tool (T): inline multiline editing in draggable, resizable paragraph boxes; font, size, color, alignment and spacing in the tool header (the color also recolors a selected text layer, and new text keeps the last color); transform text and use it as a clipping mask
- Eyedropper and a full color picker

### Adjustments and filters
- Camera Raw filter: light, color, curves, color mixer, color grading, detail, optics and geometry, in a panel beside the canvas
- Levels (with Auto), Curves, Hue/Saturation, Exposure, Gradient Map, Grain, Black & White, Color Balance and Invert
- Gaussian Blur and Motion Blur that spread past a layer's edges
- Add Noise, Vignette, Bloom / Glow, Tonal Contrast, Lens Correction and Remove Background
- Live previews, limited to the selection when there is one

### Canvas and files
- Multiple projects in tabs
- Rulers (⌘R), guides dragged from them, a layout grid with adjustable spacing and subdivisions, and Snap To for guides, grid, layers and document bounds
- Crop with snapping, ratios including 3:4 and 9:16, and Option for symmetric cropping; with a selection, the crop starts at it
- Canvas Size, Image Size and Trim
- Sharp high-quality downsampling when zoomed out, and a pixel grid when zoomed in
- Import JPEG, PNG, HEIC, TIFF, SVG, camera RAW (with a develop step first) and Photoshop PSD and PSB (8-bit RGB; not CMYK). Photoshop folders, masks, blend modes, layer styles, fill rectangles/ellipses, and horizontal text (with its per-letter colors and faces) stay editable; other vectors and vertical text become pixels. A conversion report is shown before anything is applied.
- Large documents: the memory budget scales with your Mac, and a Photoshop file too big to open has its layers cropped to the canvas instead
- Export JPEG with a live preview (⇧⌥⌘S); Copy Merged
- Keep working while a project saves
- Photoshop-style keyboard shortcuts throughout, remappable in Edit > Keyboard Shortcuts
- Drag a number's label to scrub its value, as in Photoshop
- Automatic updates, signed and notarized

### Works with AI agents
- AI agents and scripts can build and edit projects directly: a `.comp` is a folder of PNG layers and a manifest, and an open project updates live as it's written. See [Writing Compositor projects](docs/writing-comp-files.md)

## Requirements

- macOS 26.0 or later on a Mac with Apple silicon
- Xcode 26 or later (to build from source)

## Building

Open `Compositor.xcodeproj` and run the **Compositor** scheme.

## Releasing

`scripts/release.sh` builds a Release version, signs it with Developer ID, notarizes and staples it, and packages it into `dist/Compositor-<version>.dmg`.

It needs, all kept outside this repository:

- a **Developer ID Application** certificate in the login keychain
- notarization credentials saved with `xcrun notarytool store-credentials "compositor-notary" …`
- [`create-dmg`](https://github.com/create-dmg/create-dmg) (`brew install create-dmg`)

## License

MIT — see [LICENSE](LICENSE).
