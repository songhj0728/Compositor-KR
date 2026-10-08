import Foundation
import CoreGraphics

// MARK: - Platform-neutral session state
//
// The kinds and gesture records the path tools keep. The geometry they act on is in Core/VectorPath.swift.

/// The two path selection tools, as Photoshop has them on A: whole contours, or single anchors and handles.
nonisolated enum PathSelectionKind: String, CaseIterable, Sendable {
    case path, direct
}

/// The open contour the Pen is adding anchors to.
nonisolated struct PenDraft: Equatable, Sendable {
    var pathID: UUID
    var contour: Int
}

/// What a drag with a path tool is doing, measured from where it began so it never drifts.
nonisolated struct PathDrag: Sendable {
    enum Kind: Sendable {
        /// The Pen's drag after placing (or closing on) an anchor: pulls out its handles.
        case penHandles(PathAnchorRef)
        case moveAnchors(Set<PathAnchorRef>)
        case moveContours(Set<Int>)
        case handle(PathAnchorRef, outgoing: Bool, breaking: Bool)
        /// Direct Selection's box around anchors, from `start` to the pointer.
        case marquee(adding: Set<PathAnchorRef>)
    }
    var kind: Kind
    var start: PathVector
    var current: PathVector
    /// The path as the drag found it.
    var original: VectorPath
}

/// The side panel's pages.
nonisolated enum SidePanelTab: String, CaseIterable, Sendable {
    case layers, paths, channels
}

/// What the canvas shows of the color: everything, or one channel alone in gray, as Photoshop's Channels panel does.
nonisolated enum ColorChannelView: String, CaseIterable, Sendable {
    case composite, red, green, blue
    /// The byte offset of this channel in an RGBA pixel; nil for the composite.
    var offset: Int? {
        switch self {
        case .composite: nil
        case .red: 0
        case .green: 1
        case .blue: 2
        }
    }
}

// MARK: - Apple platform layer

extension PathVector {
    init(_ point: CGPoint) { self.init(Double(point.x), Double(point.y)) }
    var cgPoint: CGPoint { CGPoint(x: x, y: y) }
}

extension VectorPath {
    /// The path as Core Graphics draws and fills it.
    var cgPath: CGPath {
        let result = CGMutablePath()
        for contour in contours {
            guard let first = contour.anchors.first else { continue }
            result.move(to: first.point.cgPoint)
            for segment in contour.segments {
                result.addCurve(to: segment.end.cgPoint, control1: segment.control1.cgPoint, control2: segment.control2.cgPoint)
            }
            if contour.isClosed { result.closeSubpath() }
        }
        return result
    }

    /// A path following a Core Graphics path, as Make Work Path does with a selection's outline. Lines become corner
    /// anchors and curves keep their handles.
    init(name: String, cgPath: CGPath) {
        var contours: [PathContour] = []
        var current = PathContour()
        func finish(closed: Bool) {
            if closed, current.anchors.count > 1, let first = current.anchors.first, let last = current.anchors.last,
               first.point.distance(to: last.point) < 0.0001 {
                // A closing segment that lands back on the start: fold its last anchor into the first.
                current.anchors[0].inHandle = last.inHandle
                current.anchors.removeLast()
            }
            current.isClosed = closed && current.anchors.count > 1
            if !current.anchors.isEmpty { contours.append(current) }
            current = PathContour()
        }
        cgPath.applyWithBlock { element in
            let points = element.pointee.points
            switch element.pointee.type {
            case .moveToPoint:
                finish(closed: false)
                current.anchors.append(PathAnchor(PathVector(points[0])))
            case .addLineToPoint:
                current.anchors.append(PathAnchor(PathVector(points[0])))
            case .addQuadCurveToPoint:
                guard let last = current.anchors.last?.point else { break }
                let control = PathVector(points[0]), end = PathVector(points[1])
                current.anchors[current.anchors.count - 1].outHandle = last + (control - last) * (2.0 / 3)
                current.anchors.append(PathAnchor(end, in: end + (control - end) * (2.0 / 3)))
            case .addCurveToPoint:
                guard !current.anchors.isEmpty else { break }
                current.anchors[current.anchors.count - 1].outHandle = PathVector(points[0])
                current.anchors.append(PathAnchor(PathVector(points[2]), in: PathVector(points[1])))
            case .closeSubpath:
                finish(closed: true)
            @unknown default: break
            }
        }
        finish(closed: false)
        self.init(name: name, contours: contours)
    }
}

extension EditorSession {
    static let pathBaseName = String(localized: "Path")

    var paths: [VectorPath] { document?.paths ?? [] }
    var activePathIndex: Int? { document?.paths.firstIndex { $0.id == activePathID } }
    var activePath: VectorPath? { activePathIndex.map { paths[$0] } }
    var canEditPaths: Bool { document != nil && !isProjectBusy && !isImporting && textDraft == nil }
    var isPathTool: Bool { tool == .pen || tool == .pathSelection }
    /// Whether the canvas should outline the active path: while a path tool is in hand or the Paths panel is up.
    var showsActivePath: Bool { activePath != nil && (isPathTool || sidePanelTab == .paths) }

    /// The anchors whose handles are on screen: the selected ones, and the Pen's newest one.
    var pathAnchorsShowingHandles: Set<PathAnchorRef> {
        var shown = tool == .pathSelection && pathSelectionKind == .direct ? selectedPathAnchors : []
        if let draft = penDraft, draft.pathID == activePathID, let path = activePath, path.contours.indices.contains(draft.contour),
           !path.contours[draft.contour].anchors.isEmpty {
            shown.insert(PathAnchorRef(contour: draft.contour, anchor: path.contours[draft.contour].anchors.count - 1))
        }
        if case .penHandles(let ref)? = pathDrag?.kind { shown.insert(ref) }
        return shown
    }

    // MARK: Paths panel

    /// A new empty path, made active; the Pen fills it.
    @discardableResult
    func newPath() -> UUID? {
        guard canEditPaths, let document else { return nil }
        let path = VectorPath(name: PathEditing.nextName(after: document.paths, base: Self.pathBaseName))
        beginEdit("New Path")
        self.document?.paths.append(path)
        endEdit()
        selectPath(path.id)
        return path.id
    }

    func selectPath(_ id: UUID?) {
        activePathID = id
        selectedPathAnchors = []
        selectedPathContours = []
        if penDraft?.pathID != id { penDraft = nil }
    }

    func deletePath(_ id: UUID) {
        guard canEditPaths, let index = document?.paths.firstIndex(where: { $0.id == id }) else { return }
        beginEdit("Delete Path")
        document?.paths.remove(at: index)
        endEdit()
        if activePathID == id { selectPath(nil) }
    }

    func renamePath(_ id: UUID, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard canEditPaths, !trimmed.isEmpty, let index = document?.paths.firstIndex(where: { $0.id == id }),
              document?.paths[index].name != trimmed else { return }
        beginEdit("Rename Path")
        document?.paths[index].name = trimmed
        endEdit()
    }

    func duplicatePath(_ id: UUID) {
        guard canEditPaths, let document, let source = document.paths.first(where: { $0.id == id }) else { return }
        var copy = source
        copy.id = UUID()
        copy.name = String(localized: "\(source.name) copy")
        beginEdit("Duplicate Path")
        self.document?.paths.insert(copy, at: (document.paths.firstIndex { $0.id == id } ?? document.paths.count - 1) + 1)
        endEdit()
        selectPath(copy.id)
    }

    /// Load Path as Selection (⌘-click a path in Photoshop): its closed shape, filled with the nonzero rule.
    func loadPathAsSelection(_ id: UUID? = nil, mode: SelectionMode = .replace) {
        guard let path = paths.first(where: { $0.id == (id ?? activePathID) }), !path.isEmpty else { return }
        applySelection(path.cgPath, mode: mode, name: "Load Path as Selection")
    }

    var canMakePathFromSelection: Bool { canEditPaths && selection?.isEmpty == false }

    /// Make Work Path: the selection's outline as a new path.
    func makePathFromSelection() {
        guard canMakePathFromSelection, let selection, let document else { return }
        let path = VectorPath(name: PathEditing.nextName(after: document.paths, base: Self.pathBaseName), cgPath: selection.path)
        guard !path.isEmpty else { return }
        beginEdit("Make Path from Selection")
        self.document?.paths.append(path)
        endEdit()
        selectPath(path.id)
    }

    /// Fill Path: the foreground color inside the path, on the active layer, leaving the selection as it was.
    func fillPath(_ id: UUID? = nil) async {
        guard let path = paths.first(where: { $0.id == (id ?? activePathID) }), !path.isEmpty, canEditPixels, let document else { return }
        let kept = document.selection
        beginEdit("Fill Path")
        self.document?.selection = DocumentSelection(path: path.cgPath.intersection(CGPath(rect: CGRect(origin: .zero, size: document.size), transform: nil),
                                                                                    using: .winding),
                                                     antialiased: true)
        await fillSelection(with: .foreground)
        self.document?.selection = kept
        endEdit()
    }

    // MARK: Pen

    /// A press with the Pen at `point` (document pixels). Clicking the open contour's first anchor closes it; on the
    /// active path an anchor is deleted (Option converts it instead) and a segment gains an anchor; anywhere else a
    /// new anchor goes on the end of the open contour, or starts a new one.
    func penPress(at point: CGPoint, tolerance: CGFloat, option: Bool, shift: Bool) {
        guard canEditPaths else { return }
        var target = PathVector(point)
        beginEdit("Pen")
        if activePathIndex == nil {
            let path = VectorPath(name: PathEditing.nextName(after: paths, base: Self.pathBaseName))
            document?.paths.append(path)
            activePathID = path.id
        }
        guard let index = activePathIndex, var path = document?.paths[index] else { endEdit(); return }
        let draft = penDraft.flatMap { $0.pathID == path.id && path.contours.indices.contains($0.contour) ? $0 : nil }
        let hit = PathEditing.hitTest(path, at: target, tolerance: Double(tolerance), showingHandles: pathAnchorsShowingHandles)
        if let draft, case .anchor(let ref)? = hit, ref.contour == draft.contour, ref.anchor == 0,
           path.contours[draft.contour].anchors.count > 1 {
            // Close the contour; dragging on now shapes the first anchor.
            path.contours[draft.contour].isClosed = true
            document?.paths[index] = path
            penDraft = nil
            pathDrag = PathDrag(kind: .penHandles(ref), start: target, current: target, original: path)
            return
        }
        let newest = draft.map { PathAnchorRef(contour: $0.contour, anchor: path.contours[$0.contour].anchors.count - 1) }
        if case .anchor(let ref)? = hit, ref == newest {
            // The anchor just placed: dragging reshapes its handles again.
            pathDrag = PathDrag(kind: .penHandles(ref), start: target, current: target, original: path)
            return
        }
        if case .anchor(let ref)? = hit {
            if option { PathEditing.convert(ref, in: &path) }
            else {
                PathEditing.delete([ref], in: &path)
                // Deleting from the open contour leaves it open on its new last anchor, or ends it if it went.
                if let draft, draft.contour == ref.contour,
                   !path.contours.indices.contains(draft.contour) || path.contours.count < (document?.paths[index].contours.count ?? 0) {
                    penDraft = nil
                }
            }
            document?.paths[index] = path
            selectedPathAnchors = []
            endEdit()
            return
        }
        if case .segment(let c, let s, let t)? = hit, !option {
            if let added = PathEditing.insertAnchor(contour: c, segment: s, at: t, in: &path) {
                document?.paths[index] = path
                pathDrag = PathDrag(kind: .moveAnchors([added]), start: target, current: target, original: path)
            } else { endEdit() }
            return
        }
        // A new anchor: on the end of the open contour, or the start of a new one.
        let contour: Int
        if let draft {
            contour = draft.contour
            if shift, let last = path.contours[contour].anchors.last?.point { target = Self.constrained(target, from: last) }
            path.contours[contour].anchors.append(PathAnchor(target))
        } else {
            path.contours.append(PathContour(anchors: [PathAnchor(target)]))
            contour = path.contours.count - 1
        }
        document?.paths[index] = path
        penDraft = PenDraft(pathID: path.id, contour: contour)
        let ref = PathAnchorRef(contour: contour, anchor: path.contours[contour].anchors.count - 1)
        pathDrag = PathDrag(kind: .penHandles(ref), start: target, current: target, original: path)
    }

    // MARK: Path Selection and Direct Selection

    /// A press with Path Selection or Direct Selection. Shift adds to what's picked; with Direct Selection, Option on a
    /// handle breaks a smooth anchor into a corner. A press on nothing starts a box (Direct) or clears the pick.
    func pathSelectionPress(at point: CGPoint, tolerance: CGFloat, shift: Bool, option: Bool) {
        guard canEditPaths else { return }
        let target = PathVector(point)
        // The active path first, then the others top to bottom, as they're listed.
        let order = (activePathIndex.map { [$0] } ?? []) + paths.indices.reversed().filter { $0 != activePathIndex }
        var found: (index: Int, hit: PathHit)?
        for index in order {
            let showing = index == activePathIndex ? pathAnchorsShowingHandles : []
            if let hit = PathEditing.hitTest(paths[index], at: target, tolerance: Double(tolerance), showingHandles: showing) {
                found = (index, hit)
                break
            }
            // Path Selection also picks a closed contour by clicking inside it.
            if pathSelectionKind == .path, let inside = Self.contour(containing: target, in: paths[index]) {
                found = (index, .segment(contour: inside, index: 0, t: 0))
                break
            }
        }
        guard let found else {
            if !shift { selectedPathAnchors = []; selectedPathContours = [] }
            if pathSelectionKind == .direct, let path = activePath {
                beginEdit("Move Anchor Points")
                pathDrag = PathDrag(kind: .marquee(adding: shift ? selectedPathAnchors : []), start: target, current: target, original: path)
            }
            return
        }
        if paths[found.index].id != activePathID { selectPath(paths[found.index].id) }
        let path = paths[found.index]
        // Every case below starts a drag, which `pathDragEnded` closes.
        beginEdit(pathSelectionKind == .path ? "Move Path" : "Move Anchor Points")
        switch pathSelectionKind {
        case .path:
            let contour = found.hit.contour
            if shift { selectedPathContours.formSymmetricDifference([contour]) }
            else if !selectedPathContours.contains(contour) { selectedPathContours = [contour] }
            pathDrag = PathDrag(kind: .moveContours(selectedPathContours), start: target, current: target, original: path)
        case .direct:
            switch found.hit {
            case .anchor(let ref):
                if shift { selectedPathAnchors.formSymmetricDifference([ref]) }
                else if !selectedPathAnchors.contains(ref) { selectedPathAnchors = [ref] }
                pathDrag = PathDrag(kind: .moveAnchors(selectedPathAnchors), start: target, current: target, original: path)
            case .inHandle(let ref), .outHandle(let ref):
                let outgoing = if case .outHandle = found.hit { true } else { false }
                pathDrag = PathDrag(kind: .handle(ref, outgoing: outgoing, breaking: option), start: target, current: target, original: path)
            case .segment(let c, let s, _):
                let count = path.contours[c].anchors.count
                let ends: Set<PathAnchorRef> = [PathAnchorRef(contour: c, anchor: s), PathAnchorRef(contour: c, anchor: (s + 1) % count)]
                selectedPathAnchors = shift ? selectedPathAnchors.union(ends) : ends
                pathDrag = PathDrag(kind: .moveAnchors(selectedPathAnchors), start: target, current: target, original: path)
            }
        }
    }

    // MARK: Shared drag

    /// The pointer moved with the button down, for either path tool. Shift keeps a move to 45° steps.
    func pathDragMoved(to point: CGPoint, shift: Bool) {
        guard var drag = pathDrag, let index = document?.paths.firstIndex(where: { $0.id == drag.original.id }) else { return }
        var target = PathVector(point)
        var path = drag.original
        switch drag.kind {
        case .penHandles(let ref):
            if shift { target = Self.constrained(target, from: path.contours[ref.contour].anchors[ref.anchor].point) }
            PathEditing.dragOutHandles(ref, to: target, in: &path)
        case .moveAnchors(let refs):
            if shift { target = Self.constrained(target, from: drag.start) }
            PathEditing.move(refs, by: target - drag.start, in: &path)
        case .moveContours(let contours):
            if shift { target = Self.constrained(target, from: drag.start) }
            PathEditing.moveContours(contours, by: target - drag.start, in: &path)
        case .handle(let ref, let outgoing, let breaking):
            if shift { target = Self.constrained(target, from: path.contours[ref.contour].anchors[ref.anchor].point) }
            PathEditing.setHandle(ref, outgoing: outgoing, to: target, breaking: breaking, in: &path)
        case .marquee(let adding):
            selectedPathAnchors = adding.union(PathEditing.anchors(in: path, between: drag.start, and: target))
        }
        drag.current = target
        pathDrag = drag
        if document?.paths[index] != path { document?.paths[index] = path }
    }

    /// The button came up: the gesture is one undo step. Only a press that left a drag going kept its edit open.
    func pathDragEnded() {
        guard pathDrag != nil else { return }
        pathDrag = nil
        endEdit()
    }

    /// Return or Escape with the Pen: the open contour stays as it is, and the next click starts another.
    func finishPenContour() {
        penDraft = nil
    }

    /// Delete with a path tool: the picked anchors (Direct) or contours (Path), or the open contour's newest anchor
    /// with the Pen. False when there was nothing of a path to delete, so the key does what it does elsewhere.
    func deleteSelectedPathParts() -> Bool {
        guard isPathTool, canEditPaths, let index = activePathIndex, var path = document?.paths[index] else { return false }
        if tool == .pen, let draft = penDraft, path.contours.indices.contains(draft.contour), let last = path.contours[draft.contour].anchors.indices.last {
            PathEditing.delete([PathAnchorRef(contour: draft.contour, anchor: last)], in: &path)
            if !path.contours.indices.contains(draft.contour) || path.contours[draft.contour].anchors.isEmpty { penDraft = nil }
        } else if pathSelectionKind == .direct, !selectedPathAnchors.isEmpty {
            PathEditing.delete(selectedPathAnchors, in: &path)
            selectedPathAnchors = []
        } else if pathSelectionKind == .path, !selectedPathContours.isEmpty {
            for contour in selectedPathContours.sorted(by: >) where path.contours.indices.contains(contour) { path.contours.remove(at: contour) }
            selectedPathContours = []
        } else { return false }
        beginEdit("Delete Anchor Points")
        document?.paths[index] = path
        endEdit()
        return true
    }

    /// Arrow keys with a path selection tool: the picked anchors or contours move a pixel (ten with Shift).
    func nudgePathSelection(dx: CGFloat, dy: CGFloat) -> Bool {
        guard tool == .pathSelection, canEditPaths, let index = activePathIndex, var path = document?.paths[index] else { return false }
        let delta = PathVector(Double(dx), Double(dy))
        switch pathSelectionKind {
        case .direct:
            guard !selectedPathAnchors.isEmpty else { return false }
            PathEditing.move(selectedPathAnchors, by: delta, in: &path)
        case .path:
            guard !selectedPathContours.isEmpty else { return false }
            PathEditing.moveContours(selectedPathContours, by: delta, in: &path)
        }
        beginEdit("Nudge Path")
        document?.paths[index] = path
        endEdit()
        return true
    }

    /// Switching tools starts the pick afresh: Direct Selection shows the anchors with none picked, as Photoshop does.
    func togglePathSelectionKind() {
        pathSelectionKind = pathSelectionKind == .path ? .direct : .path
        selectedPathAnchors = []
        selectedPathContours = []
    }

    /// Shift-A: the path selection tools, switching between them on each press as Photoshop does.
    func pressPathSelectionKey() {
        if tool == .pathSelection { togglePathSelectionKind() } else { selectTool(.pathSelection) }
    }

    /// `point` moved onto the nearest 45° line through `origin`.
    static func constrained(_ point: PathVector, from origin: PathVector) -> PathVector {
        let delta = point - origin
        let length = delta.length
        guard length > 0 else { return point }
        let step = Double.pi / 4
        let angle = (atan2(delta.y, delta.x) / step).rounded() * step
        return origin + PathVector(cos(angle), sin(angle)) * length
    }

    /// The closed contour of `path` that holds `point`, topmost first.
    private static func contour(containing point: PathVector, in path: VectorPath) -> Int? {
        for (index, contour) in path.contours.enumerated().reversed() where contour.isClosed {
            if VectorPath(name: "", contours: [contour]).cgPath.contains(point.cgPoint, using: .winding) { return index }
        }
        return nil
    }
}
