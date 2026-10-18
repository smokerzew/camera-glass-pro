import AVFoundation
import CoreImage
import ImageIO
import XCTest
@testable import CameraGlassPro

final class Pack4Tests: XCTestCase {
    private let processor = ImageProcessingService.shared
    private let extent = CGRect(x: 0, y: 0, width: 300, height: 200)
    private let oneSecond = CMTimeRange(start: .zero, duration: CMTime(seconds: 1, preferredTimescale: 600))

    private func png(_ image: CIImage) -> Data? {
        processor.context.pngRepresentation(of: image, format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!)
    }

    /// Colored blocks, so geometric effects (kaleidoscope, fisheye, 3D) have something to move.
    private var scene: CIImage {
        CIImage(color: CIColor(red: 0.9, green: 0.3, blue: 0.2)).cropped(to: CGRect(x: 40, y: 30, width: 90, height: 120))
            .composited(over: CIImage(color: CIColor(red: 0.2, green: 0.5, blue: 0.8)).cropped(to: CGRect(x: 170, y: 60, width: 80, height: 80)))
            .composited(over: CIImage(color: CIColor(red: 0.5, green: 0.5, blue: 0.45)).cropped(to: extent))
    }

    func testNewFilterTabs() {
        for category in [FilterCategory.street, .neon, .pastel, .earth, .lux] {
            XCTAssertEqual(category.filters.count, 10, "\(category)")
        }
        XCTAssertEqual(FilterCategory.lux.title, "Lux")
        XCTAssertEqual(PhotoFilter.streetNoir.category, .street)
    }

    func testNewStylesChangeThePhoto() {
        let input = scene
        let new: [PhotographicStyle] = [.sunset, .honey, .peach, .softPink, .lavender, .mint, .ocean, .emerald, .punchy, .faded]
        XCTAssertEqual(PhotographicStyle.allCases.count, 26)
        for style in new {
            var state = PhotoAdjustmentState()
            state.style = style
            let output = processor.apply(state, to: input)
            XCTAssertEqual(output.extent, input.extent)
            XCTAssertNotEqual(png(output), png(input), "\(style) does nothing")
        }
    }

    func testEveryPopEffectRenders() {
        let input = scene
        for effect in PopEffect.allCases where effect != .none {
            var state = PhotoAdjustmentState()
            state.pop = effect
            state.popAmount = 1
            let output = processor.apply(state, to: input)
            XCTAssertEqual(output.extent, input.extent, "\(effect) changed the size")
            XCTAssertNotEqual(png(output), png(input), "\(effect) does nothing")
        }
        var off = PhotoAdjustmentState()
        off.pop = .glitch
        XCTAssertEqual(png(processor.apply(off, to: input)), png(input), "amount 0 is off")
    }

    func testPopOptionsResetAndShuffle() {
        XCTAssertEqual(PopEffect.kaleidoscopeSegments(0), 3)
        XCTAssertEqual(PopEffect.kaleidoscopeSegments(1), 12)
        XCTAssertEqual(PopEffect.duotoneIndex(1), PopEffect.duotoneNames.count - 1)
        var state = PhotoAdjustmentState()
        state.pop = .comic
        state.popAmount = 0.7
        state.glow = 0.5
        let reset = state.resetting(.fxPop)
        XCTAssertEqual(reset.pop, PopEffect.none)
        XCTAssertEqual(reset.glow, 0.5, "only its own page")
        var rng = SplitMix64(seed: 4)
        let shuffled = PhotoAdjustmentState().shuffling(.fxPop, using: &rng)
        XCTAssertNotEqual(shuffled?.pop, PopEffect.none)
        XCTAssertGreaterThan(shuffled?.popAmount ?? 0, 0)
        // Survives saving.
        let decoded = try? JSONDecoder().decode(PhotoAdjustmentState.self, from: JSONEncoder().encode(state))
        XCTAssertEqual(decoded?.pop, .comic)
    }

    func testNewVideoSequences() {
        let forward = LiveEffectsService.frameTimes(in: oneSecond)
        XCTAssertEqual(LiveEffectsService.sequence(for: .reverse, in: oneSecond), Array(forward.reversed()))
        let stop = LiveEffectsService.sequence(for: .stopMotion, in: oneSecond)
        XCTAssertEqual(stop.count, forward.count)
        XCTAssertEqual(stop[0], stop[3], "each picture is held")
        XCTAssertNotEqual(stop[3], stop[4])
        let ramp = LiveEffectsService.sequence(for: .speedRamp, in: oneSecond)
        let startStep = ramp[1].seconds - ramp[0].seconds
        let middle = ramp.count / 2
        let middleStep = ramp[middle + 1].seconds - ramp[middle].seconds
        XCTAssertLessThan(middleStep, startStep / 2, "slow motion in the middle")
    }

    func testEchoMovieAndGIF() async throws {
        let source = try await VideoPipelineTests.makeTestMovie(frames: 30)
        let asset = AVURLAsset(url: source)
        let url = try LiveEffectsService.newURL("mov")
        try await LiveEffectsService.renderMovie(from: asset, times: LiveEffectsService.sequence(for: .echo, in: oneSecond),
                                                 adjustments: PhotoAdjustmentState(), processor: .shared, to: url, echo: true)
        let duration = try await AVURLAsset(url: url).load(.duration).seconds
        XCTAssertEqual(duration, 1, accuracy: 0.15)

        let gif = try await LiveEffectsService.gif(from: asset, range: oneSecond, adjustments: PhotoAdjustmentState(), processor: .shared)
        let image = try XCTUnwrap(CGImageSourceCreateWithData(gif as CFData, nil))
        XCTAssertEqual(CGImageSourceGetType(image) as String?, "com.compuserve.gif")
        XCTAssertGreaterThan(CGImageSourceGetCount(image), 8)
    }
}
