import CoreImage.CIFilterBuiltins
import AVFoundation
import CoreImage
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum ExportContent: String, CaseIterable, Identifiable, Sendable {
    case original, adjusted
    var id: String { rawValue }
    var label: String { self == .original ? "Original" : "Edited Copy" }
}

enum ExportFormat: String, CaseIterable, Identifiable, Sendable {
    case jpeg, heic, png
    var id: String { rawValue }
    var label: String { rawValue.uppercased() }
    var fileExtension: String {
        switch self {
        case .jpeg: "jpg"
        case .heic: "heic"
        case .png: "png"
        }
    }
    var contentType: UTType {
        switch self {
        case .jpeg: .jpeg
        case .heic: .heic
        case .png: .png
        }
    }
}

/// Output size for edited exports. Photos are scaled by long edge (never enlarged); videos use a preset.
enum ExportSize: String, CaseIterable, Identifiable, Sendable {
    case full, large, medium, small

    var id: String { rawValue }

    var photoLabel: String {
        switch self {
        case .full: "Full"
        case .large: "12 MP"
        case .medium: "4 MP"
        case .small: "1 MP"
        }
    }

    var videoLabel: String {
        switch self {
        case .full: "Full"
        case .large: "4K"
        case .medium: "1080p"
        case .small: "720p"
        }
    }

    /// Longest side in pixels for photos (nil = keep the original size).
    var photoLongEdge: CGFloat? {
        switch self {
        case .full: nil
        case .large: 4032
        case .medium: 2304
        case .small: 1152
        }
    }

    var videoPreset: String {
        switch self {
        case .full: AVAssetExportPresetHighestQuality
        case .large: AVAssetExportPreset3840x2160
        case .medium: AVAssetExportPreset1920x1080
        case .small: AVAssetExportPreset1280x720
        }
    }
}

struct ExportOptions: Equatable, Sendable {
    var content: ExportContent = .adjusted
    var format: ExportFormat = .jpeg
    var size: ExportSize = .full
    /// Destructively crops the edited copy to the current viewfinder framing.
    var cropToFraming = false
    /// Draws the visible composition guides into the edited copy.
    var burnOverlays = false
    /// Fits the edited photo into a 9:16 frame over a blurred, darkened copy of itself (photos only).
    var storyFill = false
    /// Frame and date stamp for the finished copy (edited photos only; the original never changes).
    var finish = FinishSettings()
    /// Leaves GPS location out of the edited copy's metadata (the original keeps it).
    var removeLocation = false
}

struct OverlayBurnIn: Equatable, Sendable {
    var gridDivisions: Int?
    var center = false
    var isEmpty: Bool { gridDivisions == nil && !center }
}

struct ExportRequest: Sendable {
    let data: Data
    let typeIdentifier: String?
    let adjustments: PhotoAdjustmentState
    let options: ExportOptions
    /// 0...1 top-left-origin rect, nil = whole image.
    let normalizedCrop: CGRect?
    let overlays: OverlayBurnIn
    /// Custom Background Swap photo, if one is chosen.
    var backgroundPhoto: CIImage? = nil
}

enum PhotoExportError: LocalizedError {
    case decodeFailed, renderFailed, writeFailed

    var errorDescription: String? {
        switch self {
        case .decodeFailed: "The original photo couldn't be read for export."
        case .renderFailed: "The edited copy couldn't be rendered. Try JPEG, or export the original."
        case .writeFailed: "The exported file couldn't be saved. Check available storage."
        }
    }
}

/// Writes exports to a private temporary folder for the share sheet.
/// Never modifies the original and never adds or forges capture metadata.
struct PhotoExportService: Sendable {
    var processor: ImageProcessingService = .shared
    var directory = FileManager.default.temporaryDirectory.appendingPathComponent("Exports", isDirectory: true)

    static func fileName(content: ExportContent, fileExtension: String, date: Date = .now) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let kind = content == .original ? "Original" : "Edited"
        return "CameraGlass-\(kind)-\(formatter.string(from: date)).\(fileExtension)"
    }

    func export(_ request: ExportRequest) async throws -> URL {
        try await Task.detached(priority: .userInitiated) {
            try exportSynchronously(request)
        }.value
    }

    /// Empties the export folder (only the latest export is kept on disk) and recreates it.
    func prepareDirectory() throws {
        let fileManager = FileManager.default
        try? fileManager.removeItem(at: directory)
        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            throw PhotoExportError.writeFailed
        }
    }

    func exportSynchronously(_ request: ExportRequest) throws -> URL {
        try prepareDirectory()

        let data: Data
        let fileExtension: String
        switch request.options.content {
        case .original:
            // Byte-for-byte copy of what the user imported.
            data = request.data
            fileExtension = request.typeIdentifier.flatMap { UTType($0)?.preferredFilenameExtension } ?? "jpg"
        case .adjusted:
            data = try renderAdjusted(request)
            fileExtension = request.options.format.fileExtension
        }

        let url = directory.appendingPathComponent(
            Self.fileName(content: request.options.content, fileExtension: fileExtension))
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            throw PhotoExportError.writeFailed
        }
        return url
    }

    func renderAdjusted(_ request: ExportRequest) throws -> Data {
        guard let source = CIImage(data: request.data, options: [.applyOrientationProperty: true]) else {
            throw PhotoExportError.decodeFailed
        }
        var image = processor.apply(request.adjustments, to: source, backgroundPhoto: request.backgroundPhoto)
        if let crop = request.normalizedCrop {
            image = Self.crop(image, normalized: crop)
        }
        image = Self.burnOverlays(request.overlays, into: image)
        if !request.options.finish.isEmpty {
            image = FinishingRenderer.finish(image, settings: request.options.finish, metadata: CaptureMetadata(data: request.data),
                                             context: processor.context)
        }
        if request.options.storyFill { image = Self.storyFill(image) }
        image = Self.resized(image, longEdge: request.options.size.photoLongEdge)
        image = image.settingProperties(Self.carriedMetadata(source.properties, removeLocation: request.options.removeLocation))
        // The photo's own color space, so wide-gamut (Display P3) colors survive.
        return try processor.encode(image, as: request.options.format, colorSpace: source.colorSpace)
    }

    /// The original's capture metadata for the edited copy: camera, exposure and date stay; orientation is reset
    /// (the pixels are already upright), stale pixel sizes are dropped, and location goes if asked.
    static func carriedMetadata(_ properties: [String: Any], removeLocation: Bool) -> [String: Any] {
        var props: [String: Any] = [:]
        for key in [kCGImagePropertyExifDictionary, kCGImagePropertyTIFFDictionary, kCGImagePropertyIPTCDictionary,
                    kCGImagePropertyExifAuxDictionary, kCGImagePropertyGPSDictionary] as [CFString] {
            if let value = properties[key as String] { props[key as String] = value }
        }
        if removeLocation { props[kCGImagePropertyGPSDictionary as String] = nil }
        if var exif = props[kCGImagePropertyExifDictionary as String] as? [String: Any] {
            exif[kCGImagePropertyExifPixelXDimension as String] = nil
            exif[kCGImagePropertyExifPixelYDimension as String] = nil
            props[kCGImagePropertyExifDictionary as String] = exif
        }
        if var tiff = props[kCGImagePropertyTIFFDictionary as String] as? [String: Any] {
            tiff[kCGImagePropertyTIFFOrientation as String] = 1
            props[kCGImagePropertyTIFFDictionary as String] = tiff
        }
        props[kCGImagePropertyOrientation as String] = 1
        return props
    }

    /// Scales down (high-quality Lanczos) so the longest side is at most `longEdge`; never enlarges.
    static func resized(_ image: CIImage, longEdge: CGFloat?) -> CIImage {
        let extent = image.extent
        guard let longEdge, max(extent.width, extent.height) > longEdge else { return image }
        let scale = longEdge / max(extent.width, extent.height)
        let filter = CIFilter.lanczosScaleTransform()
        filter.inputImage = image
        filter.scale = Float(scale)
        filter.aspectRatio = 1
        guard let output = filter.outputImage else { return image }
        let target = CGRect(x: output.extent.minX, y: output.extent.minY,
                            width: (extent.width * scale).rounded(), height: (extent.height * scale).rounded())
        // Clamped: Lanczos can leave the last row a fraction short of the rounded size.
        return output.clampedToExtent().cropped(to: target).transformed(by: CGAffineTransform(translationX: -target.minX, y: -target.minY))
    }

    /// 9:16 canvas: the whole photo centered over a blurred, slightly darker copy that fills the frame.
    /// No bars, text or borders; a photo already at 9:16 comes back unchanged.
    static func storyFill(_ image: CIImage) -> CIImage {
        let e = image.extent
        guard e.width > 0, e.height > 0 else { return image }
        let ratio: CGFloat = 9.0 / 16.0
        guard abs(e.width / e.height - ratio) > 0.005 else { return image }
        let canvas = e.width / e.height > ratio
            ? CGSize(width: e.width.rounded(), height: (e.width / ratio).rounded())
            : CGSize(width: (e.height * ratio).rounded(), height: e.height.rounded())
        let frame = CGRect(origin: .zero, size: canvas)
        let photo = image.transformed(by: CGAffineTransform(translationX: -e.minX, y: -e.minY))

        // Blur a small copy (fast at any size), then scale it up to cover the canvas.
        let small: CGFloat = 360 / max(e.width, e.height)
        let cover = max(canvas.width / e.width, canvas.height / e.height)
        let blurred = photo.transformed(by: CGAffineTransform(scaleX: small, y: small))
            .clampedToExtent()
            .applyingGaussianBlur(sigma: 14)
            .applyingFilter("CIExposureAdjust", parameters: [kCIInputEVKey: -0.6])
            .transformed(by: CGAffineTransform(scaleX: cover / small, y: cover / small))
        let backdrop = blurred.transformed(by: CGAffineTransform(
            translationX: (canvas.width - e.width * cover) / 2, y: (canvas.height - e.height * cover) / 2))
            .cropped(to: frame)

        let centered = photo.transformed(by: CGAffineTransform(
            translationX: ((canvas.width - e.width) / 2).rounded(), y: ((canvas.height - e.height) / 2).rounded()))
        return centered.composited(over: backdrop).cropped(to: frame)
    }

    /// Crops with a top-left-origin normalized rect and moves the result to the origin.
    static func crop(_ image: CIImage, normalized rect: CGRect) -> CIImage {
        let extent = image.extent
        let target = CGRect(
            x: extent.minX + rect.minX * extent.width,
            y: extent.minY + (1 - rect.maxY) * extent.height, // Core Image is bottom-left origin
            width: rect.width * extent.width,
            height: rect.height * extent.height
        ).integral.intersection(extent)
        guard !target.isEmpty else { return image }
        return image.cropped(to: target)
            .transformed(by: CGAffineTransform(translationX: -target.minX, y: -target.minY))
    }

    static func burnOverlays(_ overlays: OverlayBurnIn, into image: CIImage) -> CIImage {
        guard !overlays.isEmpty else { return image }
        let extent = image.extent
        let thickness = max(2, min(extent.width, extent.height) / 600)
        var rects: [CGRect] = []

        if let divisions = overlays.gridDivisions, divisions > 1 {
            for index in 1..<divisions {
                let fraction = CGFloat(index) / CGFloat(divisions)
                let x = extent.minX + extent.width * fraction
                let y = extent.minY + extent.height * fraction
                rects.append(CGRect(x: x - thickness / 2, y: extent.minY, width: thickness, height: extent.height))
                rects.append(CGRect(x: extent.minX, y: y - thickness / 2, width: extent.width, height: thickness))
            }
        }
        if overlays.center {
            let arm = min(extent.width, extent.height) * 0.04
            rects.append(CGRect(x: extent.midX - arm, y: extent.midY - thickness / 2, width: arm * 2, height: thickness))
            rects.append(CGRect(x: extent.midX - thickness / 2, y: extent.midY - arm, width: thickness, height: arm * 2))
        }

        let line = CIImage(color: CIColor(red: 1, green: 1, blue: 1, alpha: 0.7))
        return rects.reduce(image) { line.cropped(to: $1).composited(over: $0) }
    }
}
