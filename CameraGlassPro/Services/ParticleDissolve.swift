import CoreImage

/// SUBJECT > Create > Dispersion styles. Each keeps its own settings, so switching never changes the other.
enum DispersionStyle: String, Codable, CaseIterable, Identifiable, Sendable {
    /// The original: the subject breaks into larger pieces that spray away.
    case pieces
    /// The subject dissolves into thousands of fine, image-colored particles along a direction.
    case particleDissolve

    var id: String { rawValue }
    var label: String { self == .pieces ? "Pieces" : "Particle Dissolve" }
}

/// How Particle Dissolve's sliders (all 0...1) map to what renders. Sizes scale with the picture, so the
/// preview and the full-resolution export look the same.
enum ParticleDissolveMapping {
    /// Where dissolving starts along the subject (0 = its start, 1 = its end): more Dissolve starts it earlier.
    static func edge(_ amount: Double) -> Float { Float(1.1 - 1.2 * min(max(amount, 0), 1)) }
    /// Width of the change from intact to particles, as a share of the subject's length.
    static func softness(_ value: Double) -> Float { Float(0.04 + 0.4 * min(max(value, 0), 1)) }
    /// Particle size in pixels: about 1 px per 1000 px of width at the small end, 8× that at the large end.
    static func cell(_ size: Double, width: CGFloat) -> CGFloat {
        let s = min(max(size, 0), 1)
        return max(1.5, width / 1000 * CGFloat(1 + 7 * pow(s, 1.5)))
    }
    /// Share of dissolving particles that fly off (the rest just leave gaps).
    static func density(_ value: Double) -> Float { Float(0.15 + 0.85 * min(max(value, 0), 1)) }
    /// Farthest flight, as a multiple of the subject's length along the direction.
    static func travel(_ spread: Double) -> CGFloat { CGFloat(0.1 + 1.4 * min(max(spread, 0), 1)) }
    /// How much bigger the speckled echo of the subject grows (with Spread): 1.1× up to 2×.
    static func zoom(_ spread: Double) -> Float { Float(1.1 + 0.9 * min(max(spread, 0), 1)) }
    /// Chance a speckle of the echo shows (0 = no echo).
    static func echo(_ value: Double) -> Float { Float(min(max(value, 0), 1)) }
}

extension ImageProcessingService {
    /// Particle Dissolve: the subject (white in `mask`) breaks into dense, fine particles that inherit the photo's
    /// colors, starting partway across it in `degrees` direction (0 right, 90 up) with an organic, uneven edge.
    /// Particles drift that way, densest where they left; the gaps show the scene behind the subject.
    func particleDissolve(_ image: CIImage, mask: CIImage, amount: Double, size: Double, density: Double, spread: Double,
                          degrees: Double, softness: Double, echo: Double = 0, extent e: CGRect) -> CIImage {
        guard amount > 0, let kernel = Self.particleDissolveKernel,
              let box = maskBounds(mask.cropped(to: e), extent: e) else { return image }
        let radians = degrees * .pi / 180
        let dir = CGPoint(x: cos(radians), y: sin(radians))
        let projections = [CGPoint(x: box.minX, y: box.minY), CGPoint(x: box.maxX, y: box.minY),
                           CGPoint(x: box.minX, y: box.maxY), CGPoint(x: box.maxX, y: box.maxY)].map { $0.x * dir.x + $0.y * dir.y }
        let start = projections.min() ?? 0, length = max(1, (projections.max() ?? 1) - start)
        let cell = ParticleDissolveMapping.cell(size, width: e.width)
        let travel = ParticleDissolveMapping.travel(spread) * length
        let plate = subjectPlate(image, mask: mask.cropped(to: e), extent: e)
        let reach = travel + cell * 2
        // The echo grows out from the subject's near edge, through its middle.
        let middle = CGPoint(x: box.midX, y: box.midY)
        let back = start - (middle.x * dir.x + middle.y * dir.y)
        let anchor = CGPoint(x: middle.x + dir.x * back, y: middle.y + dir.y * back)
        let subjectArea = box.insetBy(dx: -reach, dy: -reach)
        let output = kernel.apply(extent: e, roiCallback: { index, rect in
            index == 1 ? rect : rect.insetBy(dx: -reach, dy: -reach).union(subjectArea)
        }, arguments: [
            image.clampedToExtent(), plate.clampedToExtent(), mask.cropped(to: e).clampedToExtent(),
            CIVector(x: dir.x, y: dir.y), CIVector(x: start, y: length),
            ParticleDissolveMapping.edge(amount), ParticleDissolveMapping.softness(softness), Float(cell),
            ParticleDissolveMapping.density(density), Float(travel), Float(length * 0.18),
            CIVector(x: anchor.x, y: anchor.y), ParticleDissolveMapping.zoom(spread), ParticleDissolveMapping.echo(echo),
        ])
        return output?.cropped(to: e) ?? image
    }
}
