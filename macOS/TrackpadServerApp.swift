//
//  TrackpadServerApp.swift
//  TrackpadServer (macOS)
//
//  Menu bar app. Advertises over MultipeerConnectivity and injects
//  received input as CGEvents.
//
//  IMPORTANT project settings:
//    - Signing & Capabilities: REMOVE App Sandbox (CGEventPost is not
//      allowed in sandboxed apps -> no Mac App Store; distribute with
//      Developer ID + notarization)
//    - Info.plist: NSLocalNetworkUsageDescription + NSBonjourServices
//      (_trackpad-rc._tcp, _trackpad-rc._udp)
//    - LSUIElement = YES (menu bar only, no Dock icon)
//

import SwiftUI

@main
struct TrackpadServerApp: App {
    @StateObject private var server = ServerManager()

    var body: some Scene {
        MenuBarExtra {
            switch server.state {
            case .connected(let name):
                Text("Connected: \(name)")
                Button("Disconnect") { server.disconnect() }
            case .waiting:
                Text("Waiting for iPhone…")
            }

            Divider()

            if !server.hasAccessibilityPermission {
                Button("Grant Accessibility Permission…") {
                    server.promptForAccessibility()
                }
            }

            Button("Quit") { NSApplication.shared.terminate(nil) }
                .keyboardShortcut("q")
        } label: {
            Image(systemName: server.isConnected
                  ? "rectangle.and.hand.point.up.left.fill"
                  : "rectangle.and.hand.point.up.left")
        }
    }
}
