import CoreModel

// The C functions declared in Spikes/CoreModel/include/compositor_core.h. Everything a non-Swift UI can reach goes through here:
// handles are retained Swift objects, strings are UTF-8, and no Swift error or type crosses the boundary.

final class HistoryBox {
    var history: History
    init(_ history: History) { self.history = history }
}

private func box(_ handle: OpaquePointer?) -> HistoryBox? {
    handle.map { Unmanaged<HistoryBox>.fromOpaque(UnsafeRawPointer($0)).takeUnretainedValue() }
}

private func string(_ pointer: UnsafePointer<CChar>?) -> String {
    pointer.map { String(cString: $0) } ?? ""
}

private func parent(_ id: UInt64) -> LayerID? { id == 0 ? nil : LayerID(id) }

/// Copies `text` into a C buffer, cut at a character boundary to fit. Returns the full length in UTF-8 bytes.
private func copy(_ text: String, to buffer: UnsafeMutablePointer<CChar>?, capacity: Int) -> Int {
    let bytes = Array(text.utf8)
    guard let buffer, capacity > 0 else { return bytes.count }
    var count = min(bytes.count, capacity - 1)
    // Don't end partway through a multi-byte character (Korean names are three bytes a character).
    while count > 0, count < bytes.count, bytes[count] & 0xC0 == 0x80 { count -= 1 }
    for i in 0..<count { buffer[i] = CChar(bitPattern: bytes[i]) }
    buffer[count] = 0
    return bytes.count
}

@_cdecl("cc_history_create")
public func cc_history_create(_ width: Int32, _ height: Int32) -> OpaquePointer? {
    let history = History(Document(width: Int(width), height: Int(height)))
    return OpaquePointer(Unmanaged.passRetained(HistoryBox(history)).toOpaque())
}

@_cdecl("cc_history_destroy")
public func cc_history_destroy(_ handle: OpaquePointer?) {
    guard let handle else { return }
    Unmanaged<HistoryBox>.fromOpaque(UnsafeRawPointer(handle)).release()
}

@_cdecl("cc_add_layer")
public func cc_add_layer(_ handle: OpaquePointer?, _ name: UnsafePointer<CChar>?, _ parentID: UInt64) -> UInt64 {
    guard let box = box(handle) else { return 0 }
    let name = string(name)
    return (try? box.history.perform("Add Layer") { try $0.addLayer(named: name, in: parent(parentID)) })?.rawValue ?? 0
}

@_cdecl("cc_add_group")
public func cc_add_group(_ handle: OpaquePointer?, _ name: UnsafePointer<CChar>?, _ parentID: UInt64) -> UInt64 {
    guard let box = box(handle) else { return 0 }
    let name = string(name)
    return (try? box.history.perform("Add Group") { try $0.addGroup(named: name, in: parent(parentID)) })?.rawValue ?? 0
}

@_cdecl("cc_group")
public func cc_group(_ handle: OpaquePointer?, _ ids: UnsafePointer<UInt64>?, _ count: Int,
                     _ name: UnsafePointer<CChar>?) -> UInt64 {
    guard let box = box(handle), let ids, count > 0 else { return 0 }
    let members = UnsafeBufferPointer(start: ids, count: count).map(LayerID.init)
    let name = string(name)
    return (try? box.history.perform("Group Layers") { try $0.group(members, named: name) })?.rawValue ?? 0
}

@_cdecl("cc_set_visible")
public func cc_set_visible(_ handle: OpaquePointer?, _ id: UInt64, _ visible: Int32) -> Int32 {
    guard let box = box(handle) else { return 0 }
    let layer = LayerID(id), isVisible = visible != 0
    let done: ()? = try? box.history.perform(isVisible ? "Show Layer" : "Hide Layer") { document in
        switch document.node(layer) {
        case .layer?: try document.updateLayer(layer) { $0.isVisible = isVisible }
        case .group?: try document.updateGroup(layer) { $0.isVisible = isVisible }
        case nil: throw DocumentError.noSuchLayer(layer)
        }
    }
    return done == nil ? 0 : 1
}

@_cdecl("cc_rename")
public func cc_rename(_ handle: OpaquePointer?, _ id: UInt64, _ name: UnsafePointer<CChar>?) -> Int32 {
    guard let box = box(handle) else { return 0 }
    let layer = LayerID(id), name = string(name)
    let done: ()? = try? box.history.perform("Rename Layer") { document in
        switch document.node(layer) {
        case .layer?: try document.updateLayer(layer) { $0.name = name }
        case .group?: try document.updateGroup(layer) { $0.name = name }
        case nil: throw DocumentError.noSuchLayer(layer)
        }
    }
    return done == nil ? 0 : 1
}

@_cdecl("cc_undo")
public func cc_undo(_ handle: OpaquePointer?) -> Int32 { box(handle)?.history.undo() == nil ? 0 : 1 }

@_cdecl("cc_redo")
public func cc_redo(_ handle: OpaquePointer?) -> Int32 { box(handle)?.history.redo() == nil ? 0 : 1 }

@_cdecl("cc_undo_name")
public func cc_undo_name(_ handle: OpaquePointer?, _ buffer: UnsafeMutablePointer<CChar>?, _ capacity: Int) -> Int {
    guard let name = box(handle)?.history.undoName else {
        if let buffer, capacity > 0 { buffer[0] = 0 }
        return 0
    }
    return copy(name, to: buffer, capacity: capacity)
}

@_cdecl("cc_outline_count")
public func cc_outline_count(_ handle: OpaquePointer?) -> Int { box(handle)?.history.document.outline.count ?? 0 }

@_cdecl("cc_outline_row")
public func cc_outline_row(_ handle: OpaquePointer?, _ index: Int, _ id: UnsafeMutablePointer<UInt64>?,
                           _ depth: UnsafeMutablePointer<Int32>?, _ isGroup: UnsafeMutablePointer<Int32>?,
                           _ isVisible: UnsafeMutablePointer<Int32>?, _ name: UnsafeMutablePointer<CChar>?,
                           _ nameCapacity: Int) -> Int32 {
    guard let outline = box(handle)?.history.document.outline, outline.indices.contains(index) else { return 0 }
    let row = outline[index]
    id?.pointee = row.node.id.rawValue
    depth?.pointee = Int32(row.depth)
    if case .group = row.node { isGroup?.pointee = 1 } else { isGroup?.pointee = 0 }
    isVisible?.pointee = row.node.isVisible ? 1 : 0
    _ = copy(row.node.name, to: name, capacity: nameCapacity)
    return 1
}
