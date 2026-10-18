import CoreImage
import CoreImage.CIFilterBuiltins

extension ImageProcessingService {
    /// Noise Reduction: Core Image luminance noise reduction plus color-noise removal (Metal kernel).
    func reduceNoise(_ image: CIImage, amount: Double, extent: CGRect) -> CIImage {
        guard amount > 0 else { return image }
        let k = min(amount, 1)
        let luma = image.applyingFilter("CINoiseReduction", parameters: [
            "inputNoiseLevel": 0.01 + 0.05 * k, "inputSharpness": 0.4,
        ]).cropped(to: extent)
        guard let kernel = Self.kernel("chromaDenoise") else { return luma }
        let blurred = luma.clampedToExtent()
            .applyingGaussianBlur(sigma: Double(max(1, extent.width / 500)) * (0.5 + k))
            .cropped(to: extent)
        return kernel.apply(extent: extent, arguments: [luma, blurred, Float(k)])?.cropped(to: extent) ?? luma
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
        let texture = display.applyingFilter("CIDifferenceBlendMode", parameters: [kCIInputBackgroundImageKey: detail])
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
        // Feather so edits blend smoothly into rooftops and trees.
        return likelihood.clampedToExtent().applyingGaussianBlur(sigma: Double(max(1, extent.width / 120))).cropped(to: extent)
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
