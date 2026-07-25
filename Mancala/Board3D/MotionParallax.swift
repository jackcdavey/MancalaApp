import Foundation
#if canImport(CoreMotion)
import CoreMotion
#endif
#if canImport(UIKit)
import UIKit
#endif

/// Turns device attitude into small, smoothed camera-orbit offsets so the 3D
/// board's perspective shifts as the device tilts in any direction. Silent
/// no-op where device motion is unavailable (simulator, Mac).
@MainActor
final class MotionParallaxController {
    #if canImport(CoreMotion)
    private let manager = CMMotionManager()
    private var baseline: CMAttitude?
    #endif
    private var smoothedYaw: Float = 0
    private var smoothedPitch: Float = 0
    private var foregroundObserver: NSObjectProtocol?

    /// Maximum attitude delta (radians) that still adds parallax.
    private let inputClamp: Float = 0.35
    /// Attitude-to-camera gain; with the clamp this allows ≈ ±6°.
    private let gain: Float = 0.30
    /// Low-pass factor per 60 Hz sample.
    private let smoothing: Float = 0.10

    func start(_ apply: @escaping @MainActor (Float, Float) -> Void) {
        #if canImport(CoreMotion)
        guard manager.isDeviceMotionAvailable, !manager.isDeviceMotionActive else { return }
        manager.deviceMotionUpdateInterval = 1.0 / 60.0
        manager.startDeviceMotionUpdates(using: .xArbitraryZVertical, to: .main) { [weak self] motion, _ in
            guard let self, let motion else { return }
            MainActor.assumeIsolated {
                self.handle(motion.attitude, apply: apply)
            }
        }

        #if canImport(UIKit)
        // The neutral pose drifts while backgrounded; re-zero on return so
        // the board doesn't come back tilted.
        foregroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.baseline = nil
            }
        }
        #endif
        #endif
    }

    func stop() {
        #if canImport(CoreMotion)
        manager.stopDeviceMotionUpdates()
        baseline = nil
        #endif
        if let foregroundObserver {
            NotificationCenter.default.removeObserver(foregroundObserver)
            self.foregroundObserver = nil
        }
        smoothedYaw = 0
        smoothedPitch = 0
    }

    #if canImport(CoreMotion)
    private func handle(_ attitude: CMAttitude, apply: @MainActor (Float, Float) -> Void) {
        if baseline == nil {
            baseline = attitude.copy() as? CMAttitude
        }
        let relative = attitude.copy() as? CMAttitude ?? attitude
        if let baseline {
            relative.multiply(byInverseOf: baseline)
        }

        // Rolling the device left/right looks around the board horizontally;
        // pitching it toward/away looks over/under.
        let targetYaw = clamp(Float(relative.roll)) * gain
        let targetPitch = clamp(Float(relative.pitch)) * gain
        smoothedYaw += (targetYaw - smoothedYaw) * smoothing
        smoothedPitch += (targetPitch - smoothedPitch) * smoothing
        apply(smoothedYaw, smoothedPitch)
    }

    private func clamp(_ value: Float) -> Float {
        min(max(value, -inputClamp), inputClamp)
    }
    #endif
}
