import CoreImage
import CoreImage.CIFilterBuiltins

/// Speed blur, tilt-shift miniature, double exposure, and face / painted blur and pixelate.
extension ImageProcessingService {
    /// Miniature look: sharp horizontal band at `position` (0 top ... 1 bottom), blur growing above and
    /// below, plus the slightly punchier color real tilt-shift photos have.
    func tiltShift(_ image: CIImage, amount: Double, position: Double, extent e: CGRect) -> CIImage {
        guard amount > 0 else { return image }
        let k = CGFloat(min(amount, 1))
        let center = e.maxY - CGFloat(min(max(position, 0), 1)) * e.height
        let band = e.height * 0.1, fade = e.height * 0.28
        func gradient(from y0: CGFloat, to y1: CGFloat) -> CIImage? {
            let g = CIFilter.linearGradient()
            g.point0 = CGPoint(x: e.midX, y: y0)
            g.point1 = CGPoint(x: e.midX, y: y1)
            g.color0 = .black
            g.color1 = .white
            return g.outputImage?.cropped(to: e)
        }
        guard let above = gradient(from: center + band, to: center + band + fade),
              let below = gradient(from: center - band, to: center - band - fade) else { return image }
        let mask = above.applyingFilter("CIMaximumCompositing", parameters: [kCIInputBackgroundImageKey: below])
        let blur = CIFilter.maskedVariableBlur()
        blur.inputImage = image.clampedToExtent()
        blur.mask = mask
        blur.radius = Float(k * e.width / 45)
        let blurred = (blur.outputImage ?? image).cropped(to: e)
        return blurred.applyingFilter("CIColorControls", parameters: [
            kCIInputSaturationKey: 1 + 0.25 * k, kCIInputContrastKey: 1 + 0.06 * k,
        ]).cropped(to: e)
    }

    /// Speed blur: the background streaks in `degrees` direction (0 = horizontal) behind the sharp subject.
    func speedBlurred(_ background: CIImage, amount: Double, degrees: Double, extent e: CGRect) -> CIImage {
        guard amount > 0 else { return background }
        return background.clampedToExtent()
            .applyingFilter("CIMotionBlur", parameters: [
                kCIInputRadiusKey: CGFloat(min(amount, 1)) * e.width / 16,
                kCIInputAngleKey: degrees * .pi / 180,
            ])
            .cropped(to: e)
    }

    /// Double exposure: the second photo shows through the subject (screen blend) while the background
    /// washes toward white, the classic film-poster look. Without a subject it blends over the whole frame.
    func doubleExposure(_ image: CIImage, second: CIImage, mask: CIImage?, amount: Double, extent e: CGRect) -> CIImage {
        guard amount > 0 else { return image }
        let k = min(amount, 1)
        let fitted = Self.aspectFill(second, to: e)
        let screened = fitted.applyingFilter("CIScreenBlendMode", parameters: [kCIInputBackgroundImageKey: image]).cropped(to: e)
        let inside = image.applyingFilter("CIDissolveTransition", parameters: [
            kCIInputTargetImageKey: screened, kCIInputTimeKey: k,
        ]).cropped(to: e)
        guard let mask else { return inside }
        let paper = CIImage(color: CIColor(red: 0.94, green: 0.94, blue: 0.93)).cropped(to: e)
        let outside = image.applyingFilter("CIDissolveTransition", parameters: [
            kCIInputTargetImageKey: paper, kCIInputTimeKey: k * 0.85,
        ]).cropped(to: e)
        let soft = mask.clampedToExtent().applyingGaussianBlur(sigma: Double(max(1, e.width / 300))).cropped(to: e)
        let blend = CIFilter.blendWithMask()
        blend.inputImage = inside
        blend.backgroundImage = outside
        blend.maskImage = soft
        return (blend.outputImage ?? image).cropped(to: e)
    }

    /// Hides detected faces and painted strokes with a strong blur or pixelation, on the final framing.
    /// `strength` (0...1) sets the blur amount and the pixel block size.
    func redact(_ image: CIImage, faces mode: Redaction, strokes: [RedactionStroke], strength: Double = 0.5,
                extent e: CGRect) -> CIImage {
        guard mode != .none || !strokes.isEmpty else { return image }
        let longSide = max(e.width, e.height)
        let s = CGFloat(min(max(strength, 0), 1))
        let blurred = image.clampedToExtent().applyingGaussianBlur(sigma: Double(longSide * (0.006 + 0.03 * s))).cropped(to: e)
        let pixelated = image.clampedToExtent().applyingFilter("CIPixellate", parameters: [
            kCIInputScaleKey: max(4, longSide * (0.008 + 0.05 * s)), kCIInputCenterKey: CIVector(x: e.minX, y: e.minY),
        ]).cropped(to: e)
        func hidden(_ m: Redaction) -> CIImage { m == .pixelate ? pixelated : blurred }
        func apply(_ source: CIImage, through mask: CIImage, over base: CIImage) -> CIImage {
            let blend = CIFilter.blendWithMask()
            blend.inputImage = source
            blend.backgroundImage = base
            blend.maskImage = mask
            return (blend.outputImage ?? base).cropped(to: e)
        }

        var output = image
        if mode != .none {
            let faces = Self.faceRects(in: image, extent: e)
            var mask = CIImage(color: .black).cropped(to: e)
            for face in faces {
                // Covers the whole head (hair, ears), with only a thin soft edge so nothing shows through.
                let radius = max(face.width, face.height) * 0.78
                let g = CIFilter.radialGradient()
                g.center = CGPoint(x: face.midX, y: face.midY + face.height * 0.08)
                g.radius0 = Float(radius * 0.9)
                g.radius1 = Float(radius)
                g.color0 = .white
                g.color1 = .black
                if let spot = g.outputImage?.cropped(to: e) {
                    mask = spot.applyingFilter("CIMaximumCompositing", parameters: [kCIInputBackgroundImageKey: mask])
                }
            }
            if !faces.isEmpty { output = apply(hidden(mode), through: mask, over: output) }
        }
        for m in [Redaction.blur, .pixelate] {
            let painted = strokes.filter { $0.mode == m }
            if !painted.isEmpty, let mask = Self.strokeMask(painted, extent: e) {
                output = apply(hidden(m), through: mask, over: output)
            }
        }
        return output
    }

    /// White brush strokes on black, at the picture's size.
    static func strokeMask(_ strokes: [RedactionStroke], extent e: CGRect) -> CIImage? {
        let scale = min(1, 1024 / max(e.width, e.height))
        let w = max(1, Int((e.width * scale).rounded())), h = max(1, Int((e.height * scale).rounded()))
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)
        else { return nil }
        ctx.setFillColor(gray: 0, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        ctx.setStrokeColor(gray: 1, alpha: 1)
        ctx.setFillColor(gray: 1, alpha: 1)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        for stroke in strokes where !stroke.points.isEmpty {
            let diameter = max(2, CGFloat(stroke.width) * CGFloat(min(w, h)))
            // Normalized top-left points -> bitmap (bottom-left origin).
            let points = stroke.points.map { CGPoint(x: $0.x * CGFloat(w), y: (1 - $0.y) * CGFloat(h)) }
            if points.count == 1 {
                ctx.fillEllipse(in: CGRect(x: points[0].x - diameter / 2, y: points[0].y - diameter / 2,
                                           width: diameter, height: diameter))
            } else {
                ctx.setLineWidth(diameter)
                ctx.addLines(between: points)
                ctx.strokePath()
            }
        }
        guard let bitmap = ctx.makeImage() else { return nil }
        return CIImage(cgImage: bitmap)
            .transformed(by: CGAffineTransform(scaleX: e.width / CGFloat(w), y: e.height / CGFloat(h))
                .concatenating(CGAffineTransform(translationX: e.minX, y: e.minY)))
            .cropped(to: e)
    }
}
