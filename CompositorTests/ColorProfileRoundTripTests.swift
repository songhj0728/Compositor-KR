import AppKit
import ImageIO
import Testing
@testable import Compositor

/// Every RGB profile a project can be in survives the ways out of the app: the exported file carries that profile and
/// the project's own color numbers, and a layered PSD reads back in the space it was written in.
@MainActor
struct ColorProfileRoundTripTests {
    static let rgbProfiles: [DocumentColorProfile] = [.sRGB, .displayP3, .adobeRGB, .rec709, .rec2020]
    private let fill = PaletteColor(red: 0.9, green: 0.1, blue: 0.1)

    private func snapshot(_ profile: DocumentColorProfile) throws -> ProjectSnapshot {
        let session = EditorSession()
        session.createNewProject(width: 16, height: 16, profile: profile, background: fill)
        return try #require(session.projectSnapshot())
    }

    /// The RGBA numbers of the image's center pixel, read without converting out of its own space.
    private func centerPixel(_ image: CGImage) throws -> [Int] {
        let space = try #require(image.colorSpace)
        let context = try #require(CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4, space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(image, in: CGRect(x: -CGFloat(image.width / 2), y: -CGFloat(image.height / 2),
                                       width: CGFloat(image.width), height: CGFloat(image.height)))
        let data = try #require(context.data).bindMemory(to: UInt8.self, capacity: 4)
        return (0..<4).map { Int(data[$0]) }
    }

    private func expectFillNumbers(_ pixel: [Int], tolerance: Int = 2, _ comment: Comment) {
        let expected = [Int((fill.red * 255).rounded()), Int((fill.green * 255).rounded()), Int((fill.blue * 255).rounded())]
        #expect(zip(pixel.prefix(3), expected).allSatisfy { abs($0 - $1) <= tolerance }, "\(comment): \(pixel) vs \(expected)")
    }

    private func decode(_ data: Data) throws -> CGImage {
        let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        return try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
    }

    @Test(arguments: rgbProfiles)
    func pngAndJPEGCarryTheProfileAndItsNumbers(profile: DocumentColorProfile) async throws {
        let snapshot = try snapshot(profile)
        let png = try decode(try await ImageExporter.shared.pngData(snapshot))
        #expect(png.colorSpace.flatMap(DocumentColorProfile.init(matching:)) == profile, "PNG tagged \(String(describing: png.colorSpace))")
        expectFillNumbers(try centerPixel(png), "PNG \(profile.rawValue)")
        let raster = try await ImageExporter.shared.render(snapshot)
        let jpeg = try decode(try await ImageExporter.shared.jpeg(raster, options: JPEGOptions()).data)
        #expect(jpeg.colorSpace.flatMap(DocumentColorProfile.init(matching:)) == profile, "JPEG tagged \(String(describing: jpeg.colorSpace))")
        expectFillNumbers(try centerPixel(jpeg), tolerance: 4, "JPEG \(profile.rawValue)")
    }

    @Test(arguments: rgbProfiles)
    func layeredPSDReadsBackInTheSpaceItWasWrittenIn(profile: DocumentColorProfile) async throws {
        let data = try await ImageExporter.shared.psd(try snapshot(profile)).data
        let document = try PSDReader.read(data)
        let layer = try #require(document.layers.first { $0.image != nil }?.image)
        #expect(layer.colorSpace.flatMap(DocumentColorProfile.init(matching:)) == profile,
                "PSD layer tagged \(String(describing: layer.colorSpace))")
        expectFillNumbers(try centerPixel(layer), "PSD \(profile.rawValue)")
        // Opened as a new canvas, the PSD is edited in the space it was saved in.
        let session = EditorSession()
        try session.insertPhotoshop(try PSDDocumentBuilder.makeImport(document), named: "Round trip")
        #expect(session.document?.colorProfile == profile)
    }

    /// Layer effects (the portable bevel kernels included) give back pixels in the layer's own space, and leave the
    /// flat middle of a layer at the project's numbers rather than re-reading them as sRGB.
    @Test(arguments: rgbProfiles)
    func bevelKeepsTheLayersSpaceAndNumbers(profile: DocumentColorProfile) throws {
        let session = EditorSession()
        session.createNewProject(width: 64, height: 64, profile: profile, background: fill)
        let image = try #require(session.document?.layers.first?.asset?.image)
        var bevel = BevelEffect()
        bevel.size = 4
        let styled = try LayerEffectsRenderer.render(image, mask: nil, effects: LayerEffects(bevel: bevel)).image
        #expect(styled.colorSpace.flatMap(DocumentColorProfile.init(matching:)) == profile,
                "bevel output tagged \(String(describing: styled.colorSpace))")
        expectFillNumbers(try centerPixel(styled), "bevel \(profile.rawValue)")
    }

    /// Export As at another size keeps the project's space: a scaled P3 picture isn't converted to sRGB, and a CMYK
    /// project's scaled JPEG is still CMYK.
    @Test func scaledExportsKeepTheProjectsProfile() async throws {
        for profile in [DocumentColorProfile.displayP3, .cmyk] {
            let raster = try await ImageExporter.shared.render(try snapshot(profile))
            let half = try await ImageExporter.shared.resized(raster, width: 8, height: 8)
            #expect(half.profile == profile)
            if profile == .displayP3 {
                #expect(half.image.colorSpace.flatMap(DocumentColorProfile.init(matching:)) == .displayP3)
                expectFillNumbers(try centerPixel(half.image), "scaled P3")
            }
            let jpeg = try decode(try await ImageExporter.shared.jpeg(half, options: JPEGOptions()).data)
            #expect(jpeg.colorSpace?.model == (profile == .cmyk ? .cmyk : .rgb))
        }
    }
}
