import UIKit
import XCTest
@testable import CameraGlassPro

final class LiveTextTests: XCTestCase {
    func testRecognizesLargeText() throws {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let size = CGSize(width: 800, height: 300)
        let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            let text = NSAttributedString(string: "HELLO GLASS", attributes: [
                .font: UIFont.systemFont(ofSize: 96, weight: .bold),
                .foregroundColor: UIColor.black,
            ])
            text.draw(at: CGPoint(x: 40, y: 90))
        }
        let cgImage = try XCTUnwrap(image.cgImage)
        let lines = try LiveTextService.recognize(in: cgImage)
        let joined = lines.map(\.text).joined(separator: " ").uppercased()
        XCTAssertTrue(joined.contains("HELLO"), "recognized: \(joined)")
        let box = try XCTUnwrap(lines.first?.box)
        XCTAssertTrue(CGRect(x: 0, y: 0, width: 1, height: 1).contains(box.origin), "boxes are normalized")
        XCTAssertLessThan(box.minY, 0.6, "top-left origin: text sits in the upper-middle of the image")
    }

    @MainActor
    func testLiveTextControlTogglesAndClears() {
        let vm = CameraWorkspaceViewModel(defaults: UserDefaults(suiteName: "LiveText-\(UUID().uuidString)") ?? .standard)
        XCTAssertFalse(vm.isAvailable(.liveText), "needs a photo or video")
        vm.setLiveText(true)
        XCTAssertTrue(vm.liveTextEnabled)
        vm.setLiveText(false)
        XCTAssertTrue(vm.recognizedText.isEmpty)
    }
}
