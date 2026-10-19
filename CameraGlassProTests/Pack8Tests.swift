import CoreImage
import XCTest
@testable import CameraGlassPro

/// Pack 8: new adjustments, photo FX, subject effects, Particle Dissolve echo.
final class Pack8Tests: XCTestCase {
    private let processor = ImageProcessingService.shared

    private func pixel(_ image: CIImage, _ x: CGFloat, _ y: CGFloat) -> (r: Double, g: Double, b: Double) {
        var p = [UInt8](repeating: 0, count: 4)
        processor.context.render(image, toBitmap: &p, rowBytes: 4, bounds: CGRect(x: x, y: y, width: 1, height: 1),
                                 format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
        return (Double(p[0]), Double(p[1]), Double(p[2]))
    }

    private func channels(_ image: CIImage, _ rect: CGRect) -> [Double] {
        let w = Int(rect.width), h = Int(rect.height)
        var p = [UInt8](repeating: 0, count: w * h * 4)
        processor.context.render(image, toBitmap: &p, rowBytes: w * 4, bounds: rect, format: .RGBA8,
                                 colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
        return p.map(Double.init) // all channels; alpha never differs
    }

    /// A small scene: dark-to-light ramp left to right, with a bright spot (for flare, rays).
    private var scene: CIImage {
        let e = CGRect(x: 0, y: 0, width: 300, height: 200)
        let ramp = CIFilter(name: "CILinearGradient", parameters: [
            "inputPoint0": CIVector(x: 0, y: 100), "inputPoint1": CIVector(x: 300, y: 100),
            "inputColor0": CIColor(red: 0.05, green: 0.08, blue: 0.12), "inputColor1": CIColor(red: 0.6, green: 0.55, blue: 0.5),
        ])?.outputImage ?? CIImage(color: .gray)
        let spot = CIImage(color: .white).cropped(to: CGRect(x: 200, y: 140, width: 16, height: 16))
        return spot.composited(over: ramp).cropped(to: e)
    }

    private func changed(_ a: CIImage, _ b: CIImage) -> Int {
        let r = CGRect(x: 0, y: 0, width: 300, height: 200)
        return zip(channels(a, r), channels(b, r)).filter { abs($0 - $1) > 4 }.count
    }

    // MARK: Adjustments

    func testNewAdjustmentsChangeThePhotoAndKeepBlackNeutral() {
        let black = CIImage(color: .black).cropped(to: CGRect(x: 0, y: 0, width: 32, height: 32))
        for (name, change) in [("brilliance", { (s: inout PhotoAdjustmentState) in s.brilliance = 0.8 }),
                               ("clarity", { $0.clarity = 0.8 }), ("fade", { $0.fade = 0.8 }),
                               ("grade", { $0.gradeShadowAmount = 1; $0.gradeHighlightAmount = 1 })]
                as [(String, (inout PhotoAdjustmentState) -> Void)] {
            var state = PhotoAdjustmentState()
            change(&state)
            let output = processor.apply(state, to: scene)
            XCTAssertEqual(output.extent, scene.extent, name)
            XCTAssertGreaterThan(changed(output, scene), 200, "\(name) changes the photo")
            let b = pixel(processor.apply(state, to: black), 16, 16)
            XCTAssertLessThan(max(b.r, b.g, b.b) - min(b.r, b.g, b.b), 6, "\(name) keeps black neutral")
        }
        XCTAssertEqual(AdjustmentParameter.brilliance.group, .light)
        XCTAssertEqual(AdjustmentParameter.clarity.group, .detail)
        XCTAssertEqual(AdjustmentParameter.fade.group, .effects)
        var graded = PhotoAdjustmentState()
        graded.gradeShadowAmount = 0.5
        XCTAssertEqual(graded.resetting(.color).gradeShadowAmount, 0, "Reset Color clears the grade")
    }

    // MARK: Photo FX

    func testNewFXRenderAndReset() {
        let cases: [(String, (inout PhotoAdjustmentState) -> Void, ResetArea)] = [
            ("fog", { $0.weather = .fog; $0.weatherAmount = 0.9 }, .fxWeather),
            ("rain", { $0.weather = .rain; $0.weatherAmount = 0.9 }, .fxWeather),
            ("snow", { $0.weather = .snow; $0.weatherAmount = 0.9 }, .fxWeather),
            ("rays", { $0.weather = .rays; $0.weatherAmount = 0.9 }, .fxWeather),
            ("flare", { $0.flare = 0.9 }, .fxLight), ("prism", { $0.prism = 0.9 }, .fxLight),
            ("oil", { $0.paint = 0.9; $0.paintStyle = .oil }, .fxArt),
            ("watercolor", { $0.paint = 0.9; $0.paintStyle = .watercolor }, .fxArt),
            ("sketch", { $0.paint = 0.9; $0.paintStyle = .sketch }, .fxArt),
            ("mirror", { $0.mirror = .left }, .fxArt),
        ]
        for (name, change, area) in cases {
            var state = PhotoAdjustmentState()
            change(&state)
            let output = processor.apply(state, to: scene)
            XCTAssertEqual(output.extent, scene.extent, name)
            XCTAssertGreaterThan(changed(output, scene), 100, "\(name) changes the photo")
            XCTAssertTrue(state.resetting(area).isIdentity, "\(name) resets with its own page")
        }
    }

    func testMirrorReflectsTheKeptHalf() {
        var state = PhotoAdjustmentState()
        state.mirror = .left
        let output = processor.apply(state, to: scene)
        XCTAssertEqual(pixel(output, 280, 50).g, pixel(scene, 19, 50).g, accuracy: 3, "the right side is the left side, reflected")
    }

    // MARK: Subject effects

    func testSubjectEffectsUseTheMask() {
        let e = CGRect(x: 0, y: 0, width: 300, height: 200)
        let photo = CIImage(color: CIColor(red: 0.4, green: 0.4, blue: 0.4)).cropped(to: e)
        let mask = CIImage(color: .white).cropped(to: CGRect(x: 100, y: 50, width: 100, height: 100))
            .composited(over: CIImage(color: .black).cropped(to: e)).cropped(to: e)
        func render(_ change: (inout PhotoAdjustmentState) -> Void) -> CIImage {
            var state = PhotoAdjustmentState()
            change(&state)
            XCTAssertTrue(state.needsSubject)
            return processor.apply(state, to: photo, subjectMask: mask)
        }
        let neon = render { $0.neonOutline = 1; $0.neonHue = 300 }
        let edge = pixel(neon, 100, 100), far = pixel(neon, 30, 100)
        XCTAssertGreaterThan(edge.r + edge.b, far.r + far.b + 60, "neon glows along the outline")
        XCTAssertEqual(far.g, 0.4 * 255, accuracy: 30, "far from the subject nothing changes much")
        let silhouette = render { $0.silhouette = 1 }
        XCTAssertLessThan(pixel(silhouette, 150, 100).g, pixel(silhouette, 30, 100).g - 40, "the subject goes dark")
        let shadow = render { $0.subjectShadow = 1 }
        XCTAssertLessThan(pixel(shadow, 204, 80).g, pixel(photo, 204, 80).g - 10, "a shadow falls behind, down and to the right")
        let aura = render { $0.aura = 1; $0.auraHue = 45 }
        let glow = pixel(aura, 205, 100)
        XCTAssertGreaterThan(glow.r, pixel(photo, 205, 100).r + 15, "a warm glow around the subject")
        var state = PhotoAdjustmentState()
        state.aura = 0.5
        XCTAssertTrue(state.resetting(.subjectEffects).isIdentity)
        XCTAssertFalse(state.withoutSubjectEdits.hasSubjectEffects)
    }

    // MARK: Particle Dissolve echo

    func testEchoAddsAnEnlargedSpeckledCopy() {
        let e = CGRect(x: 0, y: 0, width: 600, height: 300)
        let subjectRect = CGRect(x: 100, y: 50, width: 200, height: 200)
        let photo = CIImage(color: CIColor(red: 0.9, green: 0.3, blue: 0.2)).cropped(to: subjectRect)
            .composited(over: CIImage(color: CIColor(red: 0.1, green: 0.6, blue: 0.2)).cropped(to: e)).cropped(to: e)
        let mask = CIImage(color: .white).cropped(to: subjectRect).composited(over: CIImage(color: .black).cropped(to: e)).cropped(to: e)
        func subjectPixels(_ echo: Double) -> Int {
            let out = processor.particleDissolve(photo, mask: mask, amount: 0.55, size: 0.2, density: 0.2, spread: 0.6,
                                                 degrees: 0, softness: 0.4, echo: echo, extent: e)
            var p = [UInt8](repeating: 0, count: 80 * 200 * 4)
            processor.context.render(out, toBitmap: &p, rowBytes: 80 * 4, bounds: CGRect(x: 310, y: 50, width: 80, height: 200),
                                     format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
            return stride(from: 0, to: p.count, by: 4).filter { p[$0] > p[$0 + 1] &+ 60 }.count
        }
        XCTAssertGreaterThan(subjectPixels(1), subjectPixels(0) + 300, "the echo fills the space beyond the subject with its speckles")
    }

    func testNewFieldsDecodeFromOldSaves() throws {
        let old = try JSONDecoder().decode(PhotoAdjustmentState.self, from: Data("{}".utf8))
        XCTAssertEqual(old.weather, .none)
        XCTAssertEqual(old.mirror, .off)
        XCTAssertEqual(old.dissolveEcho, 0.75)
        XCTAssertEqual(old.neonHue, 300)
        XCTAssertTrue(old.isIdentity)
        let junk = try JSONDecoder().decode(PhotoAdjustmentState.self, from: Data(#"{"weather":"tornado","paint":5,"fade":-3}"#.utf8))
        XCTAssertEqual(junk.weather, .none)
        XCTAssertEqual(junk.paint, 1)
        XCTAssertEqual(junk.fade, 0)
    }
}
