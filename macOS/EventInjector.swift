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
import os

let injectorLog = Logger(subsystem: "com.hyunholee.TrackpadServer", category: "injector")

/// Safe to hand across isolation domains: every mutable field is touched only
/// inside `queue`, and the screen layout lives behind a lock. The compiler can't
/// see that, so the conformance is unchecked.
final class EventInjector: @unchecked Sendable {

    /// Serial queue so events are injected in arrival order.
    private let queue = DispatchQueue(label: "trackpad.event-injector", qos: .userInteractive)

    /// Every screen plus their union, in CGEvent coordinates (top-left origin,
    /// y down). Read from the injector queue, written from the main thread when
    /// the screen layout changes, so it lives behind a lock.
    private let layout = OSAllocatedUnfairLock<ScreenLayout>(initialState: ScreenLayout())

    struct ScreenLayout {
        var frames: [CGRect] = []
        var union: CGRect = .zero
    }

    private var position: CGPoint = .zero
    private var isDragging = false
    /// Moves arrive at touch rate; log a sample rather than every one.
    private var moveCount = 0
    private var lastMoveTime: CFAbsoluteTime = 0
    /// Idle gap after which the cursor may have been moved by something else.
    private let resyncIdleInterval: CFAbsoluteTime = 0.4

    init() {
        position = CGEvent(source: nil)?.location ?? .zero
    }

    // MARK: - Permission

    static func checkPermission(prompt: Bool) -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [key: prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    // MARK: - Screen geometry

    /// Union of every screen, converted to CGEvent coordinates. NSScreen must be
    /// read on the main thread, so this is cached rather than read per packet.
    @MainActor
    static func currentScreenLayout() -> ScreenLayout {
        let screens = NSScreen.screens
        guard let mainHeight = screens.first?.frame.height else { return ScreenLayout() }

        var frames: [CGRect] = []
        var union: CGRect = .null
        for screen in screens {
            let f = screen.frame
            // AppKit is bottom-left origin; CGEvent is top-left origin.
            let cg = CGRect(x: f.origin.x,
                            y: mainHeight - f.origin.y - f.height,
                            width: f.width,
                            height: f.height)
            frames.append(cg)
            union = union.union(cg)
        }
        return ScreenLayout(frames: frames, union: union.isNull ? .zero : union)
    }

    /// Call on launch and whenever the display arrangement changes.
    @MainActor
    func refreshScreenLayout() -> CGRect {
        let current = Self.currentScreenLayout()
        layout.withLock { $0 = current }
        injectorLog.info("screens: \(current.frames.count, privacy: .public), desktop \(current.union.debugDescription, privacy: .public)")
        return current.union
    }

    // MARK: - Packet handling

    func handle(_ packet: InputPacket) {
        queue.async { [weak self] in
            guard let self else { return }
            switch packet.type {
            case .moveRelative:
                self.move(byNormalized: CGPoint(x: CGFloat(packet.a), y: CGFloat(packet.b)))
            case .leftClick:
                self.click(button: .left, count: Int64(packet.a))
            case .rightClick:
                self.click(button: .right, count: Int64(packet.a))
            case .scroll:
                self.scroll(dx: Int32(packet.a.rounded()), dy: Int32(packet.b.rounded()))
            case .dragBegin:
                self.dragBegin()
            case .dragEnd:
                self.dragEnd()
            case .screenInfo:
                break   // Mac sends this; it never receives it.
            }
        }
    }

    // MARK: - Injection

    private func move(byNormalized d: CGPoint) {
        let current = layout.withLock { $0 }
        guard current.union.width > 0 else {
            injectorLog.error("move dropped: no known screens")
            return
        }

        // The phone sends fractions of its own pad width; scaling by desktop
        // width makes one full swipe cover the desktop regardless of phone size.
        let delta = CGPoint(x: d.x * current.union.width,
                            y: d.y * current.union.width)

        // We track the position ourselves: CGEvent's reported location lags
        // behind rapid injection, so reading it every packet would drop motion.
        // But a real mouse may have moved the cursor while the pad was idle, so
        // resync whenever there is a gap between gestures.
        let now = CFAbsoluteTimeGetCurrent()
        if now - lastMoveTime > resyncIdleInterval, let live = CGEvent(source: nil)?.location {
            position = live
        }
        lastMoveTime = now

        let target = clamp(CGPoint(x: position.x + delta.x, y: position.y + delta.y), to: current)
        position = target

        let type: CGEventType = isDragging ? .leftMouseDragged : .mouseMoved
        let event = CGEvent(mouseEventSource: nil,
                            mouseType: type,
                            mouseCursorPosition: position,
                            mouseButton: .left)
        // Delta fields help apps (games, etc.) that read relative motion
        event?.setIntegerValueField(.mouseEventDeltaX, value: Int64(delta.x.rounded()))
        event?.setIntegerValueField(.mouseEventDeltaY, value: Int64(delta.y.rounded()))
        event?.post(tap: .cghidEventTap)

        moveCount += 1
        if moveCount % 30 == 1 {
            let landed = CGEvent(source: nil)?.location ?? .zero
            injectorLog.debug("move #\(self.moveCount, privacy: .public) delta(\(delta.x, privacy: .public), \(delta.y, privacy: .public)) -> target(\(target.x, privacy: .public), \(target.y, privacy: .public)); cursor is now (\(landed.x, privacy: .public), \(landed.y, privacy: .public)); event built: \(event != nil, privacy: .public)")
        }
    }

    /// `count` is decided on the phone, which knows the real tap timing, rather
    /// than re-guessed here from packet arrival times.
    private func click(button: CGMouseButton, count: Int64) {
        let clickState = max(1, min(count, 3))
        injectorLog.info("click \(button == .left ? "left" : "right", privacy: .public) x\(clickState, privacy: .public) at (\(self.position.x, privacy: .public), \(self.position.y, privacy: .public))")

        let (downType, upType): (CGEventType, CGEventType) = button == .left
            ? (.leftMouseDown, .leftMouseUp)
            : (.rightMouseDown, .rightMouseUp)

        for type in [downType, upType] {
            let event = CGEvent(mouseEventSource: nil,
                                mouseType: type,
                                mouseCursorPosition: position,
                                mouseButton: button)
            event?.setIntegerValueField(.mouseEventClickState, value: clickState)
            event?.post(tap: .cghidEventTap)
        }
    }

    /// Keeps the cursor on a real display. Points between two differently sized
    /// screens fall inside the union but on no screen at all, so clamp to the
    /// nearest frame rather than to the union rect.
    private func clamp(_ p: CGPoint, to layout: ScreenLayout) -> CGPoint {
        if layout.frames.contains(where: { $0.contains(p) }) { return p }

        var best = p
        var bestDistance = CGFloat.greatestFiniteMagnitude
        for frame in layout.frames {
            let clamped = CGPoint(x: min(max(p.x, frame.minX), frame.maxX - 1),
                                  y: min(max(p.y, frame.minY), frame.maxY - 1))
            let d = hypot(clamped.x - p.x, clamped.y - p.y)
            if d < bestDistance {
                bestDistance = d
                best = clamped
            }
        }
        return best
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
}
