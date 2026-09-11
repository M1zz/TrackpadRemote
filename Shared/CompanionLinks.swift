//
//  CompanionLinks.swift
//  Shared
//
//  TrackpadRemote is two apps — the iPhone pad and the Mac server — and
//  neither does anything on its own. Each one sends people to the other half
//  through the same page.
//

import Foundation

enum CompanionLinks {
    /// Download page for both apps (`docs/index.html`, served by GitHub Pages).
    /// Deliberately not a store URL: the Mac server can never be on the Mac App
    /// Store (no sandbox), and the iPhone app's App Store link can change on the
    /// page without shipping a new build of either app.
    static let downloadPage = URL(string: "https://m1zz.github.io/TrackpadRemote/")!
}
