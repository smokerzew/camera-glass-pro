import CoreImage
import XCTest
@testable import CameraGlassPro

final class FilmStockTests: XCTestCase {
    func testFilmTabHasTheStocks() {
        XCTAssertEqual(Array(FilterCategory.film.filters.prefix(6)), [.portra, .ektar, .gold, .fuji400h, .cinestill, .trix])
        XCTAssertEqual(FilterCategory.film.filters.count, 16)
        XCTAssertEqual(PhotoFilter.cinestill.label, "CineStill 800T")
    }

    @MainActor
    func testFilmBringsGrainButKeepsYours() {
        var state = PhotoAdjustmentState()
        state.filter = .cinestill
        let textured = CameraWorkspaceViewModel.withFilmTexture(state)
        XCTAssertGreaterThan(textured.grain, 0)
        XCTAssertGreaterThan(textured.halation, 0)

        state.grain = 0.8
        state.grainSize = .fine
        let kept = CameraWorkspaceViewModel.withFilmTexture(state)
        XCTAssertEqual(kept.grain, 0.8)
        XCTAssertEqual(kept.grainSize, .fine)

        var classic = PhotoAdjustmentState()
        classic.filter = .chrome
        XCTAssertEqual(CameraWorkspaceViewModel.withFilmTexture(classic), classic, "other filters add nothing")
    }

    func testTriXIsBlackAndWhite() {
        let processor = ImageProcessingService.shared
        var state = PhotoAdjustmentState()
        state.filter = .trix
        let input = CIImage(color: CIColor(red: 0.8, green: 0.3, blue: 0.2)).cropped(to: CGRect(x: 0, y: 0, width: 64, height: 64))
        let output = processor.apply(state, to: input)
        guard let average = CIFilter(name: "CIAreaAverage", parameters: [
            kCIInputImageKey: output, kCIInputExtentKey: CIVector(cgRect: output.extent),
        ])?.outputImage else { return XCTFail("no average") }
        var pixel = [UInt8](repeating: 0, count: 4)
        processor.context.render(average, toBitmap: &pixel, rowBytes: 4, bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                                 format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
        XCTAssertEqual(Double(pixel[0]), Double(pixel[2]), accuracy: 3)
    }
}

final class SkinSmoothingTests: XCTestCase {
    func testKernelShipsWithTheApp() {
        XCTAssertNotNil(ImageProcessingService.kernel("skinSmooth"))
    }

    func testNoFacesNoChange() {
        let processor = ImageProcessingService.shared
        let input = CIImage(color: CIColor(red: 0.8, green: 0.6, blue: 0.5)).cropped(to: CGRect(x: 0, y: 0, width: 200, height: 200))
        XCTAssertTrue(processor.smoothSkin(input, amount: 1, extent: input.extent) === input, "skin-colored but no face: untouched")
        XCTAssertEqual(AdjustmentParameter.skin.title, "Smooth Skin")
    }
}

final class PerspectiveTests: XCTestCase {
    private let processor = ImageProcessingService.shared

    private func alphaAndRed(_ image: CIImage, at rect: CGRect) -> (Double, Double) {
        guard let output = CIFilter(name: "CIAreaAverage", parameters: [
            kCIInputImageKey: image, kCIInputExtentKey: CIVector(cgRect: rect),
        ])?.outputImage else { return (-1, -1) }
        var pixel = [UInt8](repeating: 0, count: 4)
        processor.context.render(output, toBitmap: &pixel, rowBytes: 4, bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                                 format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
        return (Double(pixel[3]), Double(pixel[0]))
    }

    func testKeystoneKeepsSizeAndFillsCorners() {
        let photo = CIImage(color: CIColor(red: 0.5, green: 0.5, blue: 0.5)).cropped(to: CGRect(x: 0, y: 0, width: 400, height: 300))
        for (v, h) in [(1.0, 0.0), (-1.0, 0.0), (0.0, 1.0), (0.0, -1.0), (0.7, -0.6)] {
            var state = PhotoAdjustmentState()
            state.perspectiveVertical = v
            state.perspectiveHorizontal = h
            XCTAssertTrue(state.hasGeometry)
            let output = processor.apply(state, to: photo)
            XCTAssertEqual(output.extent, photo.extent, "v \(v) h \(h)")
            for corner in [CGRect(x: 0, y: 0, width: 4, height: 4), CGRect(x: 396, y: 296, width: 4, height: 4),
                           CGRect(x: 0, y: 296, width: 4, height: 4), CGRect(x: 396, y: 0, width: 4, height: 4)] {
                XCTAssertGreaterThan(alphaAndRed(output, at: corner).0, 250, "no empty corner (v \(v) h \(h))")
            }
        }
    }

    func testVerticalStretchesTheTop() {
        // A red stripe across the top: widening the top pushes it in from the sides less than the bottom.
        let photo = CIImage(color: .blue).cropped(to: CGRect(x: 0, y: 0, width: 400, height: 300))
        let stripe = CIImage(color: .red).cropped(to: CGRect(x: 0, y: 0, width: 20, height: 300)) // left edge column
        var state = PhotoAdjustmentState()
        state.perspectiveVertical = 1
        let output = processor.apply(state, to: stripe.composited(over: photo))
        let top = alphaAndRed(output, at: CGRect(x: 0, y: 280, width: 20, height: 20)).1
        let bottom = alphaAndRed(output, at: CGRect(x: 0, y: 0, width: 20, height: 20)).1
        XCTAssertGreaterThan(bottom, 200, "bottom edge unchanged")
        XCTAssertLessThan(top, bottom - 50, "the top's left column was pushed outside the frame")
    }

    func testVideosAndOldSavesIgnorePerspective() throws {
        var state = PhotoAdjustmentState()
        state.perspectiveHorizontal = 0.5
        XCTAssertFalse(state.withoutGeometry.hasGeometry)
        let json = #"{"perspectiveVertical":9,"skinSmoothing":-2}"#
        let decoded = try JSONDecoder().decode(PhotoAdjustmentState.self, from: Data(json.utf8))
        XCTAssertEqual(decoded.perspectiveVertical, 1)
        XCTAssertEqual(decoded.skinSmoothing, 0)
    }
}

final class RecipeLookTests: XCTestCase {
    func testSplitToneKernelShipsWithTheApp() {
        XCTAssertNotNil(ImageProcessingService.kernel("lookSplitTone"))
    }

    /// Recipe looks must keep pure black black (no colored night skies).
    func testRecipeLooksKeepBlackNeutral() {
        let processor = ImageProcessingService.shared
        let black = CIImage(color: .black).cropped(to: CGRect(x: 0, y: 0, width: 64, height: 64))
        // Duotone looks (Game Boy) map black to their dark color on purpose.
        for filter in PhotoFilter.allCases where LookRecipe.recipe(filter) != nil && LookRecipe.recipe(filter)?.duotone == nil {
            var state = PhotoAdjustmentState()
            state.filter = filter
            guard let average = CIFilter(name: "CIAreaAverage", parameters: [
                kCIInputImageKey: processor.apply(state, to: black), kCIInputExtentKey: CIVector(cgRect: black.extent),
            ])?.outputImage else { return XCTFail("no average") }
            var pixel = [UInt8](repeating: 0, count: 4)
            processor.context.render(average, toBitmap: &pixel, rowBytes: 4, bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                                     format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
            let spread = Int(max(pixel[0], pixel[1], pixel[2])) - Int(min(pixel[0], pixel[1], pixel[2]))
            XCTAssertLessThan(spread, 12, "\(filter) tints black")
        }
    }
}
