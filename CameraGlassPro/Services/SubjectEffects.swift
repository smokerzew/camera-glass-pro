import CoreImage
import CoreImage.CIFilterBuiltins

/// SUBJECT > Effects: neon outline, colored aura, silhouette and drop shadow, all built on the subject mask.
extension ImageProcessingService {
    /// A color from a hue in degrees (full saturation), scaled by `k`.
    private func hueColor(_ degrees: Double, _ k: CGFloat) -> CIColor {
        let h = (degrees.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360) / 60
        let x = 1 - abs(h.truncatingRemainder(dividingBy: 2) - 1)
        let (r, g, b): (Double, Double, Double) = switch Int(h) % 6 {
        case 0: (1, x, 0)
        case 1: (x, 1, 0)
        case 2: (0, 1, x)
        case 3: (0, x, 1)
        case 4: (x, 0, 1)
        default: (1, 0, x)
        }
        return CIColor(red: CGFloat(r) * k, green: CGFloat(g) * k, blue: CGFloat(b) * k)
    }

    /// A gray mask colored: white becomes `color`, black stays black.
    private func tinted(_ mask: CIImage, _ color: CIColor, extent e: CGRect) -> CIImage {
        mask.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: color.red, y: 0, z: 0, w: 0),
            "inputGVector": CIVector(x: color.green, y: 0, z: 0, w: 0),
            "inputBVector": CIVector(x: color.blue, y: 0, z: 0, w: 0),
        ]).cropped(to: e)
    }

    func subjectEffects(_ image: CIImage, mask: CIImage, _ a: PhotoAdjustmentState, extent e: CGRect) -> CIImage {
        var output = image
        let subject = mask.cropped(to: e)
        let outside = subject.applyingFilter("CIColorInvert").cropped(to: e)

        if a.subjectShadow > 0 {
            // A soft shadow cast down and to the right, only on the background.
            let k = CGFloat(min(a.subjectShadow, 1))
            let shadow = subject.transformed(by: CGAffineTransform(translationX: e.width * 0.025, y: -e.height * 0.02))
                .clampedToExtent().applyingGaussianBlur(sigma: Double(e.width / 60)).cropped(to: e)
                .applyingFilter("CIMultiplyCompositing", parameters: [kCIInputBackgroundImageKey: outside])
            let dark = output.applyingFilter("CIExposureAdjust", parameters: [kCIInputEVKey: -1.6 * k])
            output = dark.applyingFilter("CIBlendWithMask", parameters: [kCIInputBackgroundImageKey: output, kCIInputMaskImageKey: shadow])
                .cropped(to: e)
        }
        if a.aura > 0 {
            // A colored glow around the subject, behind it.
            let k = CGFloat(min(a.aura, 1))
            let glow = tinted(subject.clampedToExtent().applyingGaussianBlur(sigma: Double(e.width / 22)).cropped(to: e),
                              hueColor(a.auraHue, 1.0 * k), extent: e)
                .applyingFilter("CIMultiplyCompositing", parameters: [kCIInputBackgroundImageKey: outside])
            output = glow.applyingFilter("CIScreenBlendMode", parameters: [kCIInputBackgroundImageKey: output]).cropped(to: e)
        }
        if a.silhouette > 0 {
            // The subject goes dark against its background, keeping a faint shape.
            let k = min(a.silhouette, 1)
            let dark = output.applyingFilter("CIExposureAdjust", parameters: [kCIInputEVKey: -4 * k])
                .applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 1 - 0.7 * k])
            output = dark.applyingFilter("CIBlendWithMask", parameters: [kCIInputBackgroundImageKey: output, kCIInputMaskImageKey: subject])
                .cropped(to: e)
        }
        if a.neonOutline > 0 {
            // A glowing line traced along the subject's outline.
            let k = CGFloat(min(a.neonOutline, 1))
            let r = max(1.5, e.width / 400)
            let grown = subject.applyingFilter("CIMorphologyMaximum", parameters: [kCIInputRadiusKey: r])
            let shrunk = subject.applyingFilter("CIMorphologyMinimum", parameters: [kCIInputRadiusKey: r])
            let line = grown.applyingFilter("CIDifferenceBlendMode", parameters: [kCIInputBackgroundImageKey: shrunk]).cropped(to: e)
            let core = tinted(line, hueColor(a.neonHue, 0.6 + 0.6 * k), extent: e)
            let halo = core.clampedToExtent().applyingGaussianBlur(sigma: Double(r * 4)).cropped(to: e)
                .applyingFilter("CIColorMatrix", parameters: [
                    "inputRVector": CIVector(x: 2 * k, y: 0, z: 0, w: 0), "inputGVector": CIVector(x: 0, y: 2 * k, z: 0, w: 0),
                    "inputBVector": CIVector(x: 0, y: 0, z: 2 * k, w: 0),
                ])
            let lit = core.applyingFilter("CIScreenBlendMode", parameters: [kCIInputBackgroundImageKey: halo]).cropped(to: e)
            output = lit.applyingFilter("CIScreenBlendMode", parameters: [kCIInputBackgroundImageKey: output]).cropped(to: e)
        }
        return output
    }
}
