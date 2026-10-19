import CoreImage
import CoreImage.CIFilterBuiltins
import Vision

extension ImageProcessingService {
    /// Focus Brush: what you paint stays sharp; everything else gets a lens blur that grows with distance
    /// from the painted areas, like a shallow depth of field you place yourself.
    func focusBrush(_ image: CIImage, strokes: [MaskStroke], amount: Double, extent e: CGRect) -> CIImage {
        guard !strokes.isEmpty, amount > 0,
              let painted = cachedStrokeMask(strokes.map { RedactionStroke(mode: .blur, width: $0.width, points: $0.points) }, extent: e)
        else { return image }
        let short = min(e.width, e.height)
        // Near the painted areas: little blur; far away: full blur.
        let near = painted.clampedToExtent().applyingGaussianBlur(sigma: Double(short / 12)).cropped(to: e)
            .applyingFilter("CIColorControls", parameters: [kCIInputContrastKey: 1.6]).applyingFilter("CIColorClamp")
        let blur = CIFilter.maskedVariableBlur()
        blur.inputImage = image.clampedToExtent()
        blur.mask = near.applyingFilter("CIColorInvert")
        blur.radius = Float(min(amount, 1) * Double(short) / 30)
        let soft = (blur.outputImage ?? image).cropped(to: e)
        // The painted areas themselves stay fully sharp, with a soft edge.
        let keep = painted.clampedToExtent().applyingGaussianBlur(sigma: Double(max(1, short / 300))).cropped(to: e)
        return image.applyingFilter("CIBlendWithMask", parameters: [
            kCIInputBackgroundImageKey: soft, kCIInputMaskImageKey: keep,
        ]).cropped(to: e)
    }

    /// Face retouch on every face found on-device: brighter, crisper eyes and whiter teeth. Photos without
    /// faces (or with closed mouths) are unchanged.
    func retouchFaces(_ image: CIImage, eyes: Double, teeth: Double, extent e: CGRect) -> CIImage {
        guard eyes > 0 || teeth > 0, let masks = Self.faceFeatureMasks(in: image, extent: e) else { return image }
        var output = image
        if eyes > 0, let eyeMask = masks.eyes {
            let k = min(eyes, 1)
            let bright = output.applyingFilter("CIExposureAdjust", parameters: [kCIInputEVKey: 0.45 * k])
                .applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 1 + 0.15 * k])
                .applyingFilter("CIUnsharpMask", parameters: [kCIInputRadiusKey: max(1, masks.faceSize / 70), kCIInputIntensityKey: 0.6 * k])
                .cropped(to: e)
            output = bright.applyingFilter("CIBlendWithMask", parameters: [
                kCIInputBackgroundImageKey: output, kCIInputMaskImageKey: eyeMask,
            ]).cropped(to: e)
        }
        if teeth > 0, let mouth = masks.mouth, let kernel = Self.kernel("teethWhiten") {
            output = kernel.apply(extent: e, arguments: [output, mouth, Float(min(teeth, 1))])?.cropped(to: e) ?? output
        }
        return output
    }

    /// Soft masks of all eyes and all inner mouths (Vision face landmarks), in image coordinates.
    static func faceFeatureMasks(in image: CIImage, extent e: CGRect) -> (eyes: CIImage?, mouth: CIImage?, faceSize: CGFloat)? {
        let scale = min(1, 1024 / max(e.width, e.height))
        let w = max(1, Int(e.width * scale)), h = max(1, Int(e.height * scale))
        let small = image.cropped(to: e)
            .transformed(by: CGAffineTransform(translationX: -e.minX, y: -e.minY).concatenating(CGAffineTransform(scaleX: scale, y: scale)))
        let request = VNDetectFaceLandmarksRequest()
        guard (try? VNImageRequestHandler(ciImage: small, options: [:]).perform([request])) != nil,
              let faces = request.results, !faces.isEmpty else { return nil }
        let size = CGSize(width: w, height: h)
        func mask(_ regions: (VNFaceLandmarks2D) -> [VNFaceLandmarkRegion2D?], grow: CGFloat) -> CIImage? {
            guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return nil }
            ctx.setFillColor(gray: 0, alpha: 1)
            ctx.fill(CGRect(origin: .zero, size: size))
            ctx.setFillColor(gray: 1, alpha: 1)
            ctx.setStrokeColor(gray: 1, alpha: 1)
            ctx.setLineJoin(.round)
            var any = false
            for face in faces {
                guard let landmarks = face.landmarks else { continue }
                let faceHeight = face.boundingBox.height * CGFloat(h)
                for region in regions(landmarks).compactMap({ $0 }) where region.pointCount > 2 {
                    // Vision's image points use a bottom-left origin, like this bitmap context.
                    let points = region.pointsInImage(imageSize: size)
                    ctx.beginPath()
                    ctx.addLines(between: points)
                    ctx.closePath()
                    ctx.setLineWidth(max(1, faceHeight * grow))
                    ctx.drawPath(using: .fillStroke)
                    any = true
                }
            }
            guard any, let bitmap = ctx.makeImage() else { return nil }
            let feather = Double(max(1, CGFloat(w) / 500))
            return SubjectMasker.fitted(CIImage(cgImage: bitmap), to: e)
                .clampedToExtent().applyingGaussianBlur(sigma: feather / Double(scale)).cropped(to: e)
        }
        let faceSize = (faces.map(\.boundingBox.height).max() ?? 0.25) * e.height
        return (mask({ [$0.leftEye, $0.rightEye] }, grow: 0.02), mask({ [$0.innerLips] }, grow: 0.0), faceSize)
    }
}
