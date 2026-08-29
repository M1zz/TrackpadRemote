//
//  MotionPointer.swift
//  TrackpadRemote (iOS)
//
//  Air-mouse input: aim the back of the phone at the screen and the cursor
//  follows. Only runs while the clutch is engaged (a finger resting on the pad),
//  because an air mouse that is always live can never be put down — the cursor
//  drifts with every twitch and there is nowhere to rest your hand.
//
//  Grip independence comes from gravity, not from the attitude matrix. Device
//  motion reports gravity in device coordinates, which hands us the world's
//  vertical axis for free, so angular velocity can be split into "turn" and
//  "tilt" without caring how the phone is being held — and without depending on
//  which way CMAttitude's rotation matrix is meant to be multiplied.
//

import CoreMotion
import Foundation

final class MotionPointer {

    /// Normalized deltas in the same units the pad sends: fractions of a full
    /// desktop sweep. Called on the main queue.
    var send: ((Float, Float) -> Void)?
    /// Total movement emitted since the clutch engaged, for drag detection.
    private(set) var travel: Double = 0

    // MARK: - Tuning

    /// Turning the phone this far (radians) sweeps the cursor across the desktop.
    /// ~34°, about what a wrist can do without moving the forearm.
    private let fullSweep: Double = 0.6
    /// Angular speed below this is hand tremor, not intent.
    private let deadzone: Double = 0.02          // rad/s
    /// Exponential smoothing; higher follows the hand faster but shakes more.
    private let smoothing: Double = 0.35
    /// Flip if aiming right moves the cursor left.
    private let invertX = false
    /// Flip if raising the nose moves the cursor down.
    private let invertY = false

    // MARK: - State

    private let manager = CMMotionManager()
    private var smoothedX: Double = 0
    private var smoothedY: Double = 0
    private var lastTimestamp: TimeInterval?

    var isAvailable: Bool { manager.isDeviceMotionAvailable }

    // MARK: - Clutch

    func engage() {
        guard manager.isDeviceMotionAvailable, !manager.isDeviceMotionActive else { return }
        smoothedX = 0
        smoothedY = 0
        travel = 0
        lastTimestamp = nil
        manager.deviceMotionUpdateInterval = 1.0 / 60.0
        // Device motion, not raw gyro: this one is bias-corrected. Integrating
        // the raw gyro lets the cursor crawl on its own within seconds.
        manager.startDeviceMotionUpdates(using: .xArbitraryCorrectedZVertical,
                                         to: .main) { [weak self] motion, _ in
            guard let self, let motion else { return }
            self.handle(motion)
        }
    }

    func disengage() {
        guard manager.isDeviceMotionActive else { return }
        manager.stopDeviceMotionUpdates()
    }

    // MARK: - Mapping

    private func handle(_ motion: CMDeviceMotion) {
        // Real elapsed time, not the requested interval: the system throttles
        // updates under load, and a stale nominal interval would scale every
        // delta wrong exactly when the cursor is already struggling.
        let interval: TimeInterval
        if let last = lastTimestamp {
            interval = min(max(motion.timestamp - last, 0), 0.1)
        } else {
            interval = manager.deviceMotionUpdateInterval
        }
        lastTimestamp = motion.timestamp

        // Gravity points down in device coordinates, so its negation is world up.
        guard let up = Vec3(motion.gravity).negated.normalized else { return }
        // The phone aims out of its back: -Z in device coordinates.
        let aim = Vec3(x: 0, y: 0, z: -1)
        // Right-hand side of the aim, level with the horizon.
        guard let right = aim.cross(up).normalized else { return }   // aiming straight up/down

        let omega = Vec3(motion.rotationRate)

        // Turning about the world vertical swings the aim sideways; tilting about
        // the horizontal right axis raises or lowers it.
        var turn = omega.dot(up)
        var tilt = omega.dot(right)

        turn = abs(turn) < deadzone ? 0 : turn
        tilt = abs(tilt) < deadzone ? 0 : tilt

        smoothedX += (turn - smoothedX) * smoothing
        smoothedY += (tilt - smoothedY) * smoothing

        // Rotating about `up` by +ω swings the aim toward -right, and rotating
        // about `right` by +ω raises the aim while screen y grows downward, so
        // both axes are negated.
        var dx = -smoothedX * interval / fullSweep
        var dy = -smoothedY * interval / fullSweep
        if invertX { dx = -dx }
        if invertY { dy = -dy }

        guard dx != 0 || dy != 0 else { return }
        travel += abs(dx) + abs(dy)
        send?(Float(dx), Float(dy))
    }
}

// MARK: - Minimal vector math

private struct Vec3 {
    var x: Double
    var y: Double
    var z: Double

    init(x: Double, y: Double, z: Double) {
        self.x = x
        self.y = y
        self.z = z
    }

    init(_ a: CMAcceleration) { self.init(x: a.x, y: a.y, z: a.z) }
    init(_ r: CMRotationRate) { self.init(x: r.x, y: r.y, z: r.z) }

    var negated: Vec3 { Vec3(x: -x, y: -y, z: -z) }

    var normalized: Vec3? {
        let length = (x * x + y * y + z * z).squareRoot()
        guard length > 1e-6 else { return nil }
        return Vec3(x: x / length, y: y / length, z: z / length)
    }

    func dot(_ o: Vec3) -> Double { x * o.x + y * o.y + z * o.z }

    func cross(_ o: Vec3) -> Vec3 {
        Vec3(x: y * o.z - z * o.y,
             y: z * o.x - x * o.z,
             z: x * o.y - y * o.x)
    }
}
