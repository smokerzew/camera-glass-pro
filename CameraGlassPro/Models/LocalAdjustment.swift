import Foundation

/// A graduated (from one edge) or radial (circle) filter: brightness, saturation and warmth inside a soft mask.
/// Positions are normalized to the final (cropped) picture with a top-left origin.
struct LocalAdjustment: Equatable, Codable, Sendable, Identifiable {
    enum Shape: String, Codable, Sendable {
        case graduated, radial

        var label: String { self == .graduated ? "Graduated" : "Radial" }
        var systemImage: String { self == .graduated ? "rectangle.tophalf.inset.filled" : "circle.dashed.inset.filled" }
    }

    enum Edge: String, Codable, CaseIterable, Identifiable, Sendable {
        case top, bottom, left, right

        var id: String { rawValue }
        var label: String { rawValue.capitalized }
    }

    static let limit = 4

    var id = UUID()
    var shape: Shape
    /// Graduated: the edge the effect starts from, and how far into the picture it reaches (0...1).
    var edge: Edge = .top
    var position = 0.5
    /// Radial: center (0...1) and radius as a share of half the picture's diagonal.
    var centerX = 0.5
    var centerY = 0.45
    var size = 0.35
    /// How much of the reach fades out softly (0 = hard edge, 1 = fades all the way).
    var softness = 0.7
    /// Radial: affect the outside of the circle instead of the inside.
    var inverted = false
    var edit = RegionEdit()

    init(shape: Shape) {
        self.shape = shape
        if shape == .graduated { edit.exposure = -0.3 } else { edit.exposure = 0.3 } // a visible starting point
    }

    /// Every value inside its valid range.
    var clamped: LocalAdjustment {
        var copy = self
        func unit(_ v: Double, _ fallback: Double) -> Double { v.isFinite ? min(max(v, 0), 1) : fallback }
        copy.position = unit(position, 0.5)
        copy.centerX = unit(centerX, 0.5)
        copy.centerY = unit(centerY, 0.5)
        copy.size = max(0.02, unit(size, 0.35))
        copy.softness = unit(softness, 0.7)
        return copy
    }
}
