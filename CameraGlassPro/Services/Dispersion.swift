import CoreGraphics
import CoreImage
import CoreImage.CIFilterBuiltins

extension ImageProcessingService {
    /// Dispersion: the side of the subject facing `degrees` (0 right, 90 up) breaks into thousands of
    /// pieces that spray away. Each piece has its own random size, slight rotation and path: most stay
    /// close, the leading edge flies farthest, and pieces shrink and fade as they travel. Pieces carry only
    /// subject pixels, and the gaps they leave show the background behind (filled from its surroundings).
    /// `amount` sets how much breaks off and how far it flies; `size` sets the piece size. Deterministic, so
    /// preview and export match.
    func dispersion(_ image: CIImage, mask: CIImage, amount: Double, size: Double, degrees: Double = 0,
                    extent e: CGRect) -> CIImage {
        guard amount > 0, e.width >= 16, e.height >= 16 else { return image }
        let k = min(amount, 1)
        // Work at up to 2400 px (the preview size) and scale the result back, so exports stay fast.
        let scale = min(1, 2400 / max(e.width, e.height))
        let w = Int((e.width * scale).rounded()), h = Int((e.height * scale).rounded())
        let work = CGRect(x: 0, y: 0, width: w, height: h)
        let toWork = CGAffineTransform(translationX: -e.minX, y: -e.minY).concatenating(CGAffineTransform(scaleX: scale, y: scale))
        let img = image.cropped(to: e).transformed(by: toWork).cropped(to: work)
        let msk = mask.cropped(to: e).transformed(by: toWork).cropped(to: work)

        // Small copy of the mask (top row first) for choosing where pieces come from.
        let grid = 4
        let mw = max(1, w / grid), mh = max(1, h / grid)
        var maskPixels = [UInt8](repeating: 0, count: mw * mh * 4)
        context.render(msk.transformed(by: CGAffineTransform(scaleX: CGFloat(mw) / CGFloat(w), y: CGFloat(mh) / CGFloat(h))),
                       toBitmap: &maskPixels, rowBytes: mw * 4, bounds: CGRect(x: 0, y: 0, width: mw, height: mh),
                       format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
        func inside(_ x: CGFloat, _ y: CGFloat) -> Bool { // Core Image coords (y up)
            let col = min(mw - 1, max(0, Int(x) / grid)), row = min(mh - 1, max(0, mh - 1 - Int(y) / grid))
            return maskPixels[(row * mw + col) * 4] > 128
        }
        var minX = CGFloat(w), maxX: CGFloat = 0, minY = CGFloat(h), maxY: CGFloat = 0
        for row in 0..<mh {
            for col in 0..<mw where maskPixels[(row * mw + col) * 4] > 128 {
                let x = CGFloat(col * grid), y = CGFloat((mh - 1 - row) * grid)
                minX = min(minX, x); maxX = max(maxX, x + CGFloat(grid))
                minY = min(minY, y); maxY = max(maxY, y + CGFloat(grid))
            }
        }
        guard maxX > minX, maxY > minY else { return image }

        let radians = degrees * .pi / 180
        let dir = CGPoint(x: cos(radians), y: sin(radians))
        let side = CGPoint(x: -dir.y, y: dir.x)
        let center = CGPoint(x: (minX + maxX) / 2, y: (minY + maxY) / 2)
        let reach = abs(dir.x) * (maxX - minX) / 2 + abs(dir.y) * (maxY - minY) / 2
        let start = reach * CGFloat(0.75 - 1.3 * k)       // erosion begins here (from the center, along dir)
        let travel = reach * CGFloat(0.8 + 2.4 * k)
        let largest = CGFloat(w) * CGFloat(0.01 + 0.035 * min(max(size, 0), 1))
        let smallest = max(1.5, largest * 0.12)

        struct Piece { var t: CGFloat; var from: CGPoint; var to: CGPoint; var side: CGFloat; var drawn: CGFloat; var alpha: CGFloat; var turn: CGFloat }
        var rng = SplitMix64(seed: 7)
        let wanted = Int(700 + 2600 * k)
        var pieces: [Piece] = []
        pieces.reserveCapacity(wanted)
        var tries = 0
        while pieces.count < wanted, tries < wanted * 40 {
            tries += 1
            let p = CGPoint(x: minX + rng.unit() * (maxX - minX), y: minY + rng.unit() * (maxY - minY))
            guard inside(p.x, p.y) else { continue }
            let along = (p.x - center.x) * dir.x + (p.y - center.y) * dir.y
            let chance = pow(min(1, max(0, (along - start) / max(1, reach - start))), 1.4)
            guard rng.unit() < chance else { continue }
            let s = exp(log(smallest) + rng.unit() * (log(largest) - log(smallest)))
            let t = pow(rng.unit(), 1.8) * (0.35 + 0.65 * chance) // most stay close; the edge flies farther
            let distance = travel * t
            let spread = (rng.unit() - 0.5) * 2 * (0.12 + 0.35 * t) * distance + (rng.unit() - 0.5) * s
            let lift = sin(t * .pi) * 0.1 * distance
            let to = CGPoint(x: p.x + dir.x * distance + side.x * (spread + lift),
                             y: p.y + dir.y * distance + side.y * (spread + lift))
            pieces.append(Piece(t: t, from: p, to: to, side: s, drawn: s * (1 - 0.55 * t),
                                alpha: 1 - 0.8 * pow(t, 1.3), turn: (rng.unit() - 0.5) * 0.9))
        }
        guard !pieces.isEmpty else { return image }

        // Gaps where pieces left (a bit smaller than the pieces, so the shape stays readable).
        guard let holeContext = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                          space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)
        else { return image }
        holeContext.setFillColor(gray: 0, alpha: 1)
        holeContext.fill(work)
        holeContext.setFillColor(gray: 1, alpha: 1)
        for piece in pieces {
            let half = piece.side * 0.4
            holeContext.fill(CGRect(x: piece.from.x - half, y: piece.from.y - half, width: half * 2, height: half * 2))
        }
        guard let holeBitmap = holeContext.makeImage() else { return image }
        let holes = CIImage(cgImage: holeBitmap)
        let kept = msk.applyingFilter("CIMultiplyCompositing", parameters: [
            kCIInputBackgroundImageKey: holes.applyingFilter("CIColorInvert"),
        ]).cropped(to: work)
        let base = img.applyingFilter("CIBlendWithMask", parameters: [
            kCIInputBackgroundImageKey: subjectPlate(img, mask: msk, extent: work), kCIInputMaskImageKey: kept,
        ]).cropped(to: work)

        // Pieces carry subject pixels only (transparent elsewhere).
        let subjectOnly = img.applyingFilter("CIBlendWithMask", parameters: [
            kCIInputBackgroundImageKey: CIImage(color: .clear).cropped(to: work), kCIInputMaskImageKey: msk,
        ]).cropped(to: work)
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        guard let baseBitmap = context.createCGImage(base, from: work, format: .RGBA8, colorSpace: space),
              let subjectBitmap = context.createCGImage(subjectOnly, from: work, format: .RGBA8, colorSpace: space),
              let canvas = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                     bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return image }
        canvas.interpolationQuality = .medium
        canvas.draw(baseBitmap, in: work)
        // Farthest first, so nearer pieces sit on top.
        for piece in pieces.sorted(by: { $0.t > $1.t }) {
            let half = piece.side / 2
            // CGImage cropping uses a top-left origin.
            let source = CGRect(x: piece.from.x - half, y: CGFloat(h) - (piece.from.y + half), width: piece.side, height: piece.side)
                .integral.intersection(CGRect(x: 0, y: 0, width: w, height: h))
            guard !source.isEmpty, let chip = subjectBitmap.cropping(to: source) else { continue }
            canvas.saveGState()
            canvas.translateBy(x: piece.to.x, y: piece.to.y)
            canvas.rotate(by: piece.turn)
            canvas.setAlpha(piece.alpha)
            canvas.draw(chip, in: CGRect(x: -piece.drawn / 2, y: -piece.drawn / 2, width: piece.drawn, height: piece.drawn))
            canvas.restoreGState()
        }
        guard let result = canvas.makeImage() else { return image }
        return CIImage(cgImage: result)
            .transformed(by: toWork.inverted())
            .cropped(to: e)
    }

    /// The scene with the subject removed: its area is filled from the surrounding background only
    /// (a normalized blur that ignores the subject's own pixels), so no smudge of the subject is left.
    /// Where no background is near (the subject touches the frame edge), a soft blur of the photo is used.
    func subjectPlate(_ image: CIImage, mask: CIImage, extent e: CGRect) -> CIImage {
        // Slightly grown mask, so the subject's edge pixels don't bleed into the fill.
        let grown = mask.clampedToExtent().applyingGaussianBlur(sigma: Double(max(1, e.width / 120))).cropped(to: e)
            .applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: 4, y: 0, z: 0, w: 0), "inputGVector": CIVector(x: 0, y: 4, z: 0, w: 0),
                "inputBVector": CIVector(x: 0, y: 0, z: 4, w: 0),
            ])
            .applyingFilter("CIColorClamp")
            .cropped(to: e)
        let sigma = Double(max(2, e.width / 15))
        // Background only (transparent where the subject is), blurred.
        let blurredBackground = CIImage(color: .clear).cropped(to: e).applyingFilter("CIBlendWithMask", parameters: [
            kCIInputBackgroundImageKey: image, kCIInputMaskImageKey: grown,
        ]).cropped(to: e).clampedToExtent().applyingGaussianBlur(sigma: sigma).cropped(to: e)
        // Divided by its coverage: the color matrix un-premultiplies (color / alpha) and makes it opaque.
        let normalized = blurredBackground.applyingFilter("CIColorMatrix", parameters: [
            "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 0), "inputBiasVector": CIVector(x: 0, y: 0, z: 0, w: 1),
        ])
        // How much real background reached each spot (alpha, boosted): where none did, use a soft blur instead.
        let coverage = blurredBackground.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: 0, y: 0, z: 0, w: 20), "inputGVector": CIVector(x: 0, y: 0, z: 0, w: 20),
            "inputBVector": CIVector(x: 0, y: 0, z: 0, w: 20), "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 0),
            "inputBiasVector": CIVector(x: 0, y: 0, z: 0, w: 1),
        ]).applyingFilter("CIColorClamp").cropped(to: e)
        let soft = image.clampedToExtent().applyingGaussianBlur(sigma: sigma * 1.5).cropped(to: e)
        let fill = normalized.applyingFilter("CIBlendWithMask", parameters: [
            kCIInputBackgroundImageKey: soft, kCIInputMaskImageKey: coverage,
        ]).cropped(to: e)
        return fill.applyingFilter("CIBlendWithMask", parameters: [
            kCIInputBackgroundImageKey: image, kCIInputMaskImageKey: grown,
        ]).cropped(to: e)
    }

    /// Ghost: a translucent copy of the subject (or of the whole photo) moved `distance` toward `degrees`.
    /// The ghost sits behind the subject: when a subject is found, the real subject stays on top of it.
    /// With `hideOriginal` (subject ghost) the subject leaves its place and only the ghost remains.
    func ghost(_ image: CIImage, mask: CIImage?, wholePhoto: Bool, opacity: Double, distance: Double, degrees: Double,
               hideOriginal: Bool, extent e: CGRect) -> CIImage {
        guard opacity > 0 else { return image }
        let a = CGFloat(min(opacity, 1))
        let radians = CGFloat(degrees) * .pi / 180
        let shift = CGFloat(min(max(distance, 0), 1)) * 0.35 * max(e.width, e.height)
        let move = CGAffineTransform(translationX: cos(radians) * shift, y: sin(radians) * shift)
        let soft = mask.map { $0.clampedToExtent().applyingGaussianBlur(sigma: Double(max(1, e.width / 500))).cropped(to: e) }

        let withGhost: CIImage
        if wholePhoto {
            // A see-through copy of the whole photo laid over it (1 = an even double exposure).
            let moved = image.clampedToExtent().transformed(by: move).cropped(to: e)
            withGhost = image.applyingFilter("CIDissolveTransition", parameters: [
                kCIInputTargetImageKey: moved, kCIInputTimeKey: a * 0.5,
            ]).cropped(to: e)
        } else {
            guard let soft else { return image }
            let scene = hideOriginal ? subjectPlate(image, mask: soft, extent: e) : image
            let ghostMask = soft.clampedToExtent().transformed(by: move).cropped(to: e)
                .applyingFilter("CIColorMatrix", parameters: [
                    "inputRVector": CIVector(x: a, y: 0, z: 0, w: 0), "inputGVector": CIVector(x: 0, y: a, z: 0, w: 0),
                    "inputBVector": CIVector(x: 0, y: 0, z: a, w: 0),
                ])
            withGhost = image.transformed(by: move).applyingFilter("CIBlendWithMask", parameters: [
                kCIInputBackgroundImageKey: scene, kCIInputMaskImageKey: ghostMask,
            ]).cropped(to: e)
            if hideOriginal { return withGhost }
        }
        // The real subject goes back on top, so the ghost is behind it.
        guard let soft else { return withGhost }
        return image.applyingFilter("CIBlendWithMask", parameters: [
            kCIInputBackgroundImageKey: withGhost, kCIInputMaskImageKey: soft,
        ]).cropped(to: e)
    }
}

/// Small deterministic random generator (SplitMix64): the same seed gives the same pieces every render.
struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// Uniform in 0..<1.
    mutating func unit() -> CGFloat { CGFloat(next() >> 11) / CGFloat(1 << 53) }
}
