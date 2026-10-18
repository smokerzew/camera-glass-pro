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
    /// EXIF orientation equivalent of the track's preferred transform (1 = upright).
    var exifOrientation: Int32 = 1

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

/// The live adjustment recipe (and display-only focus peaking) read by the video compositor on its own thread.
final class AdjustmentBox: @unchecked Sendable {
    private let lock = NSLock()
    private var stored = PhotoAdjustmentState()
    private var storedPeaking = false
    private var storedZebras = false
    private var storedBackground: CIImage?
    private var storedPlayback = false
    private var storedTimeMapping: (start: Double, speed: Double) = (0, 1)
    private var lastMask: (time: Double, scale: CGFloat, mask: CIImage?)?
    private var lastFaces: (time: Double, scale: CGFloat, faces: [CGRect])?

    var value: PhotoAdjustmentState {
        get { lock.withLock { stored } }
        set { lock.withLock { stored = newValue } }
    }

    var peaking: Bool {
        get { lock.withLock { storedPeaking } }
        set { lock.withLock { storedPeaking = newValue } }
    }

    var zebras: Bool {
        get { lock.withLock { storedZebras } }
        set { lock.withLock { storedZebras = newValue } }
    }

    /// True for the live player: frames render at a lighter resolution and reuse the subject mask briefly,
    /// so playback stays smooth. Exports leave it off and render every frame at full quality.
    var playback: Bool {
        get { lock.withLock { storedPlayback } }
        set { lock.withLock { storedPlayback = newValue } }
    }

    /// The subject mask found for a nearby frame (playback only), or nil when a new one is needed.
    func cachedMask(at time: Double, scale: CGFloat) -> CIImage?? {
        lock.withLock {
            guard let last = lastMask, last.scale == scale, abs(last.time - time) < 0.12 else { return nil }
            return .some(last.mask)
        }
    }

    func storeMask(_ mask: CIImage?, at time: Double, scale: CGFloat) {
        lock.withLock { lastMask = (time, scale, mask) }
    }

    /// Face boxes found for a nearby frame (playback only), or nil when they need finding again.
    func cachedFaces(at time: Double, scale: CGFloat) -> [CGRect]? {
        lock.withLock {
            guard let last = lastFaces, last.scale == scale, abs(last.time - time) < 0.12 else { return nil }
            return last.faces
        }
    }

    func storeFaces(_ faces: [CGRect], at time: Double, scale: CGFloat) {
        lock.withLock { lastFaces = (time, scale, faces) }
    }

    /// How composition time maps to the original video's time (an export can be trimmed and re-timed),
    /// so CINEMATIC focus points land on the right frames.
    var timeMapping: (start: Double, speed: Double) {
        get { lock.withLock { storedTimeMapping } }
        set { lock.withLock { storedTimeMapping = newValue } }
    }

    func sourceTime(_ compositionTime: Double) -> Double {
        let map = timeMapping
        return map.start + compositionTime * map.speed
    }

    /// Custom Background Swap photo (nil = none).
    var backgroundPhoto: CIImage? {
        get { lock.withLock { storedBackground } }
        set { lock.withLock { storedBackground = newValue } }
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
            typeIdentifier: UTType(filenameExtension: url.pathExtension)?.identifier,
            exifOrientation: exifOrientation(for: transform)
        )
    }

    /// The source as-is, or a composition holding just `timeRange`, scaled to `speed`.
    static func retimedAsset(_ source: AVAsset, timeRange: CMTimeRange?, speed: Double) async throws -> AVAsset {
        guard timeRange != nil || speed != 1 else { return source }
        let duration = try await source.load(.duration)
        let range = timeRange ?? CMTimeRange(start: .zero, duration: duration)
        let composition = AVMutableComposition()
        let types: [AVMediaType] = speed == 1 ? [.video, .audio] : [.video]
        for type in types {
            for track in try await source.loadTracks(withMediaType: type) {
                guard let copy = composition.addMutableTrack(withMediaType: type, preferredTrackID: kCMPersistentTrackID_Invalid) else { continue }
                try copy.insertTimeRange(range, of: track, at: .zero)
                if type == .video { copy.preferredTransform = try await track.load(.preferredTransform) }
            }
        }
        if speed != 1, speed > 0 {
            composition.scaleTimeRange(
                CMTimeRange(start: .zero, duration: range.duration),
                toDuration: CMTimeMultiplyByFloat64(range.duration, multiplier: 1 / speed)
            )
        }
        return composition
    }

    /// Maps a track's rotation to the EXIF orientation that turns its frames upright.
    static func exifOrientation(for transform: CGAffineTransform) -> Int32 {
        let degrees = Int((atan2(transform.b, transform.a) * 180 / .pi).rounded())
        switch degrees {
        case 90: return 6
        case -90: return 8
        case 180, -180: return 3
        default: return 1
        }
    }

    /// Removes video copies left behind by earlier launches (call once at launch).
    static func purgeStaleCopies() {
        try? FileManager.default.removeItem(at: directory)
    }

    /// Core Image composition that applies the shared adjustment pipeline to every frame.
    /// The recipe is read per frame, so slider changes show up live during playback.
    static func composition(
        for asset: AVAsset,
        recipe: AdjustmentBox,
        processor: ImageProcessingService
    ) async throws -> AVVideoComposition {
        try await AVMutableVideoComposition.videoComposition(with: asset) { request in
            let edit = recipe.value.withoutGeometry
            let full = request.sourceImage.extent
            // Live playback renders at a lighter size (lighter still for heavy effects) and scales back up;
            // exports render every frame at full size.
            var scale: CGFloat = 1
            if recipe.playback, !edit.isIdentity {
                let limit: CGFloat = edit.isHeavy ? 900 : 1280
                scale = min(1, limit / max(full.width, full.height, 1))
            }
            let source = scale < 1
                ? request.sourceImage.transformed(by: CGAffineTransform(translationX: -full.minX, y: -full.minY)
                    .concatenating(CGAffineTransform(scaleX: scale, y: scale)))
                : request.sourceImage
            // Subject mask: found once and reused for neighbouring frames while playing (it barely moves in 0.1 s).
            var mask: CIImage?
            if edit.needsSubject {
                let time = request.compositionTime.seconds
                if recipe.playback, let cached = recipe.cachedMask(at: time, scale: scale) {
                    mask = cached
                } else {
                    // CINEMATIC: the focus point's subject (or the background), racking between points.
                    mask = edit.portrait && !edit.cinematicFocus.isEmpty
                        ? SubjectMasker.cinematicMask(for: source, keys: edit.cinematicFocus, at: recipe.sourceTime(time))
                        : SubjectMasker.mask(for: source, fast: true)
                    if recipe.playback { recipe.storeMask(mask, at: time, scale: scale) }
                }
            }
            // Face boxes (face blur / pixelate, skin smoothing): found once and reused for nearby frames while playing.
            var faces: [CGRect]?
            let wantsFaces = (edit.redactionTarget == .faces && edit.faceRedaction != .none) || edit.skinSmoothing > 0
            if recipe.playback, wantsFaces {
                let time = request.compositionTime.seconds
                if let cached = recipe.cachedFaces(at: time, scale: scale) {
                    faces = cached
                } else {
                    let found = ImageProcessingService.faceRects(in: source, extent: source.extent)
                    recipe.storeFaces(found, at: time, scale: scale)
                    faces = found
                }
            }
            let recipeForFrame = edit.needsSubject && mask == nil ? edit.withoutSubjectEdits : edit
            var output = processor.apply(recipeForFrame, to: source, subjectMask: mask, fastMask: true,
                                         backgroundPhoto: recipe.backgroundPhoto, faces: faces)
            if scale < 1 {
                output = output.transformed(by: CGAffineTransform(scaleX: 1 / scale, y: 1 / scale)
                    .concatenating(CGAffineTransform(translationX: full.minX, y: full.minY))).cropped(to: full)
            }
            let peaking = recipe.peaking, zebras = recipe.zebras
            if peaking || zebras {
                output = processor.analysisOverlay(for: output, peaking: peaking, zebras: zebras).composited(over: output)
            }
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

    /// Full-quality edited copy with the adjustments baked in, optionally trimmed and re-timed.
    /// `speed` < 1 slows down (SLO-MO), > 1 speeds up (TIME-LAPSE); audio is kept only at 1×.
    static func exportEdited(
        _ video: ImportedVideo,
        adjustments: PhotoAdjustmentState,
        processor: ImageProcessingService,
        to url: URL,
        timeRange: CMTimeRange? = nil,
        speed: Double = 1,
        preset: String = AVAssetExportPresetHighestQuality,
        backgroundPhoto: CIImage? = nil
    ) async throws {
        let asset = try await retimedAsset(video.asset, timeRange: timeRange, speed: speed)
        let recipe = AdjustmentBox()
        recipe.value = adjustments
        recipe.backgroundPhoto = backgroundPhoto
        recipe.timeMapping = (timeRange?.start.seconds ?? 0, speed)
        let composition = try await composition(for: asset, recipe: recipe, processor: processor)
        guard let session = AVAssetExportSession(asset: asset, presetName: preset) else {
            throw PhotoExportError.renderFailed
        }
        session.videoComposition = composition
        try await session.export(to: url, as: .mov)
    }
}
