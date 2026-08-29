//
//  TrackpadRemoteApp.swift
//  TrackpadRemote (iOS)
//

import SwiftUI

@main
struct TrackpadRemoteApp: App {
    @StateObject private var connection = ConnectionManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(connection)
                .preferredColorScheme(.dark)
        }
    }
}
