import CoreGraphics
import Foundation
import Vision

/// A line of text found in the current frame. `box` is normalized (0...1) with a top-left origin.
struct RecognizedText: Identifiable, Equatable, Sendable {
    let id = UUID()
    let text: String
    let box: CGRect
}

/// On-device text recognition (Vision). Nothing is sent off the device.
enum LiveTextService {
    static func recognize(in image: CGImage) throws -> [RecognizedText] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        try VNImageRequestHandler(cgImage: image, orientation: .up).perform([request])
        return (request.results ?? []).compactMap { observation in
            guard let candidate = observation.topCandidates(1).first else { return nil }
            let box = observation.boundingBox // Vision: bottom-left origin
            return RecognizedText(
                text: candidate.string,
                box: CGRect(x: box.minX, y: 1 - box.maxY, width: box.width, height: box.height)
            )
        }
    }
}
