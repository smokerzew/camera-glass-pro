import AVFoundation
import XCTest
@testable import CameraGlassPro

final class VideoPipelineTests: XCTestCase {
    /// Writes a short gray H.264 movie so the video path can be tested without fixtures.
    static func makeTestMovie(frames: Int = 12, width: Int = 64, height: Int = 48, withAudio: Bool = false) async throws -> URL {
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
        // Optional mono 440 Hz tone, one 1470-sample chunk (1/30 s) per video frame, interleaved.
        let sampleRate = 44_100
        let chunk = sampleRate / 30
        var audioInput: AVAssetWriterInput?
        var audioFormat: CMAudioFormatDescription?
        if withAudio {
            let aac = AVAssetWriterInput(mediaType: .audio, outputSettings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: sampleRate, AVNumberOfChannelsKey: 1,
                AVEncoderBitRateKey: 64_000,
            ])
            writer.add(aac)
            audioInput = aac
            var asbd = AudioStreamBasicDescription(
                mSampleRate: Float64(sampleRate), mFormatID: kAudioFormatLinearPCM,
                mFormatFlags: kLinearPCMFormatFlagIsSignedInteger | kLinearPCMFormatFlagIsPacked,
                mBytesPerPacket: 2, mFramesPerPacket: 1, mBytesPerFrame: 2, mChannelsPerFrame: 1,
                mBitsPerChannel: 16, mReserved: 0)
            CMAudioFormatDescriptionCreate(allocator: nil, asbd: &asbd, layoutSize: 0, layout: nil, magicCookieSize: 0,
                                           magicCookie: nil, extensions: nil, formatDescriptionOut: &audioFormat)
        }
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

            if let audioInput, let audioFormat {
                let samples: [Int16] = (0..<chunk).map {
                    Int16(8000 * sin(2 * .pi * 440 * Double(index * chunk + $0) / Double(sampleRate)))
                }
                let bytes = samples.withUnsafeBytes { Data($0) }
                var block: CMBlockBuffer?
                CMBlockBufferCreateWithMemoryBlock(allocator: nil, memoryBlock: nil, blockLength: bytes.count,
                                                   blockAllocator: nil, customBlockSource: nil, offsetToData: 0,
                                                   dataLength: bytes.count, flags: 0, blockBufferOut: &block)
                let blockBuffer = try XCTUnwrap(block)
                bytes.withUnsafeBytes { raw in
                    if let base = raw.baseAddress {
                        CMBlockBufferReplaceDataBytes(with: base, blockBuffer: blockBuffer, offsetIntoDestination: 0, dataLength: bytes.count)
                    }
                }
                var sample: CMSampleBuffer?
                CMAudioSampleBufferCreateReadyWithPacketDescriptions(
                    allocator: nil, dataBuffer: blockBuffer, formatDescription: audioFormat, sampleCount: chunk,
                    presentationTimeStamp: CMTime(value: CMTimeValue(index * chunk), timescale: CMTimeScale(sampleRate)),
                    packetDescriptions: nil, sampleBufferOut: &sample)
                while !audioInput.isReadyForMoreMediaData { try await Task.sleep(for: .milliseconds(5)) }
                audioInput.append(try XCTUnwrap(sample))
            }
        }
        audioInput?.markAsFinished()
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

final class VideoRetimeTests: XCTestCase {
    private func duration(of url: URL) async throws -> Double {
        try await AVURLAsset(url: url).load(.duration).seconds
    }

    func testTrimAndSlowMotionExport() async throws {
        // 30 frames at 30 fps = 1 s source.
        let source = try await VideoPipelineTests.makeTestMovie(frames: 30)
        let video = try await VideoService.load(localURL: VideoService.makeLocalCopy(of: source))
        let half = CMTimeRange(start: .zero, duration: CMTime(seconds: 0.5, preferredTimescale: 600))

        let slow = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mov")
        try await VideoService.exportEdited(video, adjustments: PhotoAdjustmentState(), processor: .shared,
                                            to: slow, timeRange: half, speed: 0.25)
        let slowDuration = try await duration(of: slow)
        XCTAssertEqual(slowDuration, 2.0, accuracy: 0.2, "0.5 s at quarter speed lasts 2 s")

        let fast = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mov")
        try await VideoService.exportEdited(video, adjustments: PhotoAdjustmentState(), processor: .shared,
                                            to: fast, timeRange: nil, speed: 4)
        let fastDuration = try await duration(of: fast)
        XCTAssertEqual(fastDuration, 0.25, accuracy: 0.1, "1 s at 4x lasts a quarter second")
    }

    func testRetimeLeavesSourceAloneWhenUnchanged() async throws {
        let source = try await VideoPipelineTests.makeTestMovie()
        let asset = AVURLAsset(url: source)
        let result = try await VideoService.retimedAsset(asset, timeRange: nil, speed: 1)
        XCTAssertTrue(result === asset)
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
