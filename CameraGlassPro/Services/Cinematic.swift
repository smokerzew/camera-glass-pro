import CoreImage
import CoreVideo
import Vision

/// CINEMATIC mode focus point: from `time` (seconds in the original video) the focus is on whatever is at
/// (x, y) (normalized, top-left origin), or on the background when `background` is true.
struct CinematicFocus: Codable, Equatable, Sendable {
    var time: Double
    var x: Double
    var y: Double
    var background = false

    static let limit = 50
    /// Seconds a rack focus takes to move from the old point to the new one.
    static let rackDuration = 0.4

    init(time: Double, x: Double, y: Double, background: Bool = false) {
        self.time = time
        self.x = x
        self.y = y
        self.background = background
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func unit(_ key: CodingKeys) -> Double {
            let v = (try? c.decodeIfPresent(Double.self, forKey: key)) ?? 0.5
            return v.isFinite ? min(max(v, 0), 1) : 0.5
        }
        let t = (try? c.decodeIfPresent(Double.self, forKey: .time)) ?? 0
        time = t.isFinite ? max(t, 0) : 0
        x = unit(.x)
        y = unit(.y)
        background = (try? c.decodeIfPresent(Bool.self, forKey: .background)) ?? false
    }

    /// The point in focus at `time`, the one before it, and how far (0...1) the rack between them has got.
    static func state(_ keys: [CinematicFocus], at time: Double) -> (current: CinematicFocus, previous: CinematicFocus?, progress: Double)? {
        let sorted = keys.sorted { $0.time < $1.time }
        guard let first = sorted.first else { return nil }
        guard let index = sorted.lastIndex(where: { $0.time <= time }) else { return (first, nil, 1) }
        let previous = index > 0 ? sorted[index - 1] : nil
        let progress = previous == nil ? 1 : min(max((time - sorted[index].time) / rackDuration, 0), 1)
        return (sorted[index], previous, progress)
    }
}

extension SubjectMasker {
    /// Mask of what `focus` points at in `image` (white = sharp): the subject under the point, else the
    /// subject nearest to it; or the background (everything but the subjects). Nil when nothing is found.
    static func focusMask(for image: CIImage, focus: CinematicFocus) -> CIImage? {
        let extent = image.extent
        guard extent.width > 1, extent.height > 1, !extent.isInfinite else { return nil }
        let handler = VNImageRequestHandler(ciImage: image, options: [:])
        let request = VNGenerateForegroundInstanceMaskRequest()
        guard (try? handler.perform([request])) != nil, let observation = request.results?.first,
              !observation.allInstances.isEmpty else {
            // No separate subjects: fall back to people, and to everything sharp for the background.
            return focus.background ? nil : mask(for: image, fast: true)
        }
        let instances: IndexSet
        if focus.background {
            instances = observation.allInstances
        } else {
            let label = Self.label(in: observation.instanceMask, x: focus.x, y: focus.y)
            instances = label.map { IndexSet(integer: $0) } ?? observation.allInstances
        }
        guard let buffer = try? observation.generateScaledMaskForImage(forInstances: instances, from: handler) else { return nil }
        let subjects = fitted(CIImage(cvPixelBuffer: buffer), to: extent)
        return focus.background ? subjects.applyingFilter("CIColorInvert").cropped(to: extent) : subjects
    }

    /// Instance label under (x, y), or the nearest labeled pixel within `reach` (fraction of the frame); nil if none.
    static func label(in buffer: CVPixelBuffer, x: Double, y: Double, reach fraction: Double = 0.2) -> Int? {
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(buffer) else { return nil }
        let width = CVPixelBufferGetWidth(buffer), height = CVPixelBufferGetHeight(buffer)
        let row = CVPixelBufferGetBytesPerRow(buffer)
        let pixels = base.assumingMemoryBound(to: UInt8.self)
        let px = min(max(Int(x * Double(width)), 0), width - 1)
        let py = min(max(Int(y * Double(height)), 0), height - 1)
        let reach = Int(Double(max(width, height)) * fraction)
        var best: (distance: Int, label: Int)?
        for dy in stride(from: -reach, through: reach, by: 2) {
            for dx in stride(from: -reach, through: reach, by: 2) {
                let sx = px + dx, sy = py + dy
                guard sx >= 0, sx < width, sy >= 0, sy < height else { continue }
                let value = Int(pixels[sy * row + sx])
                guard value > 0 else { continue }
                let distance = dx * dx + dy * dy
                if best == nil || distance < best!.distance { best = (distance, value) }
            }
        }
        return best?.label
    }

    /// True when (x, y) is on one of the image's subjects (used to decide what a tap focuses on).
    static func hasSubject(in image: CIImage, x: Double, y: Double) -> Bool {
        let handler = VNImageRequestHandler(ciImage: image, options: [:])
        let request = VNGenerateForegroundInstanceMaskRequest()
        guard (try? handler.perform([request])) != nil, let observation = request.results?.first else { return false }
        return label(in: observation.instanceMask, x: x, y: y, reach: 0.03) != nil
    }

    /// The mask for a frame at `time`: the focused subject, cross-fading from the previous one during a rack.
    static func cinematicMask(for image: CIImage, keys: [CinematicFocus], at time: Double) -> CIImage? {
        guard let state = CinematicFocus.state(keys, at: time) else { return nil }
        let current = focusMask(for: image, focus: state.current)
        guard state.progress < 1, let previous = state.previous, let old = focusMask(for: image, focus: previous) else {
            return current
        }
        let new = current ?? CIImage(color: .white).cropped(to: image.extent) // everything sharp
        return old.applyingFilter("CIDissolveTransition", parameters: [
            kCIInputTargetImageKey: new, kCIInputTimeKey: state.progress,
        ]).cropped(to: image.extent)
    }
}
