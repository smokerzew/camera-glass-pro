import AVFoundation
import CoreImage
import Foundation
import SwiftUI
import UniformTypeIdentifiers

/// An imported video. `url` is the app's private copy of the untouched original file.
struct ImportedVideo: Identifiable {
    let id = UUID()
    let url: URL
    let asset: AVURLAsset
    /// First frame, orientation-corrected and downsampled (thumbnail, share preview, ambient).
    let poster: CGImage
    /// Oriented pixel size of the video track.
    let displaySize: CGSize
    let duration: Double
    let typeIdentifier: String?

    var formatLabel: String {
        typeIdentifier.flatMap { UTType($0)?.preferredFilenameExtension?.uppercased() } ?? "MOV"
    }
}

/// Receives a picked video as a file and copies it somewhere the app owns
/// (the picker's file is deleted as soon as the import closure returns).
struct PickedVideoFile: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { SentTransferredFile($0.url) } importing: { received in
            PickedVideoFile(url: try VideoService.makeLocalCopy(of: received.file))
        }
    }
}

/// The live adjustment recipe read by the video compositor on its own thread.
final class AdjustmentBox: @unchecked Sendable {
    private let lock = NSLock()
    private var stored = PhotoAdjustmentState()

    var value: PhotoAdjustmentState {
        get { lock.withLock { stored } }
        set { lock.withLock { stored = newValue } }
    }
}

enum VideoService {
    static let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("ImportedVideos", isDirectory: true)

    static func isVideo(_ type: UTType?) -> Bool {
        guard let type else { return false }
        return type.conforms(to: .movie) || type.conforms(to: .video)
    }

    static func makeLocalCopy(of source: URL) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let ext = source.pathExtension.isEmpty ? "mov" : source.pathExtension
        let destination = directory.appendingPathComponent(UUID().uuidString).appendingPathExtension(ext)
        try FileManager.default.copyItem(at: source, to: destination)
        return destination
    }

    /// Copies a security-scoped Files URL into app storage.
    static func copyFromFiles(_ url: URL) throws -> URL {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        return try makeLocalCopy(of: url)
    }

    static func load(localURL url: URL) async throws -> ImportedVideo {
        let asset = AVURLAsset(url: url)
        guard let track = try await asset.loadTracks(withMediaType: .video).first else {
            throw PhotoImportError.unsupportedData
        }
        let (naturalSize, transform) = try await track.load(.naturalSize, .preferredTransform)
        let oriented = naturalSize.applying(transform)
        let duration = try await asset.load(.duration).seconds

        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 1600, height: 1600)
        let poster = try await generator.image(at: .zero).image

        return ImportedVideo(
            url: url,
            asset: asset,
            poster: poster,
            displaySize: CGSize(width: abs(oriented.width), height: abs(oriented.height)),
            duration: duration.isFinite ? duration : 0,
            typeIdentifier: UTType(filenameExtension: url.pathExtension)?.identifier
        )
    }

    /// Core Image composition that applies the shared adjustment pipeline to every frame.
    /// The recipe is read per frame, so slider changes show up live during playback.
    static func composition(
        for asset: AVAsset,
        recipe: AdjustmentBox,
        processor: ImageProcessingService
    ) async throws -> AVVideoComposition {
        try await AVMutableVideoComposition.videoComposition(with: asset) { request in
            let output = processor.apply(recipe.value, to: request.sourceImage)
            request.finish(with: output, context: processor.context)
        }
    }

    /// Frame at `time` with the composition applied (used for "Save Screen with UI" on videos,
    /// because window snapshots can't see AVPlayerLayer content).
    static func frame(of asset: AVAsset, at time: CMTime, composition: AVVideoComposition?) async throws -> CGImage {
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.videoComposition = composition
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        return try await generator.image(at: time).image
    }

    /// Full-quality edited copy with the adjustments baked in.
    static func exportEdited(
        _ video: ImportedVideo,
        adjustments: PhotoAdjustmentState,
        processor: ImageProcessingService,
        to url: URL
    ) async throws {
        let recipe = AdjustmentBox()
        recipe.value = adjustments
        let composition = try await composition(for: video.asset, recipe: recipe, processor: processor)
        guard let session = AVAssetExportSession(asset: video.asset, presetName: AVAssetExportPresetHighestQuality) else {
            throw PhotoExportError.renderFailed
        }
        session.videoComposition = composition
        try await session.export(to: url, as: .mov)
    }
}
