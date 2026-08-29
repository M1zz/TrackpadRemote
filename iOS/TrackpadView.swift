//
//  TrackpadView.swift
//  TrackpadRemote (iOS)
//
//  UIKit touch surface wrapped for SwiftUI.
//
//  A real trackpad, not a tablet: the pad reports how far the finger moved, and
//  the cursor continues from wherever it already is. Touching the pad never warps
//  the cursor, and lifting and replacing a finger repositions the cursor's origin
//  the way it does on a Magic Trackpad.
//
//  The view is sized to the desktop's aspect ratio by the parent, so one full
//  swipe across the pad covers the whole desktop at rest gain.
//
//  Gestures:
//    - 1-finger move        -> cursor moves by that much (with acceleration)
//    - 1-finger tap         -> left click (2nd/3rd fast tap -> double/triple click)
//    - 2-finger tap         -> right click
//    - 2-finger pan         -> scroll (natural direction)
//    - double-tap + hold    -> drag (dragBegin ... move ... dragEnd)
//

import SwiftUI
import UIKit

struct TrackpadView: UIViewRepresentable {
    /// Matches the surface's background shape so ripples are clipped to it.
    let cornerRadius: CGFloat
    let send: (InputPacket) -> Void

    func makeUIView(context: Context) -> TrackpadUIView {
        let view = TrackpadUIView()
        view.send = send
        view.layer.cornerRadius = cornerRadius
        view.layer.masksToBounds = true
        return view
    }

    func updateUIView(_ uiView: TrackpadUIView, context: Context) {
        uiView.send = send
        uiView.layer.cornerRadius = cornerRadius
    }
}

final class TrackpadUIView: UIView {

    var send: ((InputPacket) -> Void)?

    // Tuning
    private let tapMaxDuration: TimeInterval = 0.25
    private let tapMaxMovement: CGFloat = 10
    /// Window for chaining taps into a double/triple click, and for starting a drag.
    private let multiTapWindow: TimeInterval = 0.3
    /// A follow-up tap this far from the previous one starts a new click chain.
    private let multiTapMaxDistance: CGFloat = 44
    private let maxClickCount: Float = 3
    private let scrollMultiplier: CGFloat = 2.0
    /// Gain applied to a barely-moving finger; below 1 so precision work is possible.
    private let minGain: CGFloat = 0.55
    private let maxGain: CGFloat = 2.6
    /// Points per event at which acceleration reaches maxGain.
    private let accelerationDivisor: CGFloat = 9.0
    private let rippleRadius: CGFloat = 26
    private let rippleDuration: CFTimeInterval = 0.35

    // Touch tracking state
    private var activeTouches = Set<UITouch>()
    private var maxSimultaneousTouches = 0
    private var gestureStartTime: TimeInterval = 0
    private var gestureStartPoint: CGPoint = .zero
    private var totalMovement: CGFloat = 0
    private var lastPoint: CGPoint?
    private var lastTwoFingerCentroid: CGPoint?
    private var isDragging = false
    private var pendingDrag = false

    // Click-chain state, kept across gestures
    private var lastTapEndTime: TimeInterval = 0
    private var lastTapPoint: CGPoint = .zero
    private var clickCount: Float = 0

    override init(frame: CGRect) {
        super.init(frame: frame)
        isMultipleTouchEnabled = true
        backgroundColor = .clear
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // MARK: - Touch lifecycle

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        for t in touches {
            activeTouches.insert(t)
            showRipple(at: t.location(in: self))
        }
        maxSimultaneousTouches = max(maxSimultaneousTouches, activeTouches.count)

        if activeTouches.count == 1, let touch = touches.first {
            let p = touch.location(in: self)
            gestureStartTime = touch.timestamp
            gestureStartPoint = p
            totalMovement = 0

            // Continue the click chain only if this tap lands near the last one
            // and soon enough; otherwise it's the start of a new chain.
            let soonEnough = touch.timestamp - lastTapEndTime < multiTapWindow
            let closeEnough = hypot(p.x - lastTapPoint.x, p.y - lastTapPoint.y) < multiTapMaxDistance
            if !(soonEnough && closeEnough) {
                clickCount = 0
            }
            // Double-tap-and-hold begins a drag
            pendingDrag = soonEnough && closeEnough && clickCount >= 1

            // Deliberately no packet here: the cursor stays where the user left it.
            lastPoint = p

        } else if activeTouches.count == 2 {
            lastTwoFingerCentroid = centroid(of: activeTouches)
            // A second finger cancels any pending drag and any click chain
            pendingDrag = false
            clickCount = 0
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        if activeTouches.count == 1, let touch = touches.first {
            // Once a gesture has been multi-touch, don't warp the cursor to a
            // leftover finger when the others lift.
            guard maxSimultaneousTouches == 1 else { return }

            let p = touch.location(in: self)
            guard let last = lastPoint else { lastPoint = p; return }
            let rawDx = p.x - last.x
            let rawDy = p.y - last.y
            lastPoint = p
            totalMovement += abs(rawDx) + abs(rawDy)

            // Movement past threshold while a drag is pending = drag start
            if pendingDrag && !isDragging && totalMovement > tapMaxMovement {
                isDragging = true
                pendingDrag = false
                send?(InputPacket(type: .dragBegin))
            }

            sendDelta(dx: rawDx, dy: rawDy)

        } else if activeTouches.count == 2 {
            let c = centroid(of: activeTouches)
            guard let last = lastTwoFingerCentroid else { lastTwoFingerCentroid = c; return }

            let dx = (c.x - last.x) * scrollMultiplier
            let dy = (c.y - last.y) * scrollMultiplier
            lastTwoFingerCentroid = c
            totalMovement += hypot(dx, dy)

            // Natural scrolling: content follows fingers
            send?(InputPacket(type: .scroll, a: Float(dx), b: Float(dy)))
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        for t in touches { activeTouches.remove(t) }

        // Fingers rarely lift in the same event; only judge the gesture once the
        // last one is up, so a 2-finger tap isn't misread as a 1-finger tap.
        guard activeTouches.isEmpty, let touch = touches.first else {
            lastTwoFingerCentroid = nil
            return
        }
        defer { resetGestureState() }

        if isDragging {
            send?(InputPacket(type: .dragEnd))
            clickCount = 0
            return
        }

        let duration = touch.timestamp - gestureStartTime
        guard duration < tapMaxDuration, totalMovement < tapMaxMovement else {
            clickCount = 0
            return
        }

        if maxSimultaneousTouches >= 2 {
            send?(InputPacket(type: .rightClick, a: 1))
            clickCount = 0
        } else {
            clickCount = min(clickCount + 1, maxClickCount)
            send?(InputPacket(type: .leftClick, a: clickCount))
            lastTapEndTime = touch.timestamp
            lastTapPoint = gestureStartPoint
        }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        for t in touches { activeTouches.remove(t) }
        if activeTouches.isEmpty {
            if isDragging { send?(InputPacket(type: .dragEnd)) }
            clickCount = 0
            resetGestureState()
        }
    }

    // MARK: - Touch feedback

    /// Expanding ring at the point touched. On an absolute pad the finger is the
    /// cursor, so the surface has to confirm *where* it read the touch — there is
    /// no on-screen cursor here to do that.
    private func showRipple(at point: CGPoint) {
        let ring = CAShapeLayer()
        ring.path = UIBezierPath(arcCenter: .zero,
                                 radius: rippleRadius,
                                 startAngle: 0,
                                 endAngle: .pi * 2,
                                 clockwise: true).cgPath
        ring.position = point
        ring.fillColor = UIColor.tintColor.withAlphaComponent(0.18).cgColor
        ring.strokeColor = UIColor.tintColor.withAlphaComponent(0.9).cgColor
        ring.lineWidth = 1.5
        ring.opacity = 0
        layer.addSublayer(ring)

        CATransaction.begin()
        CATransaction.setCompletionBlock { [weak ring] in ring?.removeFromSuperlayer() }

        let scale = CABasicAnimation(keyPath: "transform.scale")
        scale.fromValue = 0.45
        scale.toValue = 1.15

        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 1.0
        fade.toValue = 0.0

        let group = CAAnimationGroup()
        group.animations = [scale, fade]
        group.duration = rippleDuration
        group.timingFunction = CAMediaTimingFunction(name: .easeOut)
        group.isRemovedOnCompletion = false
        group.fillMode = .forwards
        ring.add(group, forKey: "ripple")

        CATransaction.commit()
    }

    // MARK: - Helpers

    /// Sends the movement as a fraction of the pad's width, so the Mac can scale
    /// it to any desktop without knowing this phone's size. Both axes divide by
    /// width on purpose: dividing y by height would skew diagonals whenever the
    /// pad's aspect drifts from the desktop's.
    private func sendDelta(dx: CGFloat, dy: CGFloat) {
        guard bounds.width > 0 else { return }
        let (ax, ay) = accelerated(dx: dx, dy: dy)
        send?(InputPacket(type: .moveRelative,
                          a: Float(ax / bounds.width),
                          b: Float(ay / bounds.width)))
    }

    /// Pointer acceleration, the part that makes a trackpad feel like a trackpad:
    /// slow moves stay under rest gain so small targets are reachable, fast flicks
    /// multiply up so the cursor can cross the screen without a second swipe.
    private func accelerated(dx: CGFloat, dy: CGFloat) -> (CGFloat, CGFloat) {
        let speed = hypot(dx, dy)
        let multiplier = minGain + min(speed / accelerationDivisor, maxGain - minGain)
        return (dx * multiplier, dy * multiplier)
    }

    private func resetGestureState() {
        maxSimultaneousTouches = 0
        lastPoint = nil
        lastTwoFingerCentroid = nil
        isDragging = false
        pendingDrag = false
        totalMovement = 0
    }

    private func centroid(of touches: Set<UITouch>) -> CGPoint {
        var x: CGFloat = 0, y: CGFloat = 0
        for t in touches {
            let p = t.location(in: self)
            x += p.x
            y += p.y
        }
        let n = CGFloat(touches.count)
        return CGPoint(x: x / n, y: y / n)
    }
}
