import CoreImage

/// Finds how far one photo is shifted from another (Night stacking, Panorama). A brute-force search on small
/// grayscale copies, refined at larger sizes, comparing brightness-normalized pixels in the overlap, so it
/// handles big shifts (panoramas), small ones (hand shake) and exposure changes, and it says "no match"
/// instead of guessing when the overlap doesn't look alike.
enum Registration {
    /// Shift (pixels, Core Image axes: +x right, +y up) to move `frame` onto `reference`, or nil when no
    /// shift within `maxShift` (fraction of the size per axis) makes them match. Needs ≥ `minOverlap` of the width.
    static func translation(of frame: CIImage, to reference: CIImage, maxShift: CGSize, minOverlap: CGFloat = 0.15,
                            context: CIContext) -> CGPoint? {
        let e = reference.extent
        guard e.width >= 16, e.height >= 16 else { return nil }
        var shift: (x: Int, y: Int)?
        var previousScale: CGFloat = 0
        for width in [128, 512, 1024] where CGFloat(width) <= max(e.width, 128) {
            let scale = CGFloat(width) / e.width
            let w = width, h = max(8, Int((e.height * scale).rounded()))
            let a = gray(reference, extent: e, scale: scale, w: w, h: h, context: context)
            let b = gray(frame, extent: e, scale: scale, w: w, h: h, context: context)
            let found: (x: Int, y: Int, cost: Double)?
            if let shift {
                // Refine around the coarser answer.
                let cx = Int((Double(shift.x) * Double(scale / previousScale)).rounded())
                let cy = Int((Double(shift.y) * Double(scale / previousScale)).rounded())
                let r = Int((scale / previousScale).rounded(.up)) + 1
                found = search(a, b, w: w, h: h, xs: (cx - r)...(cx + r), ys: (cy - r)...(cy + r), step: 1, minOverlap: minOverlap)
            } else {
                let mx = Int(CGFloat(w) * maxShift.width), my = Int(CGFloat(h) * maxShift.height)
                guard let coarse = search(a, b, w: w, h: h, xs: -mx...mx, ys: -my...my, step: 2, minOverlap: minOverlap)
                else { return nil }
                found = search(a, b, w: w, h: h, xs: (coarse.x - 2)...(coarse.x + 2), ys: (coarse.y - 2)...(coarse.y + 2),
                               step: 1, minOverlap: minOverlap)
                // Normalized difference: 0 = identical; unrelated pictures score far higher.
                if let found, found.cost > 0.35 { return nil }
            }
            guard let found else { return nil }
            shift = (found.x, found.y)
            previousScale = scale
        }
        guard let shift else { return nil }
        // Small-image pixels (top-left origin) → full size, Core Image axes (y up).
        return CGPoint(x: CGFloat(shift.x) / previousScale, y: -CGFloat(shift.y) / previousScale)
    }

    /// Gray values (0...1) of `image` scaled into a w × h top-left-origin grid.
    private static func gray(_ image: CIImage, extent e: CGRect, scale: CGFloat, w: Int, h: Int, context: CIContext) -> [Float] {
        // A real resampling filter: a bare scale transform can be pushed into the image's own filters by
        // Core Image, so two crops of one scene came out sampled differently.
        let small = image.transformed(by: CGAffineTransform(translationX: -e.minX, y: -e.minY))
            .applyingFilter("CILanczosScaleTransform", parameters: [kCIInputScaleKey: scale, kCIInputAspectRatioKey: 1])
        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        context.render(small, toBitmap: &pixels, rowBytes: w * 4, bounds: CGRect(x: 0, y: 0, width: w, height: h),
                       format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
        // The bitmap's first row is the top of the picture; alpha 0 (outside the photo) becomes NaN = ignored.
        return stride(from: 0, to: pixels.count, by: 4).map { i in
            pixels[i + 3] < 128 ? .nan : (0.3 * Float(pixels[i]) + 0.59 * Float(pixels[i + 1]) + 0.11 * Float(pixels[i + 2])) / 255
        }
    }

    /// Best (x, y) where frame pixel (u, v) lines up with reference (u + x, v + y); cost is the mean squared
    /// difference of mean/contrast-normalized pixels over the overlap (sampled every few pixels).
    static func search(_ a: [Float], _ b: [Float], w: Int, h: Int, xs: ClosedRange<Int>, ys: ClosedRange<Int>, step: Int,
                       minOverlap: CGFloat) -> (x: Int, y: Int, cost: Double)? {
        let sample = max(1, w / 96)
        var best: (x: Int, y: Int, cost: Double)?
        for y in stride(from: ys.lowerBound, through: ys.upperBound, by: step) {
            for x in stride(from: xs.lowerBound, through: xs.upperBound, by: step) {
                let overlapW = w - abs(x), overlapH = h - abs(y)
                guard CGFloat(overlapW) >= CGFloat(w) * minOverlap, overlapH >= h / 2 else { continue }
                var sa: Float = 0, sb: Float = 0, saa: Float = 0, sbb: Float = 0, sab: Float = 0, n: Float = 0
                for v in stride(from: max(0, -y), to: min(h, h - y), by: sample) {
                    for u in stride(from: max(0, -x), to: min(w, w - x), by: sample) {
                        let pa = a[(v + y) * w + u + x], pb = b[v * w + u]
                        guard !pa.isNaN, !pb.isNaN else { continue }
                        sa += pa; sb += pb; saa += pa * pa; sbb += pb * pb; sab += pa * pb; n += 1
                    }
                }
                guard n > 20 else { continue }
                let va = saa / n - (sa / n) * (sa / n), vb = sbb / n - (sb / n) * (sb / n)
                guard va > 1e-5, vb > 1e-5 else { continue } // flat areas can't be lined up
                let correlation = (sab / n - (sa / n) * (sb / n)) / (va * vb).squareRoot()
                let cost = Double(1 - correlation) // 0 = same picture
                if best == nil || cost < best!.cost - 1e-9 || (abs(cost - best!.cost) < 1e-9 && abs(x) + abs(y) < abs(best!.x) + abs(best!.y)) {
                    best = (x, y, cost)
                }
            }
        }
        return best
    }
}
