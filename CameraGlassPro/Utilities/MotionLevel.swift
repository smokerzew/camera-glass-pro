import CoreMotion
import Foundation
import Observation

/// Reads the phone's sideways tilt from the accelerometer/gyro (CoreMotion device motion).
/// Device motion needs no permission prompt. On devices without it (the Simulator) the level stays flat.
@MainActor
@Observable
final class MotionLevel {
    /// Rotation of the phone around the screen's axis, in radians. 0 = upright and level.
    private(set) var angle: Double = 0
    /// False while the phone lies flat (face up/down), where sideways tilt is meaningless.
    private(set) var isUpright = true
    private(set) var isTracking = false

    private let manager = CMMotionManager()

    /// Within this many radians the guide snaps to level and turns yellow (~1°).
    nonisolated static let levelTolerance = 1.0 * .pi / 180

    func start() {
        guard manager.isDeviceMotionAvailable, !manager.isDeviceMotionActive else { return }
        manager.deviceMotionUpdateInterval = 1.0 / 30
        manager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let gravity = motion?.gravity else { return }
            MainActor.assumeIsolated {
                self?.update(gx: gravity.x, gy: gravity.y, gz: gravity.z)
            }
        }
        isTracking = true
    }

    func stop() {
        manager.stopDeviceMotionUpdates()
        isTracking = false
        angle = 0
    }

    private func update(gx: Double, gy: Double, gz: Double) {
        isUpright = abs(gz) < 0.85
        let raw = Self.roll(gx: gx, gy: gy)
        angle += (raw - angle) * 0.25 // light smoothing so the line doesn't jitter
    }

    /// Sideways tilt for a portrait phone: 0 when gravity points straight down the screen.
    nonisolated static func roll(gx: Double, gy: Double) -> Double {
        atan2(gx, -gy)
    }

    nonisolated static func isLevel(_ angle: Double) -> Bool {
        abs(angle) <= levelTolerance
    }
}
