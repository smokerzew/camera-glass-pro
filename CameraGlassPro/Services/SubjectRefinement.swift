import CoreImage
import CoreVideo

/// Better subject masks: the main subject only, people's finer hair mask merged in, pinholes closed, and the
/// edge fitted to the photo's real outlines (guided filter). Plus edge color clean-up for compositing.
extension SubjectMasker {
    /// Instances to treat as the subject: the biggest one plus any at least 15% of its size or 2% of the frame.
    /// Small far-off things (a person in the distance, a sign) are left out.
    static func keptInstances(counts: [Int: Int], total: Int) -> IndexSet {
        guard let biggest = counts.values.max(), biggest > 0, total > 0 else { return IndexSet() }
        let kept = counts.filter { label, count in
            label > 0 && (count * 100 >= biggest * 15 || count * 50 >= total)
        }.keys
        return IndexSet(kept)
    }

    /// Pixel count of every instance label (0 = background) in Vision's instance mask.
    static func labelCounts(_ buffer: CVPixelBuffer) -> (counts: [Int: Int], total: Int) {
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(buffer) else { return ([:], 0) }
        let width = CVPixelBufferGetWidth(buffer), height = CVPixelBufferGetHeight(buffer)
        let row = CVPixelBufferGetBytesPerRow(buffer)
        let pixels = base.assumingMemoryBound(to: UInt8.self)
        var counts: [Int: Int] = [:]
        for y in 0..<height {
            for x in 0..<width {
                let label = Int(pixels[y * row + x])
                if label > 0 { counts[label, default: 0] += 1 }
            }
        }
        return (counts, width * height)
    }

    /// Closes pinholes, then fits the mask's edge to the photo's edges (guided filter), so hair, ears and
    /// shoulders follow the picture instead of a blocky, low-resolution outline.
    static func refine(_ mask: CIImage, guide image: CIImage, extent e: CGRect) -> CIImage {
        let raw = mask.cropped(to: e)
        let r = max(1, e.width / 600)
        let closed = raw.applyingFilter("CIMorphologyMaximum", parameters: [kCIInputRadiusKey: r])
            .applyingFilter("CIMorphologyMinimum", parameters: [kCIInputRadiusKey: r])
            .cropped(to: e)
        guard let packA = ImageProcessingService.kernel("guidedPackA"), let packB = ImageProcessingService.kernel("guidedPackB"),
              let coeffs = ImageProcessingService.kernel("guidedCoeffs"), let applyKernel = ImageProcessingService.kernel("guidedApply"),
              let a = packA.apply(extent: e, arguments: [image, closed]), let b = packB.apply(extent: e, arguments: [image])
        else { return closed }
        // The window must span the rough mask's typical error (person masks are upscaled from ~512 px).
        let radius = min(100, max(2, e.width / 150))
        func box(_ x: CIImage) -> CIImage {
            x.clampedToExtent().applyingFilter("CIBoxBlur", parameters: [kCIInputRadiusKey: radius]).cropped(to: e)
        }
        guard let ab = coeffs.apply(extent: e, arguments: [box(a), box(b), Float(0.002)]),
              let refined = applyKernel.apply(extent: e, arguments: [image, box(ab)]) else { return closed }
        return refined.cropped(to: e)
    }
}

extension ImageProcessingService {
    /// The photo with its subject's edge pixels cleaned of the old background's color (for compositing onto a
    /// new, blurred or black-and-white background). Away from the edge nothing changes.
    func decontaminated(_ image: CIImage, mask: CIImage, extent e: CGRect) -> CIImage {
        guard let kernel = Self.kernel("decontaminate") else { return image }
        // Nearby background color: the photo where it's background, spread inward (premultiplied by background share).
        let background = CIImage(color: .clear).cropped(to: e).applyingFilter("CIBlendWithMask", parameters: [
            kCIInputBackgroundImageKey: image, kCIInputMaskImageKey: mask.applyingFilter("CIColorControls", parameters: [
                kCIInputContrastKey: 2.5, // only clear background feeds the estimate
            ]).applyingFilter("CIColorClamp"),
        ]).cropped(to: e)
        let nearby = background.clampedToExtent().applyingGaussianBlur(sigma: Double(max(2, e.width / 120))).cropped(to: e)
        return kernel.apply(extent: e, arguments: [image, nearby, mask])?.cropped(to: e) ?? image
    }
}
