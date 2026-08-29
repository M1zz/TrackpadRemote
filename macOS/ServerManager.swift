//
//  ServerManager.swift
//  TrackpadServer (macOS)
//
//  Advertises the service, accepts an invitation from exactly one iPhone,
//  decodes InputPackets, and forwards them to EventInjector.
//

import Foundation
import MultipeerConnectivity
import AppKit
import os

@MainActor
final class ServerManager: NSObject, ObservableObject {

    enum State: Equatable {
        case waiting
        case connected(String)
    }

    @Published var state: State = .waiting
    @Published var hasAccessibilityPermission = false

    var isConnected: Bool {
        if case .connected = state { return true }
        return false
    }

    private let peerID = MCPeerID(displayName: Host.current().localizedName ?? "Mac")
    private var session: MCSession!
    private var advertiser: MCNearbyServiceAdvertiser!
    private let injector = EventInjector()

    /// The single iPhone this Mac is bound to. Claimed the instant an invitation
    /// is accepted — not when the session reports `.connected` — so two phones
    /// inviting at the same moment can't both be let in and fight over the cursor.
    private var boundPeer: MCPeerID? {
        didSet {
            let peer = boundPeer
            acceptedPeer.withLock { $0 = peer }
        }
    }

    /// Mirror of `boundPeer` readable from the (nonisolated) data callback, which
    /// runs on MultipeerConnectivity's queue and must not hop to the main actor —
    /// a per-packet actor hop would add latency and reorder cursor deltas.
    private let acceptedPeer = OSAllocatedUnfairLock<MCPeerID?>(initialState: nil)

    /// Releases `boundPeer` if an accepted phone never finishes the handshake.
    private var handshakeTimeout: Task<Void, Never>?

    private let handshakeTimeoutInterval: TimeInterval = 15

    override init() {
        super.init()

        session = MCSession(peer: peerID,
                            securityIdentity: nil,
                            encryptionPreference: .required)
        session.delegate = self

        advertiser = MCNearbyServiceAdvertiser(peer: peerID,
                                               discoveryInfo: nil,
                                               serviceType: ServiceConfig.serviceType)
        advertiser.delegate = self
        advertiser.startAdvertisingPeer()

        hasAccessibilityPermission = EventInjector.checkPermission(prompt: false)
        // Prompt once on first launch if missing
        if !hasAccessibilityPermission {
            promptForAccessibility()
        }
    }

    func promptForAccessibility() {
        hasAccessibilityPermission = EventInjector.checkPermission(prompt: true)
    }

    func disconnect() {
        session.disconnect()
        releaseBinding()
    }

    private func releaseBinding() {
        handshakeTimeout?.cancel()
        handshakeTimeout = nil
        boundPeer = nil
        state = .waiting
        advertiser.startAdvertisingPeer()
    }
}

// MARK: - MCNearbyServiceAdvertiserDelegate

extension ServerManager: MCNearbyServiceAdvertiserDelegate {

    nonisolated func advertiser(_ advertiser: MCNearbyServiceAdvertiser,
                                didReceiveInvitationFromPeer peerID: MCPeerID,
                                withContext context: Data?,
                                invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        Task { @MainActor in
            // One phone at a time. A second phone is turned away rather than
            // silently added to the session.
            guard self.boundPeer == nil || self.boundPeer == peerID else {
                invitationHandler(false, nil)
                return
            }

            // Local network, encrypted session — accept.
            // (If you want pairing confirmation, show an NSAlert here instead.)
            self.boundPeer = peerID
            self.advertiser.stopAdvertisingPeer()
            invitationHandler(true, self.session)

            self.handshakeTimeout?.cancel()
            self.handshakeTimeout = Task { [interval = self.handshakeTimeoutInterval] in
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                guard !Task.isCancelled else { return }
                // Accepted but never connected — free the slot for another phone.
                if case .waiting = self.state { self.releaseBinding() }
            }
        }
    }
}

// MARK: - MCSessionDelegate

extension ServerManager: MCSessionDelegate {

    nonisolated func session(_ session: MCSession,
                             peer peerID: MCPeerID,
                             didChange state: MCSessionState) {
        Task { @MainActor in
            switch state {
            case .connected:
                guard peerID == self.boundPeer else {
                    // Not the phone we accepted — refuse to take its input.
                    self.session.cancelConnectPeer(peerID)
                    return
                }
                self.handshakeTimeout?.cancel()
                self.handshakeTimeout = nil
                self.state = .connected(peerID.displayName)
                self.advertiser.stopAdvertisingPeer()
                // Refresh permission state — user may have granted it by now
                self.hasAccessibilityPermission = EventInjector.checkPermission(prompt: false)

            case .notConnected:
                guard peerID == self.boundPeer else { return }
                self.releaseBinding()

            case .connecting:
                break

            @unknown default:
                break
            }
        }
    }

    nonisolated func session(_ session: MCSession, didReceive data: Data,
                             fromPeer peerID: MCPeerID) {
        // Only the bound phone may move this Mac's cursor.
        guard acceptedPeer.withLock({ $0 == peerID }) else { return }
        guard let packet = InputPacket(data: data) else { return }
        // CGEvent posting is thread-safe; keep it off the main thread entirely.
        injector.handle(packet)
    }

    nonisolated func session(_ session: MCSession, didReceive stream: InputStream,
                             withName streamName: String, fromPeer peerID: MCPeerID) {}
    nonisolated func session(_ session: MCSession,
                             didStartReceivingResourceWithName resourceName: String,
                             fromPeer peerID: MCPeerID, with progress: Progress) {}
    nonisolated func session(_ session: MCSession,
                             didFinishReceivingResourceWithName resourceName: String,
                             fromPeer peerID: MCPeerID, at localURL: URL?,
                             withError error: Error?) {}
}
