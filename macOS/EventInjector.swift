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

final class EventInjector {

    /// Serial queue so events are injected in arrival order.
    private let queue = DispatchQueue(label: "trackpad.event-injector", qos: .userInteractive)

    /// The rect the phone's pad maps onto, in CGEvent coordinates (top-left
    /// origin, y down). Read from the injector queue, written from the main
    /// thread when the screen layout changes, so it lives behind a lock.
    private let desktop = OSAllocatedUnfairLock<CGRect>(initialState: .zero)

    private var position: CGPoint = .zero
    private var isDragging = false

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
    static func currentDesktopBounds() -> CGRect {
        let screens = NSScreen.screens
        guard let mainHeight = screens.first?.frame.height else { return .zero }

        var union: CGRect = .null
        for screen in screens {
            let f = screen.frame
            // AppKit is bottom-left origin; CGEvent is top-left origin.
            union = union.union(CGRect(x: f.origin.x,
                                       y: mainHeight - f.origin.y - f.height,
                                       width: f.width,
                                       height: f.height))
        }
        return union.isNull ? .zero : union
    }

    /// Call on launch and whenever the display arrangement changes.
    @MainActor
    func refreshDesktopBounds() -> CGRect {
        let bounds = Self.currentDesktopBounds()
        desktop.withLock { $0 = bounds }
        return bounds
    }

    // MARK: - Packet handling

    func handle(_ packet: InputPacket) {
        queue.async { [weak self] in
            guard let self else { return }
            switch packet.type {
            case .moveAbsolute:
                self.move(toNormalized: CGPoint(x: CGFloat(packet.a), y: CGFloat(packet.b)))
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

    private func move(toNormalized p: CGPoint) {
        let rect = desktop.withLock { $0 }
        guard rect.width > 0, rect.height > 0 else { return }

        let target = CGPoint(
            x: rect.minX + min(max(p.x, 0), 1) * (rect.width - 1),
            y: rect.minY + min(max(p.y, 0), 1) * (rect.height - 1)
        )
        let delta = CGPoint(x: target.x - position.x, y: target.y - position.y)
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
    }

    /// `count` is decided on the phone, which knows the real tap timing, rather
    /// than re-guessed here from packet arrival times.
    private func click(button: CGMouseButton, count: Int64) {
        let clickState = max(1, min(count, 3))

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
