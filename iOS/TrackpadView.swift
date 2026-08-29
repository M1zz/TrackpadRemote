//
//  TrackpadView.swift
//  TrackpadRemote (iOS)
//
//  UIKit touch surface wrapped for SwiftUI.
//  Gestures:
//    - 1-finger move        -> cursor move
//    - 1-finger tap         -> left click
//    - 2-finger tap         -> right click
//    - 2-finger pan         -> scroll (natural direction)
//    - double-tap + hold    -> drag (dragBegin ... move ... dragEnd)
//

import SwiftUI
import UIKit

struct TrackpadView: UIViewRepresentable {
    let send: (InputPacket) -> Void

    func makeUIView(context: Context) -> TrackpadUIView {
        let view = TrackpadUIView()
        view.send = send
        return view
    }

    func updateUIView(_ uiView: TrackpadUIView, context: Context) {}
}

final class TrackpadUIView: UIView {

    var send: ((InputPacket) -> Void)?

    // Tuning
    private let tapMaxDuration: TimeInterval = 0.25
    private let tapMaxMovement: CGFloat = 10
    private let doubleTapWindow: TimeInterval = 0.3
    private let scrollMultiplier: CGFloat = 2.0

    // Touch tracking state
    private var activeTouches = Set<UITouch>()
    private var maxSimultaneousTouches = 0
    private var touchStartTime: TimeInterval = 0
    private var touchStartPoint: CGPoint = .zero
    private var totalMovement: CGFloat = 0
    private var lastPoint: CGPoint?
    private var lastTwoFingerCentroid: CGPoint?
    private var lastTapEndTime: TimeInterval = 0
    private var isDragging = false
    private var pendingDrag = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        isMultipleTouchEnabled = true
        backgroundColor = .clear
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // MARK: - Touch lifecycle

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        for t in touches { activeTouches.insert(t) }
        maxSimultaneousTouches = max(maxSimultaneousTouches, activeTouches.count)

        if activeTouches.count == 1, let touch = touches.first {
            touchStartTime = touch.timestamp
            touchStartPoint = touch.location(in: self)
            totalMovement = 0
            lastPoint = touchStartPoint

            // Double-tap-and-hold begins a drag
            if touch.timestamp - lastTapEndTime < doubleTapWindow {
                pendingDrag = true
            }
        } else if activeTouches.count == 2 {
            lastTwoFingerCentroid = centroid(of: activeTouches)
            // A second finger cancels any pending drag
            pendingDrag = false
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        if activeTouches.count == 1, let touch = touches.first {
            let p = touch.location(in: self)
            guard let last = lastPoint else { lastPoint = p; return }

            let rawDx = p.x - last.x
            let rawDy = p.y - last.y
            totalMovement += abs(rawDx) + abs(rawDy)
            lastPoint = p

            // Movement past threshold while a drag is pending = drag start
            if pendingDrag && !isDragging && totalMovement > tapMaxMovement {
                isDragging = true
                pendingDrag = false
                send?(InputPacket(type: .dragBegin))
            }

            let (dx, dy) = accelerated(dx: rawDx, dy: rawDy)
            send?(InputPacket(type: .move, dx: Float(dx), dy: Float(dy)))

        } else if activeTouches.count == 2 {
            let c = centroid(of: activeTouches)
            guard let last = lastTwoFingerCentroid else { lastTwoFingerCentroid = c; return }

            let dx = (c.x - last.x) * scrollMultiplier
            let dy = (c.y - last.y) * scrollMultiplier
            lastTwoFingerCentroid = c
            totalMovement += abs(dx) + abs(dy)

            // Natural scrolling: content follows fingers
            send?(InputPacket(type: .scroll, dx: Float(dx), dy: Float(dy)))
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        for t in touches { activeTouches.remove(t) }
        guard activeTouches.isEmpty, let touch = touches.first else {
            // One of two fingers lifted — reset centroid so cursor doesn't jump
            lastTwoFingerCentroid = nil
            return
        }
        defer { resetTouchState() }

        if isDragging {
            send?(InputPacket(type: .dragEnd))
            return
        }

        let duration = touch.timestamp - touchStartTime
        let isTap = duration < tapMaxDuration && totalMovement < tapMaxMovement

        if isTap {
            if maxSimultaneousTouches >= 2 {
                send?(InputPacket(type: .rightClick))
            } else {
                send?(InputPacket(type: .leftClick))
                lastTapEndTime = touch.timestamp
            }
        }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        for t in touches { activeTouches.remove(t) }
        if activeTouches.isEmpty {
            if isDragging { send?(InputPacket(type: .dragEnd)) }
            resetTouchState()
        }
    }

    // MARK: - Helpers

    private func resetTouchState() {
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

    /// Pointer acceleration: slow moves ~1x for precision, fast flicks up to ~3.5x.
    private func accelerated(dx: CGFloat, dy: CGFloat) -> (CGFloat, CGFloat) {
        let speed = hypot(dx, dy)
        let multiplier = 1.0 + min(speed / 8.0, 2.5)
        return (dx * multiplier, dy * multiplier)
    }
}
