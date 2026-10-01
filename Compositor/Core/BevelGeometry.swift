/// Pixel geometry shared by render backends; no image, GPU or UI objects cross this boundary.
nonisolated enum BevelGeometry {
    static func clampedSize(_ requested: Double, width: Double, height: Double) -> Double {
        min(requested, max(1, min(width, height) / 4))
    }

    /// An eight-neighbor distance to the silhouette, in two linear passes. Boundary pixels start
    /// half a pixel from the edge, including partially covered pixels on an antialiased outline.
    static func edgeDistances(_ shape: [Float], width: Int, height: Int) -> [Float] {
        precondition(width > 0 && height > 0 && shape.count == width * height)
        let diagonal: Float = Float(2).squareRoot()
        var distances = [Float](repeating: Float(width + height), count: shape.count)
        for y in 0..<height {
            for x in 0..<width {
                let i = y * width + x, inside = shape[i] >= 0.5
                if (x > 0 && (shape[i - 1] >= 0.5) != inside)
                    || (x + 1 < width && (shape[i + 1] >= 0.5) != inside)
                    || (y > 0 && (shape[i - width] >= 0.5) != inside)
                    || (y + 1 < height && (shape[i + width] >= 0.5) != inside) {
                    distances[i] = max(0.01, abs(shape[i] - 0.5))
                }
                if x > 0 { distances[i] = min(distances[i], distances[i - 1] + 1) }
                if y > 0 {
                    distances[i] = min(distances[i], distances[i - width] + 1)
                    if x > 0 { distances[i] = min(distances[i], distances[i - width - 1] + diagonal) }
                    if x + 1 < width { distances[i] = min(distances[i], distances[i - width + 1] + diagonal) }
                }
            }
        }
        for y in stride(from: height - 1, through: 0, by: -1) {
            for x in stride(from: width - 1, through: 0, by: -1) {
                let i = y * width + x
                if x + 1 < width { distances[i] = min(distances[i], distances[i + 1] + 1) }
                if y + 1 < height {
                    distances[i] = min(distances[i], distances[i + width] + 1)
                    if x > 0 { distances[i] = min(distances[i], distances[i + width - 1] + diagonal) }
                    if x + 1 < width { distances[i] = min(distances[i], distances[i + width + 1] + diagonal) }
                }
            }
        }
        return distances
    }

}
