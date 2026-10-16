import Foundation
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

/// An imported photo. `data` is the untouched original file; `preview` is a downsampled,
/// orientation-corrected copy used for display and live adjustments.
struct ImportedPhoto: Identifiable {
    let id = UUID()
    let data: Data
    let preview: CGImage
    let pixelSize: CGSize
    let typeIdentifier: String?

    var previewSize: CGSize { CGSize(width: preview.width, height: preview.height) }

    var formatLabel: String {
        guard let identifier = typeIdentifier, let type = UTType(identifier) else { return "IMAGE" }
        if type.conforms(to: .heic) || type.conforms(to: .heif) { return "HEIC" }
        if type.conforms(to: .jpeg) { return "JPEG" }
        return type.preferredFilenameExtension?.uppercased() ?? "IMAGE"
    }

    var megapixels: Double { pixelSize.width * pixelSize.height / 1_000_000 }
}

enum PhotoImportError: LocalizedError, Equatable {
    case loadFailed
    case unsupportedData
    case tooLarge
    case fileAccessDenied
    case cancelled

    var errorDescription: String? {
        switch self {
        case .loadFailed: "The photo couldn't be loaded. If it's stored in iCloud, check your connection and try again."
        case .unsupportedData: "This file isn't an image format the app can read."
        case .tooLarge: "This image is too large to edit safely on this device."
        case .fileAccessDenied: "The app wasn't given permission to read that file."
        case .cancelled: "Import cancelled."
        }
    }

    /// Maps any thrown error to a user-facing case; internal details are never shown.
    static func map(_ error: Error) -> PhotoImportError {
        if let error = error as? PhotoImportError { return error }
        if error is CancellationError { return .cancelled }
        let nsError = error as NSError
        if nsError.domain == NSCocoaErrorDomain {
            switch nsError.code {
            case NSUserCancelledError: return .cancelled
            case NSFileReadNoPermissionError: return .fileAccessDenied
            case NSFileReadCorruptFileError, NSFileReadUnknownStringEncodingError: return .unsupportedData
            default: break
            }
        }
        return .loadFailed
    }
}

protocol PhotoImporting: Sendable {
    func loadImage(from item: PhotosPickerItem) async throws -> ImportedPhoto
    func loadImage(from url: URL) async throws -> ImportedPhoto
}

struct PhotoImportService: PhotoImporting {
    var maxPreviewPixelSize = 2400
    var maxSourcePixels: Double = 250_000_000

    func loadImage(from item: PhotosPickerItem) async throws -> ImportedPhoto {
        // The system picker downloads iCloud originals as needed; no library permission is requested.
        guard let data = try await item.loadTransferable(type: Data.self) else {
            throw PhotoImportError.loadFailed
        }
        try Task.checkCancellation()
        return try await decode(data)
    }

    func loadImage(from url: URL) async throws -> ImportedPhoto {
        let data = try await Task.detached(priority: .userInitiated) {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            return try Data(contentsOf: url)
        }.value
        try Task.checkCancellation()
        return try await decode(data)
    }

    private func decode(_ data: Data) async throws -> ImportedPhoto {
        let maxPixel = maxPreviewPixelSize
        let maxSource = maxSourcePixels
        let output = try await Task.detached(priority: .userInitiated) {
            try ImageDownsampler.makePreview(from: data, maxPixelSize: maxPixel, maxSourcePixels: maxSource)
        }.value
        return ImportedPhoto(data: data, preview: output.preview, pixelSize: output.pixelSize,
                             typeIdentifier: output.typeIdentifier)
    }
}
