import CoreGraphics
import Foundation

/// How faces or painted areas are hidden.
enum Redaction: String, Codable, CaseIterable, Identifiable, Sendable {
    case none, blur, pixelate

    var id: String { rawValue }
    var label: String { self == .none ? "Off" : rawValue.capitalized }
}

/// What Blur & Pixelate hides: every detected face, or only what you draw. One at a time.
enum RedactionTarget: String, Codable, CaseIterable, Identifiable, Sendable {
    case faces, drawing

    var id: String { rawValue }
    var label: String { rawValue.capitalized }
}

/// What the Ghost effect copies.
enum GhostTarget: String, Codable, CaseIterable, Identifiable, Sendable {
    case subject, photo

    var id: String { rawValue }
    var label: String { self == .subject ? "Subject" : "Whole Photo" }
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

extension Redaction {
    /// Privacy blur radius as a share of the long side: 0 is a barely-there softening, then smoothly up to a
    /// blur that hides a face completely (strength^1.6, no built-in minimum).
    static func blurShare(_ strength: Double) -> CGFloat {
        let s = min(max(strength, 0), 1)
        return CGFloat(0.0003 + 0.036 * pow(s, 1.6))
    }

    /// Pixel block size as a share of the long side: fine 0.3% blocks at 0, up to 6% (unreadable) at full.
    static func blockShare(_ strength: Double) -> CGFloat {
        let s = min(max(strength, 0), 1)
        return CGFloat(0.003 + 0.057 * pow(s, 1.5))
    }
}
