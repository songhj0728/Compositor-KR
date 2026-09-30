import CoreGraphics
import Foundation

/// How File ▸ Export PSD writes a project.
nonisolated struct PSDExportOptions: Sendable {
    /// Adjustments Photoshop has adjustment layers for stay editable; off, every adjustment is saved as the pixels
    /// it makes.
    var editableAdjustments = true
    /// Text stays type Photoshop can edit, and layer effects stay its Layer Style; off, both are saved as pixels.
    var editableTextAndStyles = true
    /// Folders shown collapsed in the Layers panel, which Photoshop opens closed too.
    var collapsedGroups: Set<UUID> = []
}

nonisolated struct PSDExportResult: Sendable {
    let data: Data
    /// What didn't carry over as it is, by layer.
    let notes: [PSDConversion]
}

/// Writes a project as a layered Photoshop document (8-bit RGB), from Adobe's *Photoshop File Formats
/// Specification*: layers with their names, visibility, opacity, blend modes, folders, masks and clipping, the
/// adjustments Photoshop has adjustment layers for, the flattened image, resolution, color profile and guides.
extension ImageExporter {
    func psd(_ snapshot: ProjectSnapshot, options: PSDExportOptions = PSDExportOptions()) throws -> PSDExportResult {
        let manifest = snapshot.manifest
        let width = manifest.width, height = manifest.height
        guard (1...30_000).contains(width), (1...30_000).contains(height) else { throw ExportError.tooLarge }
        let profile = DocumentColorProfile(rawValue: manifest.colorSpace) ?? .sRGB
        var builder = PSDLayerBuilder(snapshot: snapshot, profile: profile, options: options)
        if profile == .cmyk {
            builder.note(nil, String(localized: "The CMYK project was saved as RGB: its layers are edited in RGB."))
        }
        // Adjustments Photoshop has no layer for are saved as what they make of the layers below.
        builder.bake = { [unowned self] id in try self.bakedAdjustment(snapshot, id: id) }
        let layers = try builder.build()
        let composite = try render(snapshot).image
        var file = PSDWriteBuffer()
        file.ascii("8BPS")
        file.u16(1)
        file.bytes(Data(count: 6))
        file.u16(4)
        file.u32(UInt32(height))
        file.u32(UInt32(width))
        file.u16(8)
        file.u16(3)
        file.u32(0)
        let resources = PSDResources.data(resolution: manifest.resolution ?? 72, profile: profile, guides: manifest.guides ?? [])
        file.u32(UInt32(resources.count))
        file.bytes(resources)
        file.u32(UInt32(layers.count))
        file.bytes(layers)
        try PSDPlanes.appendComposite(&file, composite, profile: profile)
        return PSDExportResult(data: file.data, notes: builder.notes)
    }

    /// An adjustment's result over everything under it, as a canvas-sized image.
    private func bakedAdjustment(_ snapshot: ProjectSnapshot, id: UUID) throws -> CGImage? {
        let layers = snapshot.manifest.layers
        guard let adjustment = layers.first(where: { $0.id == id })?.adjustment else { return nil }
        // Everything drawn before this layer, in stacking order; folders stay so the layers inside them keep theirs.
        let order = LayerHierarchy.entries(layers).map(\.layer.id)
        guard let position = order.firstIndex(of: id) else { return nil }
        let below = Set(order[..<position])
        var kept = layers.filter { $0.isGroup == true || below.contains($0.id) }
        let ids = Set(kept.map(\.id))
        for index in kept.indices where kept[index].maskSourceID.map({ !ids.contains($0) }) == true { kept[index].maskSourceID = nil }
        var manifest = snapshot.manifest
        manifest.layers = kept
        let under = try render(ProjectSnapshot(manifest: manifest, images: snapshot.images, masks: snapshot.masks)).image
        return try adjustment.apply(under)
    }
}

/// The layer and mask information section.
nonisolated struct PSDLayerBuilder {
    let snapshot: ProjectSnapshot
    let profile: DocumentColorProfile
    let options: PSDExportOptions
    var bake: ((UUID) throws -> CGImage?)?
    private(set) var notes: [PSDConversion] = []
    private let records: [UUID: ProjectLayerRecord]
    private let children: [UUID?: [ProjectLayerRecord]]

    init(snapshot: ProjectSnapshot, profile: DocumentColorProfile, options: PSDExportOptions) {
        self.snapshot = snapshot
        self.profile = profile
        self.options = options
        records = Dictionary(uniqueKeysWithValues: snapshot.manifest.layers.map { ($0.id, $0) })
        children = Dictionary(grouping: snapshot.manifest.layers, by: \.parentID)
    }

    mutating func note(_ layer: String?, _ message: String) {
        notes.append(PSDConversion(layerName: layer ?? "", message: message))
    }

    private struct Entry {
        var name: String
        var top = 0, left = 0, bottom = 0, right = 0
        var channels: [(id: Int16, payload: Data)] = PSDPlanes.emptyChannels
        var blendKey = "norm"
        var opacity: Double = 1
        var clipping = false
        var hidden = false
        /// Folders and their end markers carry no pixels.
        var isSection = false
        var mask: PSDPlanes.Mask?
        var extras: [(key: String, data: Data)] = []
    }

    mutating func build() throws -> Data {
        var entries: [Entry] = []
        try emit(nil, into: &entries)
        guard entries.count <= Int(Int16.max) else { throw ExportError.tooLarge }
        var records = PSDWriteBuffer()
        // Negative: the flattened image's fourth channel is its transparency, not an extra channel.
        records.i16(-Int16(entries.count))
        var pixels = PSDWriteBuffer()
        for entry in entries {
            Self.writeRecord(&records, entry)
            // In the order the record lists them: color and transparency, then the mask.
            for channel in entry.channels { pixels.bytes(channel.payload) }
            if let mask = entry.mask { pixels.bytes(mask.payload) }
        }
        var info = PSDWriteBuffer()
        info.bytes(records.data)
        info.bytes(pixels.data)
        if info.data.count % 2 == 1 { info.u8(0) }
        var section = PSDWriteBuffer()
        section.u32(UInt32(info.data.count))
        section.bytes(info.data)
        // No global layer mask.
        section.u32(0)
        return section.data
    }

    /// Bottom to top. A folder is its end marker, what's inside it, then the folder itself.
    private mutating func emit(_ parent: UUID?, into entries: inout [Entry]) throws {
        var clipBase: UUID?
        for record in children[parent] ?? [] {
            if record.isGroup == true {
                var end = Entry(name: "</Layer group>")
                end.isSection = true
                end.extras.append(("lsct", Self.section(3, blendKey: "norm")))
                entries.append(end)
                try emit(record.id, into: &entries)
                var folder = Entry(name: record.name)
                folder.isSection = true
                folder.opacity = record.opacity ?? 1
                folder.hidden = !record.isVisible
                // Compositor's folders pass their layers' blending through, as Photoshop's do by default.
                folder.blendKey = "pass"
                folder.mask = try mask(of: record, over: record.transform)
                folder.extras.append(("lsct", Self.section(options.collapsedGroups.contains(record.id) ? 2 : 1, blendKey: "pass")))
                entries.append(folder)
                clipBase = nil
                continue
            }
            var entry = try layer(record)
            // Photoshop clips a layer to the nearest unclipped layer below it; a live mask from anywhere else is
            // multiplied into the layer's pixels instead.
            if let source = record.maskSourceID {
                if source == clipBase {
                    entry.clipping = true
                } else {
                    try multiplyCoverage(of: source, into: &entry, name: record.name)
                    clipBase = record.id
                }
            } else {
                clipBase = record.adjustment == nil ? record.id : clipBase
            }
            entries.append(entry)
        }
    }

    private mutating func layer(_ record: ProjectLayerRecord) throws -> Entry {
        var entry = Entry(name: record.name)
        entry.opacity = record.opacity ?? 1
        entry.hidden = !record.isVisible
        entry.blendKey = (record.blendMode ?? .normal).psdKey
        if let adjustment = record.adjustment {
            if options.editableAdjustments {
                var messages: [String] = []
                if let encoded = PSDAdjustmentCoding.encode(adjustment, notes: &messages) {
                    for message in messages { note(record.name, message) }
                    entry.extras.append((encoded.key, encoded.data))
                    entry.mask = try mask(of: record, over: record.transform)
                    return entry
                }
                note(record.name, String(localized: "Photoshop has no adjustment layer for this, so its result was saved as pixels."))
            }
            guard let image = try bake?(record.id) else { return entry }
            let canvas = LayerTransform(origin: .zero, size: CGSize(width: image.width, height: image.height))
            try fill(&entry, image: image, transform: canvas)
            entry.mask = try mask(of: record, over: record.transform)
            return entry
        }
        guard let image = snapshot.images[record.id]?.image else {
            entry.mask = try mask(of: record, over: record.transform)
            return entry
        }
        // Effects Photoshop's Layer Style can hold stay editable there, over the layer's own pixels; the rest are drawn
        // into the pixels below.
        let effects = record.effects?.visible
        let hasStyles = !(effects?.kinds.isEmpty ?? true)
        let style = hasStyles && options.editableTextAndStyles ? effects.flatMap(PSDLayerStyle.block) : nil
        let stylesEditable = options.editableTextAndStyles && (!hasStyles || style != nil)
        if let text = record.text {
            if stylesEditable, let type = PSDTextWriter.block(text, transform: record.transform, width: image.width, height: image.height) {
                entry.extras.append(("TySh", type))
            } else {
                note(record.name, String(localized: "Text was saved as pixels."))
            }
        }
        if record.shape != nil { note(record.name, String(localized: "The shape was saved as pixels.")) }
        if stylesEditable, let effects {
            if let style { entry.extras.append(("lfx2", style)) }
            if let fillOpacity = PSDLayerStyle.fillOpacity(effects) { entry.extras.append(("iOpa", fillOpacity)) }
            try fill(&entry, image: image, transform: record.transform)
            entry.mask = try mask(of: record, over: record.transform)
            return entry
        }
        if hasStyles, options.editableTextAndStyles {
            note(record.name, String(localized: "A Pattern Overlay or bevel Texture has no Photoshop form here, so the layer's effects were merged into its pixels."))
        }
        // Effects (stroke, shadow) are drawn into the layer, mask and all, as the canvas shows them.
        var layerMask = snapshot.mask(for: record)
        layerMask?.isEnabled = true
        let clip = layerMask?.clipImage(placement: layerMask?.placement, over: record.transform, width: image.width, height: image.height)
        if let effects = LayerEffectsRenderer.cached(image, mask: snapshot.mask(for: record)?.isEnabled == true ? clip : nil,
                                                     effects: record.effects) {
            if !options.editableTextAndStyles { note(record.name, String(localized: "Layer effects were merged into the layer's pixels.")) }
            try fill(&entry, image: effects.image,
                     transform: LayerEffectsRenderer.placed(record.transform, image: effects.image, inset: effects.inset))
            if snapshot.mask(for: record)?.isEnabled == false { entry.mask = try mask(of: record, over: record.transform) }
            return entry
        }
        try fill(&entry, image: image, transform: record.transform)
        entry.mask = try mask(of: record, over: record.transform)
        return entry
    }

    /// The layer's pixels where the canvas puts them, and the rectangle they cover.
    private func fill(_ entry: inout Entry, image: CGImage, transform: LayerTransform) throws {
        let placed = try PSDPlanes.placed(image, transform: transform, space: profile.workingSpace)
        guard placed.rect.width > 0, placed.rect.height > 0 else { return }
        entry.left = Int(placed.rect.minX); entry.top = Int(placed.rect.minY)
        entry.right = Int(placed.rect.maxX); entry.bottom = Int(placed.rect.maxY)
        entry.channels = try PSDPlanes.channels(placed.image)
    }

    /// The layer's mask, drawn where the layer's pixels are.
    private func mask(of record: ProjectLayerRecord, over transform: LayerTransform) throws -> PSDPlanes.Mask? {
        guard var owned = snapshot.mask(for: record) else { return nil }
        let enabled = owned.isEnabled
        owned.isEnabled = true
        let grid = snapshot.images[record.id]?.image
        let width = grid?.width ?? owned.asset.image.width, height = grid?.height ?? owned.asset.image.height
        guard let image = owned.clipImage(placement: owned.placement, over: transform, width: width, height: height) else { return nil }
        return try PSDPlanes.mask(image, transform: transform, background: LayerMask.background(of: owned.asset.thumbnail),
                                  disabled: !enabled, linked: owned.isLinked)
    }

    /// Keeps the layer's pixels only where `source` has some.
    private mutating func multiplyCoverage(of source: UUID, into entry: inout Entry, name: String) throws {
        note(name, String(localized: "Its clipping mask isn't the layer right below it, which Photoshop can't do, so it was applied to the pixels."))
        guard entry.right > entry.left, entry.bottom > entry.top, let base = records[source],
              let image = snapshot.images[source]?.image else { entry.channels = PSDPlanes.emptyChannels; return }
        let rect = CGRect(x: entry.left, y: entry.top, width: entry.right - entry.left, height: entry.bottom - entry.top)
        let coverage = try BrushRaster.context(width: Int(rect.width), height: Int(rect.height), mask: true)
        coverage.translateBy(x: -rect.minX, y: -rect.minY)
        LayerRenderer.drawCoverage(image, transform: base.transform, in: coverage)
        entry.channels = try PSDPlanes.multiplyAlpha(entry.channels, by: coverage, width: Int(rect.width), height: Int(rect.height))
    }

    private static func section(_ type: UInt32, blendKey: String) -> Data {
        var buffer = PSDWriteBuffer()
        buffer.u32(type)
        buffer.ascii("8BIM")
        buffer.ascii(blendKey)
        return buffer.data
    }

    private static func writeRecord(_ buffer: inout PSDWriteBuffer, _ entry: Entry) {
        buffer.i32(Int32(clamping: entry.top))
        buffer.i32(Int32(clamping: entry.left))
        buffer.i32(Int32(clamping: entry.bottom))
        buffer.i32(Int32(clamping: entry.right))
        let channels = entry.channels + (entry.mask.map { [(Int16(-2), $0.payload)] } ?? [])
        buffer.u16(UInt16(channels.count))
        for channel in channels {
            buffer.i16(channel.id)
            buffer.u32(UInt32(channel.payload.count))
        }
        buffer.ascii("8BIM")
        buffer.ascii(entry.blendKey)
        buffer.u8(UInt8(clamping: Int((min(1, max(0, entry.opacity)) * 255).rounded())))
        buffer.u8(entry.clipping ? 1 : 0)
        // Bit 1 hidden; bit 3 says bit 4 is meaningful, bit 4 that the record has no pixels of its own.
        var flags: UInt8 = 0x08
        if entry.hidden { flags |= 0x02 }
        if entry.isSection { flags |= 0x10 }
        buffer.u8(flags)
        buffer.u8(0)
        var extra = PSDWriteBuffer()
        if let mask = entry.mask {
            extra.u32(20)
            extra.i32(Int32(clamping: mask.top))
            extra.i32(Int32(clamping: mask.left))
            extra.i32(Int32(clamping: mask.bottom))
            extra.i32(Int32(clamping: mask.right))
            extra.u8(mask.defaultColor)
            var maskFlags: UInt8 = mask.linked ? 0 : 1
            if mask.disabled { maskFlags |= 2 }
            extra.u8(maskFlags)
            extra.u16(0)
        } else {
            extra.u32(0)
        }
        // Blending ranges: everything blends, for gray and each channel.
        extra.u32(40)
        for _ in 0..<5 { extra.u32(0x0000_FFFF); extra.u32(0x0000_FFFF) }
        // The Pascal name is for older readers; `luni` below carries the name as it is.
        let pascal = Array(entry.name.unicodeScalars.map { $0.isASCII && $0.value >= 32 ? UInt8($0.value) : UInt8(ascii: "_") }.prefix(255))
        extra.u8(UInt8(pascal.count))
        extra.bytes(Data(pascal))
        extra.bytes(Data(count: (4 - ((1 + pascal.count) % 4)) % 4))
        var unicodeName = PSDWriteBuffer()
        unicodeName.unicode(entry.name)
        for (key, data) in [("luni", unicodeName.data)] + entry.extras {
            extra.ascii("8BIM")
            extra.ascii(key)
            // Lengths are rounded up to an even count, as Photoshop writes them.
            let padded = data.count + data.count % 2
            extra.u32(UInt32(padded))
            extra.bytes(data)
            if data.count % 2 == 1 { extra.u8(0) }
        }
        buffer.u32(UInt32(extra.data.count))
        buffer.bytes(extra.data)
    }
}

/// Pixels as Photoshop's channels: straight (not premultiplied) planes, PackBits-compressed row by row.
nonisolated enum PSDPlanes {
    struct Mask {
        var top: Int, left: Int, bottom: Int, right: Int
        var defaultColor: UInt8
        var disabled: Bool
        var linked: Bool
        var payload: Data
    }

    /// Transparency, red, green, blue, all empty: a record with no pixels.
    static let emptyChannels: [(id: Int16, payload: Data)] = [(-1, Data([0, 0])), (0, Data([0, 0])), (1, Data([0, 0])), (2, Data([0, 0]))]

    /// `image` drawn as `transform` places it, over the whole pixels it touches. An image already placed pixel for
    /// pixel is used as it is.
    static func placed(_ image: CGImage, transform: LayerTransform, space: CGColorSpace) throws -> (image: CGImage, rect: CGRect) {
        let unrotated = transform.rotation.truncatingRemainder(dividingBy: 360) == 0 && !transform.flipX && !transform.flipY
        if unrotated, transform.size == CGSize(width: image.width, height: image.height),
           transform.origin.x == transform.origin.x.rounded(), transform.origin.y == transform.origin.y.rounded() {
            return (image, CGRect(origin: transform.origin, size: transform.size))
        }
        let rect = bounds(of: transform)
        guard rect.width >= 1, rect.height >= 1, rect.width <= 30_000, rect.height <= 30_000 else { return (image, .zero) }
        let context = try BrushRaster.context(width: Int(rect.width), height: Int(rect.height), mask: false, space: space)
        context.translateBy(x: -rect.minX, y: -rect.minY)
        LayerRenderer.draw(image, transform: transform, center: transform.center, in: context)
        guard let drawn = context.makeImage() else { throw ExportError.render }
        return (drawn, rect)
    }

    /// The whole pixels a placed layer touches.
    static func bounds(of transform: LayerTransform) -> CGRect {
        let corners = [CGPoint(x: 0, y: 0), CGPoint(x: 1, y: 0), CGPoint(x: 0, y: 1), CGPoint(x: 1, y: 1)].map(transform.point)
        let minX = floor(corners.map(\.x).min()! + 0.001), maxX = ceil(corners.map(\.x).max()! - 0.001)
        let minY = floor(corners.map(\.y).min()! + 0.001), maxY = ceil(corners.map(\.y).max()! - 0.001)
        return CGRect(x: minX, y: minY, width: max(0, maxX - minX), height: max(0, maxY - minY))
    }

    /// A mask image covering the layer's grid, drawn where the layer lands, its color past the layer's edges.
    static func mask(_ image: CGImage, transform: LayerTransform, background: CGFloat, disabled: Bool, linked: Bool) throws -> Mask {
        let rect = bounds(of: transform)
        let width = Int(rect.width), height = Int(rect.height)
        let fill: UInt8 = background >= 0.5 ? 255 : 0
        guard width > 0, height > 0, width <= 30_000, height <= 30_000 else {
            return Mask(top: 0, left: 0, bottom: 0, right: 0, defaultColor: fill, disabled: disabled, linked: linked, payload: Data([0, 0]))
        }
        let context = try BrushRaster.context(width: width, height: height, mask: true)
        context.setFillColor(gray: background >= 0.5 ? 1 : 0, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.translateBy(x: -rect.minX, y: -rect.minY)
        // Black under the layer, then the mask's own values as coverage of white.
        context.saveGState()
        context.translateBy(x: transform.center.x, y: transform.center.y)
        context.rotate(by: transform.radians)
        context.setFillColor(gray: 0, alpha: 1)
        context.fill(CGRect(x: -transform.size.width / 2, y: -transform.size.height / 2, width: transform.size.width, height: transform.size.height))
        context.restoreGState()
        LayerRenderer.drawCoverage(image, transform: transform, in: context)
        guard let data = context.data?.assumingMemoryBound(to: UInt8.self) else { throw ExportError.render }
        var plane = [UInt8](repeating: 0, count: width * height)
        for y in 0..<height { plane.withUnsafeMutableBufferPointer { ($0.baseAddress! + y * width).update(from: data + y * context.bytesPerRow, count: width) } }
        return Mask(top: Int(rect.minY), left: Int(rect.minX), bottom: Int(rect.maxY), right: Int(rect.maxX),
                    defaultColor: fill, disabled: disabled, linked: linked, payload: payload(plane, width: width, height: height))
    }

    /// Transparency, red, green and blue channels of `image`.
    static func channels(_ image: CGImage) throws -> [(id: Int16, payload: Data)] {
        let planes = try split(image)
        return [(-1, planes.alpha), (0, planes.red), (1, planes.green), (2, planes.blue)].map {
            ($0.0, payload($0.1, width: image.width, height: image.height))
        }
    }

    /// Straight planes of `image`, first row at the top.
    static func split(_ image: CGImage) throws -> (red: [UInt8], green: [UInt8], blue: [UInt8], alpha: [UInt8]) {
        let width = image.width, height = image.height, count = width * height
        let context = try BrushRaster.context(width: width, height: height, mask: false, space: image.colorSpace)
        BrushRaster.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height), mask: false, context: context)
        guard let data = context.data?.assumingMemoryBound(to: UInt8.self) else { throw ExportError.render }
        var red = [UInt8](repeating: 0, count: count), green = red, blue = red, alpha = red
        red.withUnsafeMutableBufferPointer { r in green.withUnsafeMutableBufferPointer { g in
            blue.withUnsafeMutableBufferPointer { b in alpha.withUnsafeMutableBufferPointer { a in
                psd_split_planes(data, width, height, context.bytesPerRow, r.baseAddress, g.baseAddress, b.baseAddress, a.baseAddress)
            } }
        } }
        return (red, green, blue, alpha)
    }

    /// Compression 1 (PackBits): every row's compressed length, then the rows.
    static func payload(_ plane: [UInt8], width: Int, height: Int) -> Data {
        let rows = packed(plane, width: width, height: height)
        var buffer = PSDWriteBuffer()
        buffer.u16(1)
        for length in rows.lengths { buffer.u16(UInt16(length)) }
        buffer.bytes(rows.data)
        return buffer.data
    }

    static func packed(_ plane: [UInt8], width: Int, height: Int) -> (lengths: [Int], data: Data) {
        var lengths = [Int]()
        lengths.reserveCapacity(height)
        var data = Data(count: height * (width + width / 128 + 1))
        var used = 0
        plane.withUnsafeBufferPointer { source in
            data.withUnsafeMutableBytes { raw in
                let output = raw.bindMemory(to: UInt8.self).baseAddress!
                for row in 0..<height {
                    let length = psd_packbits(source.baseAddress! + row * width, width, output + used)
                    lengths.append(length)
                    used += length
                }
            }
        }
        data.count = used
        return (lengths, data)
    }

    /// Scales every channel's transparency by `coverage` (a gray context the same size).
    static func multiplyAlpha(_ channels: [(id: Int16, payload: Data)], by coverage: CGContext, width: Int, height: Int) throws
        -> [(id: Int16, payload: Data)] {
        guard let alphaPayload = channels.first(where: { $0.id == -1 })?.payload, let cover = coverage.data?.assumingMemoryBound(to: UInt8.self) else {
            return channels
        }
        var alpha = try unpack(alphaPayload, width: width, height: height)
        for y in 0..<height {
            for x in 0..<width {
                let i = y * width + x
                alpha[i] = UInt8((Int(alpha[i]) * Int(cover[y * coverage.bytesPerRow + x]) + 127) / 255)
            }
        }
        return channels.map { $0.id == -1 ? (-1, payload(alpha, width: width, height: height)) : $0 }
    }

    /// A PackBits channel back to its plane.
    private static func unpack(_ payload: Data, width: Int, height: Int) throws -> [UInt8] {
        let bytes = [UInt8](payload)
        guard bytes.count >= 2 + height * 2, bytes[0] == 0, bytes[1] == 1 else { throw ExportError.encode }
        var plane = [UInt8](repeating: 0, count: width * height)
        var offset = 2 + height * 2
        for row in 0..<height {
            let length = Int(bytes[2 + row * 2]) << 8 | Int(bytes[3 + row * 2])
            var i = offset, x = 0
            let end = offset + length
            while i < end, x < width {
                let header = Int(Int8(bitPattern: bytes[i])); i += 1
                if header >= 0 {
                    for _ in 0...header where x < width && i < end { plane[row * width + x] = bytes[i]; x += 1; i += 1 }
                } else if header != -128, i < end {
                    for _ in 0..<(1 - header) where x < width { plane[row * width + x] = bytes[i]; x += 1 }
                    i += 1
                }
            }
            offset = end
        }
        return plane
    }

    /// The flattened image: compression 1, every row's length for red, green, blue and transparency, then the rows.
    static func appendComposite(_ file: inout PSDWriteBuffer, _ image: CGImage, profile: DocumentColorProfile) throws {
        let planes = try split(image)
        let width = image.width, height = image.height
        file.u16(1)
        let packedPlanes = [planes.red, planes.green, planes.blue, planes.alpha].map { packed($0, width: width, height: height) }
        for plane in packedPlanes { for length in plane.lengths { file.u16(UInt16(length)) } }
        for plane in packedPlanes { file.bytes(plane.data) }
    }
}

/// Image resources: resolution, the color profile and guides.
nonisolated enum PSDResources {
    static func data(resolution: Double, profile: DocumentColorProfile, guides: [CanvasGuide]) -> Data {
        var buffer = PSDWriteBuffer()
        func resource(_ id: UInt16, _ payload: Data) {
            buffer.ascii("8BIM")
            buffer.u16(id)
            buffer.u16(0) // An empty name, padded to even.
            buffer.u32(UInt32(payload.count))
            buffer.bytes(payload)
            if payload.count % 2 == 1 { buffer.u8(0) }
        }
        // 1005: horizontal and vertical resolution in pixels per inch (16.16 fixed point), shown in inches.
        var info = PSDWriteBuffer()
        let fixed = UInt32((min(9600, max(1, resolution.isFinite ? resolution : 72)) * 65536).rounded())
        for _ in 0..<2 { info.u32(fixed); info.u16(1); info.u16(1) }
        resource(1005, info.data)
        // 1039: the ICC profile the pixels are in.
        if let icc = profile.workingSpace.copyICCData() as Data? { resource(1039, icc) }
        // 1032: guides, in 1/32 pixel; direction 0 is vertical, 1 horizontal.
        if !guides.isEmpty {
            var grid = PSDWriteBuffer()
            grid.u32(1)
            grid.u32(576)
            grid.u32(576)
            grid.u32(UInt32(guides.count))
            for guide in guides {
                grid.i32(Int32(clamping: Int((guide.position * 32).rounded())))
                grid.u8(guide.axis == .vertical ? 0 : 1)
            }
            resource(1032, grid.data)
        }
        return buffer.data
    }
}

extension LayerBlendMode {
    /// The blend mode's Photoshop key.
    nonisolated var psdKey: String {
        switch self {
        case .normal: "norm"
        case .multiply: "mul "
        case .screen: "scrn"
        case .overlay: "over"
        case .softLight: "sLit"
        case .darken: "dark"
        case .lighten: "lite"
        case .difference: "diff"
        case .colorDodge: "div "
        case .colorBurn: "idiv"
        case .hue: "hue "
        case .saturation: "sat "
        case .color: "colr"
        case .luminosity: "lum "
        case .linearBurn: "lbrn"
        case .linearDodge: "lddg"
        case .hardLight: "hLit"
        case .vividLight: "vLit"
        case .linearLight: "lLit"
        case .pinLight: "pLit"
        case .hardMix: "hMix"
        case .exclusion: "smud"
        case .subtract: "fsub"
        case .divide: "fdiv"
        }
    }
}
