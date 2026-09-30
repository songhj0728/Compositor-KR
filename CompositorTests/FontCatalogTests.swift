import AppKit
import Testing
@testable import Compositor

/// `FontCatalog` backs the Type bar's font family and weight/style pickers: it reads AppKit's catalog by family, so
/// choosing a family, then a weight within it, replaces what used to be one flat list of every face of every font.
@MainActor
struct FontCatalogTests {
    @Test func familiesExcludeHiddenSystemNamesAndIncludeHelvetica() {
        let families = FontCatalog.families()
        #expect(families.contains("Helvetica"))
        #expect(!families.contains { $0.hasPrefix(".") })
        #expect(families == families.sorted())
    }

    /// Helvetica's own faces, lightest to heaviest, upright before italic.
    @Test func facesListHelveticasOwnWeightsInOrder() {
        let faces = FontCatalog.faces(ofFamily: "Helvetica")
        let names = faces.map(\.postscript)
        #expect(names.contains("Helvetica") && names.contains("Helvetica-Bold"))
        let regular = faces.firstIndex { $0.postscript == "Helvetica" }
        let bold = faces.firstIndex { $0.postscript == "Helvetica-Bold" }
        let boldOblique = faces.firstIndex { $0.postscript == "Helvetica-BoldOblique" }
        if let regular, let bold { #expect(regular < bold, "Regular sorts lighter than Bold") }
        if let bold, let boldOblique { #expect(bold < boldOblique, "upright before italic") }
    }

    @Test func familyAndFaceRoundTripsAKnownFont() {
        let found = FontCatalog.familyAndFace(of: "Helvetica-Bold")
        #expect(found?.family == "Helvetica")
        #expect(found?.face == "Bold")
        #expect(FontCatalog.familyAndFace(of: "") == nil)
        #expect(FontCatalog.familyAndFace(of: "Not-An-Installed-Font-Name") == nil)
    }

    /// Switching a bold face into another family keeps it bold there instead of resetting to that family's Regular.
    @Test func convertCarriesWeightAndStyleIntoTheNewFamily() {
        let converted = FontCatalog.convert("Helvetica-Bold", toFamily: "Courier")
        let face = FontCatalog.familyAndFace(of: converted)
        #expect(face?.family == "Courier")
        #expect(face?.face.localizedCaseInsensitiveContains("Bold") == true, "stayed bold: \(converted)")
        // An unknown base font still lands somewhere in the target family rather than failing outright.
        #expect(FontCatalog.familyAndFace(of: FontCatalog.convert("", toFamily: "Courier"))?.family == "Courier")
    }
}
