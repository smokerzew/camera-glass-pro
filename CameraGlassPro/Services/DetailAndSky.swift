import CoreImage
import CoreImage.CIFilterBuiltins

extension ImageProcessingService {
    /// Noise Reduction: edge-aware brightness smoothing plus color-noise removal, in one Metal kernel.
    func reduceNoise(_ image: CIImage, amount: Double, extent: CGRect) -> CIImage {
        guard amount > 0, let kernel = Self.kernel("denoise") else { return image }
        let k = min(amount, 1)
        let base = image.clampedToExtent()
        let fine = base.applyingGaussianBlur(sigma: Double(max(1, extent.width / 800)) * (0.6 + k)).cropped(to: extent)
        let wide = base.applyingGaussianBlur(sigma: Double(max(1, extent.width / 300)) * (0.5 + k)).cropped(to: extent)
        return kernel.apply(extent: extent, arguments: [image, fine, wide, Float(k)])?.cropped(to: extent) ?? image
    }

    /// Sharpen: luminance-only sharpening sized to the picture, so preview and export match and colors don't fringe.
    func sharpen(_ image: CIImage, amount: Double, extent: CGRect) -> CIImage {
        guard amount > 0 else { return image }
        let filter = CIFilter.sharpenLuminance()
        filter.inputImage = image
        filter.sharpness = Float(min(amount, 1) * 0.9)
        filter.radius = Float(max(1, extent.width / 1500))
        return (filter.outputImage ?? image).cropped(to: extent)
    }

    /// Soft mask of the sky (white = sky). On-device heuristics, no network: blue, bright overcast or dark
    /// night sky that is smooth and sits toward the top. Bright plain walls near the top can be picked up too.
    func skyMask(for image: CIImage, extent: CGRect) -> CIImage? {
        guard let kernel = Self.kernel("skyLikelihood") else { return nil }
        let display = image.applyingFilter("CILinearToSRGBToneCurve")
        let detail = display.clampedToExtent().applyingGaussianBlur(sigma: Double(max(1, extent.width / 250)))
        // Cropped before spreading: outside the photo the difference is the blur itself, which made a
        // "textured" rim along the frame edges (no sky there).
        let texture = display.applyingFilter("CIDifferenceBlendMode", parameters: [kCIInputBackgroundImageKey: detail])
            .cropped(to: extent)
            .clampedToExtent()
            .applyingGaussianBlur(sigma: Double(max(1, extent.width / 100)))
            .cropped(to: extent)
        let top = CIFilter.linearGradient()
        top.point0 = CGPoint(x: extent.midX, y: extent.maxY - extent.height * 0.05)
        top.point1 = CGPoint(x: extent.midX, y: extent.maxY - extent.height * 0.65)
        top.color0 = .white
        top.color1 = .black
        guard let position = top.outputImage?.cropped(to: extent),
              let likelihood = kernel.apply(extent: extent, arguments: [image, texture, position]) else { return nil }
        // The smooth-area test is blurred, so it stops short of ridges and rooftops. Grow it past them, then keep
        // only pixels close to the nearby sky color, so the edge follows the skyline pixel by pixel.
        guard let refine = Self.kernel("skyRefine") else {
            return likelihood.clampedToExtent().applyingGaussianBlur(sigma: Double(max(1, extent.width / 120))).cropped(to: extent)
        }
        let grown = likelihood.applyingFilter("CIMorphologyMaximum", parameters: [kCIInputRadiusKey: max(1, extent.width / 70)])
            .cropped(to: extent)
        let skyOnly = CIImage(color: .clear).cropped(to: extent).applyingFilter("CIBlendWithMask", parameters: [
            kCIInputBackgroundImageKey: image, kCIInputMaskImageKey: likelihood.applyingFilter("CIColorInvert"),
        ]).cropped(to: extent)
        let localSky = skyOnly.clampedToExtent().applyingGaussianBlur(sigma: Double(max(2, extent.width / 40))).cropped(to: extent)
        guard let refined = refine.apply(extent: extent, arguments: [image, localSky, grown]) else { return nil }
        return refined.clampedToExtent().applyingGaussianBlur(sigma: Double(max(0.7, extent.width / 1000))).cropped(to: extent)
    }

    /// Brightness, saturation and warmth for the sky only.
    func applySkyEdit(_ edit: RegionEdit, to image: CIImage, mask: CIImage, extent: CGRect) -> CIImage {
        let blend = CIFilter.blendWithMask()
        blend.inputImage = regionEdit(edit, to: image)
        blend.backgroundImage = image
        blend.maskImage = mask
        return (blend.outputImage ?? image).cropped(to: extent)
    }
}

/// New skies for Sky Replace. Gradients are smooth photographic skies (nothing drawn, no text);
/// `.photo` uses the second photo shared with Background Swap and Double Exposure.
enum SkyReplacement: String, CaseIterable, Codable, Sendable, Identifiable {
    case none, blue, golden, sunset, overcast, photo

    var id: String { rawValue }

    var label: String {
        switch self {
        case .none: "Off"
        default: rawValue.capitalized
        }
    }

    /// sRGB colors at the top of the frame and at the horizon.
    var colors: (top: CIColor, horizon: CIColor)? {
        switch self {
        case .blue: (CIColor(red: 0.16, green: 0.38, blue: 0.78), CIColor(red: 0.64, green: 0.79, blue: 0.95))
        case .golden: (CIColor(red: 0.42, green: 0.60, blue: 0.86), CIColor(red: 1.0, green: 0.84, blue: 0.60))
        case .sunset: (CIColor(red: 0.30, green: 0.28, blue: 0.55), CIColor(red: 1.0, green: 0.60, blue: 0.36))
        case .overcast: (CIColor(red: 0.68, green: 0.70, blue: 0.74), CIColor(red: 0.88, green: 0.89, blue: 0.90))
        case .none, .photo: nil
        }
    }

    /// The light the new sky casts on the land.
    var groundLight: RegionEdit {
        var edit = RegionEdit()
        switch self {
        case .golden: edit.warmth = 0.22
        case .sunset: edit.warmth = 0.32; edit.exposure = -0.06
        case .blue: edit.warmth = -0.05
        case .overcast: edit.saturation = -0.15; edit.exposure = -0.04
        case .none, .photo: break
        }
        return edit
    }
}

extension ImageProcessingService {
    /// Puts a new sky into the sky area, then lights the land to match. `amount` 0...1 blends with the original.
    func replaceSky(_ image: CIImage, with kind: SkyReplacement, amount: Double, mask: CIImage,
                    photo: CIImage?, extent e: CGRect) -> CIImage {
        let k = min(max(amount, 0), 1)
        guard kind != .none, k > 0 else { return image }
        let newSky: CIImage
        if let colors = kind.colors {
            let gradient = CIFilter.smoothLinearGradient()
            gradient.point0 = CGPoint(x: e.midX, y: e.maxY)
            gradient.point1 = CGPoint(x: e.midX, y: e.maxY - e.height * 0.6)
            gradient.color0 = colors.top
            gradient.color1 = colors.horizon
            guard let output = gradient.outputImage else { return image }
            // Keep the original sky's clouds and haze as brightness detail, so it isn't a flat painted sky.
            let blur = image.clampedToExtent().applyingGaussianBlur(sigma: Double(max(2, e.width / 60))).cropped(to: e)
            newSky = Self.kernel("skyDetail")?.apply(extent: e, arguments: [output.cropped(to: e), image, blur, Float(0.9)])?
                .cropped(to: e) ?? output.cropped(to: e)
        } else if let photo, photo.extent.width > 0, photo.extent.height > 0 {
            // Cover the frame, anchored to the top so the photo's own sky lands in ours.
            let p = photo.extent
            let scale = max(e.width / p.width, e.height / p.height)
            newSky = photo.transformed(by: CGAffineTransform(translationX: -p.minX, y: -p.minY)
                .concatenating(CGAffineTransform(scaleX: scale, y: scale))
                .concatenating(CGAffineTransform(translationX: e.minX + (e.width - p.width * scale) / 2,
                                                 y: e.maxY - p.height * scale)))
                .cropped(to: e)
        } else {
            return image
        }
        // A slightly firmer edge. Clamped: contrast around 0.5 pushes the ground below 0, which would push it away
        // from the new sky's color.
        let edge = mask.applyingFilter("CIColorControls", parameters: [kCIInputContrastKey: 1.25])
            .applyingFilter("CIColorClamp").cropped(to: e)
        let strength = CIImage(color: CIColor(red: k, green: k, blue: k)).cropped(to: e)
        let skyMask = edge.applyingFilter("CIMultiplyCompositing", parameters: [kCIInputBackgroundImageKey: strength])
        let lit = kind.groundLight.isNeutral ? image : regionEdit(kind.groundLight.scaled(k), to: image)
        return newSky.applyingFilter("CIBlendWithMask", parameters: [
            kCIInputBackgroundImageKey: lit, kCIInputMaskImageKey: skyMask,
        ]).cropped(to: e)
    }
}

extension RegionEdit {
    /// Every value times `k` (0...1).
    func scaled(_ k: Double) -> RegionEdit {
        var copy = self
        copy.exposure *= k
        copy.saturation *= k
        copy.warmth *= k
        return copy
    }
}
