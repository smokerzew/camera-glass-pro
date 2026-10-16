import CoreImage
import CoreImage.CIFilterBuiltins
import Vision

/// Portrait Lighting effects (names as in the Camera app).
enum PortraitLighting: String, CaseIterable, Codable, Sendable, Identifiable {
    case natural, studio, contour, stage, stageMono, highKey

    var id: String { rawValue }

    var label: String {
        switch self {
        case .natural: "NATURAL LIGHT"
        case .studio: "STUDIO LIGHT"
        case .contour: "CONTOUR LIGHT"
        case .stage: "STAGE LIGHT"
        case .stageMono: "STAGE LIGHT MONO"
        case .highKey: "HIGH-KEY LIGHT MONO"
        }
    }

    var systemImage: String {
        switch self {
        case .natural: "cube"
        case .studio: "cube.fill"
        case .contour: "cube.transparent"
        case .stage: "circle.lefthalf.filled"
        case .stageMono: "circle.lefthalf.filled.inverse"
        case .highKey: "sun.max"
        }
    }
}

/// Finds the subject (people first, then any salient foreground: pets, objects) with on-device Vision.
enum SubjectMasker {
    /// Soft mask (white = subject) matching `image.extent`, or nil if no subject is found.
    /// `fast` uses quick person segmentation only (for video frames).
    static func mask(for image: CIImage, fast: Bool = false) -> CIImage? {
        let extent = image.extent
        guard extent.width > 1, extent.height > 1, !extent.isInfinite else { return nil }
        let handler = VNImageRequestHandler(ciImage: image, options: [:])

        if !fast {
            let foreground = VNGenerateForegroundInstanceMaskRequest()
            if (try? handler.perform([foreground])) != nil,
               let observation = foreground.results?.first,
               !observation.allInstances.isEmpty,
               let buffer = try? observation.generateScaledMaskForImage(forInstances: observation.allInstances, from: handler) {
                return fitted(CIImage(cvPixelBuffer: buffer), to: extent)
            }
        }

        let person = VNGeneratePersonSegmentationRequest()
        person.qualityLevel = fast ? .fast : .accurate
        person.outputPixelFormat = kCVPixelFormatType_OneComponent8
        guard (try? handler.perform([person])) != nil, let buffer = person.results?.first?.pixelBuffer else { return nil }
        let mask = fitted(CIImage(cvPixelBuffer: buffer), to: extent)
        return coverage(of: mask) > 0.01 ? mask : nil
    }

    /// Scales a mask to cover `extent` exactly.
    static func fitted(_ mask: CIImage, to extent: CGRect) -> CIImage {
        let m = mask.extent
        guard m.width > 0, m.height > 0 else { return mask }
        return mask
            .transformed(by: CGAffineTransform(translationX: -m.minX, y: -m.minY))
            .transformed(by: CGAffineTransform(scaleX: extent.width / m.width, y: extent.height / m.height))
            .transformed(by: CGAffineTransform(translationX: extent.minX, y: extent.minY))
    }

    /// Fraction of the frame that is subject (average mask brightness).
    private static func coverage(of mask: CIImage) -> Double {
        guard let average = CIFilter(name: "CIAreaAverage", parameters: [
            kCIInputImageKey: mask, kCIInputExtentKey: CIVector(cgRect: mask.extent),
        ])?.outputImage else { return 0 }
        var pixel = [UInt8](repeating: 0, count: 4)
        ImageProcessingService.shared.context.render(average, toBitmap: &pixel, rowBytes: 4,
                                                     bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                                                     format: .RGBA8, colorSpace: nil)
        return Double(pixel[0]) / 255
    }
}

extension ImageProcessingService {
    /// Background blur radius for an ƒ-number: strongest at ƒ1.4, none at ƒ16.
    static func portraitBlurRadius(aperture: Double, width: CGFloat) -> CGFloat {
        let a = min(max(aperture, 1.4), 16)
        let strength = (16 / a - 1) / (16 / 1.4 - 1) // 1 at f/1.4 … 0 at f/16
        return CGFloat(strength) * width / 36
    }

    /// Real Portrait: keeps the subject sharp, blurs the background by aperture and applies lighting.
    func applyPortrait(_ a: PhotoAdjustmentState, to image: CIImage, mask rawMask: CIImage) -> CIImage {
        let extent = image.extent
        let feather = max(1, extent.width / 400)
        let mask = rawMask.clampedToExtent()
            .applyingGaussianBlur(sigma: Double(feather))
            .cropped(to: extent)

        // Blur where the mask is dark (background).
        let inverted = mask.applyingFilter("CIColorInvert")
        let blur = CIFilter.maskedVariableBlur()
        blur.inputImage = image.clampedToExtent()
        blur.mask = inverted
        blur.radius = Float(Self.portraitBlurRadius(aperture: a.aperture, width: extent.width))
        var background = (blur.outputImage ?? image).cropped(to: extent)
        var subject = image

        switch a.lighting {
        case .natural:
            break
        case .studio:
            subject = subject.applyingFilter("CIExposureAdjust", parameters: [kCIInputEVKey: 0.3])
                .applyingFilter("CIHighlightShadowAdjust", parameters: ["inputHighlightAmount": 0.85, "inputShadowAmount": 0.25])
        case .contour:
            subject = subject.applyingFilter("CIColorControls", parameters: [kCIInputContrastKey: 1.18])
                .applyingFilter("CIHighlightShadowAdjust", parameters: ["inputShadowAmount": -0.3])
            background = background.applyingFilter("CIExposureAdjust", parameters: [kCIInputEVKey: -0.35])
        case .stage:
            subject = subject.applyingFilter("CIExposureAdjust", parameters: [kCIInputEVKey: 0.15])
            background = CIImage(color: .black).cropped(to: extent)
        case .stageMono:
            subject = subject.applyingFilter("CIPhotoEffectNoir")
            background = CIImage(color: .black).cropped(to: extent)
        case .highKey:
            subject = subject.applyingFilter("CIPhotoEffectMono")
                .applyingFilter("CIExposureAdjust", parameters: [kCIInputEVKey: 0.25])
            background = CIImage(color: .white).cropped(to: extent)
        }

        let blend = CIFilter.blendWithMask()
        blend.inputImage = subject
        blend.backgroundImage = background
        blend.maskImage = mask
        return (blend.outputImage ?? image).cropped(to: extent)
    }
}
