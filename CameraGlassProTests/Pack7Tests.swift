import CoreImage
import XCTest
@testable import CameraGlassPro

/// Pack 7: background blur and privacy strength mappings, subject region edits, Particle Dissolve.
final class Pack7Tests: XCTestCase {
    private let processor = ImageProcessingService.shared

    /// Green channel (0...255) of every pixel in `rect` (Core Image coordinates).
    private func greens(_ image: CIImage, _ rect: CGRect) -> [Double] {
        let w = Int(rect.width), h = Int(rect.height)
        var p = [UInt8](repeating: 0, count: w * h * 4)
        processor.context.render(image, toBitmap: &p, rowBytes: w * 4, bounds: rect, format: .RGBA8,
                                 colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
        return stride(from: 1, to: p.count, by: 4).map { Double(p[$0]) }
    }

    private func pixels(_ image: CIImage, _ rect: CGRect) -> [(r: Double, g: Double, b: Double)] {
        let w = Int(rect.width), h = Int(rect.height)
        var p = [UInt8](repeating: 0, count: w * h * 4)
        processor.context.render(image, toBitmap: &p, rowBytes: w * 4, bounds: rect, format: .RGBA8,
                                 colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
        return stride(from: 0, to: p.count, by: 4).map { (Double(p[$0]), Double(p[$0 + 1]), Double(p[$0 + 2])) }
    }

    private func spread(_ values: [Double]) -> Double { (values.max() ?? 0) - (values.min() ?? 0) }

    /// Sharp black and white stripes: blur shows as lost contrast.
    private func stripes(_ e: CGRect, width: CGFloat = 6) -> CIImage {
        (CIFilter(name: "CIStripesGenerator", parameters: [
            "inputColor0": CIColor.white, "inputColor1": CIColor.black, "inputWidth": width, "inputSharpness": 1,
        ])?.outputImage ?? CIImage(color: .gray)).cropped(to: e)
    }

    // MARK: Background blur

    func testBackgroundBlurStartsAtNothingAndGrowsSmoothly() {
        XCTAssertEqual(BackgroundBlurKind.curve(0), 0)
        XCTAssertEqual(BackgroundBlurKind.curve(0.1), 0.01, accuracy: 1e-9)
        XCTAssertEqual(BackgroundBlurKind.curve(1), 1)
        let e = CGRect(x: 0, y: 0, width: 600, height: 300)
        let source = stripes(e)
        // Off-center, where zoom and spin streak across the stripes.
        let row = CGRect(x: 480, y: 270, width: 100, height: 1)
        for kind in BackgroundBlurKind.allCases {
            var previous = Double.infinity
            for amount in [0.0, 0.05, 0.25, 0.5, 1.0] {
                let blurred = processor.blurredBackground(source, kind: kind, amount: amount, center: CGPoint(x: 300, y: 150), extent: e)
                let contrast = spread(greens(blurred, row))
                if amount == 0 { XCTAssertGreaterThan(contrast, 240, "\(kind) at 0 leaves the background sharp") }
                if amount == 0.05 { XCTAssertGreaterThan(contrast, 150, "\(kind) at 5% is still subtle") }
                XCTAssertLessThanOrEqual(contrast, previous + 3, "\(kind) never gets sharper as the slider goes up")
                previous = contrast
            }
            XCTAssertLessThan(previous, 200, "\(kind) at full blurs clearly")
        }
    }

    // MARK: Privacy

    func testPrivacyBlurAndPixelateGrowFromSubtle() {
        XCTAssertLessThan(Redaction.blurShare(0), 0.001)
        XCTAssertLessThan(Redaction.blockShare(0), 0.004)
        var lastBlur: CGFloat = 0, lastBlock: CGFloat = 0
        for s in stride(from: 0.0, through: 1.0, by: 0.1) {
            XCTAssertGreaterThan(Redaction.blurShare(s), lastBlur)
            XCTAssertGreaterThan(Redaction.blockShare(s), lastBlock)
            lastBlur = Redaction.blurShare(s); lastBlock = Redaction.blockShare(s)
        }
        let e = CGRect(x: 0, y: 0, width: 600, height: 300)
        let source = stripes(e, width: 10)
        let painted = [RedactionStroke(mode: .blur, width: 0.6, points: [CGPoint(x: 0.5, y: 0.5)]),
                       RedactionStroke(mode: .pixelate, width: 0.3, points: [CGPoint(x: 0.85, y: 0.5)])]
        let row = CGRect(x: 270, y: 150, width: 60, height: 1)
        let low = processor.redact(source, faces: .none, strokes: [painted[0]], strength: 0, extent: e)
        let high = processor.redact(source, faces: .none, strokes: [painted[0]], strength: 1, extent: e)
        XCTAssertGreaterThan(spread(greens(low, row)), 200, "blur at 0 is only a light softening")
        XCTAssertLessThan(spread(greens(high, row)), 20, "blur at full hides the detail")
        XCTAssertEqual(greens(low, CGRect(x: 10, y: 10, width: 1, height: 1))[0], greens(source, CGRect(x: 10, y: 10, width: 1, height: 1))[0],
                       accuracy: 1, "outside the painted area nothing changes")
    }

    // MARK: Subject region edits (screen recording: Brightness -83 seemed to do nothing)

    func testSubjectBrightnessDarkensOnlyTheSubject() {
        let e = CGRect(x: 0, y: 0, width: 200, height: 100)
        let photo = CIImage(color: CIColor(red: 0.6, green: 0.6, blue: 0.6)).cropped(to: e)
        let mask = CIImage(color: .white).cropped(to: CGRect(x: 0, y: 0, width: 100, height: 100))
            .composited(over: CIImage(color: .black).cropped(to: e)).cropped(to: e)
        var state = PhotoAdjustmentState()
        state.subjectEdit.exposure = -0.83
        let output = processor.apply(state, to: photo, subjectMask: mask)
        let subject = greens(output, CGRect(x: 30, y: 50, width: 1, height: 1))[0]
        let background = greens(output, CGRect(x: 170, y: 50, width: 1, height: 1))[0]
        XCTAssertLessThan(subject, background - 40, "the subject is clearly darker")
        XCTAssertEqual(background, greens(photo, CGRect(x: 170, y: 50, width: 1, height: 1))[0], accuracy: 2)
    }

    // MARK: Particle Dissolve

    /// A textured red-orange subject in the middle of a plain green scene.
    private var scene: (photo: CIImage, mask: CIImage, extent: CGRect) {
        let e = CGRect(x: 0, y: 0, width: 600, height: 300)
        let subjectRect = CGRect(x: 150, y: 50, width: 200, height: 200)
        let texture = (CIFilter(name: "CICheckerboardGenerator", parameters: [
            "inputColor0": CIColor(red: 0.9, green: 0.3, blue: 0.2), "inputColor1": CIColor(red: 0.7, green: 0.2, blue: 0.1),
            "inputWidth": 7,
        ])?.outputImage ?? CIImage(color: .red)).cropped(to: subjectRect)
        let photo = texture.composited(over: CIImage(color: CIColor(red: 0.1, green: 0.6, blue: 0.2)).cropped(to: e)).cropped(to: e)
        let mask = CIImage(color: .white).cropped(to: subjectRect).composited(over: CIImage(color: .black).cropped(to: e)).cropped(to: e)
        return (photo, mask, e)
    }

    private func isSubjectColor(_ p: (r: Double, g: Double, b: Double)) -> Bool { p.r > p.g + 60 }
    private func isBackground(_ p: (r: Double, g: Double, b: Double)) -> Bool { p.g > p.r + 40 }

    func testParticleDissolveBreaksTheFarSideIntoImageColoredParticles() throws {
        XCTAssertNotNil(ImageProcessingService.particleDissolveKernel)
        let s = scene
        let output = processor.particleDissolve(s.photo, mask: s.mask, amount: 0.55, size: 0.3, density: 0.75, spread: 0.45,
                                                degrees: 0, softness: 0.5, extent: s.extent)
        XCTAssertEqual(output.extent, s.extent)
        let intact = pixels(output, CGRect(x: 152, y: 140, width: 18, height: 20))
        XCTAssertGreaterThan(Double(intact.filter(isSubjectColor).count) / Double(intact.count), 0.9, "the near side stays intact")
        let far = pixels(output, CGRect(x: 320, y: 140, width: 25, height: 20))
        let gaps = Double(far.filter(isBackground).count) / Double(far.count)
        XCTAssertGreaterThan(gaps, 0.2, "the far side has broken up, showing what's behind")
        XCTAssertGreaterThan(far.filter(isSubjectColor).count, 0, "but particles of it remain")
        let near = pixels(output, CGRect(x: 360, y: 60, width: 40, height: 180)).filter(isSubjectColor).count
        let farther = pixels(output, CGRect(x: 520, y: 60, width: 40, height: 180)).filter(isSubjectColor).count
        XCTAssertGreaterThan(near, 20, "particles fly off to the right, carrying the subject's colors")
        XCTAssertGreaterThan(near, farther, "densest near the subject, thinning out farther away")
        let left = pixels(output, CGRect(x: 40, y: 60, width: 60, height: 180)).filter(isSubjectColor).count
        XCTAssertEqual(left, 0, "nothing flies the other way")
    }

    func testParticleDissolveControlsChangeTheRender() {
        let s = scene
        func render(_ change: (inout PhotoAdjustmentState) -> Void) -> [Double] {
            var state = PhotoAdjustmentState()
            state.dispersionStyle = .particleDissolve
            state.dissolveAmount = 0.55
            change(&state)
            return greens(processor.apply(state, to: s.photo, subjectMask: s.mask), CGRect(x: 280, y: 60, width: 300, height: 180))
        }
        let base = render { _ in }
        for (name, change) in [("size", { (s: inout PhotoAdjustmentState) in s.dissolveSize = 0.9 }),
                               ("density", { $0.dissolveDensity = 0.1 }), ("spread", { $0.dissolveSpread = 0.95 }),
                               ("direction", { $0.dissolveAngle = 90 }), ("softness", { $0.dissolveSoftness = 0.05 }),
                               ("amount", { $0.dissolveAmount = 0.9 })] as [(String, (inout PhotoAdjustmentState) -> Void)] {
            let changed = render(change)
            let differing = zip(base, changed).filter { abs($0 - $1) > 10 }.count
            XCTAssertGreaterThan(differing, 200, "\(name) changes the render")
        }
        var off = PhotoAdjustmentState()
        off.dispersionStyle = .particleDissolve
        XCTAssertFalse(off.needsSubject, "Dissolve at 0 is off")
    }

    func testStylesKeepTheirOwnSettings() throws {
        var state = PhotoAdjustmentState()
        state.dispersion = 0.7
        state.dispersionStyle = .particleDissolve
        state.dissolveAmount = 0.4
        XCTAssertTrue(state.dispersionActive)
        state.dispersionStyle = .pieces
        XCTAssertEqual(state.dissolveAmount, 0.4, "switching styles keeps the other style's settings")
        XCTAssertEqual(state.dispersion, 0.7)
        let decoded = try JSONDecoder().decode(PhotoAdjustmentState.self, from: Data("{}".utf8))
        XCTAssertEqual(decoded.dispersionStyle, .pieces, "old saves keep the original style")
        XCTAssertEqual(decoded.dissolveAmount, 0)
        XCTAssertEqual(state.resetting(.subjectCreate).dissolveAmount, 0)
        var rng = SplitMix64(seed: 3)
        state.dispersionStyle = .particleDissolve
        let shuffled = try XCTUnwrap(state.shuffling(.subjectCreate, using: &rng))
        XCTAssertEqual(shuffled.dispersion, 0.7, "shuffling Particle Dissolve leaves Pieces alone")
        XCTAssertNotEqual(shuffled.dissolveAmount, 0.4)
    }
}
