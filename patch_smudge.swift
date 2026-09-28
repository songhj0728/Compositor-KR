import Foundation

let path = "Compositor/Document/SmudgeLiquify.swift"
var lines = try String(contentsOfFile: path).components(separatedBy: .newlines)

let liquifyModeStr = """
nonisolated enum LiquifyMode: String, CaseIterable, Sendable, Codable {
    case forwardWarp = "Forward Warp"
    case reconstruct = "Reconstruct"
    case twirlClockwise = "Twirl Clockwise"
    case pucker = "Pucker"
    case bloat = "Bloat"
    case pushLeft = "Push Left"
    
    var displayName: String {
        switch self {
        case .forwardWarp: return "Forward Warp"
        case .reconstruct: return "Reconstruct"
        case .twirlClockwise: return "Twirl Clockwise"
        case .pucker: return "Pucker"
        case .bloat: return "Bloat"
        case .pushLeft: return "Push Left"
        }
    }
}
"""

if let idx = lines.firstIndex(where: { $0.contains("enum BlurToolMode") }) {
    lines.insert(liquifyModeStr, at: idx)
}

let warpStrokeInit = "    init(layer: ImageLayer, image: CGImage, transform: LayerTransform, canvas: CGSize, mode: BlurToolMode, settings: BrushSettings) throws {"
let warpStrokeInitNew = """
    let liquifyMode: LiquifyMode
    init(layer: ImageLayer, image: CGImage, transform: LayerTransform, canvas: CGSize, mode: BlurToolMode, liquifyMode: LiquifyMode = .forwardWarp, settings: BrushSettings) throws {
        self.liquifyMode = liquifyMode
"""
if let idx = lines.firstIndex(where: { $0 == warpStrokeInit }) {
    lines[idx] = warpStrokeInitNew
}

let appendCall = "            if mode == .smudge { smudge(at: next) } else { push(from: previous, to: next) }"
let appendCallNew = "            if mode == .smudge { smudge(at: next) } else { liquifyApply(from: previous, to: next) }"
if let idx = lines.firstIndex(where: { $0.contains(appendCall) }) {
    lines[idx] = appendCallNew
}

// Replace push function with liquifyApply that has math
let pushStart = "    private func push(from a: CGPoint, to b: CGPoint) {"
if let startIdx = lines.firstIndex(where: { $0 == pushStart }) {
    let endIdx = lines[startIdx...].firstIndex(where: { $0 == "    }" })!
    lines.removeSubrange(startIdx...endIdx)
    
    let liquifyApplyStr = """
    private func liquifyApply(from a: CGPoint, to b: CGPoint) {
        if liquifyMode == .forwardWarp { push(from: a, to: b); return }
        
        let r = radius
        let cx = Int(b.x.rounded()), cy = Int(b.y.rounded())
        let x0 = max(0, cx - r), x1 = min(width - 1, cx + r)
        let y0 = max(0, cy - r), y1 = min(height - 1, cy + r)
        guard x0 <= x1, y0 <= y1 else { return }
        
        let cw = x1 - x0 + 1, ch = y1 - y0 + 1
        if scratch.count < cw * ch * 4 { scratch = [Float](repeating: 0, count: cw * ch * 4) }
        for y in y0...y1 {
            for x in x0...x1 {
                let p = (y * width + x) * 4, s = ((y - y0) * cw + (x - x0)) * 4
                for k in 0..<4 { scratch[s + k] = Float(pixels[p + k]) }
            }
        }
        
        let invR = 1 / Float(diameter / 2)
        let dx_stroke = Float(b.x - a.x) * Float(strength)
        let dy_stroke = Float(b.y - a.y) * Float(strength)
        
        for dy in -r...r {
            let y = cy + dy
            guard y >= 0, y < height else { continue }
            for dx in -r...r {
                let x = cx + dx
                guard x >= 0, x < width else { continue }
                
                let u = Float(dx * dx + dy * dy).squareRoot() * invR
                let w = weight(u) * Float(strength)
                guard w > 0 else { continue }
                
                var sx = Float(x)
                var sy = Float(y)
                
                switch liquifyMode {
                case .pucker:
                    sx = Float(x) + Float(dx) * w * 0.5
                    sy = Float(y) + Float(dy) * w * 0.5
                case .bloat:
                    sx = Float(x) - Float(dx) * w * 0.5
                    sy = Float(y) - Float(dy) * w * 0.5
                case .twirlClockwise:
                    let theta = w * 1.5
                    let c = cos(theta)
                    let s = sin(theta)
                    sx = Float(cx) + (Float(dx) * c - Float(dy) * s)
                    sy = Float(cy) + (Float(dx) * s + Float(dy) * c)
                case .pushLeft:
                    sx = Float(x) - dy_stroke * w * 0.5
                    sy = Float(y) + dx_stroke * w * 0.5
                default:
                    break
                }
                
                let rx = max(Float(x0), min(Float(x1), sx))
                let ry = max(Float(y0), min(Float(y1), sy))
                let ix = Int(rx), iy = Int(ry)
                let fx = rx - Float(ix), fy = ry - Float(iy)
                let s00 = ((iy - y0) * cw + (ix - x0)) * 4
                let s10 = ix + 1 <= x1 ? s00 + 4 : s00
                let s01 = iy + 1 <= y1 ? s00 + cw * 4 : s00
                let s11 = (ix + 1 <= x1 && iy + 1 <= y1) ? s01 + 4 : s01
                
                let p = (y * width + x) * 4
                for k in 0..<4 {
                    let top = scratch[s00 + k] + (scratch[s10 + k] - scratch[s00 + k]) * fx
                    let bottom = scratch[s01 + k] + (scratch[s11 + k] - scratch[s01 + k]) * fx
                    let val = top + (bottom - top) * fy
                    pixels[p + k] = UInt8(max(0, min(255, val.rounded())))
                }
            }
        }
    }
    
    private func push(from a: CGPoint, to b: CGPoint) {
"""
    lines.insert(liquifyApplyStr, at: startIdx)
}

let callStr = "            let stroke = try WarpStroke(layer: layer, image: image, transform: displayedTransform(for: layer),"
let callStrNew = "            let stroke = try WarpStroke(layer: layer, image: image, transform: displayedTransform(for: layer),\n                                        canvas: document.size, mode: blurMode, liquifyMode: liquifyMode, settings: brushSettings)"

if let startIdx = lines.firstIndex(where: { $0.contains(callStr) }) {
    lines.remove(at: startIdx)
    lines.remove(at: startIdx)
    lines.insert(callStrNew, at: startIdx)
}


try lines.joined(separator: "\n").write(toFile: path, atomically: true, encoding: .utf8)
