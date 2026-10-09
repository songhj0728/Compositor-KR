import Foundation
import CoreGraphics

/// The composite rendered for the Channels panel and the canvas's single-channel view, kept until the document
/// changes. The channel arithmetic is in Core/ColorChannels.swift; this is the Core Graphics side.
final class ChannelPreviewCache {
    private struct Key: Equatable { let revision: UUID; let maxSide: Int; let channel: ColorChannelView }
    private var composites: [Int: (revision: UUID, image: CGImage)] = [:]
    private var channels: [(key: Key, image: CGImage)] = []

    /// The composite at most `maxSide` pixels on its longer side, for `revision`.
    func composite(maxSide: Int, revision: UUID, render: () -> CGImage?) -> CGImage? {
        if let cached = composites[maxSide], cached.revision == revision { return cached.image }
        guard let image = render() else { return nil }
        composites[maxSide] = (revision, image)
        return image
    }

    func channel(_ channel: ColorChannelView, maxSide: Int, revision: UUID, make: () -> CGImage?) -> CGImage? {
        let key = Key(revision: revision, maxSide: maxSide, channel: channel)
        if let cached = channels.first(where: { $0.key == key }) { return cached.image }
        guard let image = make() else { return nil }
        channels.removeAll { $0.key.revision != revision || ($0.key.maxSide == maxSide && $0.key.channel == channel) }
        channels.append((key, image))
        return image
    }
}

extension EditorSession {
    /// The visible layers flattened, scaled to fit `maxSide`, as the canvas shows them.
    func compositeImage(maxSide: Int) -> CGImage? {
        guard let document else { return nil }
        let revision = history.currentRevision
        return channelPreviews.composite(maxSide: maxSide, revision: revision) {
            let scale = min(1, CGFloat(maxSide) / CGFloat(max(document.width, document.height)))
            let width = max(1, Int((CGFloat(document.width) * scale).rounded())), height = max(1, Int((CGFloat(document.height) * scale).rounded()))
            guard let context = try? BrushRaster.context(width: width, height: height, mask: false) else { return nil }
            context.interpolationQuality = .high
            context.scaleBy(x: CGFloat(width) / CGFloat(document.width), y: CGFloat(height) / CGFloat(document.height))
            drawLiveComposite(document, in: context)
            return context.makeImage()
        }
    }

    /// One channel of the composite in gray, or the composite itself for `.composite`.
    func channelImage(_ channel: ColorChannelView, maxSide: Int) -> CGImage? {
        guard let composite = compositeImage(maxSide: maxSide) else { return nil }
        guard let offset = channel.offset else { return composite }
        return channelPreviews.channel(channel, maxSide: maxSide, revision: history.currentRevision) {
            // Read back as premultiplied RGBA bytes, whatever the composite's own layout.
            guard let context = try? BrushRaster.context(width: composite.width, height: composite.height, mask: false),
                  let data = context.data else { return nil }
            BrushRaster.draw(composite, in: CGRect(x: 0, y: 0, width: composite.width, height: composite.height), mask: false, context: context)
            let count = context.bytesPerRow * composite.height
            let gray = ColorChannels.gray(premultipliedRGBA: UnsafeBufferPointer(start: data.assumingMemoryBound(to: UInt8.self), count: count),
                                          width: composite.width, height: composite.height, bytesPerRow: context.bytesPerRow, channel: offset)
            guard let provider = CGDataProvider(data: Data(gray) as CFData) else { return nil }
            return CGImage(width: composite.width, height: composite.height, bitsPerComponent: 8, bitsPerPixel: 8,
                           bytesPerRow: composite.width, space: CGColorSpaceCreateDeviceGray(),
                           bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
                           provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
        }
    }
}
