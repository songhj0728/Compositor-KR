/// Pixel geometry shared by render backends; no image, GPU or UI objects cross this boundary.
nonisolated enum BevelGeometry {
    static func clampedSize(_ requested: Double, width: Double, height: Double) -> Double {
        min(requested, max(1, min(width, height) / 4))
    }

    enum Profile: Sendable { case inner, outer, emboss, pillow }

    /// A rounded shoulder and foot keep lighting continuous at both ends of a
    /// smooth bevel, without moving either end of its distance-defined width.
    static func roundedHeight(_ height: Float) -> Float {
        let h = min(1, max(0, height))
        return h * h * (3 - 2 * h)
    }

    /// Unit height before contour, technique smoothing and depth. Kept independent
    /// of platform image APIs so display, export and Windows use the same surface.
    static func height(distance: Float, size: Float, profile: Profile) -> Float {
        let size = max(0.01, size)
        switch profile {
        case .inner: return min(1, max(0, distance / size))
        case .outer: return min(1, max(0, 1 + distance / size))
        case .emboss: return min(1, max(0, 0.5 + distance / (2 * size)))
        case .pillow: return min(1, abs(distance) / size)
        }
    }

    /// Diffuse lighting of a height field, with downward-positive image rows.
    static func lighting(slopeX: Float, slopeY: Float, light: SIMD3<Float>) -> Float {
        let length = (slopeX * slopeX + slopeY * slopeY + 1).squareRoot()
        return (-slopeX * light.x - slopeY * light.y + light.z) / length
    }

    /// Normalize each side against its available diffuse range. Dividing shadow
    /// by the flat intensity alone clips every below-horizon normal to solid dark.
    static func shading(lit: Float, flat: Float) -> (highlight: Float, shadow: Float) {
        let highlight = flat < 0.9999 ? max(0, (lit - flat) / (1 - flat)) : 0
        let shadow = max(0, (flat - lit) / (1 + flat))
        return (min(1, highlight), min(1, shadow))
    }

    /// Exact Euclidean distances to opposite coverage, with a half-pixel edge correction.
    /// Separable lower envelopes of parabolas keep the work linear in the pixel count.
    enum CalculationError: Error { case cancelled }

    static func edgeDistances(_ shape: [Float], width: Int, height: Int) -> [Float] {
        // This overload cannot cancel; the throwing form is used by preview workers.
        try! edgeDistances(shape, width: width, height: height, isCancelled: { false })
    }

    static func edgeDistances(_ shape: [Float], width: Int, height: Int,
                              isCancelled: () -> Bool) throws -> [Float] {
        precondition(width > 0 && height > 0 && shape.count == width * height)
        if isCancelled() { throw CalculationError.cancelled }
        let limit = Double(width) * Double(width) + Double(height) * Double(height) + 1
        // Reuse line buffers rather than allocating arrays for every row and column.
        let lineLength = max(width, height)
        var values = [Double](repeating: 0, count: lineLength)
        var sites = [Int](repeating: 0, count: lineLength)
        var cuts = [Double](repeating: 0, count: lineLength + 1)
        func squaredDistances(toInside: Bool) throws -> [Double] {
            var field = shape.map { ($0 >= 0.5) == toInside ? 0.0 : limit }
            try field.withUnsafeMutableBufferPointer { pixels in
                try values.withUnsafeMutableBufferPointer { values in
                    try sites.withUnsafeMutableBufferPointer { sites in
                        try cuts.withUnsafeMutableBufferPointer { cuts in
                            func transform(start: Int, stride: Int, count: Int) {
                                for q in 0..<count { values[q] = pixels[start + q * stride] }
                                var last = 0
                                sites[0] = 0
                                cuts[0] = -.infinity
                                cuts[1] = .infinity
                                for q in 1..<count {
                                    var crossing: Double
                                    repeat {
                                        let v = sites[last]
                                        crossing = ((values[q] + Double(q) * Double(q))
                                            - (values[v] + Double(v) * Double(v))) / Double(2 * (q - v))
                                        if crossing > cuts[last] { break }
                                        last -= 1
                                    } while last >= 0
                                    last += 1
                                    sites[last] = q
                                    cuts[last] = crossing
                                    cuts[last + 1] = .infinity
                                }
                                last = 0
                                for q in 0..<count {
                                    while cuts[last + 1] < Double(q) { last += 1 }
                                    let delta = Double(q - sites[last])
                                    pixels[start + q * stride] = delta * delta + values[sites[last]]
                                }
                            }
                            for y in 0..<height {
                                if isCancelled() { throw CalculationError.cancelled }
                                transform(start: y * width, stride: 1, count: width)
                            }
                            for x in 0..<width {
                                if isCancelled() { throw CalculationError.cancelled }
                                transform(start: x, stride: width, count: height)
                            }
                        }
                    }
                }
            }
            return field
        }
        let toInside = try squaredDistances(toInside: true)
        let toOutside = try squaredDistances(toInside: false)
        return shape.indices.map { i in
            let squared = shape[i] >= 0.5 ? toOutside[i] : toInside[i]
            // Antialiased boundary coverage shifts the edge within its pixel.
            return max(0.01, Float(squared.squareRoot()) - 1 + abs(shape[i] - 0.5))
        }
    }
}
