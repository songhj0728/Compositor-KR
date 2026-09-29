import AppKit
import CoreImage

extension EditorSession {
    /// What a Blur or Sharpen stroke paints: the layer's own pixels (or, painting the mask, its mask), softened or
    /// crisped a little by an amount that follows the brush size on the canvas, at the layer's own resolution. It is
    /// taken when the stroke starts, so going over an area again in a new stroke works it further, as in Photoshop.
    /// The amount stays small: a strong blur painted at full strength would lay the area's average color down like paint.
    func blurSample(for stroke: BrushStroke, sharpen: Bool = false) -> (image: CGImage, placed: CGRect, inGrid: Bool)? {
        let layer = stroke.layer
        guard let image = stroke.isMask ? layer.mask?.asset.image : layer.asset?.image else { return nil }
        // The canvas's amount, carried into the layer's pixels: wider there when the layer is scaled down.
        let map = stroke.pixelToDocument
        let perPixel = max(1e-6, abs(map.a * map.d - map.b * map.c).squareRoot())
        let sidePixels = max(stroke.sourceRect.width, stroke.sourceRect.height)
        let diameter = Double(brushSettings.diameter)
        let sigma = min((sharpen ? min(3, max(1, diameter / 50)) : min(4, max(1, diameter / 40))) / perPixel, sidePixels / 2)
        // Room for the blur to spread past the pixels' edges, as it does on the canvas.
        let margin = ceil(3 * sigma)
        let region = stroke.sourceRect.insetBy(dx: -margin, dy: -margin)
        // At the layer's own resolution up to a budget of several canvases; a huge layer's sample is made coarser
        // instead (the stroke scales it back over the layer), rather than a surface too large to make at every stroke.
        let canvas = (document?.width ?? 0) * (document?.height ?? 0)
        let budget = Double(min(DocumentLimits.maxSurfacePixels, max(16_000_000, 4 * canvas)))
        let fit = min(1, (budget / Double(region.width * region.height)).squareRoot())
        let width = max(1, Int((region.width * fit).rounded(.up))), height = max(1, Int((region.height * fit).rounded(.up)))
        guard let context = try? BrushRaster.context(width: width, height: height, mask: stroke.isMask) else { return nil }
        let extent = CGRect(x: 0, y: 0, width: width, height: height)
        let placed = CGRect(x: margin * fit, y: margin * fit, width: stroke.sourceRect.width * fit, height: stroke.sourceRect.height * fit)
        if stroke.isMask, let owned = layer.mask {
            // Past its pixels a mask keeps its edge tone, so blurring near its edge doesn't pull in the wrong one.
            context.setFillColor(gray: LayerMask.background(of: owned.asset.thumbnail), alpha: 1)
            context.fill(extent)
        }
        BrushRaster.draw(image, in: placed, mask: stroke.isMask, context: context)
        guard let sharp = context.makeImage() else { return nil }
        let source = CIImage(cgImage: sharp)
        // A mask carries on in its edge tone; a layer's own edge pixels carry on past it, so its border (the canvas's,
        // for a layer that fills it) doesn't soften toward transparent. Core Image counts rows from the bottom.
        let own = CGRect(x: placed.minX, y: Double(height) - placed.maxY, width: placed.width, height: placed.height)
        let clamped = stroke.isMask ? source.clampedToExtent() : source.cropped(to: own).clampedToExtent()
        let worked = sharpen
            ? clamped.applyingFilter("CIUnsharpMask", parameters: [kCIInputRadiusKey: sigma * fit, kCIInputIntensityKey: 0.6])
            : clamped.applyingGaussianBlur(sigma: sigma * fit)
        guard let result = try? PixelAdjust.render(worked.cropped(to: extent), width: width, height: height, isMask: stroke.isMask) else { return nil }
        return (result, region, true)
    }
}
