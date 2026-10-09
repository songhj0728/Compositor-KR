import Testing
@testable import Compositor

struct NewCanvasPresetTests {
    @Test func ratioButtonsMatchEitherWayUp() {
        #expect(DigitalAspectRatio.matching(width: 3840, height: 2160) == .widescreen)
        #expect(DigitalAspectRatio.matching(width: 1080, height: 1920) == .widescreen)
        #expect(DigitalAspectRatio.matching(width: 1440, height: 1080) == .standard)
        #expect(DigitalAspectRatio.matching(width: 1080, height: 1080) == .square)
        #expect(DigitalAspectRatio.matching(width: 1080, height: 1350) == nil)
        #expect(DigitalAspectRatio.matching(width: 1080, height: 608) == nil)
    }

    @Test func otherRatiosReadAsNumbers() {
        #expect(aspectRatioText(width: 1080, height: 1350) == "4:5")
        #expect(aspectRatioText(width: 2560, height: 1080) == "2.37:1")
        #expect(aspectRatioText(width: 1206, height: 2622) == "1:2.17")
        #expect(aspectRatioText(width: 1080, height: 608) == "1.78:1")
    }

    @Test func presetsAreSplitIntoSocialAndDevice() {
        #expect(CanvasPreset.all(.social).map(\.title).allSatisfy { $0.hasPrefix("Instagram") || $0.hasPrefix("YouTube") })
        #expect(CanvasPreset.all(.device).contains { $0.title == "4K" })
        #expect(CanvasPreset.sections(.device).count == 2)
    }

    @Test func deviceResolutionsInclude720p() {
        #expect(CanvasPreset.all(.device).contains { $0.title == "720p" && $0.width == 1280 && $0.height == 720 })
    }

    @Test func paperPresetsAreDistinctAndUpright() {
        let all = PaperPreset.all
        #expect(Set(all.map(\.id)).count == all.count)
        #expect(all.allSatisfy { $0.width > 0 && $0.width <= $0.height })
        #expect(PaperPreset.common.map(\.id).prefix(3) == ["A4", "A3", "A5"])
        #expect(PaperPreset.more.count >= 5)
        // Nothing listed twice, above and below the divider.
        let below = Set(PaperPreset.more.flatMap(\.sizes).map(\.id))
        #expect(below.isDisjoint(with: PaperPreset.common.map(\.id)))
    }

    @Test func paperMatchesEitherWayUp() {
        let a4 = PaperPreset.all.first { $0.id == "A4" }!
        #expect(a4.matches(width: 210, height: 297))
        #expect(a4.matches(width: 297, height: 210))
        #expect(!a4.matches(width: 216, height: 279))
        let letter = PaperPreset.all.first { $0.id == "Letter" }!
        #expect(letter.matches(width: 215.9, height: 279.4))
        // ISO and JIS B4 are different sheets.
        let matches = PaperPreset.all.filter { $0.matches(width: 257, height: 364) }.map(\.id)
        #expect(matches == ["B4 (JIS)"])
    }

    @Test func lengthUnitsConvertThroughMillimeters() {
        #expect(LengthUnit.allCases == [.millimeters, .centimeters, .inches])
        #expect(LengthUnit.centimeters.value(fromMillimeters: 297) == 29.7)
        #expect(LengthUnit.centimeters.millimeters(from: 21) == 210)
        #expect(abs(LengthUnit.inches.millimeters(from: 11) - 279.4) < 1e-9)
        #expect(LengthUnit.allCases.map(\.symbol) == ["mm", "cm", "in"])
    }
}
