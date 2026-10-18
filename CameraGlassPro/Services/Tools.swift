import CoreGraphics
import CoreImage
import CoreImage.CIFilterBuiltins

/// A Refine Subject brush stroke: adds to or erases from the detected subject. Normalized points
/// (0...1, top-left origin) on the photo before crop and rotation.
struct MaskStroke: Equatable, Codable, Sendable {
    var add: Bool
    var width: Double
    var points: [CGPoint]

    static let limit = 80
}

/// A Liquify push: content under the brush moves along the stroke. Same coordinates as `MaskStroke`.
struct LiquifyStroke: Equatable, Codable, Sendable {
    var points: [CGPoint]
    /// Brush radius as a share of the photo's shorter side, and how far content follows (0...1).
    var radius: Double
    var strength: Double

    static let limit = 60
}

extension ImageProcessingService {
    /// The subject mask with Refine Subject strokes applied in order (add paints white, erase paints black).
    /// Works without a detected subject too: add strokes then define it.
    func refineMask(_ mask: CIImage?, strokes: [MaskStroke], extent e: CGRect) -> CIImage? {
        guard !strokes.isEmpty else { return mask }
        var refined = mask?.cropped(to: e) ?? CIImage(color: .black).cropped(to: e)
        // Consecutive strokes of the same kind are drawn together.
        var index = 0
        while index < strokes.count {
            let add = strokes[index].add
            var run: [RedactionStroke] = []
            while index < strokes.count, strokes[index].add == add {
                run.append(RedactionStroke(mode: .blur, width: strokes[index].width, points: strokes[index].points))
                index += 1
            }
            guard let painted = Self.strokeMask(run, extent: e) else { continue }
            refined = add
                ? painted.applyingFilter("CIMaximumCompositing", parameters: [kCIInputBackgroundImageKey: refined])
                : painted.applyingFilter("CIColorInvert").applyingFilter("CIMinimumCompositing", parameters: [kCIInputBackgroundImageKey: refined])
            refined = refined.cropped(to: e)
        }
        return refined
    }

    /// Liquify: pushes content along each stroke with a soft round brush. The displacement is worked out on a
    /// coarse grid and smoothly interpolated, then the photo is resampled (bilinear).
    func liquify(_ image: CIImage, strokes: [LiquifyStroke], extent e: CGRect) -> CIImage {
        guard !strokes.isEmpty, e.width >= 8, e.height >= 8 else { return image }
        let scale = min(1, 1600 / max(e.width, e.height))
        let w = Int((e.width * scale).rounded()), h = Int((e.height * scale).rounded())
        let work = CGRect(x: 0, y: 0, width: w, height: h)
        let toWork = CGAffineTransform(translationX: -e.minX, y: -e.minY).concatenating(CGAffineTransform(scaleX: scale, y: scale))
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        var source = [UInt32](repeating: 0, count: w * h)
        source.withUnsafeMutableBytes { raw in
            context.render(image.cropped(to: e).transformed(by: toWork), toBitmap: raw.baseAddress!, rowBytes: w * 4,
                           bounds: work, format: .RGBA8, colorSpace: space)
        }

        // Displacement on a grid every `step` pixels (top-left origin, pixels).
        let step = 8
        let gw = w / step + 2, gh = h / step + 2
        var dispX = [Double](repeating: 0, count: gw * gh), dispY = [Double](repeating: 0, count: gw * gh)
        let short = Double(min(w, h))
        for stroke in strokes where stroke.points.count > 1 {
            let r = max(2, stroke.radius * short), r2 = r * r
            let pts = stroke.points.map { (Double($0.x) * Double(w), Double($0.y) * Double(h)) }
            for i in 1..<pts.count {
                let (ax, ay) = pts[i - 1], (bx, by) = pts[i]
                let dx = (bx - ax) * stroke.strength, dy = (by - ay) * stroke.strength
                let minGX = max(0, Int((ax - 3 * r) / Double(step))), maxGX = min(gw - 1, Int((ax + 3 * r) / Double(step)) + 1)
                let minGY = max(0, Int((ay - 3 * r) / Double(step))), maxGY = min(gh - 1, Int((ay + 3 * r) / Double(step)) + 1)
                guard minGX <= maxGX, minGY <= maxGY else { continue }
                for gy in minGY...maxGY {
                    for gx in minGX...maxGX {
                        let px = Double(gx * step) - ax, py = Double(gy * step) - ay
                        let weight = exp(-(px * px + py * py) / r2)
                        dispX[gy * gw + gx] += dx * weight
                        dispY[gy * gw + gx] += dy * weight
                    }
                }
            }
        }
        @inline(__always) func channel(_ p: UInt32, _ shift: UInt32) -> Double { Double((p >> shift) & 0xFF) }
        func sample(_ x: Double, _ y: Double) -> UInt32 {
            let cx = min(Double(w - 1), max(0, x)), cy = min(Double(h - 1), max(0, y))
            let x0 = min(w - 2, Int(cx)), y0 = min(h - 2, Int(cy))
            let fx = cx - Double(x0), fy = cy - Double(y0)
            let p00 = source[y0 * w + x0], p10 = source[y0 * w + x0 + 1]
            let p01 = source[(y0 + 1) * w + x0], p11 = source[(y0 + 1) * w + x0 + 1]
            var out: UInt32 = 0
            for shift: UInt32 in [0, 8, 16, 24] {
                let top = channel(p00, shift) * (1 - fx) + channel(p10, shift) * fx
                let bottom = channel(p01, shift) * (1 - fx) + channel(p11, shift) * fx
                out |= UInt32((top * (1 - fy) + bottom * fy).rounded()) << shift
            }
            return out
        }
        var output = [UInt32](repeating: 0, count: w * h)
        for y in 0..<h {
            let gyf = Double(y) / Double(step), gy = min(gh - 2, Int(gyf)), ty = gyf - Double(gy)
            for x in 0..<w {
                let gxf = Double(x) / Double(step), gx = min(gw - 2, Int(gxf)), tx = gxf - Double(gx)
                func lerp(_ field: [Double]) -> Double {
                    let a = field[gy * gw + gx] * (1 - tx) + field[gy * gw + gx + 1] * tx
                    let b = field[(gy + 1) * gw + gx] * (1 - tx) + field[(gy + 1) * gw + gx + 1] * tx
                    return a * (1 - ty) + b * ty
                }
                // Content moved forward, so each pixel looks back along the push.
                output[y * w + x] = sample(Double(x) - lerp(dispX), Double(y) - lerp(dispY))
            }
        }
        let data = output.withUnsafeBytes { Data($0) }
        guard let provider = CGDataProvider(data: data as CFData),
              let warped = CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: w * 4, space: space,
                                   bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                                   provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
        else { return image }
        return CIImage(cgImage: warped).transformed(by: toWork.inverted()).cropped(to: e)
    }
}
