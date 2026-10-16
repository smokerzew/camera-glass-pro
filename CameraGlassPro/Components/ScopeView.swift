import SwiftUI

/// Exposure scope panel: luminance histogram, RGB histogram or RGB Parade waveform.
struct ScopeView: View {
    let mode: ScopeMode
    let data: ScopeData

    var body: some View {
        Canvas { context, size in
            switch mode {
            case .off:
                break
            case .luminance:
                context.fill(histogramPath(data.luma, in: size), with: .color(.white.opacity(0.85)))
            case .rgb:
                context.blendMode = .plusLighter
                context.fill(histogramPath(data.red, in: size), with: .color(.red.opacity(0.7)))
                context.fill(histogramPath(data.green, in: size), with: .color(.green.opacity(0.7)))
                context.fill(histogramPath(data.blue, in: size), with: .color(.blue.opacity(0.8)))
            case .parade:
                let third = size.width / 3
                drawWaveform(data.redWave, color: .red, in: CGRect(x: 0, y: 0, width: third - 2, height: size.height), context: &context)
                drawWaveform(data.greenWave, color: .green, in: CGRect(x: third, y: 0, width: third - 2, height: size.height), context: &context)
                drawWaveform(data.blueWave, color: .blue, in: CGRect(x: third * 2, y: 0, width: third - 2, height: size.height), context: &context)
            }
            // Quarter guides, like a scope graticule.
            for fraction in [0.25, 0.5, 0.75] {
                var line = Path()
                line.move(to: CGPoint(x: 0, y: size.height * fraction))
                line.addLine(to: CGPoint(x: size.width, y: size.height * fraction))
                context.stroke(line, with: .color(.white.opacity(0.12)), lineWidth: 0.5)
            }
        }
        .padding(6)
        .frame(width: 156, height: 88)
        .background(.black.opacity(0.35), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .cameraGlass(.subtle, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(alignment: .topTrailing) {
            Text(mode.shortLabel ?? "")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(.white.opacity(0.7))
                .padding(5)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(mode.label) scope")
        .accessibilityValue(accessibilitySummary)
    }

    private func histogramPath(_ values: [Float], in size: CGSize) -> Path {
        var path = Path()
        guard values.count > 1 else { return path }
        let step = size.width / CGFloat(values.count - 1)
        path.move(to: CGPoint(x: 0, y: size.height))
        for (index, value) in values.enumerated() {
            path.addLine(to: CGPoint(x: CGFloat(index) * step, y: size.height * (1 - CGFloat(value))))
        }
        path.addLine(to: CGPoint(x: size.width, y: size.height))
        path.closeSubpath()
        return path
    }

    private func drawWaveform(_ wave: [Float], color: Color, in rect: CGRect, context: inout GraphicsContext) {
        let bins = ScopeData.bins
        let columns = data.columns
        guard columns > 0, wave.count == columns * bins else { return }
        let cellWidth = rect.width / CGFloat(columns)
        let cellHeight = rect.height / CGFloat(bins)
        for column in 0..<columns {
            for bin in 0..<bins {
                let value = wave[column * bins + bin]
                guard value > 0.02 else { continue }
                let cell = CGRect(
                    x: rect.minX + CGFloat(column) * cellWidth,
                    y: rect.maxY - CGFloat(bin + 1) * cellHeight,
                    width: cellWidth + 0.3, height: cellHeight + 0.3
                )
                context.fill(Path(cell), with: .color(color.opacity(Double(value) * 0.9)))
            }
        }
    }

    /// Spoken summary: where most of the tones sit.
    private var accessibilitySummary: String {
        let bins = data.luma
        guard !bins.isEmpty else { return "" }
        let total = bins.reduce(0, +)
        guard total > 0 else { return "" }
        let weighted = bins.enumerated().reduce(Float(0)) { $0 + Float($1.offset) * $1.element } / total
        let position = weighted / Float(bins.count - 1)
        switch position {
        case ..<0.33: return "Mostly dark tones"
        case ..<0.66: return "Mostly midtones"
        default: return "Mostly bright tones"
        }
    }
}
