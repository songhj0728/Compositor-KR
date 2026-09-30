import SwiftUI
import Testing
@testable import Compositor

struct FilterKindTests {
    private let expected: [(FilterKind, String)] = [
        (.gaussianBlur, "Gaussian Blur"), (.motionBlur, "Motion Blur"), (.addNoise, "Add Noise"),
        (.vignette, "Vignette"), (.bloomGlow, "Bloom / Glow"), (.dither, "Dither"),
        (.tonalContrast, "Tonal Contrast"), (.lensCorrection, "Lens Correction"), (.cameraRaw, "Camera Raw Filter"),
        (.removeBackground, "Remove Background"), (.contentAwareFill, "Content-Aware Fill"), (.curves, "Curves"),
        (.exposure, "Exposure"), (.gradientMap, "Gradient Map"), (.grain, "Grain"),
        (.blackWhite, "Black & White"), (.colorBalance, "Color Balance"),
    ]

    /// Case order feeds the Filter menu; raw values also name history entries and filter panels.
    @Test func casesRawValuesAndOrderStayStable() {
        #expect(FilterKind.allCases == expected.map { $0.0 })
        #expect(Set(FilterKind.allCases).count == expected.count)
        for (kind, rawValue) in expected {
            #expect(kind.rawValue == rawValue)
            #expect(FilterKind(rawValue: rawValue) == kind)
        }
        #expect(FilterKind(rawValue: "Unknown Filter") == nil)
    }

    @Test func classificationsKeepMenuAndPreviewBehavior() {
        #expect(FilterKind.allCases.filter(\.isAutomatic) == [.removeBackground, .contentAwareFill])
        #expect(FilterKind.allCases.filter(\.isImageAdjustment) == [
            .curves, .exposure, .gradientMap, .grain, .blackWhite, .colorBalance,
        ])
        #expect(FilterKind.allCases.filter { $0 != .contentAwareFill && !$0.isImageAdjustment } == [
            .gaussianBlur, .motionBlur, .addNoise, .vignette, .bloomGlow, .dither,
            .tonalContrast, .lensCorrection, .cameraRaw, .removeBackground,
        ])
    }

    /// Keep the original literal localization keys; the catalog and the menu's Text construction stay unchanged.
    @Test func presentationCoversEveryCaseWithItsOriginalKey() {
        for (kind, key) in expected {
            #expect(kind.displayName == LocalizedStringKey(key))
        }
    }
}
