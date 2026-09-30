import Foundation

/// A layer's effects as Photoshop's own Layer Style (`lfx2`), so they stay editable there, and its Fill Opacity
/// (`iOpa`). From Adobe's *Photoshop File Formats Specification* (Object Based Effects Layer Info) and the descriptor
/// keys Photoshop writes for each style.
nonisolated enum PSDLayerStyle {
    /// The `lfx2` block, or nil when a style has no Photoshop form Compositor can write — a Pattern Overlay or a
    /// bevel's Texture, whose patterns live in Photoshop's own library — so the caller draws the effects into the
    /// layer's pixels instead.
    static func block(_ effects: LayerEffects) -> Data? {
        let effects = effects.visible
        guard effects.isValid else { return nil }
        if effects.patternOverlay != nil || effects.bevel?.hasTexture == true { return nil }
        var items: [(String, PSDDescriptorItem)] = [("Scl ", .unit("#Prc", 100)), ("masterFXSwitch", .bool(true))]
        if let shadow = effects.shadow {
            items.append(("DrSh", .object(classID: "DrSh", items: [
                ("enab", .bool(true)), ("present", .bool(true)), ("showInDialog", .bool(true)),
                ("Md  ", mode(shadow.blendMode)), ("Clr ", color(shadow.color)), ("Opct", percent(shadow.opacity)),
                ("uglg", .bool(false)), ("lagl", .unit("#Ang", Double(shadow.angle))),
                ("Dstn", .unit("#Pxl", Double(shadow.distance))), ("Ckmt", .unit("#Pxl", Double(shadow.spread ?? 0))),
                ("blur", .unit("#Pxl", Double(shadow.blur))), ("Nose", .unit("#Prc", 0)), ("AntA", .bool(false)),
                ("TrnS", contour(shadow.contour ?? .linear)), ("layerConceals", .bool(true))
            ])))
        }
        if let inner = effects.innerShadow {
            items.append(("IrSh", .object(classID: "IrSh", items: [
                ("enab", .bool(true)), ("present", .bool(true)), ("showInDialog", .bool(true)),
                ("Md  ", mode(inner.blendMode)), ("Clr ", color(inner.color)), ("Opct", percent(inner.opacity)),
                ("uglg", .bool(false)), ("lagl", .unit("#Ang", Double(inner.angle))),
                ("Dstn", .unit("#Pxl", Double(inner.distance))), ("Ckmt", .unit("#Pxl", Double(inner.choke ?? 0))),
                ("blur", .unit("#Pxl", Double(inner.blur))), ("Nose", .unit("#Prc", 0)), ("AntA", .bool(false)),
                ("TrnS", contour(inner.contour ?? .linear))
            ])))
        }
        if let glow = effects.outerGlow {
            items.append(("OrGl", .object(classID: "OrGl", items: [
                ("enab", .bool(true)), ("present", .bool(true)), ("showInDialog", .bool(true)),
                ("Md  ", mode(glow.blendMode)), ("Clr ", color(glow.color)), ("Opct", percent(glow.opacity)),
                ("GlwT", .enumeration(type: "BETE", value: "SfBL")),
                ("Ckmt", .unit("#Pxl", Double(glow.spread ?? 0))), ("blur", .unit("#Pxl", Double(glow.size))),
                ("Nose", .unit("#Prc", 0)), ("ShdN", .unit("#Prc", 0)), ("AntA", .bool(false)),
                ("TrnS", contour(glow.contour ?? .linear)), ("Inpr", .unit("#Prc", 50))
            ])))
        }
        if let glow = effects.innerGlow {
            items.append(("IrGl", .object(classID: "IrGl", items: [
                ("enab", .bool(true)), ("present", .bool(true)), ("showInDialog", .bool(true)),
                ("Md  ", mode(glow.blendMode)), ("Clr ", color(glow.color)), ("Opct", percent(glow.opacity)),
                ("GlwT", .enumeration(type: "BETE", value: "SfBL")),
                ("Ckmt", .unit("#Pxl", Double(glow.choke ?? 0))), ("blur", .unit("#Pxl", Double(glow.size))),
                ("ShdN", .unit("#Prc", 0)), ("Nose", .unit("#Prc", 0)), ("AntA", .bool(false)),
                ("glwS", .enumeration(type: "IGSr", value: glow.fromCenter == true ? "SrcC" : "SrcE")),
                ("TrnS", contour(glow.contour ?? .linear)), ("Inpr", .unit("#Prc", 50))
            ])))
        }
        if let bevel = effects.bevel {
            let style: String
            switch bevel.style {
            case .outerBevel: style = "OtrB"
            case .innerBevel: style = "InrB"
            case .emboss: style = "Embs"
            case .pillowEmboss: style = "PlEb"
            }
            let technique: String
            switch bevel.technique {
            case .smooth: technique = "SfBL"
            case .chiselHard: technique = "PrBL"
            case .chiselSoft: technique = "Slmt"
            }
            items.append(("ebbl", .object(classID: "ebbl", items: [
                ("enab", .bool(true)), ("present", .bool(true)), ("showInDialog", .bool(true)),
                ("hglM", mode(bevel.highlightMode)), ("hglC", color(bevel.highlightColor)), ("hglO", percent(bevel.highlightOpacity)),
                ("sdwM", mode(bevel.shadowMode)), ("sdwC", color(bevel.shadowColor)), ("sdwO", percent(bevel.shadowOpacity)),
                ("bvlT", .enumeration(type: "bvlT", value: technique)), ("bvlS", .enumeration(type: "BESl", value: style)),
                ("uglg", .bool(false)), ("lagl", .unit("#Ang", Double(bevel.angle))), ("Lald", .unit("#Ang", Double(bevel.altitude))),
                ("srgR", .unit("#Prc", Double(bevel.depth))), ("blur", .unit("#Pxl", Double(bevel.size))),
                ("bvlD", .enumeration(type: "BESs", value: bevel.up ? "In  " : "Out ")),
                ("TrnS", contour(bevel.gloss)), ("antialiasGloss", .bool(false)),
                ("Sftn", .unit("#Pxl", Double(bevel.soften))),
                ("useShape", .bool(bevel.hasContour)), ("MpgS", contour(bevel.contour)), ("AntA", .bool(false)),
                ("Inpr", .unit("#Prc", Double(bevel.contourRange))), ("useTexture", .bool(false))
            ])))
        }
        if let satin = effects.satin {
            items.append(("ChFX", .object(classID: "ChFX", items: [
                ("enab", .bool(true)), ("present", .bool(true)), ("showInDialog", .bool(true)),
                ("Md  ", mode(satin.blendMode)), ("Clr ", color(satin.color)), ("AntA", .bool(true)), ("Invr", .bool(satin.invert)),
                ("Opct", percent(satin.opacity)), ("lagl", .unit("#Ang", Double(satin.angle))),
                ("Dstn", .unit("#Pxl", Double(satin.distance))), ("blur", .unit("#Pxl", Double(satin.size))),
                ("MpgS", contour(satin.contour))
            ])))
        }
        if let overlay = effects.colorOverlay {
            items.append(("SoFi", .object(classID: "SoFi", items: [
                ("enab", .bool(true)), ("present", .bool(true)), ("showInDialog", .bool(true)),
                ("Md  ", mode(overlay.blendMode)), ("Opct", percent(overlay.opacity)), ("Clr ", color(overlay.color))
            ])))
        }
        if let stroke = effects.stroke {
            items.append(("FrFX", .object(classID: "FrFX", items: [
                ("enab", .bool(true)), ("present", .bool(true)), ("showInDialog", .bool(true)),
                ("Styl", .enumeration(type: "FStl", value: stroke.centered == true ? "CtrF" : stroke.inside ? "InsF" : "OutF")),
                ("PntT", .enumeration(type: "FrFl", value: "SClr")),
                ("Md  ", mode(stroke.blendMode)), ("Opct", percent(stroke.opacity)),
                ("Sz  ", .unit("#Pxl", Double(stroke.size))), ("Clr ", color(stroke.color)), ("overprint", .bool(false))
            ])))
        }
        guard items.count > 2 else { return nil }
        var buffer = PSDWriteBuffer()
        // Object effects version, then the descriptor's own version.
        buffer.u32(0)
        buffer.u32(16)
        PSDDescriptorItem.body(&buffer, classID: "null", items: items)
        return buffer.data
    }

    /// Fill Opacity: one byte, then three of padding.
    static func fillOpacity(_ effects: LayerEffects) -> Data? {
        guard effects.fill < 1 else { return nil }
        return Data([UInt8((min(1, max(0, effects.fill)) * 255).rounded()), 0, 0, 0])
    }

    private static func percent(_ value: Double) -> PSDDescriptorItem { .unit("#Prc", min(100, max(0, value * 100))) }

    private static func color(_ color: PaletteColor) -> PSDDescriptorItem {
        .object(classID: "RGBC", items: [("Rd  ", .double(Double(color.red) * 255)), ("Grn ", .double(Double(color.green) * 255)),
                                         ("Bl  ", .double(Double(color.blue) * 255))])
    }

    private static func mode(_ mode: LayerBlendMode?) -> PSDDescriptorItem {
        .enumeration(type: "BlnM", value: descriptorKey(mode ?? .normal))
    }

    /// The blend mode's key in a descriptor, which differs from the layer record's four-letter key.
    static func descriptorKey(_ mode: LayerBlendMode) -> String {
        switch mode {
        case .normal: "Nrml"
        case .darken: "Drkn"
        case .multiply: "Mltp"
        case .colorBurn: "CBrn"
        case .linearBurn: "linearBurn"
        case .lighten: "Lghn"
        case .screen: "Scrn"
        case .colorDodge: "CDdg"
        case .linearDodge: "linearDodge"
        case .overlay: "Ovrl"
        case .softLight: "SftL"
        case .hardLight: "HrdL"
        case .vividLight: "vividLight"
        case .linearLight: "linearLight"
        case .pinLight: "pinLight"
        case .hardMix: "hardMix"
        case .difference: "Dfrn"
        case .exclusion: "Xclu"
        case .subtract: "blendSubtraction"
        case .divide: "blendDivide"
        case .hue: "H   "
        case .saturation: "Strt"
        case .color: "Clr "
        case .luminosity: "Lmns"
        }
    }

    /// A contour as Photoshop's curve of points, 0–255 each way.
    private static func contour(_ contour: EffectContour) -> PSDDescriptorItem {
        let steps = contour == .linear ? 1 : 16
        let points: [PSDDescriptorItem] = (0...steps).map { step in
            let x = Float(step) / Float(steps)
            return .object(classID: "CrPt", items: [("Hrzn", .double(Double(x * 255))), ("Vrtc", .double(Double(contour.value(x) * 255)))])
        }
        return .object(classID: "ShpC", items: [("Nm  ", .text(contour.rawValue)), ("Crv ", .list(points))])
    }
}
