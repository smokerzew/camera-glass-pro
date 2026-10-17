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

    func testLivePhotoUsesTheWholeRange() async throws {
        // A 2-second source must produce a 2-second Live Photo movie, not a 3-second-capped slice.
        let source = try await VideoPipelineTests.makeTestMovie(frames: 60)
        let twoSeconds = CMTimeRange(start: .zero, duration: CMTime(seconds: 2, preferredTimescale: 600))
        let pair = try await LiveEffectsService.makeLivePhoto(
            from: AVURLAsset(url: source), range: twoSeconds, keyTime: CMTime(seconds: 1, preferredTimescale: 600),
            adjustments: PhotoAdjustmentState(), processor: .shared)
        let duration = try await AVURLAsset(url: pair.video).load(.duration).seconds
        XCTAssertEqual(duration, 2, accuracy: 0.1)
    }

    func testLivePhotoSoundSwitch() async throws {
        let source = try await VideoPipelineTests.makeTestMovie(frames: 30, withAudio: true)
        let sourceAudio = try await AVURLAsset(url: source).loadTracks(withMediaType: .audio)
        XCTAssertEqual(sourceAudio.count, 1, "test movie has a sound track")

        let key = CMTime(seconds: 0.5, preferredTimescale: 600)
        let withSound = try await LiveEffectsService.makeLivePhoto(
            from: AVURLAsset(url: source), range: oneSecond, keyTime: key,
            adjustments: PhotoAdjustmentState(), processor: .shared, includeAudio: true)
        let silent = try await LiveEffectsService.makeLivePhoto(
            from: AVURLAsset(url: source), range: oneSecond, keyTime: key,
            adjustments: PhotoAdjustmentState(), processor: .shared, includeAudio: false)

        let soundTracks = try await AVURLAsset(url: withSound.video).loadTracks(withMediaType: .audio)
        let silentTracks = try await AVURLAsset(url: silent.video).loadTracks(withMediaType: .audio)
        XCTAssertEqual(soundTracks.count, 1, "sound on keeps the audio")
        XCTAssertEqual(silentTracks.count, 0, "sound off saves a silent Live Photo")
        let duration = try await AVURLAsset(url: withSound.video).load(.duration).seconds
        XCTAssertEqual(duration, 1, accuracy: 0.15)
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
