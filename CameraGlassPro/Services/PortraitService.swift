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

    /// Subject compositing for Portrait, Color Splash and Background Swap.
    /// Order: choose the background (original or replacement) → Portrait depth blur and lighting →
    /// Color Splash (background to black and white) → blend under the sharp subject.
    func composeSubject(_ a: PhotoAdjustmentState, to image: CIImage, mask rawMask: CIImage,
                        backgroundPhoto: CIImage?) -> CIImage {
        let extent = image.extent
        let feather = max(1, extent.width / 400)
        let mask = rawMask.clampedToExtent()
            .applyingGaussianBlur(sigma: Double(feather))
            .cropped(to: extent)
        var subject = image
        var background = replacementBackground(a.background, for: image, photo: backgroundPhoto) ?? image

        if a.portrait {
            let radius = Self.portraitBlurRadius(aperture: a.aperture, width: extent.width)
            if a.background == .original {
                // Depth blur that respects the mask edge.
                let blur = CIFilter.maskedVariableBlur()
                blur.inputImage = image.clampedToExtent()
                blur.mask = mask.applyingFilter("CIColorInvert")
                blur.radius = Float(radius)
                background = (blur.outputImage ?? image).cropped(to: extent)
            } else if a.background == .photo, radius > 0.5 {
                background = background.clampedToExtent().applyingGaussianBlur(sigma: Double(radius) / 2).cropped(to: extent)
            }

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
        }

        if a.colorSplash {
            background = background.applyingFilter("CIPhotoEffectMono")
        }
        background = speedBlurred(background, amount: a.speedBlur, degrees: a.speedAngle, extent: extent)
        subject = regionEdit(a.subjectEdit, to: subject)
        background = regionEdit(a.backgroundEdit, to: background)

        let blend = CIFilter.blendWithMask()
        blend.inputImage = subject
        blend.backgroundImage = background
        blend.maskImage = mask
        return (blend.outputImage ?? image).cropped(to: extent)
    }

    /// Brightness, saturation and warmth for one side of the subject mask.
    func regionEdit(_ edit: RegionEdit, to image: CIImage) -> CIImage {
        guard !edit.isNeutral else { return image }
        var output = image
        if edit.exposure != 0 {
            output = output.applyingFilter("CIExposureAdjust", parameters: [kCIInputEVKey: edit.exposure * 1.5])
        }
        if edit.saturation != 0 {
            output = output.applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 1 + edit.saturation])
        }
        if edit.warmth != 0 {
            let filter = CIFilter.temperatureAndTint()
            filter.inputImage = output
            filter.neutral = CIVector(x: 6500, y: 0)
            filter.targetNeutral = CIVector(x: 6500 - edit.warmth * 2500, y: 0) // same direction as global Warmth
            output = filter.outputImage ?? output
        }
        return output
    }

    /// The swapped background at the image's size, or nil to keep the original.
    private func replacementBackground(_ style: BackgroundStyle, for image: CIImage, photo: CIImage?) -> CIImage? {
        let extent = image.extent
        switch style {
        case .original:
            return nil
        case .blur:
            return image.clampedToExtent().applyingGaussianBlur(sigma: Double(extent.width / 45)).cropped(to: extent)
        case .black:
            return CIImage(color: CIColor(red: 0.02, green: 0.02, blue: 0.02)).cropped(to: extent)
        case .white:
            return CIImage(color: CIColor(red: 0.97, green: 0.97, blue: 0.96)).cropped(to: extent)
        case .gray:
            return gradient(extent, top: CIColor(red: 0.62, green: 0.62, blue: 0.63), bottom: CIColor(red: 0.36, green: 0.36, blue: 0.38))
        case .sky:
            return gradient(extent, top: CIColor(red: 0.42, green: 0.66, blue: 0.93), bottom: CIColor(red: 0.82, green: 0.9, blue: 0.98))
        case .sunset:
            return gradient(extent, top: CIColor(red: 0.36, green: 0.27, blue: 0.55), bottom: CIColor(red: 0.98, green: 0.62, blue: 0.4))
        case .photo:
            guard let photo else { return nil }
            return Self.aspectFill(photo, to: extent)
        }
    }

    /// Soft vertical studio-style gradient.
    private func gradient(_ extent: CGRect, top: CIColor, bottom: CIColor) -> CIImage {
        let f = CIFilter.linearGradient()
        f.point0 = CGPoint(x: extent.midX, y: extent.maxY)
        f.point1 = CGPoint(x: extent.midX, y: extent.minY)
        f.color0 = top
        f.color1 = bottom
        return (f.outputImage ?? CIImage(color: top)).cropped(to: extent)
    }

    /// Scales and centers `image` so it covers `extent`.
    static func aspectFill(_ image: CIImage, to extent: CGRect) -> CIImage {
        let source = image.extent
        guard source.width > 0, source.height > 0 else { return image }
        let scale = max(extent.width / source.width, extent.height / source.height)
        let scaled = image.transformed(by: CGAffineTransform(translationX: -source.minX, y: -source.minY)
            .concatenating(CGAffineTransform(scaleX: scale, y: scale)))
        let dx = extent.minX + (extent.width - source.width * scale) / 2
        let dy = extent.minY + (extent.height - source.height * scale) / 2
        return scaled.transformed(by: CGAffineTransform(translationX: dx, y: dy)).cropped(to: extent)
    }
}

/// Backgrounds for Background Swap.
enum BackgroundStyle: String, CaseIterable, Codable, Sendable, Identifiable {
    case original, blur, black, white, gray, sky, sunset, photo

    var id: String { rawValue }

    var label: String {
        switch self {
        case .original: "ORIGINAL"
        case .photo: "PHOTO…"
        default: rawValue.uppercased()
        }
    }

    var systemImage: String {
        switch self {
        case .original: "photo"
        case .blur: "drop.halffull"
        case .black: "circle.fill"
        case .white: "circle"
        case .gray: "circle.lefthalf.filled"
        case .sky: "cloud.sun"
        case .sunset: "sun.horizon"
        case .photo: "photo.on.rectangle"
        }
    }
}
