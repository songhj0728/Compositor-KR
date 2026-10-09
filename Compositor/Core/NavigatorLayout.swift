// The Navigator minimap's geometry (View › Navigator, from upstream 1.4.8): where the whole document sits in the
// Navigator's box, fitted and centered with its proportions kept, and the conversions between that picture, document
// pixels and the canvas's scroll.
//
// Platform-neutral on purpose: plain Doubles, standard library only, so a Windows port draws the same minimap and
// moves the view the same way. Rendering/NavigatorGeometry.swift adapts it to Core Graphics for the macOS app.

/// A rectangle in some plane's units, top-left origin.
nonisolated struct PlaneRect: Equatable, Sendable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double
    static let zero = PlaneRect(x: 0, y: 0, width: 0, height: 0)
}

nonisolated enum NavigatorLayout {
    /// The document fitted inside a `boxWidth` × `boxHeight` box, centered; empty when either has no size.
    static func imageRect(documentWidth: Double, documentHeight: Double, boxWidth: Double, boxHeight: Double) -> PlaneRect {
        guard documentWidth > 0, documentHeight > 0, boxWidth > 0, boxHeight > 0 else { return .zero }
        let scale = min(boxWidth / documentWidth, boxHeight / documentHeight)
        let width = documentWidth * scale, height = documentHeight * scale
        return PlaneRect(x: (boxWidth - width) / 2, y: (boxHeight - height) / 2, width: width, height: height)
    }

    /// Box points per document pixel.
    static func scale(documentWidth: Double, imageRect: PlaneRect) -> Double {
        documentWidth > 0 ? imageRect.width / documentWidth : 0
    }

    /// A rectangle of document pixels (the part the canvas shows, say) where it falls in the box.
    static func thumbnailRect(for documentRect: PlaneRect, documentWidth: Double, imageRect: PlaneRect) -> PlaneRect {
        let scale = scale(documentWidth: documentWidth, imageRect: imageRect)
        return PlaneRect(x: imageRect.x + documentRect.x * scale, y: imageRect.y + documentRect.y * scale,
                         width: documentRect.width * scale, height: documentRect.height * scale)
    }

    /// The document pixel under a point in the box, held to the document's edges.
    static func documentPoint(x: Double, y: Double, documentWidth: Double, documentHeight: Double,
                              imageRect: PlaneRect) -> (x: Double, y: Double) {
        let scale = scale(documentWidth: documentWidth, imageRect: imageRect)
        guard scale > 0 else { return (0, 0) }
        return (min(max((x - imageRect.x) / scale, 0), documentWidth), min(max((y - imageRect.y) / scale, 0), documentHeight))
    }

    /// The canvas pan that puts document pixel (`x`, `y`) in the middle of the view at `pointsPerPixel`, with the
    /// document centered at a pan of zero, as the canvas lays it out.
    static func centeredPan(onX x: Double, y: Double, documentWidth: Double, documentHeight: Double,
                            pointsPerPixel: Double) -> (width: Double, height: Double) {
        (documentWidth * pointsPerPixel / 2 - x * pointsPerPixel, documentHeight * pointsPerPixel / 2 - y * pointsPerPixel)
    }
}
