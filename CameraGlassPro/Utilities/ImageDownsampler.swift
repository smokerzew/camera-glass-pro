import Foundation
import ImageIO

/// Builds an orientation-corrected, memory-friendly preview with ImageIO
/// without decoding the full-resolution bitmap.
enum ImageDownsampler {
    struct Output {
        let preview: CGImage
        /// Oriented full-resolution size of the source.
        let pixelSize: CGSize
        let typeIdentifier: String?
    }

    static func makePreview(from data: Data, maxPixelSize: Int, maxSourcePixels: Double) throws -> Output {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions),
              CGImageSourceGetCount(source) > 0 else {
            throw PhotoImportError.unsupportedData
        }

        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let width = properties?[kCGImagePropertyPixelWidth] as? Int ?? 0
        let height = properties?[kCGImagePropertyPixelHeight] as? Int ?? 0
        let orientation = properties?[kCGImagePropertyOrientation] as? UInt32 ?? 1
        guard width > 0, height > 0 else { throw PhotoImportError.unsupportedData }
        guard Double(width) * Double(height) <= maxSourcePixels else { throw PhotoImportError.tooLarge }

        let thumbnailOptions = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true, // applies EXIF orientation
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ] as CFDictionary
        guard let preview = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions) else {
            throw PhotoImportError.unsupportedData
        }

        let rotated = (5...8).contains(orientation) // EXIF orientations that swap width and height
        return Output(
            preview: preview,
            pixelSize: rotated ? CGSize(width: height, height: width) : CGSize(width: width, height: height),
            typeIdentifier: CGImageSourceGetType(source) as String?
        )
    }
}
