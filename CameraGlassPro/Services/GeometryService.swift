import CoreImage
import Vision

/// Crop, rotate, flip and straighten (photos). Applied after the looks and before grain.
extension ImageProcessingService {
    /// Rotation, mirror and straightening only (no crop): what the crop editor shows.
    func applyOrientation(_ a: PhotoAdjustmentState, to image: CIImage) -> CIImage {
        var output = image
        if a.flipped { output = output.oriented(.upMirrored) }
        switch ((a.rotation % 4) + 4) % 4 {
        case 1: output = output.oriented(.right) // 90° clockwise
        case 2: output = output.oriented(.down)
        case 3: output = output.oriented(.left)
        default: break
        }
        output = Self.atOrigin(output)

        let degrees = min(max(a.straighten, -45), 45)
        guard abs(degrees) > 0.01 else {
            return Self.keystone(output, vertical: a.perspectiveVertical, horizontal: a.perspectiveHorizontal)
        }
        // Rotate about the center, then crop to the largest same-shape rect with no empty corners.
        let extent = output.extent
        let radians = -degrees * .pi / 180 // positive straighten turns the picture clockwise
        let center = CGPoint(x: extent.midX, y: extent.midY)
        let turn = CGAffineTransform(translationX: center.x, y: center.y)
            .rotated(by: CGFloat(radians))
            .translatedBy(x: -center.x, y: -center.y)
        // Clamped so the antialiased rotated edge never leaves see-through pixels in the corners.
        let rotated = output.clampedToExtent().transformed(by: turn)
        let scale = Self.straightenScale(width: extent.width, height: extent.height, degrees: degrees)
        let inner = CGRect(x: center.x - extent.width * scale / 2, y: center.y - extent.height * scale / 2,
                           width: extent.width * scale, height: extent.height * scale).integral
        return Self.keystone(Self.atOrigin(rotated.cropped(to: inner)),
                             vertical: a.perspectiveVertical, horizontal: a.perspectiveHorizontal)
    }

    /// Full geometry: orientation, then the normalized crop (top-left origin).
    func applyGeometry(_ a: PhotoAdjustmentState, to image: CIImage) -> CIImage {
        guard a.hasGeometry else { return image }
        let oriented = applyOrientation(a, to: image)
        guard a.cropRect != PhotoAdjustmentState.fullCrop else { return oriented }
        return Self.atOrigin(PhotoExportService.crop(oriented, normalized: a.cropRect))
    }

    /// How much a rotated image must shrink so a same-aspect, axis-aligned rect fits inside it.
    static func straightenScale(width: CGFloat, height: CGFloat, degrees: Double) -> CGFloat {
        let theta = abs(degrees) * .pi / 180
        let c = CGFloat(cos(theta)), s = CGFloat(sin(theta))
        guard width > 0, height > 0 else { return 1 }
        return min(width / (width * c + height * s), height / (width * s + height * c))
    }

    /// Keystone (perspective) correction. Only the edge being corrected is stretched outward, so the
    /// original frame stays fully covered: no empty corners, same output size.
    /// `vertical` + widens the top (buildings leaning in when shot from below), − widens the bottom.
    /// `horizontal` + widens the right side, − the left.
    static func keystone(_ image: CIImage, vertical: Double, horizontal: Double) -> CIImage {
        guard abs(vertical) > 0.001 || abs(horizontal) > 0.001 else { return image }
        let e = image.extent
        let dv = CGFloat(min(abs(vertical), 1)) * e.width * 0.3
        let dh = CGFloat(min(abs(horizontal), 1)) * e.height * 0.3
        let m: CGFloat = 1 // a pixel of overlap so edge pixels stay fully opaque
        var tl = CGPoint(x: e.minX - m, y: e.maxY + m), tr = CGPoint(x: e.maxX + m, y: e.maxY + m)
        var bl = CGPoint(x: e.minX - m, y: e.minY - m), br = CGPoint(x: e.maxX + m, y: e.minY - m)
        if vertical > 0 { tl.x -= dv; tr.x += dv } else if vertical < 0 { bl.x -= dv; br.x += dv }
        if horizontal > 0 { tr.y += dh; br.y -= dh } else if horizontal < 0 { tl.y += dh; bl.y -= dh }
        let filter = CIFilter.perspectiveTransform()
        filter.inputImage = image
        filter.topLeft = tl
        filter.topRight = tr
        filter.bottomLeft = bl
        filter.bottomRight = br
        return (filter.outputImage ?? image).cropped(to: e)
    }

    static func atOrigin(_ image: CIImage) -> CIImage {
        image.transformed(by: CGAffineTransform(translationX: -image.extent.minX, y: -image.extent.minY))
    }

    /// Horizon tilt in degrees (Vision), as a straighten value that levels it; nil if none found.
    static func horizonStraighten(for image: CGImage) -> Double? {
        let request = VNDetectHorizonRequest()
        try? VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
        guard let angle = request.results?.first?.angle else { return nil }
        let degrees = Double(angle) * 180 / .pi
        return abs(degrees) < 0.2 ? nil : min(max(degrees, -45), 45)
    }
}

/// Crop aspect presets in the editor.
enum CropAspect: String, CaseIterable, Identifiable {
    case freeform, original, square, fourThree, threeFour, sixteenNine, nineSixteen

    var id: String { rawValue }

    var label: String {
        switch self {
        case .freeform: "Freeform"
        case .original: "Original"
        case .square: "Square"
        case .fourThree: "4:3"
        case .threeFour: "3:4"
        case .sixteenNine: "16:9"
        case .nineSixteen: "9:16"
        }
    }

    /// The same shape turned 90° (4:3 ↔ 3:4, 16:9 ↔ 9:16), used when the photo is rotated.
    var rotated: CropAspect {
        switch self {
        case .fourThree: .threeFour
        case .threeFour: .fourThree
        case .sixteenNine: .nineSixteen
        case .nineSixteen: .sixteenNine
        default: self
        }
    }

    /// Width / height, nil for freeform; `original` uses the image's own ratio.
    func ratio(imageSize: CGSize) -> CGFloat? {
        switch self {
        case .freeform: nil
        case .original: imageSize.height > 0 ? imageSize.width / imageSize.height : nil
        case .square: 1
        case .fourThree: 4.0 / 3.0
        case .threeFour: 3.0 / 4.0
        case .sixteenNine: 16.0 / 9.0
        case .nineSixteen: 9.0 / 16.0
        }
    }

    /// Largest centered normalized crop with `ratio` inside an image of `imageSize`.
    static func centeredCrop(ratio: CGFloat, imageSize: CGSize) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0, ratio > 0 else { return PhotoAdjustmentState.fullCrop }
        let imageRatio = imageSize.width / imageSize.height
        var w: CGFloat = 1, h: CGFloat = 1
        if ratio > imageRatio { h = imageRatio / ratio } else { w = ratio / imageRatio }
        return CGRect(x: (1 - w) / 2, y: (1 - h) / 2, width: w, height: h)
    }
}
