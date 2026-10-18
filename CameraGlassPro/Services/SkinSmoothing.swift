import CoreImage
import CoreImage.CIFilterBuiltins
import Vision

extension ImageProcessingService {
    /// Smooths skin only: inside soft areas around detected faces, on skin-colored pixels, and never
    /// across edges (eyes, brows, lips, hair keep their detail). Photos without faces are unchanged.
    func smoothSkin(_ image: CIImage, amount: Double, extent: CGRect) -> CIImage {
        guard amount > 0, let kernel = Self.kernel("skinSmooth") else { return image }
        let faces = Self.faceRects(in: image, extent: extent)
        guard !faces.isEmpty else { return image }

        // Soft round areas covering each face, forehead and cheeks.
        var area = CIImage(color: .black).cropped(to: extent)
        for face in faces {
            let radius = max(face.width, face.height) * 0.72
            let gradient = CIFilter.radialGradient()
            gradient.center = CGPoint(x: face.midX, y: face.midY + face.height * 0.05)
            gradient.radius0 = Float(radius * 0.55)
            gradient.radius1 = Float(radius)
            gradient.color0 = .white
            gradient.color1 = .black
            if let spot = gradient.outputImage?.cropped(to: extent) {
                area = spot.applyingFilter("CIMaximumCompositing", parameters: [kCIInputBackgroundImageKey: area])
            }
        }
        // Blur sized to the faces, so pores and blemishes soften the same at any resolution.
        let faceSize = faces.map(\.height).max() ?? extent.height / 4
        let blurred = image.clampedToExtent().applyingGaussianBlur(sigma: Double(max(1, faceSize / 45))).cropped(to: extent)
        return kernel.apply(extent: extent, arguments: [image, blurred, area, Float(min(amount, 1))])?.cropped(to: extent) ?? image
    }

    /// Face rectangles in image coordinates (Vision, on a small copy for speed).
    static func faceRects(in image: CIImage, extent: CGRect) -> [CGRect] {
        let scale = min(1, 720 / max(extent.width, extent.height))
        let small = image.cropped(to: extent)
            .transformed(by: CGAffineTransform(translationX: -extent.minX, y: -extent.minY).scaledBy(x: scale, y: scale))
        let request = VNDetectFaceRectanglesRequest()
        try? VNImageRequestHandler(ciImage: small, options: [:]).perform([request])
        // Vision's normalized boxes use a bottom-left origin, like Core Image.
        return (request.results ?? []).map { face in
            let box = face.boundingBox
            return CGRect(x: extent.minX + box.minX * extent.width, y: extent.minY + box.minY * extent.height,
                          width: box.width * extent.width, height: box.height * extent.height)
        }
    }
}
