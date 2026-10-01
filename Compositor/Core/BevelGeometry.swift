/// Pixel geometry shared by render backends; no image, GPU or UI objects cross this boundary.
nonisolated enum BevelGeometry {
    static func clampedSize(_ requested: Double, width: Double, height: Double) -> Double {
        min(requested, max(1, min(width, height) / 4))
    }

    /// Exact Euclidean distances to opposite coverage, with a half-pixel edge correction.
    /// Separable lower envelopes of parabolas keep the work linear in the pixel count.
    static func edgeDistances(_ shape: [Float], width: Int, height: Int) -> [Float] {
        precondition(width > 0 && height > 0 && shape.count == width * height)
        let limit = Double(width) * Double(width) + Double(height) * Double(height) + 1
        func transform(_ input: [Double]) -> [Double] {
            let count = input.count
            var sites = [Int](repeating: 0, count: count)
            var cuts = [Double](repeating: 0, count: count + 1)
            var last = 0
            cuts[0] = -.infinity
            cuts[1] = .infinity
            for q in 1..<count {
                var crossing: Double
                repeat {
                    let v = sites[last]
                    crossing = ((input[q] + Double(q) * Double(q))
                        - (input[v] + Double(v) * Double(v))) / Double(2 * (q - v))
                    if crossing > cuts[last] { break }
                    last -= 1
                } while last >= 0
                last += 1
                sites[last] = q
                cuts[last] = crossing
                cuts[last + 1] = .infinity
            }
            var result = [Double](repeating: 0, count: count)
            last = 0
            for q in 0..<count {
                while cuts[last + 1] < Double(q) { last += 1 }
                let delta = Double(q - sites[last])
                result[q] = delta * delta + input[sites[last]]
            }
            return result
        }
        func squaredDistances(toInside: Bool) -> [Double] {
            var field = shape.map { ($0 >= 0.5) == toInside ? 0.0 : limit }
            for y in 0..<height {
                let row = transform(Array(field[(y * width)..<((y + 1) * width)]))
                field.replaceSubrange((y * width)..<((y + 1) * width), with: row)
            }
            for x in 0..<width {
                let column = transform((0..<height).map { field[$0 * width + x] })
                for y in 0..<height { field[y * width + x] = column[y] }
            }
            return field
        }
        let toInside = squaredDistances(toInside: true)
        let toOutside = squaredDistances(toInside: false)
        return shape.indices.map { i in
            let squared = shape[i] >= 0.5 ? toOutside[i] : toInside[i]
            // Antialiased boundary coverage shifts the edge within its pixel.
            return max(0.01, Float(squared.squareRoot()) - 1 + abs(shape[i] - 0.5))
        }
    }
}
