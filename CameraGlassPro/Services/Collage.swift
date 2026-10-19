import CoreImage
import Foundation

/// Collage: 2-6 photos in a seamless grid (no gaps, borders or text), in one of a few layouts and shapes.
enum Collage {
    static let maxPhotos = 6

    enum Shape: String, CaseIterable, Identifiable, Sendable {
        case square, portrait, story, landscape

        var id: String { rawValue }
        var label: String {
            switch self {
            case .square: "1:1"
            case .portrait: "4:5"
            case .story: "9:16"
            case .landscape: "3:2"
            }
        }
        /// Width / height.
        var ratio: CGFloat {
            switch self {
            case .square: 1
            case .portrait: 4.0 / 5
            case .story: 9.0 / 16
            case .landscape: 3.0 / 2
            }
        }
    }

    /// How the cells get their edits.
    enum EditMode: String, CaseIterable, Identifiable, Sendable {
        /// Each photo keeps the edit you gave it (swipe to each photo and edit it first).
        case individual
        /// The current photo's edit goes on every photo.
        case same

        var id: String { rawValue }
        var label: String { self == .individual ? "Each Photo's Own" : "Same Edit on All" }
    }

    /// Layouts for `count` photos: cells as unit rects (top-left origin), one per photo, in order.
    static func layouts(for count: Int) -> [[CGRect]] {
        func r(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect { CGRect(x: x, y: y, width: w, height: h) }
        let t: CGFloat = 1.0 / 3
        switch count {
        case 2: return [[r(0, 0, 0.5, 1), r(0.5, 0, 0.5, 1)],
                        [r(0, 0, 1, 0.5), r(0, 0.5, 1, 0.5)]]
        case 3: return [[r(0, 0, 0.5, 1), r(0.5, 0, 0.5, 0.5), r(0.5, 0.5, 0.5, 0.5)],
                        [r(0, 0, 1, 0.5), r(0, 0.5, 0.5, 0.5), r(0.5, 0.5, 0.5, 0.5)],
                        [r(0, 0, t, 1), r(t, 0, t, 1), r(2 * t, 0, t, 1)]]
        case 4: return [[r(0, 0, 0.5, 0.5), r(0.5, 0, 0.5, 0.5), r(0, 0.5, 0.5, 0.5), r(0.5, 0.5, 0.5, 0.5)],
                        [r(0, 0, 1, 0.6), r(0, 0.6, t, 0.4), r(t, 0.6, t, 0.4), r(2 * t, 0.6, t, 0.4)],
                        [r(0, 0, 0.6, 1), r(0.6, 0, 0.4, t), r(0.6, t, 0.4, t), r(0.6, 2 * t, 0.4, t)]]
        case 5: return [[r(0, 0, 0.5, 0.5), r(0.5, 0, 0.5, 0.5), r(0, 0.5, t, 0.5), r(t, 0.5, t, 0.5), r(2 * t, 0.5, t, 0.5)],
                        [r(0, 0, 0.5, 1), r(0.5, 0, 0.25, 0.5), r(0.75, 0, 0.25, 0.5), r(0.5, 0.5, 0.25, 0.5), r(0.75, 0.5, 0.25, 0.5)]]
        case 6: return [[r(0, 0, 0.5, t), r(0.5, 0, 0.5, t), r(0, t, 0.5, t), r(0.5, t, 0.5, t), r(0, 2 * t, 0.5, t), r(0.5, 2 * t, 0.5, t)],
                        [r(0, 0, t, 0.5), r(t, 0, t, 0.5), r(2 * t, 0, t, 0.5), r(0, 0.5, t, 0.5), r(t, 0.5, t, 0.5), r(2 * t, 0.5, t, 0.5)]]
        default: return []
        }
    }

    /// Renders the collage, `longEdge` pixels on its long side. Each photo fills its cell (centered crop).
    static func render(_ photos: [CIImage], layout: [CGRect], shape: Shape, longEdge: CGFloat) -> CIImage? {
        guard !photos.isEmpty, photos.count == layout.count else { return nil }
        let size = shape.ratio >= 1
            ? CGSize(width: longEdge, height: (longEdge / shape.ratio).rounded())
            : CGSize(width: (longEdge * shape.ratio).rounded(), height: longEdge)
        let canvas = CGRect(origin: .zero, size: size)
        var output = CIImage(color: .black).cropped(to: canvas)
        for (photo, unit) in zip(photos, layout) {
            // Whole pixels, so neighboring cells meet exactly with no seam.
            let x0 = (unit.minX * size.width).rounded(), x1 = (unit.maxX * size.width).rounded()
            let top = (unit.minY * size.height).rounded(), bottom = (unit.maxY * size.height).rounded()
            let cell = CGRect(x: x0, y: size.height - bottom, width: x1 - x0, height: bottom - top) // Core Image: y up
            let e = photo.extent
            guard e.width > 0, e.height > 0, cell.width > 0, cell.height > 0 else { continue }
            let scale = max(cell.width / e.width, cell.height / e.height)
            let placed = photo.transformed(by: CGAffineTransform(translationX: -e.midX, y: -e.midY)
                .concatenating(CGAffineTransform(scaleX: scale, y: scale))
                .concatenating(CGAffineTransform(translationX: cell.midX, y: cell.midY)))
                .cropped(to: cell)
            output = placed.composited(over: output)
        }
        return output.cropped(to: canvas)
    }
}
