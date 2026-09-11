//
//  CompanionWindow.swift
//  TrackpadServer (macOS)
//
//  The server does nothing without the iPhone app, and as a menu bar app it
//  has no window in which to say so. This is that window: a QR code the
//  iPhone's camera opens straight into the download page.
//

import AppKit
import CoreImage.CIFilterBuiltins
import SwiftUI

@MainActor
enum CompanionWindow {
    private static var window: NSWindow?

    static func show() {
        if window == nil {
            let hosting = NSHostingView(rootView: CompanionView())
            let newWindow = NSWindow(contentRect: NSRect(origin: .zero, size: hosting.fittingSize),
                                     styleMask: [.titled, .closable],
                                     backing: .buffered,
                                     defer: false)
            newWindow.title = "Get the iPhone App"
            newWindow.contentView = hosting
            newWindow.isReleasedWhenClosed = false
            newWindow.center()
            window = newWindow
        }
        // A menu bar app is never frontmost by itself; without this the window
        // opens behind whatever the user is doing and looks like nothing happened.
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}

struct CompanionView: View {
    private let link = CompanionLinks.downloadPage

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "laptopcomputer.and.iphone")
                .font(.system(size: 34))
                .foregroundStyle(.tint)

            VStack(spacing: 6) {
                Text("TrackpadRemote is two apps")
                    .font(.title2.bold())
                Text("This Mac app moves the cursor. The trackpad itself is the "
                     + "TrackpadRemote app on your iPhone — install it, then keep "
                     + "both devices on Wi-Fi with Bluetooth on.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let qrCode = Self.qrCode(for: link) {
                Image(nsImage: qrCode)
                    .interpolation(.none)   // modules must stay hard-edged to scan
                    .resizable()
                    .frame(width: 176, height: 176)
                    .padding(12)
                    .background(.white, in: RoundedRectangle(cornerRadius: 12))
            }

            Text("Scan with your iPhone's camera")
                .font(.callout)
                .foregroundStyle(.secondary)

            HStack {
                Button("Copy Link") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(link.absoluteString, forType: .string)
                }
                Button("Open in Browser") {
                    NSWorkspace.shared.open(link)
                }
            }
        }
        .padding(28)
        .frame(width: 380)
    }

    /// One pixel per module; the view scales it up without smoothing.
    private static func qrCode(for url: URL) -> NSImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(url.absoluteString.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage,
              let cgImage = CIContext().createCGImage(output, from: output.extent) else {
            return nil
        }
        return NSImage(cgImage: cgImage, size: output.extent.size)
    }
}
