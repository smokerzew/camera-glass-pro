import CoreGraphics
import Foundation

/// Exposure scope presets reported for the iOS 27 Camera app.
enum ScopeMode: String, CaseIterable {
    case off, luminance, rgb, parade

    var label: String {
        switch self {
        case .off: "Off"
        case .luminance: "Luminance"
        case .rgb: "RGB"
        case .parade: "RGB Parade"
        }
    }

    /// Short text for the control's circle / top bar.
    var shortLabel: String? {
        switch self {
        case .off: nil
        case .luminance: "LUMA"
        case .rgb: "RGB"
        case .parade: "PARADE"
        }
    }

    var next: ScopeMode {
        let all = Self.allCases
        let index = all.firstIndex(of: self) ?? 0
        return all[(index + 1) % all.count]
    }
}

/// Histogram and waveform data computed from a small copy of the current frame.
struct ScopeData: Equatable, Sendable {
    static let bins = 64

    /// Histograms normalized so the tallest bin is 1.
    var luma: [Float]
    var red: [Float]
    var green: [Float]
    var blue: [Float]
    /// Waveforms for RGB Parade: `columns` × `bins` per channel (row-major by column), normalized 0...1.
    var columns: Int
    var redWave: [Float]
    var greenWave: [Float]
    var blueWave: [Float]

    /// Downsamples to at most `maxWidth` pixels wide and counts every pixel. Pure CPU, safe off the main thread.
    static func compute(from image: CGImage, maxWidth: Int = 160, columns: Int = 64) -> ScopeData? {
        let scale = min(1, Double(maxWidth) / Double(max(image.width, 1)))
        let width = max(1, Int(Double(image.width) * scale))
        let height = max(1, Int(Double(image.height) * scale))
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
            ) else { return false }
            context.interpolationQuality = .low
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return nil }

        let bins = Self.bins
        var luma = [Float](repeating: 0, count: bins)
        var red = luma, green = luma, blue = luma
        var redWave = [Float](repeating: 0, count: columns * bins)
        var greenWave = redWave, blueWave = redWave

        for y in 0..<height {
            for x in 0..<width {
                let i = (y * width + x) * 4
                let r = Int(pixels[i]), g = Int(pixels[i + 1]), b = Int(pixels[i + 2])
                let l = (2126 * r + 7152 * g + 722 * b) / 10000
                red[r * bins / 256] += 1
                green[g * bins / 256] += 1
                blue[b * bins / 256] += 1
                luma[l * bins / 256] += 1
                let column = x * columns / width
                redWave[column * bins + r * bins / 256] += 1
                greenWave[column * bins + g * bins / 256] += 1
                blueWave[column * bins + b * bins / 256] += 1
            }
        }

        return ScopeData(
            luma: normalized(luma), red: normalized(red), green: normalized(green), blue: normalized(blue),
            columns: columns,
            redWave: normalized(redWave, curve: true),
            greenWave: normalized(greenWave, curve: true),
            blueWave: normalized(blueWave, curve: true)
        )
    }

    /// Scales so the max is 1; `curve` lifts faint traces so sparse waveforms stay visible.
    private static func normalized(_ values: [Float], curve: Bool = false) -> [Float] {
        guard let peak = values.max(), peak > 0 else { return values }
        return values.map { curve ? ($0 / peak).squareRoot() : $0 / peak }
    }
}
