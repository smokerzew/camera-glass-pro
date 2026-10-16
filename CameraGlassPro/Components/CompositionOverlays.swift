import SwiftUI

/// Evenly spaced grid. Drawn only in the viewfinder layer, never into the image data.
struct GridShape: Shape {
    var divisions: Int

    /// Interior line positions for `length` split into `divisions` parts.
    static func lineOffsets(divisions: Int, length: CGFloat) -> [CGFloat] {
        guard divisions > 1 else { return [] }
        return (1..<divisions).map { length * CGFloat($0) / CGFloat(divisions) }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        for x in Self.lineOffsets(divisions: divisions, length: rect.width) {
            path.move(to: CGPoint(x: rect.minX + x, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.minX + x, y: rect.maxY))
        }
        for y in Self.lineOffsets(divisions: divisions, length: rect.height) {
            path.move(to: CGPoint(x: rect.minX, y: rect.minY + y))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + y))
        }
        return path
    }
}

struct CameraGridOverlay: View {
    let style: GridStyle
    let opacity: Double

    var body: some View {
        if let divisions = style.divisions {
            GridShape(divisions: divisions)
                .stroke(.white.opacity(opacity), lineWidth: style == .fine ? 0.5 : 0.8)
                .shadow(color: .black.opacity(0.35), radius: 0.5) // keeps lines visible on bright skies
                .accessibilityHidden(true)
        }
    }
}

/// Static composition level: a horizon reference with a centered alignment mark.
/// It does not read device sensors; it is a guide for lining up the imported photo.
struct CameraLevelGuide: View {
    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let center = CGPoint(x: proxy.size.width / 2, y: proxy.size.height / 2)
            ZStack {
                Path { path in
                    let gap: CGFloat = 26
                    let arm = width * 0.18
                    path.move(to: CGPoint(x: center.x - gap - arm, y: center.y))
                    path.addLine(to: CGPoint(x: center.x - gap, y: center.y))
                    path.move(to: CGPoint(x: center.x + gap, y: center.y))
                    path.addLine(to: CGPoint(x: center.x + gap + arm, y: center.y))
                }
                .stroke(.white.opacity(0.85), style: StrokeStyle(lineWidth: 1.2, lineCap: .round))

                Path { path in
                    path.move(to: CGPoint(x: center.x - 14, y: center.y))
                    path.addLine(to: CGPoint(x: center.x + 14, y: center.y))
                }
                .stroke(.yellow, style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
            }
            .shadow(color: .black.opacity(0.4), radius: 1)
        }
        .accessibilityHidden(true)
    }
}

/// Center crosshair, as in the reference screenshots.
struct CenterGuide: View {
    var body: some View {
        ZStack {
            Rectangle().frame(width: 44, height: 1.2)
            Rectangle().frame(width: 1.2, height: 44)
        }
        .foregroundStyle(.yellow)
        .shadow(color: .black.opacity(0.4), radius: 1)
        .accessibilityHidden(true)
    }
}

/// Dims everything outside a centered landscape band (video, cinematic, pano guides).
struct ModeFramingGuide: View {
    let ratio: CGFloat

    var body: some View {
        GeometryReader { proxy in
            let bandHeight = min(proxy.size.height, proxy.size.width / ratio)
            let inset = (proxy.size.height - bandHeight) / 2
            VStack(spacing: 0) {
                Color.black.opacity(0.55).frame(height: inset)
                Rectangle().strokeBorder(.white.opacity(0.6), lineWidth: 1).frame(height: bandHeight)
                Color.black.opacity(0.55).frame(height: inset)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Soft vignette for the preview-only Portrait look.
struct PortraitVignette: View {
    var body: some View {
        GeometryReader { proxy in
            RadialGradient(
                colors: [.clear, .black.opacity(0.55)],
                center: .center,
                startRadius: min(proxy.size.width, proxy.size.height) * 0.3,
                endRadius: max(proxy.size.width, proxy.size.height) * 0.75
            )
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
