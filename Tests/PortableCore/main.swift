// Compile with Compositor/Core/*.swift. This harness uses only the Swift standard library and Foundation, which
// Swift ships on Windows and Linux too.
import Foundation
let locks: [Int: (locked: Bool, parent: Int?)] = [
    1: (true, nil), 2: (false, 1), 3: (false, 2), 4: (false, nil)
]
precondition(LayerLockRules.isLocked(3) { locks[$0] })
precondition(!LayerLockRules.isLocked(4) { locks[$0] })
precondition(LayerLockRules.isLocked(1) { id in (false, id) })
precondition(LayerLockRules.toggledValue([false, true]))
precondition(!LayerLockRules.toggledValue([true, true]))
precondition(BevelGeometry.clampedSize(250, width: 24, height: 24) == 6)
precondition(BevelGeometry.clampedSize(0, width: 24, height: 24) == 0)
precondition(BevelGeometry.clampedSize(2, width: 24, height: 24) == 2)
let square: [Float] = [
    0, 0, 0, 0, 0,
    0, 1, 1, 1, 0,
    0, 1, 1, 1, 0,
    0, 1, 1, 1, 0,
    0, 0, 0, 0, 0
]
let distances = BevelGeometry.edgeDistances(square, width: 5, height: 5)
precondition(distances[12] == 1.5)
precondition(distances[6] == 0.5 && abs(distances[0] - (Float(2).squareRoot() - 0.5)) < 0.00001)
for y in 0..<5 {
    for x in 0..<5 {
        precondition(distances[y * 5 + x] == distances[y * 5 + 4 - x])
        precondition(distances[y * 5 + x] == distances[(4 - y) * 5 + x])
    }
}
print("Portable core tests passed: inherited locks, cycles, toggles, bevel limits and silhouette symmetry")

// Compare against a brute-force Euclidean oracle, including a circular hole.
let side = 41
let disk: [Float] = (0..<(side * side)).map { i in
    let x = i % side - 20, y = i / side - 20
    return x * x + y * y <= 144 ? 0 : 1
}
let circular = BevelGeometry.edgeDistances(disk, width: side, height: side)
for i in disk.indices {
    var nearest = Float.infinity
    for j in disk.indices where disk[j] != disk[i] {
        let dx = i % side - j % side, dy = i / side - j / side
        nearest = min(nearest, Float(dx * dx + dy * dy).squareRoot())
    }
    precondition(abs(circular[i] - (nearest - 0.5)) < 0.00001,
                 "Circular bevel distances must be Euclidean at every angle")
}
print("Circular hole Euclidean oracle passed")

// Interrupted obsolete requests must stop before both complete transforms finish.
var cancellationChecks = 0
do {
    _ = try BevelGeometry.edgeDistances(disk, width: side, height: side, isCancelled: {
        cancellationChecks += 1
        return cancellationChecks == 5
    })
    preconditionFailure("An obsolete distance calculation completed")
} catch BevelGeometry.CalculationError.cancelled {
    precondition(cancellationChecks == 5)
} catch { preconditionFailure("Unexpected cancellation error") }
let narrow = BevelGeometry.edgeDistances([0, 1, 1, 0], width: 1, height: 4)
precondition(narrow == [0.5, 0.5, 0.5, 0.5])
print("Cooperative cancellation and single-column geometry passed")

precondition(BevelGeometry.height(distance: -2, size: 4, profile: .inner) == 0)
precondition(BevelGeometry.height(distance: 2, size: 4, profile: .inner) == 0.5)
precondition(BevelGeometry.height(distance: 8, size: 4, profile: .inner) == 1)
precondition(BevelGeometry.height(distance: -2, size: 4, profile: .outer) == 0.5)
precondition(BevelGeometry.height(distance: 0, size: 4, profile: .emboss) == 0.5)
precondition(BevelGeometry.height(distance: -2, size: 4, profile: .pillow)
    == BevelGeometry.height(distance: 2, size: 4, profile: .pillow))
precondition(BevelGeometry.lighting(slopeX: 0, slopeY: 0, light: SIMD3(0, 0, 1)) == 1)
print("Shared bevel profiles and flat-surface lighting passed")

precondition(BevelGeometry.roundedHeight(0) == 0)
precondition(BevelGeometry.roundedHeight(1) == 1)
precondition(BevelGeometry.roundedHeight(0.5) == 0.5)
let shoulderSlope = BevelGeometry.roundedHeight(0.01) / 0.01
let middleSlope = (BevelGeometry.roundedHeight(0.51) - BevelGeometry.roundedHeight(0.49)) / 0.02
precondition(shoulderSlope < 0.04 && middleSlope > 1.4)
precondition(abs((1 - BevelGeometry.roundedHeight(0.99)) / 0.01 - shoulderSlope) < 0.0001)
print("Smooth bevel endpoints and tapered slopes passed")
let shadeA = BevelGeometry.shading(lit: -0.1, flat: 0.5)
let shadeB = BevelGeometry.shading(lit: -0.3, flat: 0.5)
precondition(shadeA.shadow < shadeB.shadow && shadeB.shadow < 1)
precondition(BevelGeometry.shading(lit: 0.5, flat: 0.5).shadow == 0)
precondition(BevelGeometry.shading(lit: -1, flat: 0.5).shadow == 1)
print("Diffuse shadows remain graded below the horizon")

// Vector paths: the editing rules the Pen and the path selection tools share.
var path = VectorPath(name: "Path 1", contours: [PathContour(anchors: [
    PathAnchor(PathVector(0, 0)), PathAnchor(PathVector(100, 0)), PathAnchor(PathVector(100, 100))
])])
if case .anchor(let ref)? = PathEditing.hitTest(path, at: PathVector(99, 1), tolerance: 4) {
    precondition(ref == PathAnchorRef(contour: 0, anchor: 1))
} else { preconditionFailure("an anchor under the pointer is hit") }
if case .segment(0, 0, let t)? = PathEditing.hitTest(path, at: PathVector(50, 2), tolerance: 4) {
    precondition(abs(t - 0.5) < 0.01)
    let added = PathEditing.insertAnchor(contour: 0, segment: 0, at: t, in: &path)
    precondition(added == PathAnchorRef(contour: 0, anchor: 1) && path.contours[0].anchors.count == 4)
    precondition(path.contours[0].anchors[1].point.distance(to: PathVector(50, 0)) < 0.6, "a split keeps the curve")
} else { preconditionFailure("a segment under the pointer is hit") }
PathEditing.dragOutHandles(PathAnchorRef(contour: 0, anchor: 3), to: PathVector(130, 100), in: &path)
let dragged = path.contours[0].anchors[3]
precondition(dragged.isSmooth && dragged.inHandle == PathVector(70, 100), "the Pen's drag mirrors the handles")
PathEditing.setHandle(PathAnchorRef(contour: 0, anchor: 3), outgoing: true, to: PathVector(100, 140), breaking: false, in: &path)
precondition(path.contours[0].anchors[3].inHandle.distance(to: PathVector(100, 70)) < 0.0001, "a smooth anchor keeps its handles in line")
PathEditing.setHandle(PathAnchorRef(contour: 0, anchor: 3), outgoing: true, to: PathVector(140, 140), breaking: true, in: &path)
precondition(!path.contours[0].anchors[3].isSmooth && path.contours[0].anchors[3].inHandle.distance(to: PathVector(100, 70)) < 0.0001)
PathEditing.moveContours([0], by: PathVector(10, 5), in: &path)
precondition(path.contours[0].anchors[0].point == PathVector(10, 5) && path.contours[0].anchors[3].outHandle == PathVector(150, 145))
PathEditing.delete([PathAnchorRef(contour: 0, anchor: 0), PathAnchorRef(contour: 0, anchor: 1)], in: &path)
precondition(path.contours[0].anchors.count == 2)
PathEditing.delete([PathAnchorRef(contour: 0, anchor: 0), PathAnchorRef(contour: 0, anchor: 1)], in: &path)
precondition(path.contours.isEmpty, "a contour with nothing left goes")
print("Portable path tests passed: hits, splits, handles, moves and deletes")

// Workspaces: the side panel's tab order, saved layouts and Reset Workspace.
var layout = WorkspaceLayout.standard
precondition(layout.tabOrder == [.layers, .channels, .paths] && layout.toolIconSize == .small && !layout.floatsTools)
layout.move(.paths, to: .layers)
precondition(layout.tabOrder == [.paths, .layers, .channels], "a dragged tab takes the place it's dropped on")
layout.move(.channels, by: -1)
precondition(layout.tabOrder == [.paths, .channels, .layers])
var broken = layout
broken.tabOrder = [.layers, .layers]
broken.sidePanelWidth = 9_000
broken.toolsFrame = PanelFrame(x: 0, y: 0, width: .nan, height: 10)
let fixed = broken.normalized()
precondition(fixed.tabOrder == [.layers, .channels, .paths] && fixed.sidePanelWidth == 352 && fixed.toolsFrame == nil)
var library = WorkspaceLibrary()
library.current = layout
precondition(library.save(as: "  Painting  ") && library.activeName == "Painting" && !library.save(as: "   "))
library.reset()
precondition(library.current == .standard && library.activeName == nil && library.saved.count == 1, "reset keeps saved workspaces")
precondition(library.choose("Painting") && library.current.tabOrder == [.paths, .channels, .layers])
let reread = WorkspaceLibrary.decoded(library.encoded())
precondition(reread == library, "a library survives being stored")
let newer = #"{"current":{"tabOrder":["history","paths","layers"],"toolIconSize":"large"},"saved":[]}"#.data(using: .utf8)!
precondition(WorkspaceLibrary.decoded(newer).current.tabOrder == [.paths, .layers, .channels], "unknown tabs are skipped, missing ones added")
precondition(WorkspaceLibrary.decoded(Data("garbage".utf8)) == WorkspaceLibrary())
print("Portable workspace tests passed: tab order, normalizing, save, choose, reset and storage")

// Dragging panels and tabs: generous drop targets.
precondition(WorkspaceDocking.insertionIndex(forX: 500, midpoints: [30, 90]) == 2, "anywhere past the last tab's middle is the end")
precondition(WorkspaceDocking.insertionIndex(forX: 10, midpoints: [30, 90]) == 0)
precondition(WorkspaceDocking.insertionIndex(forX: 60, midpoints: [30, 90]) == 1, "between two tabs, by their middles")
var order = WorkspaceLayout.standard
order.move(.layers, toIndex: 2)
precondition(order.tabOrder == [.channels, .paths, .layers])
precondition(WorkspaceDocking.toolsDock(atX: 10) && !WorkspaceDocking.toolsDock(atX: 30), "only right against the edge")
precondition(WorkspaceDocking.sidePanelDocks(right: 990, editorWidth: 1000) && !WorkspaceDocking.sidePanelDocks(right: 970, editorWidth: 1000))
let kept = WorkspaceDocking.clamped(PanelFrame(x: 5000, y: -50, width: 44, height: 600), editorWidth: 1000, height: 700)
precondition(kept.x == 960 && kept.y == 0, "a panel dragged off the editor stays within reach")
print("Portable docking tests passed: insertion points, snapping and keeping panels in reach")

// The Navigator minimap: the document fitted in its box, and the canvas centered on a picked pixel.
let navImage = NavigatorLayout.imageRect(documentWidth: 400, documentHeight: 200, boxWidth: 200, boxHeight: 200)
precondition(navImage == PlaneRect(x: 0, y: 50, width: 200, height: 100), "fitted to the longer side and centered")
precondition(NavigatorLayout.imageRect(documentWidth: 0, documentHeight: 10, boxWidth: 10, boxHeight: 10) == .zero)
precondition(NavigatorLayout.thumbnailRect(for: PlaneRect(x: 100, y: 0, width: 200, height: 100), documentWidth: 400, imageRect: navImage)
             == PlaneRect(x: 50, y: 50, width: 100, height: 50))
let picked = NavigatorLayout.documentPoint(x: 300, y: -20, documentWidth: 400, documentHeight: 200, imageRect: navImage)
precondition(picked.x == 400 && picked.y == 0, "held to the document's edges")
let pan = NavigatorLayout.centeredPan(onX: 100, y: 50, documentWidth: 400, documentHeight: 200, pointsPerPixel: 2)
precondition(pan.width == 200 && pan.height == 100)
print("Portable navigator tests passed: fitting, thumbnails, picking and centering")
