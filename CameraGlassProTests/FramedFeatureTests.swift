import CoreImage
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import CameraGlassPro

/// Composition, framing, curves, calibration, film damage, projects and finishing: everything about the
/// camera workflow that can be checked without camera hardware.
final class CompositionTests: XCTestCase {
    private func features(_ subjects: [SceneSubject], aspect: CGFloat = 0.75) -> SceneFeatures {
        var f = SceneFeatures()
        f.subjects = subjects
        f.imageAspect = aspect
        return f
    }

    func testMaxCropSizeFitsTheImage() {
        let square = CompositionEngine.maxCropSize(aspect: 1, imageAspect: 0.75)
        XCTAssertEqual(square.width, 1, accuracy: 0.0001)
        XCTAssertEqual(square.height, 0.75, accuracy: 0.0001, "a square in a 3:4 frame uses the full width")
        let tall = CompositionEngine.maxCropSize(aspect: 9.0 / 16.0, imageAspect: 0.75)
        XCTAssertEqual(tall.height, 1, accuracy: 0.0001)
        XCTAssertEqual(tall.width, 0.75, accuracy: 0.0001)
    }

    func testNoSubjectIsInconclusive() {
        let result = CompositionEngine.analyze(features([]))
        XCTAssertFalse(result.isConclusive)
        XCTAssertNil(result.primary)
        XCTAssertEqual(result.guidance.first?.id, "no-subject")
    }

    func testSuggestionKeepsSubjectAndPutsItOnAThird() throws {
        let subject = SceneSubject(kind: .salient, box: CGRect(x: 0.45, y: 0.45, width: 0.12, height: 0.1), confidence: 0.9)
        let result = CompositionEngine.analyze(features([subject]), aspect: 0.75)
        let best = try XCTUnwrap(result.primary)
        XCTAssertTrue(best.rect.contains(subject.box), "the subject is never cut")
        XCTAssertTrue(CGRect(x: 0, y: 0, width: 1, height: 1).insetBy(dx: -0.0001, dy: -0.0001).contains(best.rect))
        let toThird = CompositionEngine.thirds.map { hypot($0.x - best.target.x, $0.y - best.target.y) }.min() ?? 1
        let toCenter = hypot(best.target.x - 0.5, best.target.y - 0.5)
        XCTAssertLessThan(min(toThird, toCenter), 0.08, "the subject lands on a third or the center")
        XCTAssertTrue(result.isConclusive)
    }

    func testResultDependsOnTheScene() throws {
        let left = SceneSubject(kind: .salient, box: CGRect(x: 0.15, y: 0.4, width: 0.12, height: 0.1), confidence: 0.9)
        let right = SceneSubject(kind: .salient, box: CGRect(x: 0.72, y: 0.4, width: 0.12, height: 0.1), confidence: 0.9)
        let a = try XCTUnwrap(CompositionEngine.analyze(features([left])).primary)
        let b = try XCTUnwrap(CompositionEngine.analyze(features([right])).primary)
        XCTAssertNotEqual(a.rect, b.rect, "different scenes get different frames")
    }

    func testAlternativePlacesTheSubjectElsewhere() throws {
        let subject = SceneSubject(kind: .salient, box: CGRect(x: 0.45, y: 0.45, width: 0.08, height: 0.07), confidence: 0.9)
        let result = CompositionEngine.analyze(features([subject]))
        let best = try XCTUnwrap(result.primary)
        if let alternative = result.alternative {
            XCTAssertTrue(abs(alternative.target.x - best.target.x) > 0.1 || abs(alternative.target.y - best.target.y) > 0.1)
        }
    }

    func testFacesWinOverSalientObjects() {
        let face = SceneSubject(kind: .face, box: CGRect(x: 0.6, y: 0.2, width: 0.1, height: 0.08), confidence: 0.9)
        let thing = SceneSubject(kind: .salient, box: CGRect(x: 0.1, y: 0.6, width: 0.3, height: 0.3), confidence: 1)
        XCTAssertEqual(CompositionEngine.primarySubject(features([thing, face]))?.kind, .face)
    }

    func testGuidanceSeparatesMeasurementsFromSuggestions() {
        var f = features([SceneSubject(kind: .person, box: CGRect(x: 0.4, y: 0.3, width: 0.2, height: 0.5), confidence: 0.9)])
        f.horizonDegrees = 4
        f.highlightClipping = 0.1
        let result = CompositionEngine.analyze(f)
        XCTAssertTrue(result.guidance.contains { $0.id == "level" && $0.kind == .measured })
        XCTAssertTrue(result.guidance.contains { $0.id == "highlights" && $0.kind == .measured })
        XCTAssertTrue(result.guidance.contains { $0.kind == .suggestion }, "taste is labeled as a suggestion")
        XCTAssertFalse(CompositionEngine.analyze(f, isFrontCamera: true).guidance.contains { $0.id == "level" })
    }

    func testAlignmentHintsPointTheRightWay() {
        let frame = CGRect(x: 0, y: 0, width: 1, height: 1)
        // Subject right of the right third: it must move left in the picture, so the phone pans right.
        let right = CompositionEngine.alignment(subject: CGRect(x: 0.78, y: 0.3, width: 0.06, height: 0.06), in: frame)
        XCTAssertFalse(right.isAligned)
        XCTAssertTrue(right.hint.hasPrefix("Pan right"), right.hint)
        let on = CompositionEngine.alignment(subject: CGRect(x: 2.0 / 3 - 0.03, y: 1.0 / 3 - 0.03, width: 0.06, height: 0.06), in: frame)
        XCTAssertTrue(on.isAligned)
        XCTAssertEqual(on.hint, "")
    }

    func testAspectFillMappingRoundTrips() {
        let view = CGSize(width: 400, height: 400) // a 1:1 frame showing a 3:4 image
        let visible = AspectFillMapping.visibleRect(imageAspect: 0.75, viewSize: view)
        XCTAssertEqual(visible.minX, 0, accuracy: 0.0001)
        XCTAssertEqual(visible.width, 1, accuracy: 0.0001)
        XCTAssertEqual(visible.height, 0.75, accuracy: 0.0001)
        XCTAssertEqual(visible.minY, 0.125, accuracy: 0.0001, "a square shows the middle of the 3:4 frame")
        let point = CGPoint(x: 0.3, y: 0.6)
        let back = AspectFillMapping.toImage(AspectFillMapping.toView(point, imageAspect: 0.75, viewSize: view), imageAspect: 0.75, viewSize: view)
        XCTAssertEqual(back.x, point.x, accuracy: 0.0001)
        XCTAssertEqual(back.y, point.y, accuracy: 0.0001)
    }

    func testCaptureAspectsCropTheRightShape() {
        for (option, ratio) in [(AspectRatioOption.fourThree, 3.0 / 4.0), (.fiveFour, 4.0 / 5.0), (.square, 1.0), (.sixteenNine, 9.0 / 16.0)] {
            let r = option.resolvedRatio(imageSize: CGSize(width: 3, height: 4))
            XCTAssertEqual(r, ratio, accuracy: 0.0001, "\(option)")
            let crop = AspectFillMapping.visibleRect(imageAspect: 0.75, viewSize: CGSize(width: r, height: 1))
            // Pixel aspect of the crop on a 3000 × 4000 photo.
            XCTAssertEqual(crop.width * 3000 / (crop.height * 4000), ratio, accuracy: 0.002, "\(option)")
        }
        XCTAssertEqual(AspectRatioOption.sixteenNine.portraitLabel, "9:16")
        XCTAssertEqual(AspectRatioOption.fiveFour.portraitLabel, "4:5")
    }

    @MainActor
    func testCustomFrameKeepsItsAspectInsideTheImage() {
        let frame = LiveCameraModel.constrained(CGRect(x: 0.8, y: 0.8, width: 0.5, height: 0.2), aspect: 1, imageAspect: 0.75)
        XCTAssertEqual(frame.width * 3000 / (frame.height * 4000), 1, accuracy: 0.002)
        XCTAssertTrue(CGRect(x: 0, y: 0, width: 1, height: 1).insetBy(dx: -0.0001, dy: -0.0001).contains(frame))
        let free = LiveCameraModel.constrained(CGRect(x: 0.1, y: 0.2, width: 0.3, height: 0.4), aspect: nil, imageAspect: 0.75)
        XCTAssertEqual(free, CGRect(x: 0.1, y: 0.2, width: 0.3, height: 0.4))
    }

    func testZoomPresetsFollowTheLenses() {
        XCTAssertEqual(CameraService.zoomPresets(minZoom: 0.5, maxZoom: 25, switchOvers: [1, 5]), [0.5, 1, 2, 5])
        XCTAssertEqual(CameraService.zoomPresets(minZoom: 1, maxZoom: 10, switchOvers: []), [1, 2])
        XCTAssertEqual(CameraService.zoomPresets(minZoom: 1, maxZoom: 1.5, switchOvers: []), [1])
    }

    func testScanFramesAreMerged() throws {
        var a = SceneFeatures(), b = SceneFeatures()
        a.meanLuminance = 0.2
        b.meanLuminance = 0.4
        a.horizonDegrees = 2
        let merged = try XCTUnwrap(FrameRouter.merge([a, b]))
        XCTAssertEqual(merged.meanLuminance, 0.3, accuracy: 0.0001)
        XCTAssertEqual(merged.horizonDegrees, 2)
    }
}

final class CurvesCalibrationDamageTests: XCTestCase {
    private let processor = ImageProcessingService.shared

    func testIdentityCurveIsALine() {
        let samples = ToneCurves.sample(ToneCurves.xs, count: 11)
        for (i, v) in samples.enumerated() { XCTAssertEqual(v, Double(i) / 10, accuracy: 0.0001) }
        XCTAssertTrue(ToneCurves().isIdentity)
    }

    func testCurveHasNoOvershoot() {
        let samples = ToneCurves.sample([0, 0.05, 0.9, 0.95, 1], count: 200)
        for (a, b) in zip(samples, samples.dropFirst()) { XCTAssertGreaterThanOrEqual(b, a - 1e-9, "monotone points stay monotone") }
        XCTAssertTrue(samples.allSatisfy { (0...1).contains($0) })
    }

    func testCurvesChangeThePicture() throws {
        let gray = CIImage(color: CIColor(red: 0.5, green: 0.5, blue: 0.5)).cropped(to: CGRect(x: 0, y: 0, width: 16, height: 16))
        var state = PhotoAdjustmentState()
        state.curves.red = [0, 0.4, 0.75, 0.9, 1]
        let out = processor.apply(state, to: gray)
        let pixel = try XCTUnwrap(rgb(out))
        XCTAssertGreaterThan(pixel.r, pixel.b + 20, "lifting the red curve warms a gray")
    }

    func testOldEditsWithoutNewFieldsStillLoad() throws {
        let state = try JSONDecoder().decode(PhotoAdjustmentState.self, from: Data(#"{"exposure":0.5}"#.utf8))
        XCTAssertEqual(state.exposure, 0.5)
        XCTAssertTrue(state.curves.isIdentity)
        XCTAssertTrue(state.calibration.isNeutral)
        XCTAssertEqual(state.dust, 0)
        let bad = try JSONDecoder().decode(PhotoAdjustmentState.self, from: Data(#"{"curves":{"red":[2,0]},"dust":9}"#.utf8))
        XCTAssertTrue(bad.curves.isIdentity, "malformed curves fall back to identity")
        XCTAssertEqual(bad.dust, 1)
    }

    func testNeutralCalibrationIsIdentity() {
        let m = ColorCalibration().matrix()
        for r in 0..<3 { for c in 0..<3 { XCTAssertEqual(m[r][c], r == c ? 1 : 0, accuracy: 1e-9) } }
        var c = ColorCalibration()
        c.redSaturation = -1
        let red = c.matrix().map { $0[0] }
        XCTAssertLessThan(red[0] - max(red[1], red[2]), 1 - 0.0001, "less saturated red primary")
    }

    func testDustAndScratchesMarkTheImageTheSameWayEveryTime() throws {
        let gray = CIImage(color: CIColor(red: 0.4, green: 0.4, blue: 0.4)).cropped(to: CGRect(x: 0, y: 0, width: 600, height: 400))
        let a = processor.filmDamage(gray, dust: 1, scratches: 1, extent: gray.extent)
        let b = processor.filmDamage(gray, dust: 1, scratches: 1, extent: gray.extent)
        XCTAssertEqual(a.extent, gray.extent)
        let pa = try XCTUnwrap(bytes(a)), pb = try XCTUnwrap(bytes(b))
        XCTAssertEqual(pa, pb, "same photo, same marks")
        XCTAssertTrue(pa.contains { abs(Int($0) - 102) > 25 }, "marks are visible")
        XCTAssertTrue(processor.filmDamage(gray, dust: 0, scratches: 0, extent: gray.extent) === gray)
    }

    @MainActor
    func testSignaturePresetsAreDistinctLooks() {
        let looks: [PhotoFilter] = [.daylightNeg, .push1600, .sunFaded, .silverTone, .softBloom, .deepPrint, .quietCinema, .goldenSplit]
        XCTAssertEqual(FilterCategory.signature.filters, looks)
        for look in looks {
            XCTAssertNotNil(LookRecipe.recipe(look), "\(look) has a recipe")
            XCTAssertEqual(LookRecipe.recipe(look)?.category, .signature)
        }
        XCTAssertNotNil(LookRecipe.recipe(.silverTone)?.mono, "Silver Tone is monochrome")
        XCTAssertEqual(CameraWorkspaceViewModel.withFilmTexture({ var s = PhotoAdjustmentState(); s.filter = .push1600; return s }()).grainSize, .coarse)
        var warm = PhotoAdjustmentState(), cool = PhotoAdjustmentState()
        warm.filter = .goldenSplit
        cool.filter = .quietCinema
        XCTAssertNotEqual(warm, cool)
    }

    private func rgb(_ image: CIImage) -> (r: Int, g: Int, b: Int)? {
        guard let data = bytes(image.cropped(to: CGRect(x: 4, y: 4, width: 1, height: 1))) else { return nil }
        return (Int(data[0]), Int(data[1]), Int(data[2]))
    }

    private func bytes(_ image: CIImage) -> [UInt8]? {
        let e = image.extent
        guard let cg = processor.context.createCGImage(image, from: e) else { return nil }
        var out = [UInt8](repeating: 0, count: Int(e.width) * Int(e.height) * 4)
        let drawn = out.withUnsafeMutableBytes { buffer -> Bool in
            guard let ctx = CGContext(data: buffer.baseAddress, width: Int(e.width), height: Int(e.height), bitsPerComponent: 8,
                                      bytesPerRow: Int(e.width) * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: e.width, height: e.height))
            return true
        }
        return drawn ? out : nil
    }
}

final class ProjectAndFinishTests: XCTestCase {
    private var store: ProjectStore!

    override func setUp() {
        store = ProjectStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent("projects-\(UUID().uuidString)"))
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: store.directory)
    }

    /// A small JPEG with real EXIF capture facts.
    private func photoData(exif: [CFString: Any]? = nil, tiff: [CFString: Any]? = nil) throws -> Data {
        let ctx = try XCTUnwrap(CGContext(data: nil, width: 120, height: 90, bitsPerComponent: 8, bytesPerRow: 0,
                                          space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        ctx.setFillColor(CGColor(red: 0.3, green: 0.5, blue: 0.7, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: 120, height: 90))
        let image = try XCTUnwrap(ctx.makeImage())
        let data = NSMutableData()
        let dest = try XCTUnwrap(CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil))
        var props: [CFString: Any] = [:]
        if let exif { props[kCGImagePropertyExifDictionary] = exif }
        if let tiff { props[kCGImagePropertyTIFFDictionary] = tiff }
        CGImageDestinationAddImage(dest, image, props as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(dest))
        return data as Data
    }

    func testProjectKeepsOriginalAndEdit() throws {
        let original = try photoData()
        var state = SessionState(kind: .photo, fileName: "")
        state.adjustments.filter = .deepPrint
        state.adjustments.cropRect = CGRect(x: 0, y: 0.1, width: 1, height: 0.8)
        var project = try store.create(original: original, typeIdentifier: UTType.jpeg.identifier, source: .camera, state: state)
        XCTAssertEqual(try Data(contentsOf: store.originalURL(project)), original, "the original is stored byte for byte")
        XCTAssertEqual(store.projectID(forOriginal: store.originalURL(project)), project.id)

        project.state.adjustments.exposure = 0.7
        project.finish = FinishSettings(frame: .paper, dateStamp: true)
        try store.save(project)
        let loaded = try XCTUnwrap(store.load(project.id))
        XCTAssertEqual(loaded.state.adjustments.exposure, 0.7)
        XCTAssertEqual(loaded.state.adjustments.filter, .deepPrint)
        XCTAssertEqual(loaded.finish.frame, .paper)
        XCTAssertEqual(try Data(contentsOf: store.originalURL(loaded)), original, "saving an edit never touches the original")

        let copy = try store.duplicate(loaded)
        XCTAssertNotEqual(copy.id, loaded.id)
        XCTAssertEqual(store.list().count, 2)
        store.delete(loaded.id)
        XCTAssertEqual(store.list().map(\.id), [copy.id], "deleting one edit keeps the other")
    }

    func testMissingOriginalIsReportedNotHidden() throws {
        let project = try store.create(original: try photoData(), typeIdentifier: UTType.jpeg.identifier, source: .imported,
                                       state: SessionState(kind: .photo, fileName: ""))
        try FileManager.default.removeItem(at: store.originalURL(project))
        XCTAssertEqual(store.list().count, 1)
        XCTAssertFalse(store.hasOriginal(project))
        XCTAssertThrowsError(try store.duplicate(project))
    }

    func testMetadataIsReadNotInvented() throws {
        let data = try photoData(exif: [kCGImagePropertyExifISOSpeedRatings: [200], kCGImagePropertyExifExposureTime: 0.004,
                                        kCGImagePropertyExifFNumber: 1.8, kCGImagePropertyExifDateTimeOriginal: "2026:10:22 14:05:00"],
                                 tiff: [kCGImagePropertyTIFFMake: "Apple", kCGImagePropertyTIFFModel: "iPhone 16 Pro"])
        let m = CaptureMetadata(data: data)
        XCTAssertEqual(m.iso, 200)
        XCTAssertEqual(m.cameraLine, "iPhone 16 Pro")
        XCTAssertTrue(m.settingsLine.contains("1/250s"), m.settingsLine)
        XCTAssertTrue(m.settingsLine.contains("ƒ/1.8"), m.settingsLine)
        XCTAssertEqual(m.stampText, "'26 10 22")

        let bare = CaptureMetadata(data: try photoData())
        XCTAssertNil(bare.date)
        XCTAssertNil(bare.stampText, "no date, no stamp")
        XCTAssertNil(bare.iso)
        XCTAssertFalse(bare.settingsLine.contains("ISO"))
    }

    func testFramesGrowTheCanvasAndKeepThePhoto() throws {
        let ctx = try XCTUnwrap(CGContext(data: nil, width: 300, height: 200, bitsPerComponent: 8, bytesPerRow: 0,
                                          space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        ctx.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: 300, height: 200))
        let photo = try XCTUnwrap(ctx.makeImage())
        for style in FrameStyle.allCases where style != .none {
            let out = try XCTUnwrap(FinishingRenderer.render(photo, settings: FinishSettings(frame: style), metadata: CaptureMetadata()), "\(style)")
            let inset = FinishingRenderer.insets(for: style, size: CGSize(width: 300, height: 200))
            XCTAssertEqual(out.width, Int(300 + inset.left + inset.right), "\(style)")
            XCTAssertEqual(out.height, Int(200 + inset.top + inset.bottom), "\(style)")
        }
        let none = FinishingRenderer.finish(CIImage(cgImage: photo), settings: FinishSettings(), metadata: CaptureMetadata())
        XCTAssertEqual(none.extent.size, CGSize(width: 300, height: 200), "no finish, no change")
    }

    func testExportAddsTheFrameOnlyToTheEditedCopy() throws {
        let original = try photoData()
        var options = ExportOptions(content: .adjusted, format: .jpeg)
        options.finish = FinishSettings(frame: .white)
        let request = ExportRequest(data: original, typeIdentifier: UTType.jpeg.identifier, adjustments: PhotoAdjustmentState(),
                                    options: options, normalizedCrop: nil, overlays: OverlayBurnIn())
        let edited = try PhotoExportService().renderAdjusted(request)
        let source = try XCTUnwrap(CGImageSourceCreateWithData(edited as CFData, nil))
        let props = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
        XCTAssertGreaterThan(props[kCGImagePropertyPixelWidth] as? Int ?? 0, 120, "the white frame widens the edited copy")
    }
}
