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

    /// The icon has to distinguish "no phone yet" from "phone connected but I am
    /// not allowed to move the cursor" — they look identical otherwise.
    private var menuBarSymbol: String {
        guard server.hasAccessibilityPermission else {
            return "exclamationmark.triangle.fill"
        }
        return server.isConnected
            ? "rectangle.and.hand.point.up.left.fill"
            : "rectangle.and.hand.point.up.left"
    }

    var body: some Scene {
        MenuBarExtra {
            // Missing permission is the failure that looks like nothing at all:
            // the phone connects, packets arrive, CGEventPost is refused and the
            // cursor sits still. Say so before anything else.
            if !server.hasAccessibilityPermission {
                Text("⚠︎ No Accessibility permission — input is being ignored")
                Button("Grant Accessibility Permission…") {
                    server.promptForAccessibility()
                }
                Button("Open Accessibility Settings…") {
                    server.openAccessibilitySettings()
                }
                Divider()
            }

            switch server.state {
            case .connected(let name):
                Text("Connected: \(name)")
                Button("Disconnect") { server.disconnect() }
            case .waiting:
                Text("Waiting for iPhone…")
            }

            Divider()

            Button("Quit") { NSApplication.shared.terminate(nil) }
                .keyboardShortcut("q")
        } label: {
            Image(systemName: menuBarSymbol)
        }
    }
}
