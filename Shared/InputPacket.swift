//
//  InputPacket.swift
//  TrackpadRemote (Shared — add to BOTH iOS and macOS targets)
//
//  Fixed-size binary protocol: 1 byte type + 4 bytes Float32 a + 4 bytes Float32 b
//  (9 bytes total, little-endian). Much cheaper than JSON for high-frequency
//  pointer events.
//

import Foundation

enum PacketType: UInt8 {
    /// iPhone → Mac. `a`, `b` = how far the finger moved, as a fraction of the
    /// pad's width (both axes use width, so the gain is isotropic whatever the
    /// pad's shape). Relative like a real trackpad: the cursor moves *from where
    /// it is*, so touching the pad never warps it. The Mac scales by the desktop
    /// width, which makes one full swipe across the pad cross the whole desktop.
    case moveRelative = 0x01
    /// iPhone → Mac. `a` = click count (1 single, 2 double, 3 triple).
    case leftClick    = 0x02
    /// iPhone → Mac. `a` = click count.
    case rightClick   = 0x03
    /// iPhone → Mac. `a`, `b` = scroll delta in pixels.
    case scroll       = 0x04
    /// iPhone → Mac. Left button down (drag start).
    case dragBegin    = 0x05
    /// iPhone → Mac. Left button up (drag end).
    case dragEnd      = 0x06
    /// Mac → iPhone. `a`, `b` = desktop width/height in points, so the phone can
    /// letterbox its pad to the display's aspect ratio and keep the map undistorted.
    case screenInfo   = 0x07
    /// iPhone → Mac. `a` = `SwipeDirection.rawValue`. Three fingers.
    case swipe        = 0x08
    /// iPhone → Mac. `a` = +1 to zoom in, -1 to zoom out. One step per pinch notch.
    case zoom         = 0x09
}

/// Direction the fingers travelled, in pad coordinates. What the Mac does with
/// it (spaces, Mission Control) is the Mac's business.
enum SwipeDirection: UInt8 {
    case up    = 1
    case down  = 2
    case left  = 3
    case right = 4
}

struct InputPacket {
    let type: PacketType
    /// Meaning depends on `type` — see `PacketType`.
    let a: Float
    /// Meaning depends on `type` — see `PacketType`.
    let b: Float

    init(type: PacketType, a: Float = 0, b: Float = 0) {
        self.type = type
        self.a = a
        self.b = b
    }

    // MARK: - Encoding

    func encoded() -> Data {
        var data = Data(capacity: 9)
        data.append(type.rawValue)
        var x = a.bitPattern.littleEndian
        var y = b.bitPattern.littleEndian
        withUnsafeBytes(of: &x) { data.append(contentsOf: $0) }
        withUnsafeBytes(of: &y) { data.append(contentsOf: $0) }
        return data
    }

    // MARK: - Decoding

    init?(data: Data) {
        guard data.count == 9,
              let type = PacketType(rawValue: data[data.startIndex]) else { return nil }

        let base = data.startIndex
        let xBits = data.subdata(in: (base + 1)..<(base + 5))
            .withUnsafeBytes { $0.load(as: UInt32.self) }
        let yBits = data.subdata(in: (base + 5)..<(base + 9))
            .withUnsafeBytes { $0.load(as: UInt32.self) }

        self.type = type
        self.a = Float(bitPattern: UInt32(littleEndian: xBits))
        self.b = Float(bitPattern: UInt32(littleEndian: yBits))
    }
}

enum ServiceConfig {
    /// Must match NSBonjourServices in BOTH Info.plists:
    /// _trackpad-rc._tcp and _trackpad-rc._udp
    static let serviceType = "trackpad-rc"
}
