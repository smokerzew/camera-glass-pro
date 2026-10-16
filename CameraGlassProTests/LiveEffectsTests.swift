import AVFoundation
import ImageIO
import XCTest
@testable import CameraGlassPro

final class LiveEffectsTests: XCTestCase {
    private let oneSecond = CMTimeRange(start: .zero, duration: CMTime(seconds: 1, preferredTimescale: 600))

    func testLoopAndBounceSequences() {
        XCTAssertEqual(LiveEffectsService.frameTimes(in: oneSecond).count, 30)
        XCTAssertEqual(LiveEffectsService.sequence(for: .loop, in: oneSecond).count, 90)
        let bounce = LiveEffectsService.sequence(for: .bounce, in: oneSecond)
        XCTAssertEqual(bounce.count, (30 + 28) * 2)
        XCTAssertEqual(bounce[30], LiveEffectsService.frameTimes(in: oneSecond)[28], "turns around without repeating the last frame")
    }

    func testLivePhotoWindowStaysInside() {
        let ten = CMTimeRange(start: .zero, duration: CMTime(seconds: 10, preferredTimescale: 600))
        let early = LiveEffectsService.livePhotoRange(center: 1, available: ten)
        XCTAssertEqual(early.start.seconds, 0, accuracy: 0.01)
        XCTAssertEqual(early.duration.seconds, 3, accuracy: 0.01)
        let late = LiveEffectsService.livePhotoRange(center: 9.5, available: ten)
        XCTAssertEqual(late.end.seconds, 10, accuracy: 0.01)
        let short = CMTimeRange(start: .zero, duration: CMTime(seconds: 2, preferredTimescale: 600))
        XCTAssertEqual(LiveEffectsService.livePhotoRange(center: 1, available: short).duration.seconds, 2, accuracy: 0.01)
    }

    func testBounceMovieLength() async throws {
        let source = try await VideoPipelineTests.makeTestMovie(frames: 30)
        let asset = AVURLAsset(url: source)
        let url = try LiveEffectsService.newURL("mov")
        try await LiveEffectsService.renderMovie(
            from: asset, times: LiveEffectsService.sequence(for: .bounce, in: oneSecond),
            adjustments: PhotoAdjustmentState(), processor: .shared, to: url)
        let duration = try await AVURLAsset(url: url).load(.duration).seconds
        XCTAssertEqual(duration, Double((30 + 28) * 2) / 30, accuracy: 0.15)
    }

    func testLongExposureProducesAPhoto() async throws {
        let source = try await VideoPipelineTests.makeTestMovie(frames: 30)
        let data = try await LiveEffectsService.longExposure(
            from: AVURLAsset(url: source), range: oneSecond, adjustments: PhotoAdjustmentState(), processor: .shared)
        let image = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
        XCTAssertEqual(CGImageSourceGetType(image) as String?, "public.jpeg")
        XCTAssertEqual(CGImageSourceGetCount(image), 1)
    }

    func testVideoBecomesPairedLivePhotoFiles() async throws {
        let source = try await VideoPipelineTests.makeTestMovie(frames: 30)
        let pair = try await LiveEffectsService.makeLivePhoto(
            from: AVURLAsset(url: source), range: oneSecond, keyTime: CMTime(seconds: 0.5, preferredTimescale: 600),
            adjustments: PhotoAdjustmentState(), processor: .shared)

        // Still: maker note key 17 holds the pairing identifier.
        let still = try XCTUnwrap(CGImageSourceCreateWithURL(pair.photo as CFURL, nil))
        let properties = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(still, 0, nil) as? [CFString: Any])
        let makerApple = try XCTUnwrap(properties[kCGImagePropertyMakerAppleDictionary] as? [String: Any])
        let photoIdentifier = try XCTUnwrap(makerApple["17"] as? String)

        // Movie: same identifier in its metadata, plus the still-image-time track.
        let movie = AVURLAsset(url: pair.video)
        let metadata = try await movie.load(.metadata)
        var movieIdentifier: String?
        for item in metadata where (item.key as? String) == "com.apple.quicktime.content.identifier" {
            movieIdentifier = try await item.load(.stringValue)
        }
        XCTAssertEqual(movieIdentifier, photoIdentifier)
        let metadataTracks = try await movie.loadTracks(withMediaType: .metadata)
        XCTAssertEqual(metadataTracks.count, 1)
    }

    @MainActor
    func testEffectsNeedMotion() {
        let vm = CameraWorkspaceViewModel(defaults: UserDefaults(suiteName: "Effects-\(UUID().uuidString)") ?? .standard)
        XCTAssertFalse(vm.canMakeEffects)
        XCTAssertFalse(vm.isAvailable(.effects))
        vm.perform(.effects)
        XCTAssertTrue(vm.showEffectsPicker, "opens and explains what's needed")
    }
}
