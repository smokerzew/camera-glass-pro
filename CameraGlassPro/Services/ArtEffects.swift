import CoreGraphics
import CoreImage
import CoreImage.CIFilterBuiltins

/// Hologram, thermal / night vision, pixel sort, orbit clones, melt, and the background blur kinds.
extension ImageProcessingService {
    // MARK: Background blur kinds

    /// The blurred background used by SUBJECT > Style > Blur. `center` is the subject's center (zoom and spin).
    /// Background blur for SUBJECT > Style > Blur. `amount` 0...1 maps to the blur through `curve`
    /// (0 = no blur at all, 10% barely visible, full = the kind's maximum), with no built-in minimum.
    /// `source` should be the background with the subject removed (see `subjectPlate`), so the subject's
    /// colors don't smear into the background around its edges.
    func blurredBackground(_ source: CIImage, kind: BackgroundBlurKind, amount: Double, center: CGPoint, extent e: CGRect) -> CIImage {
        let k = CGFloat(BackgroundBlurKind.curve(amount))
        guard k > 0 else { return source.cropped(to: e) }
        let base = source.clampedToExtent()
        switch kind {
        case .soft:
            return base.applyingGaussianBlur(sigma: Double(k * e.width / 28)).cropped(to: e)
        case .lens:
            // Real lens look: bright spots become soft discs (bokeh) instead of smears.
            return base.applyingFilter("CIBokehBlur", parameters: [
                kCIInputRadiusKey: max(0.5, min(400, k * e.width / 23)),
                "inputRingAmount": 0.25, "inputRingSize": 0.1, "inputSoftness": 1.0,
            ]).cropped(to: e)
        case .zoom:
            // Zoom burst: streaks rushing out from behind the subject.
            return base.applyingFilter("CIZoomBlur", parameters: [
                kCIInputCenterKey: CIVector(x: center.x, y: center.y), "inputAmount": k * e.width / 12,
            ]).cropped(to: e)
        case .spin:
            // Spin: the background turns around the subject (average of slightly rotated copies).
            let maxAngle = 0.2 * k
            let steps = 12
            var result = base
            for i in 1...steps {
                let angle = maxAngle * (CGFloat(i) / CGFloat(steps) - 0.5) * 2
                let turned = base.transformed(by: CGAffineTransform(translationX: -center.x, y: -center.y)
                    .concatenating(CGAffineTransform(rotationAngle: angle))
                    .concatenating(CGAffineTransform(translationX: center.x, y: center.y)))
                result = result.applyingFilter("CIDissolveTransition", parameters: [
                    kCIInputTargetImageKey: turned, kCIInputTimeKey: 1 / CGFloat(i + 1),
                ])
            }
            return result.cropped(to: e)
        case .motion:
            return base.applyingFilter("CIMotionBlur", parameters: [
                kCIInputRadiusKey: k * e.width / 13, kCIInputAngleKey: 0,
            ]).cropped(to: e)
        }
    }

    // MARK: Hologram

    /// The subject becomes a see-through, glowing blue hologram with scan lines and a slight color split.
    func hologram(_ image: CIImage, mask: CIImage, amount: Double, extent e: CGRect) -> CIImage {
        guard amount > 0 else { return image }
        let k = CGFloat(min(amount, 1))
        let soft = mask.clampedToExtent().applyingGaussianBlur(sigma: Double(max(1, e.width / 600))).cropped(to: e)
        let luma = CIVector(x: 0.2126, y: 0.7152, z: 0.0722, w: 0)
        func scaled(_ v: CIVector, _ s: CGFloat) -> CIVector { CIVector(x: v.x * s, y: v.y * s, z: v.z * s, w: 0) }
        let cyan = image.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": scaled(luma, 0.25), "inputGVector": scaled(luma, 1.0), "inputBVector": scaled(luma, 1.3),
            "inputBiasVector": CIVector(x: 0, y: 0.02, z: 0.05, w: 0),
        ]).cropped(to: e)
        // Horizontal scan lines.
        let stripes = CIFilter.stripesGenerator()
        stripes.color0 = .white
        stripes.color1 = CIColor(red: 0.45, green: 0.45, blue: 0.45)
        stripes.width = Float(max(1.5, e.height / 260))
        stripes.sharpness = 0.6
        let lines = (stripes.outputImage ?? CIImage(color: .white))
            .transformed(by: CGAffineTransform(rotationAngle: .pi / 2)).cropped(to: e)
        let scanned = cyan.applyingFilter("CIMultiplyCompositing", parameters: [kCIInputBackgroundImageKey: lines]).cropped(to: e)
        // A faint magenta copy a few pixels over (projector color split).
        let split = scanned.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: 0, y: 0.9, z: 0, w: 0), "inputGVector": CIVector(x: 0, y: 0.1, z: 0, w: 0),
            "inputBVector": CIVector(x: 0, y: 0.6, z: 0, w: 0),
        ]).transformed(by: CGAffineTransform(translationX: e.width / 350, y: 0)).cropped(to: e)
        let holo = split.applyingFilter("CIScreenBlendMode", parameters: [kCIInputBackgroundImageKey: scanned]).cropped(to: e)
        // See-through: the background shows through the subject.
        let alpha = 0.45 + 0.4 * k
        let see = soft.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: alpha, y: 0, z: 0, w: 0), "inputGVector": CIVector(x: 0, y: alpha, z: 0, w: 0),
            "inputBVector": CIVector(x: 0, y: 0, z: alpha, w: 0),
        ])
        let projected = holo.applyingFilter("CIBlendWithMask", parameters: [
            kCIInputBackgroundImageKey: subjectPlate(image, mask: mask, extent: e), kCIInputMaskImageKey: see,
        ]).cropped(to: e)
        // Glow around the figure.
        let glow = holo.applyingFilter("CIBlendWithMask", parameters: [
            kCIInputBackgroundImageKey: CIImage(color: .black).cropped(to: e), kCIInputMaskImageKey: soft,
        ]).clampedToExtent().applyingGaussianBlur(sigma: Double(e.width / 90)).cropped(to: e)
            .applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: 0.7 * k, y: 0, z: 0, w: 0), "inputGVector": CIVector(x: 0, y: 0.7 * k, z: 0, w: 0),
                "inputBVector": CIVector(x: 0, y: 0, z: 0.7 * k, w: 0),
            ])
        return glow.applyingFilter("CIScreenBlendMode", parameters: [kCIInputBackgroundImageKey: projected]).cropped(to: e)
    }

    // MARK: Thermal / night vision

    func vision(_ image: CIImage, mode: VisionMode, amount: Double, extent e: CGRect) -> CIImage {
        guard mode != .none, amount > 0, let kernel = Self.kernel("visionLook") else { return image }
        let k = min(amount, 1)
        var output = kernel.apply(extent: image.extent.isInfinite ? e : image.extent,
                                  arguments: [image, Float(mode == .thermal ? 0 : 1), Float(k)])?.cropped(to: e) ?? image
        if mode == .thermal {
            // Heat images are soft.
            output = output.clampedToExtent().applyingGaussianBlur(sigma: Double(max(0.5, e.width / 700))).cropped(to: e)
        } else {
            // Goggles: dark edges and coarse sensor grain.
            output = vignette(output, amount: 0.7 * k, extent: e)
            output = filmGrain(output, amount: 0.6 * k, size: .coarse, extent: e)
        }
        return output
    }

    // MARK: Pixel sort

    /// Glitch-art pixel sorting: along each row (or column), runs of pixels brighter than a threshold are
    /// sorted dark to bright. More `amount` lowers the threshold, so the streaks get longer. With a mask,
    /// only the subject is sorted.
    func pixelSort(_ image: CIImage, amount: Double, vertical: Bool, mask: CIImage?, extent e: CGRect) -> CIImage {
        guard amount > 0, e.width >= 4, e.height >= 4 else { return image }
        let scale = min(1, 1600 / max(e.width, e.height))
        let w = Int((e.width * scale).rounded()), h = Int((e.height * scale).rounded())
        let work = CGRect(x: 0, y: 0, width: w, height: h)
        let toWork = CGAffineTransform(translationX: -e.minX, y: -e.minY).concatenating(CGAffineTransform(scaleX: scale, y: scale))
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        var pixels = [UInt32](repeating: 0, count: w * h)
        pixels.withUnsafeMutableBytes { raw in
            context.render(image.cropped(to: e).transformed(by: toWork), toBitmap: raw.baseAddress!, rowBytes: w * 4,
                           bounds: work, format: .RGBA8, colorSpace: space)
        }
        var allowed = [UInt8](repeating: 255, count: w * h)
        if let mask {
            var rgba = [UInt8](repeating: 0, count: w * h * 4)
            context.render(mask.cropped(to: e).transformed(by: toWork), toBitmap: &rgba, rowBytes: w * 4,
                           bounds: work, format: .RGBA8, colorSpace: space)
            for i in 0..<(w * h) { allowed[i] = rgba[i * 4] }
        }
        @inline(__always) func luma(_ p: UInt32) -> Int {
            let r = Int(p & 0xFF), g = Int((p >> 8) & 0xFF), b = Int((p >> 16) & 0xFF)
            return (r * 54 + g * 183 + b * 19) >> 8
        }
        let threshold = Int(255 * (0.78 - 0.55 * min(amount, 1)))
        let lines = vertical ? w : h, length = vertical ? h : w
        var run: [UInt32] = []
        run.reserveCapacity(length)
        for line in 0..<lines {
            var i = 0
            while i < length {
                let index = vertical ? i * w + line : line * w + i
                guard allowed[index] > 128, luma(pixels[index]) > threshold else { i += 1; continue }
                let start = i
                run.removeAll(keepingCapacity: true)
                while i < length {
                    let j = vertical ? i * w + line : line * w + i
                    guard allowed[j] > 128, luma(pixels[j]) > threshold else { break }
                    run.append(pixels[j])
                    i += 1
                }
                if run.count > 1 {
                    run.sort { luma($0) < luma($1) }
                    for (offset, value) in run.enumerated() {
                        let j = vertical ? (start + offset) * w + line : line * w + start + offset
                        pixels[j] = value
                    }
                }
            }
        }
        // The bitmap rows run top to bottom, which is what CGImage expects.
        let data = pixels.withUnsafeBytes { Data($0) }
        guard let provider = CGDataProvider(data: data as CFData),
              let sorted = CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: w * 4, space: space,
                                   bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                                   provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
        else { return image }
        return CIImage(cgImage: sorted).transformed(by: toWork.inverted()).cropped(to: e)
    }

    // MARK: Little planet

    /// Wraps the picture into a tiny round planet (stereographic projection): the bottom of the photo
    /// becomes the ground at the center and the top becomes the sky around it. The photo is mirrored
    /// side to side so the wrap has no seam. `amount` (0...1) sets the planet size, `spin` turns it.
    func littlePlanet(_ image: CIImage, amount: Double, spin: Double, extent e: CGRect) -> CIImage {
        guard amount > 0, e.width >= 8, e.height >= 8 else { return image }
        let scale = min(1, 1400 / max(e.width, e.height))
        let w = Int((e.width * scale).rounded()), h = Int((e.height * scale).rounded())
        let work = CGRect(x: 0, y: 0, width: w, height: h)
        let toWork = CGAffineTransform(translationX: -e.minX, y: -e.minY).concatenating(CGAffineTransform(scaleX: scale, y: scale))
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        var source = [UInt32](repeating: 0, count: w * h)
        source.withUnsafeMutableBytes { raw in
            context.render(image.cropped(to: e).transformed(by: toWork), toBitmap: raw.baseAddress!, rowBytes: w * 4,
                           bounds: work, format: .RGBA8, colorSpace: space)
        }
        @inline(__always) func channel(_ p: UInt32, _ shift: UInt32) -> Double { Double((p >> shift) & 0xFF) }
        func sample(_ x: Double, _ y: Double) -> UInt32 { // bilinear, top-left origin
            let x0 = min(w - 2, max(0, Int(x))), y0 = min(h - 2, max(0, Int(y)))
            let fx = min(1, max(0, x - Double(x0))), fy = min(1, max(0, y - Double(y0)))
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
        let k = min(amount, 1)
        let zoom = 2.2 - 1.6 * k // smaller = bigger planet
        let turn = spin * .pi / 180
        let cx = Double(w) / 2, cy = Double(h) / 2, radius = Double(min(w, h)) / 2
        var output = [UInt32](repeating: 0, count: w * h)
        for y in 0..<h {
            for x in 0..<w {
                let dx = Double(x) - cx, dy = cy - Double(y)
                let rho = (dx * dx + dy * dy).squareRoot() / radius
                var u = (atan2(dy, dx) + turn) / (2 * .pi)
                u -= u.rounded(.down) // 0..<1 around the planet
                // Mirrored strip: 0 -> right edge -> 0, so both ends of the wrap match.
                let sx = (u < 0.5 ? u * 2 : (1 - u) * 2) * Double(w - 1)
                let t = 2 / Double.pi * atan(rho * zoom)
                let sy = (1 - t) * Double(h - 1)
                output[y * w + x] = sample(sx, sy)
            }
        }
        let data = output.withUnsafeBytes { Data($0) }
        guard let provider = CGDataProvider(data: data as CFData),
              let planet = CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: w * 4, space: space,
                                   bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                                   provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
        else { return image }
        return CIImage(cgImage: planet).transformed(by: toWork.inverted()).cropped(to: e)
    }

    // MARK: Orbit clones

    /// Smaller copies of the subject arranged in a circle around it, behind the real subject.
    func orbitClones(_ image: CIImage, mask: CIImage, count: Int, size: Double, distance: Double, extent e: CGRect) -> CIImage {
        guard count >= 2, let box = maskBounds(mask, extent: e) else { return image }
        let soft = mask.clampedToExtent().applyingGaussianBlur(sigma: Double(max(1, e.width / 600))).cropped(to: e)
        let subject = image.applyingFilter("CIBlendWithMask", parameters: [
            kCIInputBackgroundImageKey: CIImage(color: .clear).cropped(to: e), kCIInputMaskImageKey: soft,
        ]).cropped(to: e)
        let center = CGPoint(x: box.midX, y: box.midY)
        let scale = 0.22 + 0.4 * CGFloat(min(max(size, 0), 1))
        let radius = max(box.width, box.height) * (0.45 + 0.75 * CGFloat(min(max(distance, 0), 1)))
        var output = image
        for i in 0..<count {
            let angle = 2 * .pi * CGFloat(i) / CGFloat(count) + .pi / 2
            let spot = CGPoint(x: center.x + cos(angle) * radius, y: center.y + sin(angle) * radius)
            let clone = subject.transformed(by: CGAffineTransform(translationX: -center.x, y: -center.y)
                .concatenating(CGAffineTransform(scaleX: scale, y: scale))
                .concatenating(CGAffineTransform(translationX: spot.x, y: spot.y)))
            output = clone.composited(over: output)
        }
        // The real subject stays in front.
        return image.applyingFilter("CIBlendWithMask", parameters: [
            kCIInputBackgroundImageKey: output, kCIInputMaskImageKey: soft,
        ]).cropped(to: e)
    }

    // MARK: Melt

    /// The subject sags and drips downward like wax: its lower parts stretch down and drips of varied
    /// length run from every lower edge. Deterministic (same drips every render).
    func melt(_ image: CIImage, mask: CIImage, amount: Double, extent e: CGRect) -> CIImage {
        guard amount > 0, e.width >= 8, e.height >= 8 else { return image }
        let k = min(amount, 1)
        let scale = min(1, 1600 / max(e.width, e.height))
        let w = Int((e.width * scale).rounded()), h = Int((e.height * scale).rounded())
        let work = CGRect(x: 0, y: 0, width: w, height: h)
        let toWork = CGAffineTransform(translationX: -e.minX, y: -e.minY).concatenating(CGAffineTransform(scaleX: scale, y: scale))
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let soft = mask.clampedToExtent().applyingGaussianBlur(sigma: Double(max(0.5, e.width / 900))).cropped(to: e)
        let subject = image.applyingFilter("CIBlendWithMask", parameters: [
            kCIInputBackgroundImageKey: CIImage(color: .clear).cropped(to: e), kCIInputMaskImageKey: soft,
        ]).cropped(to: e)
        // Premultiplied RGBA, top row first.
        var source = [UInt32](repeating: 0, count: w * h)
        source.withUnsafeMutableBytes { raw in
            context.render(subject.transformed(by: toWork), toBitmap: raw.baseAddress!, rowBytes: w * 4,
                           bounds: work, format: .RGBA8, colorSpace: space)
        }
        @inline(__always) func alpha(_ p: UInt32) -> UInt32 { p >> 24 }

        // Drip length per column: smooth value noise, squared so most drips are short and a few are long.
        var rng = SplitMix64(seed: 11)
        let knotSpacing = max(4, w / 45)
        let knots = (0...(w / knotSpacing + 2)).map { _ in pow(rng.unit(), 2.2) }
        func noise(_ x: Int) -> CGFloat {
            let f = CGFloat(x) / CGFloat(knotSpacing), i = Int(f), t = f - CGFloat(i)
            let s = (1 - cos(t * .pi)) / 2
            return knots[i] * (1 - s) + knots[i + 1] * s
        }
        let longest = CGFloat(h) * CGFloat(0.08 + 0.32 * k)
        var output = [UInt32](repeating: 0, count: w * h)
        for x in 0..<w {
            let drip = longest * noise(x)
            var y = 0
            while y < h {
                guard alpha(source[y * w + x]) > 128 else { y += 1; continue }
                // One run of subject pixels in this column: [top, end).
                let top = y
                while y < h, alpha(source[y * w + x]) > 128 { y += 1 }
                let end = y
                let runLength = CGFloat(end - top)
                // Sag: the lower part of the run stretches down (pixels are pulled from higher up).
                let sag = drip * 0.6
                for row in top..<end {
                    let t = CGFloat(row - top) / max(1, runLength)
                    let from = row - Int(sag * t * t)
                    output[row * w + x] = source[max(top, from) * w + x]
                }
                // Drip: the edge color runs down past the run's end, with a rounded, fading tip.
                let edge = source[(end - 1) * w + x]
                let dripRows = Int(drip)
                if dripRows > 0 {
                    for d in 0..<dripRows {
                        let row = end + d
                        guard row < h else { break }
                        let fade = 1 - pow(CGFloat(d) / CGFloat(dripRows), 4)
                        let a = UInt32(CGFloat(alpha(edge)) * fade)
                        guard a > alpha(output[row * w + x]) else { continue }
                        // Scale the premultiplied color with the alpha.
                        let r = UInt32(CGFloat(edge & 0xFF) * fade), g = UInt32(CGFloat((edge >> 8) & 0xFF) * fade)
                        let b = UInt32(CGFloat((edge >> 16) & 0xFF) * fade)
                        output[row * w + x] = r | (g << 8) | (b << 16) | (a << 24)
                    }
                }
            }
        }
        let data = output.withUnsafeBytes { Data($0) }
        guard let provider = CGDataProvider(data: data as CFData),
              let melted = CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: w * 4, space: space,
                                   bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                                   provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
        else { return image }
        let layer = CIImage(cgImage: melted).transformed(by: toWork.inverted()).cropped(to: e)
        return layer.composited(over: image).cropped(to: e)
    }
}
