import CoreGraphics
import Foundation
import Testing
@testable import Compositor

/// The Blur brush softens by its own Radius, whatever its size.
@MainActor
struct BlurBrushTests {
    /// A hard vertical edge, blurred with one stroke along it, from past the canvas's top to past its bottom (the Blur
    /// brush builds up dab by dab, so a stroke shorter than the brush would soften less with a bigger brush): how many
    /// columns it spreads over.
    private func spread(radius: CGFloat, diameter: CGFloat = 60, strength: CGFloat = 1) throws -> Int {
        let session = EditorSession()
        session.createDocument(width: 200, height: 100)
        let context = try BrushRaster.context(width: 200, height: 100, mask: false)
        context.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 200, height: 100))
        context.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 100, y: 0, width: 100, height: 100))
        let image = try #require(context.makeImage())
        session.insert(ImportedImage(image: image, thumbnail: image, name: "Edge"))
        session.selectTool(.blur)
        session.blurMode = .blur
        session.brushSettings.diameter = diameter
        session.brushSettings.hardness = 1
        session.brushSettings.opacity = strength
        session.brushSettings.blurRadius = radius
        session.beginBrush(at: CGPoint(x: 100, y: -60))
        session.continueBrush(at: CGPoint(x: 100, y: 160))
        session.finishBrushImmediately()
        let result = try BrushRaster.copy(try #require(session.activeLayer?.asset?.image))
        let data = try #require(result.data).assumingMemoryBound(to: UInt8.self)
        // Columns along row 50 that are neither black nor white any more.
        return (0..<200).filter { let v = data[50 * result.bytesPerRow + $0 * 4]; return v > 10 && v < 245 }.count
    }

    @Test func radiusSetsHowFarItSoftens() throws {
        let narrow = try spread(radius: 2), wide = try spread(radius: 12)
        #expect(wide > narrow * 2, "a wider radius spreads the edge further: \(narrow) against \(wide)")
        // Brush size doesn't change the reach, give or take where the dabs happen to fall.
        let bigger = try spread(radius: 12, diameter: 80)
        #expect(abs(bigger - wide) <= 2, "\(wide) columns with a 60-pixel brush, \(bigger) with an 80")
    }
}
