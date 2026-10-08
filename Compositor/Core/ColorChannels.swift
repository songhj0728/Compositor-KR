// The Channels panel's arithmetic: one color channel of the composite, shown in gray as Photoshop shows a channel on
// its own. Standard library only, so a Windows port reuses it as it is; Document/ChannelView.swift renders the
// composite and turns the result into an image.

nonisolated enum ColorChannels {
    /// One channel (byte `offset` 0, 1 or 2 of each pixel) of premultiplied RGBA pixels, as opaque gray. A clear
    /// pixel shows white, a half-clear one its channel value halfway to white, as if the canvas were laid on paper.
    static func gray(premultipliedRGBA pixels: UnsafeBufferPointer<UInt8>, width: Int, height: Int, bytesPerRow: Int,
                     channel offset: Int) -> [UInt8] {
        precondition((0...2).contains(offset), "a color channel")
        var result = [UInt8](repeating: 255, count: max(0, width * height))
        guard width > 0, height > 0, pixels.count >= bytesPerRow * (height - 1) + width * 4 else { return result }
        for y in 0..<height {
            let row = y * bytesPerRow
            for x in 0..<width {
                let i = row + x * 4
                // Premultiplied: value + (255 − alpha) is the straight value laid over white.
                let value = Int(pixels[i + offset]) + 255 - Int(pixels[i + 3])
                result[y * width + x] = UInt8(min(255, max(0, value)))
            }
        }
        return result
    }
}
