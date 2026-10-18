import CoreGraphics
import Foundation

/// How faces or painted areas are hidden.
enum Redaction: String, Codable, CaseIterable, Identifiable, Sendable {
    case none, blur, pixelate

    var id: String { rawValue }
    var label: String { self == .none ? "Off" : rawValue.capitalized }
}

/// One finger stroke painted in the Blur & Pixelate editor.
struct RedactionStroke: Equatable, Codable, Sendable {
    var mode: Redaction
    /// Brush diameter as a share of the picture's shorter side.
    var width: Double
    /// Normalized points (0...1, top-left origin) on the final framing.
    var points: [CGPoint]

    static let limit = 60
}
