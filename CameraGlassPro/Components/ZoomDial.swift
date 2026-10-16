import SwiftUI

/// Camera-style curved zoom dial: ticks on an arc (log scale, 0.5×–5×) slide under a fixed pointer.
/// Purely visual; the drag that drives it lives on the zoom area in `CameraShutterControls`.
struct ZoomDial: View {
    let zoom: CGFloat

    /// Angle (radians) the full 0.5×–5× range spans on the arc.
    static let span: Double = 1.7

    /// 0...1 position of a zoom value on the dial (log scale, like the Camera app).
    static func position(for zoom: CGFloat) -> Double {
        log(Double(ZoomLimits.clamp(zoom)) / Double(ZoomLimits.minimum))
            / log(Double(ZoomLimits.maximum) / Double(ZoomLimits.minimum))
    }

    static func zoom(at position: Double) -> CGFloat {
        let ratio = Double(ZoomLimits.maximum) / Double(ZoomLimits.minimum)
        return ZoomLimits.clamp(CGFloat(Double(ZoomLimits.minimum) * pow(ratio, min(max(position, 0), 1))))
    }

    /// Zoom after dragging `distance` points along an arc of `radius` (drag left = zoom in).
    static func zoom(from start: CGFloat, dragDistance distance: CGFloat, radius: CGFloat) -> CGFloat {
        guard radius > 0 else { return start }
        let deltaPosition = -Double(distance / radius) / span
        return zoom(at: position(for: start) + deltaPosition)
    }

    private static let ticks: [CGFloat] = stride(from: 0.5, through: 5.0001, by: 0.1).map { CGFloat($0) }

    var body: some View {
        VStack(spacing: 2) {
            Text(ZoomLimits.label(for: zoom) + "×")
                .font(.system(size: 15, weight: .semibold).monospacedDigit())
                .foregroundStyle(.yellow)
                .rotatesWithDevice()
            Canvas { context, size in
                let radius = size.width * 0.95
                let center = CGPoint(x: size.width / 2, y: 14 + radius)
                let current = Self.position(for: zoom)

                // Dark band along the arc.
                var band = Path()
                band.addArc(center: center, radius: radius + 4, startAngle: .degrees(-150), endAngle: .degrees(-30), clockwise: false)
                band.addArc(center: center, radius: radius - 44, startAngle: .degrees(-30), endAngle: .degrees(-150), clockwise: true)
                band.closeSubpath()
                context.fill(band, with: .color(.black.opacity(0.45)))

                for tick in Self.ticks {
                    let theta = (Self.position(for: tick) - current) * Self.span
                    guard abs(theta) < 0.62 else { continue }
                    let isMajor = ZoomLimits.presets.contains { abs($0 - tick) < 0.01 }
                    let length: CGFloat = isMajor ? 12 : 6
                    let outer = point(center: center, radius: radius, angle: theta)
                    let inner = point(center: center, radius: radius - length, angle: theta)
                    var line = Path()
                    line.move(to: outer)
                    line.addLine(to: inner)
                    context.stroke(line, with: .color(.white.opacity(isMajor ? 0.95 : 0.55)), lineWidth: isMajor ? 1.5 : 1)
                    if isMajor {
                        let labelPoint = point(center: center, radius: radius - 26, angle: theta)
                        context.draw(
                            Text(ZoomLimits.label(for: tick)).font(.system(size: 12, weight: .semibold)).foregroundStyle(.white),
                            at: labelPoint
                        )
                    }
                }

                // Fixed pointer at the top.
                var pointer = Path()
                pointer.move(to: CGPoint(x: size.width / 2, y: 10))
                pointer.addLine(to: CGPoint(x: size.width / 2, y: 26))
                context.stroke(pointer, with: .color(.yellow), lineWidth: 2)
            }
            .frame(height: 64)
        }
        .accessibilityHidden(true) // the zoom area carries the accessible adjustable action
    }

    private func point(center: CGPoint, radius: CGFloat, angle: Double) -> CGPoint {
        CGPoint(x: center.x + radius * CGFloat(sin(angle)), y: center.y - radius * CGFloat(cos(angle)))
    }
}
