import AppKit
import ImageIO
import Testing
@testable import Compositor

@MainActor
struct ColorProfileTests {
    // Sessions made here aren't in front of any workspace, so they leave the shared working space the other
    // suites' buffers use alone; what's checked is what the project itself carries.

    private func newProject(_ profile: DocumentColorProfile, background: PaletteColor?) -> EditorSession {
        let session = EditorSession()
        session.createNewProject(width: 64, height: 32, profile: profile, background: background)
        return session
    }

    @Test func transparentCanvasStartsWithAnEmptyLayer() throws {
        let session = newProject(.sRGB, background: nil)
        let layers = try #require(session.document?.layers)
        #expect(layers.count == 1)
        #expect(layers[0].name == "Layer 1")
        #expect(layers[0].asset == nil)
    }

    @Test(arguments: [PaletteColor.white, PaletteColor(red: 0.2, green: 0.4, blue: 0.8)])
    func coloredCanvasStartsWithABackgroundLayer(color: PaletteColor) throws {
        let session = newProject(.displayP3, background: color)
        let document = try #require(session.document)
        #expect(document.colorProfile == .displayP3)
        #expect(document.layers.count == 1)
        let layer = document.layers[0]
        #expect(layer.name == String(localized: "Background"))
        #expect(session.activeLayerID == layer.id)
        let image = try #require(layer.asset?.image)
        #expect(image.width == 64 && image.height == 32)
        #expect(image.colorSpace?.name == CGColorSpace.displayP3)
        // Filled with the color's own numbers, in the project's space.
        let context = try #require(CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
            space: DocumentColorProfile.displayP3.workingSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(image, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        let pixel = try #require(context.data).bindMemory(to: UInt8.self, capacity: 4)
        #expect(abs(Int(pixel[0]) - Int((color.red * 255).rounded())) <= 1)
        #expect(abs(Int(pixel[2]) - Int((color.blue * 255).rounded())) <= 1)
        #expect(pixel[3] == 255)
    }

    @Test(arguments: DocumentColorProfile.allCases)
    func profileIsSavedAndLoadedWithTheProject(profile: DocumentColorProfile) async throws {
        let session = newProject(profile, background: .white)
        let snapshot = try #require(session.projectSnapshot())
        #expect(snapshot.manifest.colorSpace == profile.rawValue)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).comp")
        defer { try? FileManager.default.removeItem(at: url) }
        try await ProjectStore.shared.save(snapshot, to: url)
        let loaded = try await ProjectStore.shared.load(from: url)
        #expect(loaded.manifest.colorSpace == profile.rawValue)
        let reopened = EditorSession()
        reopened.installProject(loaded, from: url)
        #expect(reopened.document?.colorProfile == profile)
    }

    @Test func projectsOfOtherSpacesStillOpenAsSRGB() {
        #expect(DocumentColorProfile(rawValue: "sRGB") == .sRGB)
        #expect(DocumentColorProfile(rawValue: "ProPhoto") == nil)
    }

    @Test func exportCarriesTheProfileAndCMYKJPEGsAreCMYK() async throws {
        for profile in [DocumentColorProfile.adobeRGB, .rec2020, .cmyk] {
            let session = newProject(profile, background: PaletteColor(red: 0.9, green: 0.1, blue: 0.1))
            let snapshot = try #require(session.projectSnapshot())
            let raster = try await ImageExporter.shared.render(snapshot)
            #expect(raster.profile == profile)
            #expect(raster.image.colorSpace?.name == profile.workingSpace.name)
            let jpeg = try await ImageExporter.shared.jpeg(raster, options: JPEGOptions())
            let source = try #require(CGImageSourceCreateWithData(jpeg.data as CFData, nil))
            let decoded = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
            #expect(decoded.colorSpace?.model == (profile == .cmyk ? .cmyk : .rgb))
        }
    }
}
