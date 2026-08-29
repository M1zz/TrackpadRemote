//
//  EventInjector.swift
//  TrackpadServer (macOS)
//
//  Translates InputPackets into CGEvents.
//  Requires Accessibility permission (System Settings > Privacy & Security
//  > Accessibility). Not available to sandboxed apps.
//

import Foundation
import CoreGraphics
import AppKit

final class EventInjector {

    /// Serial queue so events are injected in arrival order.
    private let queue = DispatchQueue(label: "trackpad.event-injector", qos: .userInteractive)

    /// Tracked cursor position. CGEvent's own location can lag behind
    /// rapid injection, so we keep our own and clamp to screen bounds.
    private var position: CGPoint
    private var isDragging = false
    private var lastClickTime: TimeInterval = 0
    private var clickCount: Int64 = 1

    init() {
        position = CGEvent(source: nil)?.location ?? .zero
    }

    // MARK: - Permission

    static func checkPermission(prompt: Bool) -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [key: prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    // MARK: - Packet handling

    func handle(_ packet: InputPacket) {
        queue.async { [weak self] in
            guard let self else { return }
            switch packet.type {
            case .move:
                self.move(dx: CGFloat(packet.dx), dy: CGFloat(packet.dy))
            case .leftClick:
                self.click(button: .left)
            case .rightClick:
                self.click(button: .right)
            case .scroll:
                self.scroll(dx: Int32(packet.dx.rounded()), dy: Int32(packet.dy.rounded()))
            case .dragBegin:
                self.dragBegin()
            case .dragEnd:
                self.dragEnd()
            }
        }
    }

    // MARK: - Injection

    private func move(dx: CGFloat, dy: CGFloat) {
        position.x += dx
        position.y += dy
        position = clampToScreens(position)

        let type: CGEventType = isDragging ? .leftMouseDragged : .mouseMoved
        let event = CGEvent(mouseEventSource: nil,
                            mouseType: type,
                            mouseCursorPosition: position,
                            mouseButton: .left)
        // Delta fields help apps (games, etc.) that read relative motion
        event?.setIntegerValueField(.mouseEventDeltaX, value: Int64(dx.rounded()))
        event?.setIntegerValueField(.mouseEventDeltaY, value: Int64(dy.rounded()))
        event?.post(tap: .cghidEventTap)
    }

    private func click(button: CGMouseButton) {
        // Support double-click detection (450 ms is the macOS default-ish window)
        let now = CFAbsoluteTimeGetCurrent()
        if button == .left, now - lastClickTime < 0.45 {
            clickCount += 1
        } else {
            clickCount = 1
        }
        lastClickTime = now

        let (downType, upType): (CGEventType, CGEventType) = button == .left
            ? (.leftMouseDown, .leftMouseUp)
            : (.rightMouseDown, .rightMouseUp)

        for type in [downType, upType] {
            let event = CGEvent(mouseEventSource: nil,
                                mouseType: type,
                                mouseCursorPosition: position,
                                mouseButton: button)
            event?.setIntegerValueField(.mouseEventClickState, value: clickCount)
            event?.post(tap: .cghidEventTap)
        }
    }

    private func scroll(dx: Int32, dy: Int32) {
        // Pixel-unit scrolling feels like a real trackpad (vs. line units)
        let event = CGEvent(scrollWheelEvent2Source: nil,
                            units: .pixel,
                            wheelCount: 2,
                            wheel1: dy,   // vertical
                            wheel2: dx,   // horizontal
                            wheel3: 0)
        event?.post(tap: .cghidEventTap)
    }

    private func dragBegin() {
        guard !isDragging else { return }
        isDragging = true
        CGEvent(mouseEventSource: nil,
                mouseType: .leftMouseDown,
                mouseCursorPosition: position,
                mouseButton: .left)?
            .post(tap: .cghidEventTap)
    }

    private func dragEnd() {
        guard isDragging else { return }
        isDragging = false
        CGEvent(mouseEventSource: nil,
                mouseType: .leftMouseUp,
                mouseCursorPosition: position,
                mouseButton: .left)?
            .post(tap: .cghidEventTap)
    }

    // MARK: - Helpers

    /// Clamp to the union-adjacent screen containing (or nearest to) the point,
    /// so the cursor can cross between multiple displays but never escape.
    private func clampToScreens(_ p: CGPoint) -> CGPoint {
        // CGEvent coordinates: origin top-left of main display, y grows downward.
        var frames: [CGRect] = []
        for screen in NSScreen.screens {
            let f = screen.frame
            guard let mainHeight = NSScreen.screens.first?.frame.height else { continue }
            // Convert AppKit (bottom-left origin) to CG (top-left origin)
            let cgFrame = CGRect(x: f.origin.x,
                                 y: mainHeight - f.origin.y - f.height,
                                 width: f.width,
                                 height: f.height)
            frames.append(cgFrame)
        }

        // Already inside a screen
        if frames.contains(where: { $0.contains(p) }) { return p }

        // Clamp to the nearest screen
        var best = p
        var bestDistance = CGFloat.greatestFiniteMagnitude
        for frame in frames {
            let clamped = CGPoint(
                x: min(max(p.x, frame.minX), frame.maxX - 1),
                y: min(max(p.y, frame.minY), frame.maxY - 1)
            )
            let d = hypot(clamped.x - p.x, clamped.y - p.y)
            if d < bestDistance {
                bestDistance = d
                best = clamped
            }
        }
        return best
    }
}
