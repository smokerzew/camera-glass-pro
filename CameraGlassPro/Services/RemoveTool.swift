import CoreImage

/// Remove brush: paint over a small object or blemish and it's filled from what's around it.
/// The fill has two parts: a smooth, seamless color fill that grows inward from the edge of the painted area
/// (coarse to fine), plus the fine texture of the best-matching nearby patch so the fill isn't blurry.
/// Works best on small things against sky, walls, grass or skin; large or detailed areas can look smeared.
extension ImageProcessingService {
    func removeObjects(_ image: CIImage, strokes: [MaskStroke], extent e: CGRect) -> CIImage {
        guard !strokes.isEmpty, e.width >= 16, e.height >= 16 else { return image }
        let runs = strokes.map { RedactionStroke(mode: .blur, width: $0.width, points: $0.points) }
        guard let painted = cachedStrokeMask(runs, extent: e) else { return image }
        // A little wider than painted, so the object's soft edge goes too.
        let grow = Double(max(1.5, min(e.width, e.height) / 400))
        let hole = painted.applyingFilter("CIMorphologyMaximum", parameters: [kCIInputRadiusKey: grow])
            .cropped(to: e)
        let feathered = hole.clampedToExtent().applyingGaussianBlur(sigma: grow).cropped(to: e)

        let smooth = diffusionFill(image, hole: hole, extent: e)
        var filled = smooth
        if let kernel = Self.kernel("addDetail") {
            let patch = matchingPatches(image, strokes: runs, hole: hole, extent: e)
            let sigma = Double(max(2, min(e.width, e.height) / 250))
            let patchBlur = patch.clampedToExtent().applyingGaussianBlur(sigma: sigma).cropped(to: e)
            filled = kernel.apply(extent: e, arguments: [smooth, patch, patchBlur, hole])?.cropped(to: e) ?? smooth
        }
        return filled.applyingFilter("CIBlendWithMask", parameters: [
            kCIInputBackgroundImageKey: image, kCIInputMaskImageKey: feathered,
        ]).cropped(to: e)
    }

    /// Fills the hole from its surroundings: the known pixels (alpha = known) blurred at shrinking sizes, each
    /// level laid over the coarser one by how much known area it saw. Blurring premultiplied pixels and reading
    /// them back un-premultiplied is exactly "average of the known neighbors".
    func diffusionFill(_ image: CIImage, hole: CIImage, extent e: CGRect) -> CIImage {
        let known = CIImage(color: .clear).cropped(to: e).applyingFilter("CIBlendWithMask", parameters: [
            kCIInputBackgroundImageKey: image, kCIInputMaskImageKey: hole, // hole → clear, rest → the photo
        ]).cropped(to: e)
        let side = Double(max(e.width, e.height))
        var sigmas: [Double] = []
        var s = side / 8
        while s >= 1.5 { sigmas.append(s); s /= 2 }
        var fill = known.clampedToExtent().applyingGaussianBlur(sigma: side / 4).cropped(to: e)
            .applyingFilter("CIColorMatrix", parameters: ["inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1000)])
            .applyingFilter("CIColorClamp")
            .cropped(to: e)
        for sigma in sigmas {
            // Confidence: alpha × 3, capped at 1 (CIColorMatrix works on un-premultiplied color, so hue is kept).
            let level = known.clampedToExtent().applyingGaussianBlur(sigma: sigma).cropped(to: e)
                .applyingFilter("CIColorMatrix", parameters: ["inputAVector": CIVector(x: 0, y: 0, z: 0, w: 3)])
                .applyingFilter("CIColorClamp")
            fill = level.composited(over: fill).cropped(to: e)
        }
        return fill.settingAlphaOne(in: e)
    }

    /// The photo moved, per stroke, by the offset whose surroundings best match the stroke's surroundings,
    /// so each painted area gets texture from a similar nearby area. Unpainted parts are the photo itself.
    func matchingPatches(_ image: CIImage, strokes: [RedactionStroke], hole: CIImage, extent e: CGRect) -> CIImage {
        let side = 256
        let scale = CGFloat(side) / max(e.width, e.height)
        let w = max(8, Int(e.width * scale)), h = max(8, Int(e.height * scale))
        let toSmall = CGAffineTransform(translationX: -e.minX, y: -e.minY).concatenating(CGAffineTransform(scaleX: scale, y: scale))
        let bounds = CGRect(x: 0, y: 0, width: w, height: h)
        func gray(_ source: CIImage) -> [UInt8] {
            var pixels = [UInt8](repeating: 0, count: w * h * 4)
            context.render(source.transformed(by: toSmall), toBitmap: &pixels, rowBytes: w * 4, bounds: bounds,
                           format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
            return stride(from: 0, to: pixels.count, by: 4).map { pixels[$0 + 1] }
        }
        let photo = gray(image), allHoles = gray(hole)
        var patch = image
        for stroke in strokes {
            guard let mask = cachedStrokeMask([stroke], extent: e) else { continue }
            let own = gray(mask.applyingFilter("CIMorphologyMaximum", parameters: [kCIInputRadiusKey: 3]).cropped(to: e))
            guard let offset = Self.bestOffset(photo: photo, hole: own, allHoles: allHoles, width: w, height: h) else { continue }
            // Small-image pixels (top-left origin) → photo pixels (Core Image, bottom-left origin).
            let shift = CGAffineTransform(translationX: CGFloat(offset.x) / scale, y: -CGFloat(offset.y) / scale)
            let moved = image.clampedToExtent().transformed(by: shift.inverted()).cropped(to: e)
            let region = mask.applyingFilter("CIMorphologyMaximum", parameters: [kCIInputRadiusKey: 6]).cropped(to: e)
            patch = moved.applyingFilter("CIBlendWithMask", parameters: [
                kCIInputBackgroundImageKey: patch, kCIInputMaskImageKey: region,
            ]).cropped(to: e)
        }
        return patch
    }

    /// Offset (small-image pixels, top-left origin) where the ring around `hole` matches best and the source area
    /// itself has no painted pixels. Tries 8 directions at 3 distances. Nil when the hole is empty.
    static func bestOffset(photo: [UInt8], hole: [UInt8], allHoles: [UInt8], width w: Int, height h: Int) -> (x: Int, y: Int)? {
        var minX = w, minY = h, maxX = -1, maxY = -1
        for y in 0..<h { for x in 0..<w where hole[y * w + x] > 64 {
            minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
        } }
        guard maxX >= 0 else { return nil }
        let size = max(maxX - minX, maxY - minY) + 1
        let pad = max(3, size / 4)
        // Ring: known pixels within `pad` of the hole's box.
        var ring: [Int] = []
        var inside: [Int] = []
        for y in max(0, minY - pad)...min(h - 1, maxY + pad) {
            for x in max(0, minX - pad)...min(w - 1, maxX + pad) {
                let i = y * w + x
                if hole[i] > 64 { inside.append(i) } else if allHoles[i] <= 64 { ring.append(i) }
            }
        }
        guard !ring.isEmpty else { return nil }
        var best: (cost: Double, x: Int, y: Int)?
        for distance in [1.2, 1.7, 2.4] {
            let d = Int((Double(size) * distance).rounded())
            for (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1), (1, 1), (-1, 1), (1, -1), (-1, -1)] {
                let ox = dx * d, oy = dy * d
                // Every pixel the fill would copy from must be in the frame and unpainted.
                let usable = inside.allSatisfy { i in
                    let x = i % w + ox, y = i / w + oy
                    return x >= 0 && x < w && y >= 0 && y < h && allHoles[y * w + x] <= 64
                }
                guard usable else { continue }
                var cost = 0.0, count = 0.0
                for i in ring {
                    let x = i % w + ox, y = i / w + oy
                    guard x >= 0, x < w, y >= 0, y < h else { continue }
                    let diff = Double(photo[i]) - Double(photo[y * w + x])
                    cost += diff * diff
                    count += 1
                }
                guard count > Double(ring.count) / 2 else { continue }
                let average = cost / count + Double(d) * 0.05 // prefer nearer on ties
                if best == nil || average < best!.cost { best = (average, ox, oy) }
            }
        }
        return best.map { ($0.x, $0.y) }
    }
}
