//
//  ContentView.swift
//  TrackpadRemote (iOS)
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject var connection: ConnectionManager


    var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()

            switch connection.state {
            case .connected(let macName):
                trackpadSurface(macName: macName)
            case .connecting(let macName):
                statusView(icon: "wifi", title: "Connecting to \(macName)…", spinning: true)
            case .searching:
                searchingView
            }
        }
        // Keep the screen awake while acting as a trackpad
        .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
    }

    // MARK: - Trackpad

    private func trackpadSurface(macName: String) -> some View {
        VStack(spacing: 0) {
            HStack {
                Label(macName, systemImage: "laptopcomputer")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Disconnect") { connection.disconnect() }
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal)
            .padding(.top, 2)

            // Letterboxed to the Mac's aspect ratio: the pad is a scale model of
            // the desktop, so it must not be stretched to fill the phone.
            TrackpadView { packet in
                connection.send(packet)
            }
            .aspectRatio(connection.desktopAspect, contentMode: .fit)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color(.secondarySystemBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .strokeBorder(Color.accentColor.opacity(0.35), lineWidth: 1)
            )
            .overlay(alignment: .top) { topMarker }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(8)
        }
    }

    /// Orientation cue. The phone lies face-up on a desk with no visual cursor
    /// feedback of its own, so the surface has to say which edge is "up".
    private var topMarker: some View {
        VStack(spacing: 3) {
            Image(systemName: "chevron.up")
                .font(.system(size: 9, weight: .bold))
            Text("TOP")
                .font(.system(size: 10, weight: .semibold))
                .kerning(2.5)
        }
        .foregroundStyle(.tertiary)
        .padding(.top, 8)
        // Never swallow a touch meant for the pad
        .allowsHitTesting(false)
    }

    // MARK: - Status screens

    private var searchingView: some View {
        ScrollView {
            VStack(spacing: 16) {
                statusView(icon: "magnifyingglass", title: "Looking for your Mac…", spinning: true)

                if !connection.discoveredMacs.isEmpty {
                    VStack(spacing: 12) {
                        ForEach(connection.discoveredMacs, id: \.self) { mac in
                            Button {
                                connection.invite(mac)
                            } label: {
                                Label(mac.displayName, systemImage: "laptopcomputer")
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(Color(.secondarySystemBackground))
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .frame(maxWidth: 420)
                    .padding(.horizontal, 32)
                }

                Text("Make sure TrackpadServer is running on your Mac\nand both devices have Wi-Fi & Bluetooth on.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
        }
    }

    private func statusView(icon: String, title: String, spinning: Bool) -> some View {
        VStack(spacing: 16) {
            if spinning {
                ProgressView().controlSize(.large)
            } else {
                Image(systemName: icon).font(.largeTitle)
            }
            Text(title).font(.headline)
        }
    }
}
