import CoreGraphics

enum AspectRatioOption: String, CaseIterable, Identifiable {
    case original
    case fourThree = "4:3"
    case sixteenNine = "16:9"
    case square = "1:1"

    var id: String { rawValue }
    var label: String { self == .original ? "Full" : rawValue }

    /// Long side / short side, nil for the image's own ratio.
    private var longToShort: CGFloat? {
        switch self {
        case .original: nil
        case .fourThree: 4.0 / 3.0
        case .sixteenNine: 16.0 / 9.0
        case .square: 1
        }
    }

    /// Width / height of the viewfinder. Fixed ratios follow the image's orientation,
    /// so a landscape photo gets a landscape 4:3 frame.
    func resolvedRatio(imageSize: CGSize) -> CGFloat {
        let landscape = imageSize.width > imageSize.height
        guard let r = longToShort else {
            guard imageSize.width > 0, imageSize.height > 0 else { return 3.0 / 4.0 }
            return imageSize.width / imageSize.height
        }
        return landscape ? r : 1 / r
    }

    var next: AspectRatioOption {
        let all = Self.allCases
        let index = all.firstIndex(of: self) ?? 0
        return all[(index + 1) % all.count]
    }
}

enum ZoomLimits {
    static let minimum: CGFloat = 0.5
    static let maximum: CGFloat = 5
    static let presets: [CGFloat] = [0.5, 1, 2, 5]

    static func clamp(_ zoom: CGFloat) -> CGFloat {
        guard zoom.isFinite else { return 1 }
        return min(max(zoom, minimum), maximum)
    }

    static func label(for zoom: CGFloat) -> String {
        let rounded = (zoom * 10).rounded() / 10
        if rounded == 0.5 { return ".5" }
        return rounded.truncatingRemainder(dividingBy: 1) == 0
            ? String(Int(rounded)) : String(format: "%.1f", Double(rounded))
    }
}

/// One coordinate system shared by the preview, the overlays and the "crop to framing" export,
/// so what the viewfinder shows is exactly what gets cropped.
enum FramingGeometry {
    /// Largest size with `ratio` (w/h) that fits in `container`.
    static func frameSize(ratio: CGFloat, in container: CGSize) -> CGSize {
        guard ratio > 0, container.width > 0, container.height > 0 else { return .zero }
        var width = container.width
        var height = width / ratio
        if height > container.height {
            height = container.height
            width = height * ratio
        }
        return CGSize(width: width, height: height)
    }

    /// Scale mapping image pixels to frame points at 1x zoom.
    static func baseScale(image: CGSize, frame: CGSize, fill: Bool) -> CGFloat {
        guard image.width > 0, image.height > 0, frame.width > 0, frame.height > 0 else { return 1 }
        let sx = frame.width / image.width
        let sy = frame.height / image.height
        return fill ? max(sx, sy) : min(sx, sy)
    }

    /// Centered region of the image (pixels, top-left origin) visible in a frame of `ratio` at `zoom`.
    static func visibleRect(image: CGSize, ratio: CGFloat, zoom: CGFloat, fill: Bool) -> CGRect {
        guard image.width > 0, image.height > 0, ratio > 0 else { return .zero }
        let frame = CGSize(width: ratio, height: 1) // scale-invariant, only the ratio matters
        let scale = baseScale(image: image, frame: frame, fill: fill) * ZoomLimits.clamp(zoom)
        let width = min(image.width, frame.width / scale)
        let height = min(image.height, frame.height / scale)
        return CGRect(x: (image.width - width) / 2, y: (image.height - height) / 2, width: width, height: height)
    }

    /// `visibleRect` expressed in 0...1 units of the image.
    static func normalizedVisibleRect(image: CGSize, ratio: CGFloat, zoom: CGFloat, fill: Bool) -> CGRect {
        let rect = visibleRect(image: image, ratio: ratio, zoom: zoom, fill: fill)
        guard image.width > 0, image.height > 0 else { return CGRect(x: 0, y: 0, width: 1, height: 1) }
        return CGRect(x: rect.minX / image.width, y: rect.minY / image.height,
                      width: rect.width / image.width, height: rect.height / image.height)
    }
}
