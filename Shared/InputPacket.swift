//
//  InputPacket.swift
//  TrackpadRemote (Shared — add to BOTH iOS and macOS targets)
//
//  Fixed-size binary protocol: 1 byte type + 4 bytes Float32 dx + 4 bytes Float32 dy
//  (9 bytes total, little-endian). Much cheaper than JSON for high-frequency move events.
//

import Foundation

enum PacketType: UInt8 {
    case move       = 0x01  // dx, dy = cursor delta in points
    case leftClick  = 0x02
    case rightClick = 0x03
    case scroll     = 0x04  // dx, dy = scroll delta in pixels
    case dragBegin  = 0x05  // left button down (drag start)
    case dragEnd    = 0x06  // left button up (drag end)
}

struct InputPacket {
    let type: PacketType
    let dx: Float
    let dy: Float

    init(type: PacketType, dx: Float = 0, dy: Float = 0) {
        self.type = type
        self.dx = dx
        self.dy = dy
    }

    // MARK: - Encoding

    func encoded() -> Data {
        var data = Data(capacity: 9)
        data.append(type.rawValue)
        var x = dx.bitPattern.littleEndian
        var y = dy.bitPattern.littleEndian
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
        self.dx = Float(bitPattern: UInt32(littleEndian: xBits))
        self.dy = Float(bitPattern: UInt32(littleEndian: yBits))
    }
}

enum ServiceConfig {
    /// Must match NSBonjourServices in BOTH Info.plists:
    /// _trackpad-rc._tcp and _trackpad-rc._udp
    static let serviceType = "trackpad-rc"
}
