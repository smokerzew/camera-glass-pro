import AVFoundation
import XCTest
@testable import CameraGlassPro

final class VideoPipelineTests: XCTestCase {
    /// Writes a short gray H.264 movie so the video path can be tested without fixtures.
    static func makeTestMovie(frames: Int = 12, width: Int = 64, height: Int = 48) async throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mov")
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
        ])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
        ])
        writer.add(input)
        XCTAssertTrue(writer.startWriting())
        writer.startSession(atSourceTime: .zero)
        let pool = try XCTUnwrap(adaptor.pixelBufferPool)

        for index in 0..<frames {
            while !input.isReadyForMoreMediaData { try await Task.sleep(for: .milliseconds(5)) }
            var buffer: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer)
            let pixels = try XCTUnwrap(buffer)
            CVPixelBufferLockBaseAddress(pixels, [])
            if let base = CVPixelBufferGetBaseAddress(pixels) {
                memset(base, 128, CVPixelBufferGetBytesPerRow(pixels) * height)
            }
            CVPixelBufferUnlockBaseAddress(pixels, [])
            XCTAssertTrue(adaptor.append(pixels, withPresentationTime: CMTime(value: CMTimeValue(index), timescale: 30)))
        }
        input.markAsFinished()
        await writer.finishWriting()
        XCTAssertEqual(writer.status, .completed, "test movie couldn't be written: \(String(describing: writer.error))")
        return url
    }

    func testTypeDetection() {
        XCTAssertTrue(VideoService.isVideo(.quickTimeMovie))
        XCTAssertTrue(VideoService.isVideo(.mpeg4Movie))
        XCTAssertFalse(VideoService.isVideo(.jpeg))
        XCTAssertFalse(VideoService.isVideo(nil))
    }

    func testAdjustmentBoxRoundTrips() {
        let box = AdjustmentBox()
        var state = PhotoAdjustmentState()
        state.filter = .noir
        box.value = state
        XCTAssertEqual(box.value, state)
    }

    func testLoadFrameAndEditedExport() async throws {
        let source = try await Self.makeTestMovie()
        let video = try await VideoService.load(localURL: VideoService.makeLocalCopy(of: source))
        XCTAssertEqual(video.displaySize, CGSize(width: 64, height: 48))
        XCTAssertGreaterThan(video.duration, 0)
        XCTAssertEqual(video.poster.width, 64)

        var adjustments = PhotoAdjustmentState()
        adjustments.exposure = 0.5
        adjustments.filter = .mono
        let recipe = AdjustmentBox()
        recipe.value = adjustments
        let composition = try await VideoService.composition(for: video.asset, recipe: recipe, processor: .shared)
        let frame = try await VideoService.frame(of: video.asset, at: .zero, composition: composition)
        XCTAssertEqual(frame.width, 64)

        let output = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mov")
        try await VideoService.exportEdited(video, adjustments: adjustments, processor: .shared, to: output)
        let tracks = try await AVURLAsset(url: output).loadTracks(withMediaType: .video)
        XCTAssertEqual(tracks.count, 1)
    }
}

@MainActor
final class DepthTagTests: XCTestCase {
    func testDepthTagShowsThenFades() async throws {
        let name = "DepthTagTests-\(UUID().uuidString)"
        let vm = CameraWorkspaceViewModel(defaults: UserDefaults(suiteName: name) ?? .standard)
        vm.setDepth(true)
        XCTAssertTrue(vm.depthEffect)
        XCTAssertEqual(vm.depthTag, "PORTRAIT")
        vm.setDepth(false)
        XCTAssertEqual(vm.depthTag, "PORTRAIT OFF")
        try await Task.sleep(for: .seconds(2))
        XCTAssertNil(vm.depthTag, "the tag should fade out on its own")
    }
}
