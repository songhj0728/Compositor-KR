import CoreGraphics

/// Where the whole document sits in the Navigator's box (fitted, centered, its proportions kept), and the
/// conversions between that picture and document pixels.
///
/// Compositor-KR: the arithmetic is Core/NavigatorLayout.swift, shared with a Windows port; this adapts it to Core
/// Graphics, keeping upstream's API so the minimap and its tests read the same.
struct NavigatorGeometry: Equatable {
    let documentSize: CGSize
    let box: CGSize

    var imageRect: CGRect {
        NavigatorLayout.imageRect(documentWidth: Double(documentSize.width), documentHeight: Double(documentSize.height),
                                  boxWidth: Double(box.width), boxHeight: Double(box.height)).cgRect
    }

    func thumbnailRect(for documentRect: CGRect) -> CGRect {
        NavigatorLayout.thumbnailRect(for: PlaneRect(documentRect), documentWidth: Double(documentSize.width),
                                      imageRect: PlaneRect(imageRect)).cgRect
    }

    /// The document pixel under a point in the box, held to the document's edges.
    func documentPoint(for point: CGPoint) -> CGPoint {
        let p = NavigatorLayout.documentPoint(x: Double(point.x), y: Double(point.y), documentWidth: Double(documentSize.width),
                                              documentHeight: Double(documentSize.height), imageRect: PlaneRect(imageRect))
        return CGPoint(x: p.x, y: p.y)
    }
}

extension PlaneRect {
    init(_ rect: CGRect) { self.init(x: Double(rect.minX), y: Double(rect.minY), width: Double(rect.width), height: Double(rect.height)) }
    var cgRect: CGRect { CGRect(x: x, y: y, width: width, height: height) }
}

extension CanvasViewport {
    /// The part of the document the canvas shows, in document pixels. It reaches past the document's edges when the
    /// canvas shows more than the document.
    func visibleDocumentRect(documentSize: CGSize) -> CGRect {
        let topLeft = documentPoint(from: .zero, documentSize: documentSize)
        let bottomRight = documentPoint(from: CGPoint(x: viewSize.width, y: viewSize.height), documentSize: documentSize)
        return CGRect(x: min(topLeft.x, bottomRight.x), y: min(topLeft.y, bottomRight.y),
                      width: abs(bottomRight.x - topLeft.x), height: abs(bottomRight.y - topLeft.y))
    }

    /// Scrolls so `point` (document pixels) is in the middle of the canvas, at the same zoom. Goes through
    /// `translate(by:)` so the view stops following Fit, as any scroll the person makes does.
    mutating func centerView(on point: CGPoint, documentSize: CGSize) {
        let target = NavigatorLayout.centeredPan(onX: Double(point.x), y: Double(point.y), documentWidth: Double(documentSize.width),
                                                 documentHeight: Double(documentSize.height), pointsPerPixel: Double(pointsPerPixel))
        translate(by: CGSize(width: CGFloat(target.width) - pan.width, height: CGFloat(target.height) - pan.height))
    }
}
