import AVFoundation
import CoreImage
import UIKit
import XCTest
@testable import CameraGlassPro

final class ImageProcessingTests: XCTestCase {
    private let processor = ImageProcessingService.shared

    private func solid(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat, size: CGFloat = 16) -> CIImage {
        CIImage(color: CIColor(red: red, green: green, blue: blue)).cropped(to: CGRect(x: 0, y: 0, width: size, height: size))
    }

    /// Average RGB of the image rendered in sRGB.
    private func averageRGB(_ image: CIImage) -> (r: Double, g: Double, b: Double) {
        let filter = CIFilter(name: "CIAreaAverage", parameters: [
            kCIInputImageKey: image,
            kCIInputExtentKey: CIVector(cgRect: image.extent),
        ])
        guard let output = filter?.outputImage else { XCTFail("no average"); return (0, 0, 0) }
        var pixel = [UInt8](repeating: 0, count: 4)
        processor.context.render(output, toBitmap: &pixel, rowBytes: 4,
                                 bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                                 format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
        return (Double(pixel[0]), Double(pixel[1]), Double(pixel[2]))
    }

    func testIdentityReturnsInputUnchanged() {
        let input = solid(0.5, 0.5, 0.5)
        let output = processor.apply(PhotoAdjustmentState(), to: input)
        XCTAssertEqual(output.extent, input.extent)
        XCTAssertTrue(output === input, "identity recipe should not build a filter graph")
    }

    func testExtentIsPreservedForEveryFilter() {
        var state = PhotoAdjustmentState()
        state.exposure = 1; state.contrast = 1.2; state.warmth = 0.5; state.highlights = -0.5; state.shadows = 0.5
        state.nightLook = true
        let input = solid(0.4, 0.4, 0.4, size: 64)
        XCTAssertEqual(processor.apply(state, to: input).extent, input.extent)
    }

    func testFiltersKeepExtentAndChangePixels() {
        let input = solid(0.8, 0.3, 0.2, size: 32)
        for look in PhotoFilter.allCases where look != .none {
            var state = PhotoAdjustmentState()
            state.filter = look
            XCTAssertFalse(state.isIdentity)
            let output = processor.apply(state, to: input)
            XCTAssertEqual(output.extent, input.extent, "\(look) changed the extent")
        }
        var mono = PhotoAdjustmentState()
        mono.filter = .mono
        let rgb = averageRGB(processor.apply(mono, to: input))
        XCTAssertEqual(rgb.r, rgb.b, accuracy: 3, "mono should be gray")
    }

    func testExposureBrightens() {
        var state = PhotoAdjustmentState()
        state.exposure = 1
        let before = averageRGB(solid(0.3, 0.3, 0.3))
        let after = averageRGB(processor.apply(state, to: solid(0.3, 0.3, 0.3)))
        XCTAssertGreaterThan(after.g, before.g + 10)
    }

    func testSaturationZeroIsGray() {
        var state = PhotoAdjustmentState()
        state.saturation = 0
        let rgb = averageRGB(processor.apply(state, to: solid(0.8, 0.2, 0.2)))
        XCTAssertEqual(rgb.r, rgb.g, accuracy: 3)
        XCTAssertEqual(rgb.g, rgb.b, accuracy: 3)
    }

    func testWarmthDirection() {
        var warm = PhotoAdjustmentState()
        warm.warmth = 1
        var cool = PhotoAdjustmentState()
        cool.warmth = -1
        let warmRGB = averageRGB(processor.apply(warm, to: solid(0.5, 0.5, 0.5)))
        let coolRGB = averageRGB(processor.apply(cool, to: solid(0.5, 0.5, 0.5)))
        XCTAssertGreaterThan(warmRGB.r - warmRGB.b, 0, "positive warmth should look warmer")
        XCTAssertLessThan(coolRGB.r - coolRGB.b, 0, "negative warmth should look cooler")
    }

    func testEncodeAllFormats() throws {
        let image = solid(0.2, 0.6, 0.9, size: 256)
        for format in ExportFormat.allCases {
            let data: Data
            do {
                data = try processor.encode(image, as: format)
            } catch {
                #if targetEnvironment(simulator)
                if format == .heic { continue } // CI simulators may lack a HEVC encoder; devices have one
                #endif
                throw error
            }
            XCTAssertGreaterThan(data.count, 0, "\(format) produced no data")
        }
    }
}

final class ExportTests: XCTestCase {
    func testFileNaming() {
        var components = DateComponents()
        components.year = 2026; components.month = 10; components.day = 16
        components.hour = 9; components.minute = 5; components.second = 7
        let date = Calendar.current.date(from: components) ?? .now
        XCTAssertEqual(PhotoExportService.fileName(content: .adjusted, fileExtension: "jpg", date: date),
                       "CameraGlass-Edited-20261016-090507.jpg")
        XCTAssertEqual(PhotoExportService.fileName(content: .original, fileExtension: "heic", date: date),
                       "CameraGlass-Original-20261016-090507.heic")
    }

    func testFormatMetadata() {
        XCTAssertEqual(ExportFormat.jpeg.fileExtension, "jpg")
        XCTAssertEqual(ExportFormat.heic.contentType, .heic)
        XCTAssertEqual(ExportFormat.png.contentType, .png)
    }

    func testNormalizedCrop() {
        let image = CIImage(color: .red).cropped(to: CGRect(x: 0, y: 0, width: 400, height: 300))
        let cropped = PhotoExportService.crop(image, normalized: CGRect(x: 0.25, y: 0, width: 0.5, height: 1))
        XCTAssertEqual(cropped.extent, CGRect(x: 0, y: 0, width: 200, height: 300))
    }

    func testBurnOverlaysKeepsExtent() {
        let image = CIImage(color: .black).cropped(to: CGRect(x: 0, y: 0, width: 300, height: 300))
        XCTAssertTrue(PhotoExportService.burnOverlays(OverlayBurnIn(), into: image) === image)
        let burned = PhotoExportService.burnOverlays(OverlayBurnIn(gridDivisions: 3, center: true), into: image)
        XCTAssertEqual(burned.extent, image.extent)
    }

    func testOriginalExportIsByteForByte() throws {
        let data = try XCTUnwrap(Self.samplePNG(width: 40, height: 30))
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let service = PhotoExportService(directory: directory)
        let request = ExportRequest(data: data, typeIdentifier: "public.png", adjustments: PhotoAdjustmentState(),
                                    options: ExportOptions(content: .original), normalizedCrop: nil, overlays: OverlayBurnIn())
        let url = try service.exportSynchronously(request)
        XCTAssertEqual(url.pathExtension, "png")
        XCTAssertEqual(try Data(contentsOf: url), data)
    }

    func testAdjustedExportWithCrop() throws {
        let data = try XCTUnwrap(Self.samplePNG(width: 40, height: 30))
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let service = PhotoExportService(directory: directory)
        var adjustments = PhotoAdjustmentState()
        adjustments.exposure = 0.5
        let request = ExportRequest(data: data, typeIdentifier: "public.png", adjustments: adjustments,
                                    options: ExportOptions(content: .adjusted, format: .png, cropToFraming: true),
                                    normalizedCrop: CGRect(x: 0, y: 0, width: 0.5, height: 1), overlays: OverlayBurnIn())
        let url = try service.exportSynchronously(request)
        let image = try XCTUnwrap(UIImage(contentsOfFile: url.path)?.cgImage)
        XCTAssertEqual(image.width, 20)
        XCTAssertEqual(image.height, 30)
    }

    static func samplePNG(width: Int, height: Int) -> Data? {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format)
        return renderer.pngData { context in
            UIColor.systemTeal.setFill()
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
    }
}

final class DownsamplerTests: XCTestCase {
    func testPreviewIsDownsampledAndKeepsFullSize() throws {
        let data = try XCTUnwrap(ExportTests.samplePNG(width: 300, height: 200))
        let output = try ImageDownsampler.makePreview(from: data, maxPixelSize: 100, maxSourcePixels: 1_000_000)
        XCTAssertEqual(max(output.preview.width, output.preview.height), 100)
        XCTAssertEqual(output.pixelSize, CGSize(width: 300, height: 200))
        XCTAssertEqual(output.typeIdentifier, "public.png")
    }

    func testRejectsGarbage() {
        XCTAssertThrowsError(try ImageDownsampler.makePreview(from: Data("not an image".utf8), maxPixelSize: 100, maxSourcePixels: 1e9)) {
            XCTAssertEqual($0 as? PhotoImportError, .unsupportedData)
        }
    }

    func testRejectsOversizedSource() throws {
        let data = try XCTUnwrap(ExportTests.samplePNG(width: 300, height: 200))
        XCTAssertThrowsError(try ImageDownsampler.makePreview(from: data, maxPixelSize: 100, maxSourcePixels: 1000)) {
            XCTAssertEqual($0 as? PhotoImportError, .tooLarge)
        }
    }
}

final class ExportSizeTests: XCTestCase {
    func testPhotoSizesScaleByLongEdgeAndNeverEnlarge() {
        let big = CIImage(color: .red).cropped(to: CGRect(x: 0, y: 0, width: 4000, height: 3000))
        let small = PhotoExportService.resized(big, longEdge: ExportSize.small.photoLongEdge)
        XCTAssertEqual(small.extent, CGRect(x: 0, y: 0, width: 1152, height: 864))
        XCTAssertTrue(PhotoExportService.resized(big, longEdge: nil) === big, "Full keeps the original")
        let tiny = CIImage(color: .red).cropped(to: CGRect(x: 0, y: 0, width: 800, height: 600))
        XCTAssertEqual(PhotoExportService.resized(tiny, longEdge: 2304).extent, tiny.extent, "never upscales")
    }

    func testLabels() {
        XCTAssertEqual(ExportSize.large.photoLabel, "12 MP")
        XCTAssertEqual(ExportSize.medium.videoLabel, "1080p")
        XCTAssertEqual(ExportSize.full.videoPreset, AVAssetExportPresetHighestQuality)
    }
}
