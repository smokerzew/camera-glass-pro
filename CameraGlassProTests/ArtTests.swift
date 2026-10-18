import CoreImage
import CoreImage.CIFilterBuiltins
import XCTest
@testable import CameraGlassPro

final class ArtTests: XCTestCase {
    private let processor = ImageProcessingService.shared
    private let extent = CGRect(x: 0, y: 0, width: 300, height: 300)
    private let subjectRect = CGRect(x: 110, y: 110, width: 80, height: 100)

    private var photo: CIImage {
        CIImage(color: CIColor(red: 0.9, green: 0.2, blue: 0.1)).cropped(to: subjectRect)
            .composited(over: CIImage(color: CIColor(red: 0.3, green: 0.3, blue: 0.3)).cropped(to: extent))
    }

    private var mask: CIImage {
        CIImage(color: .white).cropped(to: subjectRect).composited(over: CIImage(color: .black).cropped(to: extent))
    }

    private func average(_ image: CIImage, _ rect: CGRect) -> [Int] {
        let averaged = image.applyingFilter("CIAreaAverage", parameters: [kCIInputExtentKey: CIVector(cgRect: rect)])
        var pixel = [UInt8](repeating: 0, count: 4)
        processor.context.render(averaged, toBitmap: &pixel, rowBytes: 4, bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                                 format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
        return [Int(pixel[0]), Int(pixel[1]), Int(pixel[2])]
    }

    func testHologramTurnsTheSubjectBlue() {
        var state = PhotoAdjustmentState()
        state.hologram = 1
        XCTAssertTrue(state.needsSubject)
        let rgb = average(processor.apply(state, to: photo, subjectMask: mask), CGRect(x: 130, y: 130, width: 40, height: 60))
        XCTAssertGreaterThan(rgb[2], rgb[0], "blue-cyan instead of red")
    }

    func testThermalAndNightVision() {
        let ramp = CIFilter.linearGradient()
        ramp.point0 = CGPoint(x: 0, y: 0)
        ramp.point1 = CGPoint(x: 300, y: 0)
        ramp.color0 = .black
        ramp.color1 = .white
        let input = (ramp.outputImage ?? photo).cropped(to: extent)
        var state = PhotoAdjustmentState()
        state.visionMode = .thermal
        let thermal = processor.apply(state, to: input)
        let cold = average(thermal, CGRect(x: 10, y: 100, width: 20, height: 100))
        let hot = average(thermal, CGRect(x: 250, y: 100, width: 20, height: 100))
        XCTAssertGreaterThan(cold[2], cold[1], "dark parts are blue/purple")
        XCTAssertGreaterThan(hot[0], hot[2] + 40, "bright parts are yellow/red")
        state.visionMode = .night
        let night = average(processor.apply(state, to: input), CGRect(x: 140, y: 100, width: 40, height: 100))
        XCTAssertGreaterThan(night[1], night[0] + 40, "night vision is green")
        XCTAssertNotNil(ImageProcessingService.kernel("visionLook"))
    }

    func testPixelSortOrdersBrightRuns() {
        // Bright random-ish stripes: after sorting, each row's bright run goes from darker to brighter.
        let f = CIFilter.stripesGenerator()
        f.color0 = CIColor(red: 0.95, green: 0.95, blue: 0.95)
        f.color1 = CIColor(red: 0.6, green: 0.6, blue: 0.6)
        f.width = 3
        let input = (f.outputImage ?? photo).cropped(to: extent)
        var state = PhotoAdjustmentState()
        state.pixelSort = 1
        let output = processor.apply(state, to: input)
        let w = 300
        var row = [UInt8](repeating: 0, count: w * 4)
        processor.context.render(output, toBitmap: &row, rowBytes: w * 4, bounds: CGRect(x: 0, y: 150, width: w, height: 1),
                                 format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
        let greens: [Int] = stride(from: 0, to: row.count, by: 4).map { (i: Int) -> Int in Int(row[i + 1]) }
        var drops = 0
        for i in 1..<greens.count where greens[i] + 3 < greens[i - 1] { drops += 1 }
        XCTAssertLessThan(drops, 6, "sorted: almost never gets darker along the row")
    }

    func testOrbitClonesCircleTheSubject() {
        var state = PhotoAdjustmentState()
        state.orbitCount = 6
        state.orbitDistance = 0.5
        XCTAssertEqual(state.orbitClones, 6)
        let output = processor.apply(state, to: photo, subjectMask: mask)
        XCTAssertEqual(output.extent, extent)
        // A clone straight above the subject (first one is placed at 90°).
        let above = average(output, CGRect(x: 140, y: 255, width: 20, height: 20))
        XCTAssertGreaterThan(above[0], above[2] + 60, "a red clone above")
        state.orbitCount = 1
        XCTAssertEqual(state.orbitClones, 0, "under 2 is off")
    }

    func testMeltDripsBelowTheSubject() {
        var state = PhotoAdjustmentState()
        state.melt = 1
        let output = processor.apply(state, to: photo, subjectMask: mask)
        let below = CGRect(x: 115, y: 60, width: 70, height: 45) // under the subject (CI y up)
        XCTAssertGreaterThan(average(output, below)[0], average(photo, below)[0] + 15, "red drips run down")
    }

    func testBackgroundBlurKindsAllRender() {
        let f = CIFilter.checkerboardGenerator()
        f.color0 = .black
        f.color1 = .white
        f.width = 6
        let scene = CIImage(color: CIColor(red: 0.9, green: 0.2, blue: 0.1)).cropped(to: subjectRect)
            .composited(over: (f.outputImage ?? photo).cropped(to: extent))
        var outputs: [Data] = []
        for kind in BackgroundBlurKind.allCases {
            var state = PhotoAdjustmentState()
            state.background = .blur
            state.backgroundBlurKind = kind
            let output = processor.apply(state, to: scene, subjectMask: mask)
            XCTAssertEqual(output.extent, extent, "\(kind)")
            if let png = processor.context.pngRepresentation(of: output, format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!) {
                outputs.append(png)
            }
        }
        XCTAssertEqual(Set(outputs).count, BackgroundBlurKind.allCases.count, "each kind looks different")
    }

    func testArtResetAndShuffle() {
        var state = PhotoAdjustmentState()
        state.hologram = 0.5
        state.pixelSort = 0.5
        state.exposure = 0.3
        let reset = state.resetting(.fxArt)
        XCTAssertEqual(reset.hologram, 0)
        XCTAssertEqual(reset.pixelSort, 0)
        XCTAssertEqual(reset.exposure, 0.3)
        var rng = SystemRandomNumberGenerator()
        for _ in 0..<10 {
            let shuffled = state.shuffling(.fxArt, using: &rng)!
            XCTAssertEqual(shuffled.exposure, 0.3, "only Art changes")
            let effectsOn = [shuffled.hologram > 0, shuffled.visionMode != .none, shuffled.pixelSort > 0,
                             shuffled.orbitClones > 0, shuffled.melt > 0].filter { $0 }.count
            XCTAssertEqual(effectsOn, 1, "one art effect at a time")
        }
    }
}
