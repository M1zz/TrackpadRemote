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

private let serverLog = Logger(subsystem: "com.hyunholee.TrackpadServer", category: "server")

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
    // Reached from the nonisolated packet callback, which must not hop to the
    // main actor for every cursor delta.
    private nonisolated let injector = EventInjector()

    /// Size of the rect the phone's pad maps onto, in points.
    private var desktopSize: CGSize = .zero

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

    /// Accessibility can be revoked at any time — and every rebuild of an
    /// unsigned binary silently drops the grant — so the state is polled rather
    /// than sampled once at launch. Without it the app just stops moving the
    /// cursor and says nothing.
    private var permissionPoll: Task<Void, Never>?

    private var hasPromptedThisRun = false

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
        serverLog.info("advertising as \(self.peerID.displayName, privacy: .public) on \(ServiceConfig.serviceType, privacy: .public)")

        desktopSize = injector.refreshScreenLayout().size

        // Rearranging displays changes the rect the pad maps onto, so the phone
        // has to be told to re-letterbox its surface.
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.desktopSize = self.injector.refreshScreenLayout().size
                self.sendScreenInfo()
            }
        }

        // Deliberately no prompt here. The server sits in the menu bar doing
        // nothing until a phone shows up, so asking at launch interrupts the user
        // for a permission that is not needed yet.
        hasAccessibilityPermission = EventInjector.checkPermission(prompt: false)
        serverLog.info("accessibility at launch: \(self.hasAccessibilityPermission, privacy: .public)")
        startPermissionPolling()
    }

    private func startPermissionPolling() {
        permissionPoll = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                guard let self else { return }
                let trusted = EventInjector.checkPermission(prompt: false)
                guard trusted != self.hasAccessibilityPermission else { continue }
                self.hasAccessibilityPermission = trusted
                serverLog.info("accessibility changed to \(trusted, privacy: .public)")
            }
        }
    }

    /// Tells the phone how big the desktop is, so it can match its aspect ratio.
    private func sendScreenInfo() {
        guard !session.connectedPeers.isEmpty,
              desktopSize.width > 0, desktopSize.height > 0 else {
            serverLog.error("screenInfo not sent: peers=\(self.session.connectedPeers.count, privacy: .public) size=\(self.desktopSize.debugDescription, privacy: .public)")
            return
        }
        serverLog.info("sending screenInfo \(self.desktopSize.debugDescription, privacy: .public)")
        let packet = InputPacket(type: .screenInfo,
                                 a: Float(desktopSize.width),
                                 b: Float(desktopSize.height))
        try? session.send(packet.encoded(),
                          toPeers: session.connectedPeers,
                          with: .reliable)
    }

    func promptForAccessibility() {
        hasAccessibilityPermission = EventInjector.checkPermission(prompt: true)
    }

    /// Asks only at the moment input would actually be dropped — a phone has
    /// connected and is about to send events — and only once per run, so
    /// dismissing it doesn't turn into a loop.
    private func promptForAccessibilityIfNeeded() {
        guard !hasAccessibilityPermission, !hasPromptedThisRun else { return }
        hasPromptedThisRun = true
        serverLog.info("prompting for accessibility: a phone connected without it")
        promptForAccessibility()
    }

    /// The system prompt only appears once per binary; this always works.
    func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
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
                serverLog.info("rejected \(peerID.displayName, privacy: .public): already bound")
                invitationHandler(false, nil)
                return
            }

            // Local network, encrypted session — accept.
            // (If you want pairing confirmation, show an NSAlert here instead.)
            serverLog.info("accepted invitation from \(peerID.displayName, privacy: .public)")
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
                serverLog.info("connected to \(peerID.displayName, privacy: .public)")
                self.state = .connected(peerID.displayName)
                self.advertiser.stopAdvertisingPeer()
                self.sendScreenInfo()
                // Refresh permission state — user may have granted it by now
                self.hasAccessibilityPermission = EventInjector.checkPermission(prompt: false)
                // Now it is genuinely needed: input is about to arrive.
                self.promptForAccessibilityIfNeeded()

            case .notConnected:
                serverLog.info("disconnected from \(peerID.displayName, privacy: .public)")
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
        guard acceptedPeer.withLock({ $0 == peerID }) else {
            serverLog.error("packet dropped: \(peerID.displayName, privacy: .public) is not the bound peer")
            return
        }
        guard let packet = InputPacket(data: data) else {
            serverLog.error("undecodable packet, \(data.count, privacy: .public) bytes")
            return
        }
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
