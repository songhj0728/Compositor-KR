import AppKit
import Testing
@testable import Compositor

@MainActor
struct SmearToolTests {
    /// A 200 × 100 canvas holding one layer: `left` gray on the left half, `right` gray on the right.
    private func session(left: CGFloat, right: CGFloat) throws -> EditorSession {
        let session = EditorSession()
        session.createDocument(width: 200, height: 100)
        let context = try BrushRaster.context(width: 200, height: 100, mask: false)
        context.setFillColor(CGColor(srgbRed: left, green: left, blue: left, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 100, height: 100))
        context.setFillColor(CGColor(srgbRed: right, green: right, blue: right, alpha: 1))
        context.fill(CGRect(x: 100, y: 0, width: 100, height: 100))
        let image = try #require(context.makeImage())
        session.insert(ImportedImage(image: image, thumbnail: image, name: "Step"))
        return session
    }

    private func gray(_ image: CGImage, x: Int, y: Int = 50) throws -> Int {
        let context = try BrushRaster.context(width: image.width, height: image.height, mask: false)
        BrushRaster.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height), mask: false, context: context)
        return Int(try #require(context.data).assumingMemoryBound(to: UInt8.self)[y * context.bytesPerRow + x * 4])
    }

    /// The Blur (or Sharpen) sample a stroke on the layer starts with, and a reader of it at the layer's pixels.
    private func sample(_ session: EditorSession, sharpen: Bool = false) throws -> (Int) throws -> Int {
        let layer = try #require(session.activeLayer)
        let stroke = try session.makeRasterEdit(for: layer)
        let sample = try #require(session.blurSample(for: stroke, sharpen: sharpen))
        return { x in try self.gray(sample.image, x: x - Int(sample.placed.minX), y: 50 - Int(sample.placed.minY)) }
    }

    @Test func modesAreBlurSharpenAndSmudge() {
        #expect(BlurToolMode.allCases == [.blur, .sharpen, .smudge])
        #expect(EditorSession().blurMode == .blur)
    }

    /// A big brush still only softens the edge a little, so an area a few pixels away keeps its own color instead of
    /// being painted over with the average of everything under the brush.
    @Test func blurSoftensTheEdgeWithoutPaintingTheAverageColor() throws {
        let s = try session(left: 0, right: 1)
        s.brushSettings.diameter = 200
        let soft = try sample(s)
        #expect(try soft(85) < 5)
        #expect(try soft(115) > 250)
        let edge = try soft(99)
        #expect(edge > 60 && edge < 200)
        // The canvas's own border doesn't soften toward transparent.
        #expect(try soft(199) > 250)
    }

    @Test func sharpenDeepensTheEdgeOnBothSides() throws {
        let s = try session(left: 0.4, right: 0.6)
        s.brushSettings.diameter = 100
        let crisp = try sample(s, sharpen: true)
        #expect(try crisp(99) < 100)
        #expect(try crisp(100) > 155)
        // Away from the edge, flat gray stays as it is.
        #expect(abs(try crisp(30) - 102) <= 2)
    }

    @Test func sharpenStrokesPaintAndCommitOneUndoStep() throws {
        let s = try session(left: 0.4, right: 0.6)
        s.tool = .blur
        s.blurMode = .sharpen
        s.brushSettings.diameter = 40
        s.brushSettings.opacity = 1
        let before = try #require(s.activeLayer?.asset?.image)
        s.beginBrush(at: CGPoint(x: 100, y: 20))
        s.continueBrush(at: CGPoint(x: 100, y: 80))
        #expect(s.finishBrushImmediately())
        let after = try #require(s.activeLayer?.asset?.image)
        #expect(after !== before)
        // A 40 px brush sharpens within about a pixel of the edge: the dark side's last column (102 before) darkens.
        #expect(try gray(after, x: 99) < 100)
        s.undo()
        #expect(s.activeLayer?.asset?.image === before)
    }

    @Test func statusBarSaysWhetherTheCanvasIsTransparent() throws {
        let transparent = EditorSession()
        transparent.createNewProject(width: 50, height: 40, profile: .displayP3, background: nil)
        #expect(transparent.document?.hasOpaqueBackground == false)
        #expect(transparent.document?.colorProfile == .displayP3)

        let white = EditorSession()
        white.createNewProject(width: 50, height: 40, background: .white)
        #expect(white.document?.hasOpaqueBackground == true)
        // Hidden, faded or moved off the corner, the background no longer covers the canvas.
        white.document?.layers[0].opacity = 0.5
        #expect(white.document?.hasOpaqueBackground == false)
        white.document?.layers[0].opacity = 1
        white.document?.layers[0].transform.origin.x = 5
        #expect(white.document?.hasOpaqueBackground == false)
        white.document?.layers[0].transform.origin.x = 0
        white.document?.layers[0].isVisible = false
        #expect(white.document?.hasOpaqueBackground == false)

        // A layer that covers the canvas but has transparent pixels isn't a background.
        let half = try session(left: 1, right: 1)
        #expect(half.document?.hasOpaqueBackground == true)
        let holey = EditorSession()
        holey.createDocument(width: 200, height: 100)
        let context = try BrushRaster.context(width: 200, height: 100, mask: false)
        context.setFillColor(CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 100, height: 100))
        let image = try #require(context.makeImage())
        holey.insert(ImportedImage(image: image, thumbnail: image, name: "Half"))
        #expect(holey.document?.hasOpaqueBackground == false)
    }
}

/// Clicking Blur over and over in one place softens what's there without drawing it toward the brush's center.
@MainActor
struct BlurDriftTests {
    /// White, with a dark vertical line at x 88–89: off the brush's center (100), so a pull toward it would show.
    private func session() throws -> EditorSession {
        let session = EditorSession()
        session.createDocument(width: 200, height: 100)
        let context = try BrushRaster.context(width: 200, height: 100, mask: false)
        context.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 200, height: 100))
        context.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 88, y: 0, width: 2, height: 100))
        let image = try #require(context.makeImage())
        session.insert(ImportedImage(image: image, thumbnail: image, name: "Line"))
        session.tool = .blur
        session.blurMode = .blur
        session.brushSettings.diameter = 80
        session.brushSettings.hardness = 0
        session.brushSettings.opacity = 1
        return session
    }

    /// Row 50's darkness from x 50 to 150: where it's centered, how far it's spread (its standard deviation), and how
    /// much there is.
    private func darkness(_ image: CGImage) throws -> (center: Double, spread: Double, total: Double, peak: Int) {
        let context = try BrushRaster.context(width: image.width, height: image.height, mask: false)
        BrushRaster.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height), mask: false, context: context)
        let data = try #require(context.data).assumingMemoryBound(to: UInt8.self)
        var weighted = 0.0, squared = 0.0, total = 0.0, peak = 0
        for x in 50...150 {
            let dark = 255 - Int(data[50 * context.bytesPerRow + x * 4])
            weighted += Double(dark) * (Double(x) + 0.5)
            squared += Double(dark) * (Double(x) + 0.5) * (Double(x) + 0.5)
            total += Double(dark)
            peak = max(peak, dark)
        }
        let center = weighted / max(1, total)
        return (center, max(0, squared / max(1, total) - center * center).squareRoot(), total, peak)
    }

    @Test func repeatedClicksDoNotPullTowardTheCenter() throws {
        let s = try session()
        let before = try darkness(#require(s.activeLayer?.asset?.image))
        for _ in 0..<25 {
            s.beginBrush(at: CGPoint(x: 100, y: 50))
            #expect(s.finishBrushImmediately())
        }
        let after = try darkness(#require(s.activeLayer?.asset?.image))
        // Softened: the line spreads, its darkest point lighter than before.
        #expect(after.peak < before.peak - 30)
        // Not pulled along: a soft brush's weight falls toward its rim, so a line off its center spreads a little more
        // toward the center than away, but its middle stays where it was next to how far it has spread (the old Blur
        // dragged it 3.4 pixels here). And nothing is gained or lost, give or take 8-bit rounding.
        #expect(abs(after.center - before.center) < 0.15 * after.spread,
                "moved from \(before.center) to \(after.center), spread \(after.spread)")
        #expect(abs(after.total - before.total) / before.total < 0.03, "from \(before.total) to \(after.total)")
    }

    @Test func aFlatAreaStaysFlat() throws {
        let s = try session()
        for _ in 0..<10 {
            s.beginBrush(at: CGPoint(x: 150, y: 50))
            #expect(s.finishBrushImmediately())
        }
        let image = try #require(s.activeLayer?.asset?.image)
        let context = try BrushRaster.context(width: image.width, height: image.height, mask: false)
        BrushRaster.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height), mask: false, context: context)
        let data = try #require(context.data).assumingMemoryBound(to: UInt8.self)
        // Right of the line everything was white, and still is: no ring where the brush's edge fades.
        for x in 120..<200 { #expect(data[50 * context.bytesPerRow + x * 4] >= 254) }
    }
}
