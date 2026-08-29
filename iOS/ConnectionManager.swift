//
//  ConnectionManager.swift
//  TrackpadRemote (iOS)
//
//  Browses for the Mac (which advertises), connects to exactly one of them,
//  and sends InputPackets. Move/scroll go unreliable, clicks reliable.
//

import Foundation
import MultipeerConnectivity
import UIKit

@MainActor
final class ConnectionManager: NSObject, ObservableObject {

    enum State: Equatable {
        case searching
        case connecting(String)
        case connected(String)
    }

    @Published var state: State = .searching
    @Published var discoveredMacs: [MCPeerID] = []

    /// Desktop width / height, reported by the Mac. The pad is letterboxed to
    /// this so the 1:1 map isn't stretched. Defaults to 16:10 until the Mac says.
    @Published var desktopAspect: CGFloat = 1.6

    private let peerID = MCPeerID(displayName: UIDevice.current.name)
    // `send(_:)` is nonisolated so touch events can be forwarded without a main-actor hop.
    // MCSession is internally thread-safe, so unchecked access is fine here.
    private nonisolated(unsafe) var session: MCSession!
    private var browser: MCNearbyServiceBrowser!

    /// The single Mac this phone is bound to. Non-nil from the moment we invite
    /// a peer until it disconnects — a trackpad driving two Macs at once would
    /// send every delta to both, so only one pairing is ever allowed.
    private var boundPeer: MCPeerID?

    /// An invite that is never answered would otherwise pin `boundPeer` forever.
    private var inviteTimeout: Task<Void, Never>?

    private let invitationTimeout: TimeInterval = 15

    override init() {
        super.init()
        session = MCSession(peer: peerID,
                            securityIdentity: nil,
                            encryptionPreference: .required)
        session.delegate = self

        browser = MCNearbyServiceBrowser(peer: peerID,
                                         serviceType: ServiceConfig.serviceType)
        browser.delegate = self
        browser.startBrowsingForPeers()
    }

    func invite(_ mac: MCPeerID) {
        // Already bound (or mid-handshake) — ignore. Tapping a second Mac in the
        // list must not stack a second invitation on top of a live one.
        guard boundPeer == nil else { return }

        boundPeer = mac
        state = .connecting(mac.displayName)
        browser.stopBrowsingForPeers()
        browser.invitePeer(mac, to: session,
                           withContext: nil, timeout: invitationTimeout)

        inviteTimeout = Task { [invitationTimeout] in
            try? await Task.sleep(nanoseconds: UInt64(invitationTimeout * 1_000_000_000))
            guard !Task.isCancelled else { return }
            // Handshake never completed — release the binding and look again.
            if case .connecting = self.state { self.resetToSearching() }
        }
    }

    func disconnect() {
        session.disconnect()
        resetToSearching()
    }

    private func resetToSearching() {
        inviteTimeout?.cancel()
        inviteTimeout = nil
        boundPeer = nil
        state = .searching
        discoveredMacs.removeAll()
        browser.startBrowsingForPeers()
    }

    // MARK: - Sending

    nonisolated func send(_ packet: InputPacket) {
        let reliable: Bool
        switch packet.type {
        case .moveRelative, .scroll:
            reliable = false   // lossy is fine; the next position supersedes
        case .leftClick, .rightClick, .dragBegin, .dragEnd, .screenInfo:
            reliable = true    // must never be dropped
        }

        guard !session.connectedPeers.isEmpty else { return }
        try? session.send(packet.encoded(),
                          toPeers: session.connectedPeers,
                          with: reliable ? .reliable : .unreliable)
    }
}

// MARK: - MCSessionDelegate

extension ConnectionManager: MCSessionDelegate {

    nonisolated func session(_ session: MCSession,
                             peer peerID: MCPeerID,
                             didChange state: MCSessionState) {
        Task { @MainActor in
            switch state {
            case .connected:
                guard peerID == self.boundPeer else {
                    // A Mac we never invited (or a stale one) got in — drop it.
                    self.session.cancelConnectPeer(peerID)
                    return
                }
                self.inviteTimeout?.cancel()
                self.inviteTimeout = nil
                self.state = .connected(peerID.displayName)
                self.browser.stopBrowsingForPeers()
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()

            case .connecting:
                guard peerID == self.boundPeer else { return }
                self.state = .connecting(peerID.displayName)

            case .notConnected:
                guard peerID == self.boundPeer else { return }
                self.resetToSearching()

            @unknown default:
                break
            }
        }
    }

    nonisolated func session(_ session: MCSession, didReceive data: Data,
                             fromPeer peerID: MCPeerID) {
        guard let packet = InputPacket(data: data),
              packet.type == .screenInfo,
              packet.a > 0, packet.b > 0 else { return }
        let aspect = CGFloat(packet.a) / CGFloat(packet.b)
        Task { @MainActor in
            guard peerID == self.boundPeer else { return }
            self.desktopAspect = aspect
        }
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

// MARK: - MCNearbyServiceBrowserDelegate

extension ConnectionManager: MCNearbyServiceBrowserDelegate {

    nonisolated func browser(_ browser: MCNearbyServiceBrowser,
                             foundPeer peerID: MCPeerID,
                             withDiscoveryInfo info: [String: String]?) {
        Task { @MainActor in
            guard self.boundPeer == nil else { return }
            guard !self.discoveredMacs.contains(peerID) else { return }
            self.discoveredMacs.append(peerID)
            // Auto-connect if it's the only Mac around
            if self.discoveredMacs.count == 1, case .searching = self.state {
                self.invite(peerID)
            }
        }
    }

    nonisolated func browser(_ browser: MCNearbyServiceBrowser,
                             lostPeer peerID: MCPeerID) {
        Task { @MainActor in
            self.discoveredMacs.removeAll { $0 == peerID }
        }
    }
}
