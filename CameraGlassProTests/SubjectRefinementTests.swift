import CoreImage
import XCTest
@testable import CameraGlassPro

/// Subject masks: main-subject choice, edge fitting and edge color clean-up.
final class SubjectRefinementTests: XCTestCase {
    private let processor = ImageProcessingService.shared

    private func value(_ image: CIImage, _ x: CGFloat, _ y: CGFloat) -> (r: Double, g: Double, b: Double) {
        var p = [UInt8](repeating: 0, count: 4)
        processor.context.render(image, toBitmap: &p, rowBytes: 4, bounds: CGRect(x: x, y: y, width: 1, height: 1),
                                 format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
        return (Double(p[0]), Double(p[1]), Double(p[2]))
    }

    func testMainSubjectLeavesSmallFarThingsOut() {
        // A big subject (label 1), a person half its size (2) and a tiny sign far away (3).
        let kept = SubjectMasker.keptInstances(counts: [1: 40_000, 2: 20_000, 3: 300], total: 400_000)
        XCTAssertEqual(kept, IndexSet([1, 2]))
        XCTAssertTrue(SubjectMasker.keptInstances(counts: [:], total: 100).isEmpty)
        // Several small but sizable things in a big frame all count (each ≥ 2% of the frame).
        XCTAssertEqual(SubjectMasker.keptInstances(counts: [1: 30_000, 2: 4_000], total: 100_000), IndexSet([1, 2]))
    }

    /// A rough, blurry mask whose edge sits in the wrong place snaps to the photo's real edge.
    func testRefinedEdgeFollowsThePhoto() {
        let e = CGRect(x: 0, y: 0, width: 1200, height: 200)
        let photo = CIImage(color: CIColor(red: 0.1, green: 0.1, blue: 0.1)).cropped(to: CGRect(x: 0, y: 0, width: 600, height: 200))
            .composited(over: CIImage(color: CIColor(red: 0.9, green: 0.9, blue: 0.9)).cropped(to: e))
            .cropped(to: e) // dark left half (the subject), light right half: the real edge is at x = 600
        let rough = CIImage(color: .white).cropped(to: CGRect(x: 0, y: 0, width: 590, height: 200)) // edge 10 px too early
            .composited(over: CIImage(color: .black).cropped(to: e))
            .clampedToExtent().applyingGaussianBlur(sigma: 5).cropped(to: e)
        let refined = SubjectMasker.refine(rough, guide: photo, extent: e)
        XCTAssertEqual(refined.extent, e)
        /// Where the mask crosses 50% along the middle row.
        func crossing(_ mask: CIImage) -> Int {
            let values = value(row: mask, y: 100, from: 560, count: 80)
            return 560 + (values.firstIndex { $0 < 128 } ?? 80)
        }
        let before = crossing(rough), after = crossing(refined)
        XCTAssertLessThan(abs(after - 600), abs(before - 600), "the edge moves toward the photo's real edge (\(before) → \(after))")
        XCTAssertGreaterThan(value(refined, 300, 100).r, 240, "well inside stays subject")
        XCTAssertLessThan(value(refined, 900, 100).r, 15, "well outside stays background")
    }

    private func value(row image: CIImage, y: CGFloat, from x: CGFloat, count: Int) -> [UInt8] {
        var p = [UInt8](repeating: 0, count: count * 4)
        processor.context.render(image, toBitmap: &p, rowBytes: count * 4, bounds: CGRect(x: x, y: y, width: CGFloat(count), height: 1),
                                 format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
        return stride(from: 0, to: p.count, by: 4).map { p[$0] }
    }

    /// An edge pixel that is half red subject, half green background comes out red once cleaned.
    func testEdgeColorLosesTheOldBackground() {
        let e = CGRect(x: 0, y: 0, width: 200, height: 100)
        let green = CIImage(color: CIColor(red: 0, green: 0.8, blue: 0)).cropped(to: e)
        let mixed = CIImage(color: CIColor(red: 0.5, green: 0.4, blue: 0)).cropped(to: CGRect(x: 95, y: 0, width: 10, height: 100))
        let photo = mixed.composited(over: CIImage(color: CIColor(red: 1, green: 0, blue: 0)).cropped(to: CGRect(x: 0, y: 0, width: 95, height: 100)))
            .composited(over: green).cropped(to: e)
        let mask = CIImage(color: CIColor(red: 0.5, green: 0.5, blue: 0.5)).cropped(to: CGRect(x: 95, y: 0, width: 10, height: 100))
            .composited(over: CIImage(color: .white).cropped(to: CGRect(x: 0, y: 0, width: 95, height: 100)))
            .composited(over: CIImage(color: .black).cropped(to: e)).cropped(to: e)
        let cleaned = processor.decontaminated(photo, mask: mask, extent: e)
        let before = value(photo, 100, 50), after = value(cleaned, 100, 50)
        XCTAssertLessThan(after.g, before.g - 20, "less of the old green background")
        XCTAssertGreaterThan(after.r, before.r, "more of the red subject")
        XCTAssertEqual(value(cleaned, 40, 50).r, value(photo, 40, 50).r, accuracy: 2, "inside the subject nothing changes")
    }
}
