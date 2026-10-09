import Foundation

// Vector paths, as the Pen tool draws them and the Path Selection and Direct Selection tools edit them: contours of
// anchor points joined by cubic Bézier segments, in document pixels (top-left origin, y down).
//
// Platform-neutral on purpose: Foundation only, Doubles rather than Core Graphics types, so a Windows port can reuse
// the model, the editing rules and their tests unchanged. The Apple layer (CGPath, drawing) lives in
// Document/PathEditing.swift.

/// A point in document pixels.
nonisolated struct PathVector: Equatable, Hashable, Codable, Sendable {
    var x: Double
    var y: Double

    init(_ x: Double, _ y: Double) { self.x = x; self.y = y }
    static let zero = PathVector(0, 0)
    static func + (a: PathVector, b: PathVector) -> PathVector { PathVector(a.x + b.x, a.y + b.y) }
    static func - (a: PathVector, b: PathVector) -> PathVector { PathVector(a.x - b.x, a.y - b.y) }
    static func * (a: PathVector, s: Double) -> PathVector { PathVector(a.x * s, a.y * s) }
    var length: Double { (x * x + y * y).squareRoot() }
    func distance(to other: PathVector) -> Double { (self - other).length }
    /// The point mirrored through `center`: where a smooth anchor's other handle goes.
    func mirrored(around center: PathVector) -> PathVector { center * 2 - self }
}

/// One anchor of a contour, with the handles that shape the segments either side of it. A handle sitting on its
/// anchor means no handle: that side of the anchor is a straight line.
nonisolated struct PathAnchor: Equatable, Codable, Sendable {
    var point: PathVector
    /// Shapes the segment arriving at this anchor.
    var inHandle: PathVector
    /// Shapes the segment leaving it.
    var outHandle: PathVector
    /// Smooth anchors keep their two handles in line, so the curve passes through without a corner.
    var isSmooth: Bool

    init(_ point: PathVector, in inHandle: PathVector? = nil, out outHandle: PathVector? = nil, smooth: Bool = false) {
        self.point = point
        self.inHandle = inHandle ?? point
        self.outHandle = outHandle ?? point
        self.isSmooth = smooth
    }
    var hasInHandle: Bool { inHandle != point }
    var hasOutHandle: Bool { outHandle != point }

    /// The anchor moved by `delta`, its handles with it.
    func offset(by delta: PathVector) -> PathAnchor {
        var moved = self
        moved.point = point + delta
        moved.inHandle = inHandle + delta
        moved.outHandle = outHandle + delta
        return moved
    }
}

/// A run of anchors, open (a line with two ends) or closed (a loop).
nonisolated struct PathContour: Equatable, Codable, Sendable {
    var anchors: [PathAnchor] = []
    var isClosed = false

    /// The cubic segments, each from one anchor to the next (and back to the first when closed).
    var segments: [PathSegment] {
        guard anchors.count > 1 else { return [] }
        let count = isClosed ? anchors.count : anchors.count - 1
        return (0..<count).map { index in
            let from = anchors[index], to = anchors[(index + 1) % anchors.count]
            return PathSegment(start: from.point, control1: from.outHandle, control2: to.inHandle, end: to.point)
        }
    }
}

/// One cubic Bézier segment.
nonisolated struct PathSegment: Equatable, Sendable {
    var start: PathVector
    var control1: PathVector
    var control2: PathVector
    var end: PathVector

    func point(at t: Double) -> PathVector {
        let u = 1 - t
        return start * (u * u * u) + control1 * (3 * u * u * t) + control2 * (3 * u * t * t) + end * (t * t * t)
    }
    /// The two halves of the segment at `t` (de Casteljau), for adding an anchor without changing the curve.
    func split(at t: Double) -> (PathSegment, PathSegment) {
        let a = start + (control1 - start) * t, b = control1 + (control2 - control1) * t, c = control2 + (end - control2) * t
        let d = a + (b - a) * t, e = b + (c - b) * t
        let middle = d + (e - d) * t
        return (PathSegment(start: start, control1: a, control2: d, end: middle),
                PathSegment(start: middle, control1: e, control2: c, end: end))
    }
    /// The parameter and distance of the segment's point nearest `target`, found by sampling then refining.
    func nearest(to target: PathVector) -> (t: Double, distance: Double) {
        var best = (t: 0.0, distance: Double.infinity)
        let steps = 48
        for step in 0...steps {
            let t = Double(step) / Double(steps)
            let distance = point(at: t).distance(to: target)
            if distance < best.distance { best = (t, distance) }
        }
        var span = 1.0 / Double(steps)
        for _ in 0..<12 {
            for t in [best.t - span / 2, best.t + span / 2] where (0...1).contains(t) {
                let distance = point(at: t).distance(to: target)
                if distance < best.distance { best = (t, distance) }
            }
            span /= 2
        }
        return best
    }
    /// Points along the segment, close enough together that straight lines between them follow it within `tolerance`.
    func flattened(tolerance: Double) -> [PathVector] {
        let hull = start.distance(to: control1) + control1.distance(to: control2) + control2.distance(to: end)
        let steps = max(1, min(256, Int((hull / max(tolerance, 0.01)).squareRoot() * 2)))
        return (1...steps).map { point(at: Double($0) / Double(steps)) }
    }
}

/// A named path in the Paths panel: one or more contours.
nonisolated struct VectorPath: Identifiable, Equatable, Codable, Sendable {
    var id = UUID()
    var name: String
    var contours: [PathContour] = []

    var isEmpty: Bool { contours.allSatisfy { $0.anchors.isEmpty } }
    /// The smallest box holding every anchor and handle, or nil for an empty path.
    var bounds: (min: PathVector, max: PathVector)? {
        let points = contours.flatMap { $0.anchors.flatMap { [$0.point, $0.inHandle, $0.outHandle] } }
        guard let first = points.first else { return nil }
        return points.reduce((first, first)) { box, p in
            (PathVector(Swift.min(box.0.x, p.x), Swift.min(box.0.y, p.y)), PathVector(Swift.max(box.1.x, p.x), Swift.max(box.1.y, p.y)))
        }
    }
}

/// Which anchor of which contour.
nonisolated struct PathAnchorRef: Hashable, Sendable {
    var contour: Int
    var anchor: Int
}

/// What a click landed on.
nonisolated enum PathHit: Equatable, Sendable {
    case anchor(PathAnchorRef)
    case inHandle(PathAnchorRef)
    case outHandle(PathAnchorRef)
    /// On segment `index` of `contour`, at parameter `t`.
    case segment(contour: Int, index: Int, t: Double)

    var contour: Int {
        switch self {
        case .anchor(let ref), .inHandle(let ref), .outHandle(let ref): ref.contour
        case .segment(let contour, _, _): contour
        }
    }
}

/// The editing rules the path tools share, as pure functions of a path.
nonisolated enum PathEditing {
    /// What lies under `point` within `tolerance` (document pixels). Handles count only for the anchors in
    /// `showingHandles`, the ones whose handles are on screen; anchors win over handles, handles over segments.
    static func hitTest(_ path: VectorPath, at point: PathVector, tolerance: Double,
                        showingHandles: Set<PathAnchorRef> = []) -> PathHit? {
        var best: (hit: PathHit, distance: Double)?
        func consider(_ hit: PathHit, _ distance: Double) {
            if distance <= tolerance, distance < (best?.distance ?? .infinity) { best = (hit, distance) }
        }
        for (c, contour) in path.contours.enumerated() {
            for (a, anchor) in contour.anchors.enumerated() { consider(.anchor(PathAnchorRef(contour: c, anchor: a)), anchor.point.distance(to: point)) }
        }
        if let best { return best.hit }
        for ref in showingHandles where path.contours.indices.contains(ref.contour)
            && path.contours[ref.contour].anchors.indices.contains(ref.anchor) {
            let anchor = path.contours[ref.contour].anchors[ref.anchor]
            if anchor.hasInHandle { consider(.inHandle(ref), anchor.inHandle.distance(to: point)) }
            if anchor.hasOutHandle { consider(.outHandle(ref), anchor.outHandle.distance(to: point)) }
        }
        if let best { return best.hit }
        for (c, contour) in path.contours.enumerated() {
            for (s, segment) in contour.segments.enumerated() {
                let nearest = segment.nearest(to: point)
                consider(.segment(contour: c, index: s, t: nearest.t), nearest.distance)
            }
        }
        return best?.hit
    }

    /// Moves the given anchors (with their handles) by `delta`.
    static func move(_ refs: Set<PathAnchorRef>, by delta: PathVector, in path: inout VectorPath) {
        for ref in refs where valid(ref, in: path) {
            path.contours[ref.contour].anchors[ref.anchor] = path.contours[ref.contour].anchors[ref.anchor].offset(by: delta)
        }
    }

    /// Moves whole contours by `delta`.
    static func moveContours(_ contours: Set<Int>, by delta: PathVector, in path: inout VectorPath) {
        for c in contours where path.contours.indices.contains(c) {
            path.contours[c].anchors = path.contours[c].anchors.map { $0.offset(by: delta) }
        }
    }

    /// Puts one handle at `position`. On a smooth anchor the other handle turns to stay in line, keeping its own
    /// length, unless `breaking` (Option-drag), which makes the anchor a corner instead.
    static func setHandle(_ ref: PathAnchorRef, outgoing: Bool, to position: PathVector, breaking: Bool, in path: inout VectorPath) {
        guard valid(ref, in: path) else { return }
        var anchor = path.contours[ref.contour].anchors[ref.anchor]
        if outgoing { anchor.outHandle = position } else { anchor.inHandle = position }
        if breaking { anchor.isSmooth = false }
        if anchor.isSmooth {
            let moved = position - anchor.point
            let length = moved.length
            if length > 0 {
                let other = outgoing ? anchor.inHandle : anchor.outHandle
                let keep = other.distance(to: anchor.point)
                let opposite = anchor.point - moved * ((keep > 0 ? keep : length) / length)
                if outgoing { anchor.inHandle = opposite } else { anchor.outHandle = opposite }
            }
        }
        path.contours[ref.contour].anchors[ref.anchor] = anchor
    }

    /// The Pen's drag after placing an anchor: the outgoing handle follows the pointer and the incoming one mirrors
    /// it, making a smooth anchor; a drag back onto the anchor leaves a corner.
    static func dragOutHandles(_ ref: PathAnchorRef, to position: PathVector, in path: inout VectorPath) {
        guard valid(ref, in: path) else { return }
        var anchor = path.contours[ref.contour].anchors[ref.anchor]
        anchor.outHandle = position
        anchor.inHandle = position.mirrored(around: anchor.point)
        anchor.isSmooth = anchor.hasOutHandle
        path.contours[ref.contour].anchors[ref.anchor] = anchor
    }

    /// Adds an anchor on segment `index` at `t` without changing the curve's shape.
    @discardableResult
    static func insertAnchor(contour c: Int, segment index: Int, at t: Double, in path: inout VectorPath) -> PathAnchorRef? {
        guard path.contours.indices.contains(c) else { return nil }
        let segments = path.contours[c].segments
        guard segments.indices.contains(index) else { return nil }
        let (first, second) = segments[index].split(at: min(max(t, 0.001), 0.999))
        let count = path.contours[c].anchors.count
        let next = (index + 1) % count
        path.contours[c].anchors[index].outHandle = first.control1
        path.contours[c].anchors[next].inHandle = second.control2
        let added = PathAnchor(first.end, in: first.control2, out: second.control1, smooth: true)
        path.contours[c].anchors.insert(added, at: index + 1)
        return PathAnchorRef(contour: c, anchor: index + 1)
    }

    /// Removes anchors. A contour left with nothing goes; an open one keeps what's left, a closed one with a single
    /// anchor opens.
    static func delete(_ refs: Set<PathAnchorRef>, in path: inout VectorPath) {
        for c in Set(refs.map(\.contour)).sorted(by: >) where path.contours.indices.contains(c) {
            let doomed = Set(refs.filter { $0.contour == c }.map(\.anchor))
            path.contours[c].anchors = path.contours[c].anchors.enumerated().filter { !doomed.contains($0.offset) }.map(\.element)
            if path.contours[c].anchors.isEmpty { path.contours.remove(at: c) }
            else if path.contours[c].anchors.count < 2 { path.contours[c].isClosed = false }
        }
    }

    /// Turns a smooth anchor into a corner with no handles, or a corner into a smooth one with handles along the
    /// line through its neighbors, as the Convert Point gesture (Option-click with the Pen) does.
    static func convert(_ ref: PathAnchorRef, in path: inout VectorPath) {
        guard valid(ref, in: path) else { return }
        let contour = path.contours[ref.contour]
        var anchor = contour.anchors[ref.anchor]
        if anchor.isSmooth || anchor.hasInHandle || anchor.hasOutHandle {
            anchor.inHandle = anchor.point
            anchor.outHandle = anchor.point
            anchor.isSmooth = false
        } else {
            let count = contour.anchors.count
            let hasPrevious = contour.isClosed || ref.anchor > 0, hasNext = contour.isClosed || ref.anchor < count - 1
            let previous = hasPrevious ? contour.anchors[(ref.anchor - 1 + count) % count].point : anchor.point
            let next = hasNext ? contour.anchors[(ref.anchor + 1) % count].point : anchor.point
            let direction = next - previous
            guard direction.length > 0 else { return }
            let reach = min(previous.distance(to: anchor.point), next.distance(to: anchor.point)) / 3
            let unit = direction * (1 / direction.length)
            anchor.outHandle = anchor.point + unit * reach
            anchor.inHandle = anchor.point - unit * reach
            anchor.isSmooth = true
        }
        path.contours[ref.contour].anchors[ref.anchor] = anchor
    }

    /// Every contour as straight-line points, for filling into a selection or testing containment.
    static func polygons(_ path: VectorPath, tolerance: Double = 0.25) -> [[PathVector]] {
        path.contours.compactMap { contour in
            guard let first = contour.anchors.first else { return nil }
            return [first.point] + contour.segments.flatMap { $0.flattened(tolerance: tolerance) }
        }
    }

    /// The anchors whose points lie inside the box between `a` and `b`, for the Direct Selection tool's marquee.
    static func anchors(in path: VectorPath, between a: PathVector, and b: PathVector) -> Set<PathAnchorRef> {
        let minX = min(a.x, b.x), maxX = max(a.x, b.x), minY = min(a.y, b.y), maxY = max(a.y, b.y)
        var result = Set<PathAnchorRef>()
        for (c, contour) in path.contours.enumerated() {
            for (i, anchor) in contour.anchors.enumerated()
            where (minX...maxX).contains(anchor.point.x) && (minY...maxY).contains(anchor.point.y) {
                result.insert(PathAnchorRef(contour: c, anchor: i))
            }
        }
        return result
    }

    /// Every anchor of the given contours.
    static func allAnchors(of contours: Set<Int>, in path: VectorPath) -> Set<PathAnchorRef> {
        Set(contours.filter { path.contours.indices.contains($0) }.flatMap { c in
            path.contours[c].anchors.indices.map { PathAnchorRef(contour: c, anchor: $0) }
        })
    }

    /// The next unused "Path N" name.
    static func nextName(after paths: [VectorPath], base: String) -> String {
        let used = Set(paths.map(\.name))
        var n = paths.count + 1
        while used.contains("\(base) \(n)") { n += 1 }
        return "\(base) \(n)"
    }

    private static func valid(_ ref: PathAnchorRef, in path: VectorPath) -> Bool {
        path.contours.indices.contains(ref.contour) && path.contours[ref.contour].anchors.indices.contains(ref.anchor)
    }
}

/// An affine map of document points, for carrying paths through Image Size, Canvas Size, Crop, Rotate and Flip.
nonisolated struct PathAffine: Equatable, Sendable {
    var a = 1.0, b = 0.0, c = 0.0, d = 1.0, tx = 0.0, ty = 0.0

    static func scale(_ sx: Double, _ sy: Double) -> PathAffine { PathAffine(a: sx, d: sy) }
    static func offset(_ dx: Double, _ dy: Double) -> PathAffine { PathAffine(tx: dx, ty: dy) }
    func apply(_ p: PathVector) -> PathVector { PathVector(a * p.x + c * p.y + tx, b * p.x + d * p.y + ty) }
}

extension VectorPath {
    /// The path with every anchor and handle mapped through `map`.
    func transformed(_ map: PathAffine) -> VectorPath {
        var copy = self
        copy.contours = contours.map { contour in
            var moved = contour
            moved.anchors = contour.anchors.map { anchor in
                var mapped = anchor
                mapped.point = map.apply(anchor.point)
                mapped.inHandle = map.apply(anchor.inHandle)
                mapped.outHandle = map.apply(anchor.outHandle)
                return mapped
            }
            return moved
        }
        return copy
    }

    /// Whether every coordinate is a finite number within `limit`, as a saved path must be.
    func isWellFormed(limit: Double = 1_000_000) -> Bool {
        contours.allSatisfy { $0.anchors.allSatisfy { anchor in
            [anchor.point, anchor.inHandle, anchor.outHandle].allSatisfy { $0.x.isFinite && $0.y.isFinite && abs($0.x) <= limit && abs($0.y) <= limit }
        } }
    }
}
