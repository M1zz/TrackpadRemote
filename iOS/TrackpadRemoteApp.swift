//
//  TrackpadRemoteApp.swift
//  TrackpadRemote (iOS)
//

import SwiftUI

@main
struct TrackpadRemoteApp: App {
    @StateObject private var connection = ConnectionManager()
    @StateObject private var settings = PadSettings()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(connection)
                .environmentObject(settings)
                .preferredColorScheme(.dark)
        }
    }
}
