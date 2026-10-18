import Foundation

/// Average and spread of a photo's brightness (Y) and color (Cb, Cr), in display values 0...1.
struct ColorStats: Equatable, Sendable {
    var mean: [Double]
    var std: [Double]

    /// From sRGB RGBA8 pixels.
    static func from(rgba: [UInt8]) -> ColorStats {
        var sum = [0.0, 0.0, 0.0], squares = [0.0, 0.0, 0.0]
        var count = 0.0
        for i in stride(from: 0, to: rgba.count - 3, by: 4) {
            let r = Double(rgba[i]) / 255, g = Double(rgba[i + 1]) / 255, b = Double(rgba[i + 2]) / 255
            let y = 0.299 * r + 0.587 * g + 0.114 * b
            let values = [y, (b - y) * 0.564 + 0.5, (r - y) * 0.713 + 0.5]
            for c in 0..<3 {
                sum[c] += values[c]
                squares[c] += values[c] * values[c]
            }
            count += 1
        }
        guard count > 0 else { return ColorStats(mean: [0.5, 0.5, 0.5], std: [0.2, 0.05, 0.05]) }
        let mean = sum.map { $0 / count }
        let std = (0..<3).map { max(0.001, (squares[$0] / count - mean[$0] * mean[$0]).squareRoot()) }
        return ColorStats(mean: mean, std: std)
    }
}

/// Match Look: moves this photo's brightness and color statistics onto a reference photo's
/// (Reinhard-style color transfer in YCbCr), blended by `amount`.
struct LookMatch: Equatable, Codable, Sendable {
    /// Per channel (Y, Cb, Cr): new = old * scale + offset.
    var scale: [Double]
    var offset: [Double]
    var amount = 0.8

    var isUsable: Bool {
        scale.count == 3 && offset.count == 3 && (scale + offset + [amount]).allSatisfy(\.isFinite)
    }

    /// Transfer from `source` to `reference`, with limits so odd references can't produce wild results.
    static func between(source: ColorStats, reference: ColorStats, amount: Double = 0.8) -> LookMatch {
        let limits: [ClosedRange<Double>] = [0.6...1.6, 0.5...2.0, 0.5...2.0]
        let offsetLimits: [Double] = [0.3, 0.12, 0.12]
        var scale = [1.0, 1.0, 1.0], offset = [0.0, 0.0, 0.0]
        for c in 0..<3 {
            let s = min(max(reference.std[c] / source.std[c], limits[c].lowerBound), limits[c].upperBound)
            scale[c] = s
            // Offset is measured around the neutral point (0.5 for color), so it stays a small shift.
            let pivot = c == 0 ? 0.0 : 0.5
            let shift = (reference.mean[c] - pivot) - (source.mean[c] - pivot) * s
            offset[c] = min(max(shift, -offsetLimits[c]), offsetLimits[c]) + pivot * (1 - s)
        }
        return LookMatch(scale: scale, offset: offset, amount: min(max(amount, 0), 1))
    }
}
