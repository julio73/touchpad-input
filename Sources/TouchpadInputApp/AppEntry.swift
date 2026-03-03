import AppKit
import SwiftUI
import TouchpadInputCore

@available(macOS 11.0, *)
@main
struct TouchpadInputApp: App {
    var body: some Scene {
        WindowGroup("Touchpad Diagnostics") {
            ContentView()
                .frame(minWidth: 960, minHeight: 620)
                .onAppear {
                    NSApplication.shared.activate(ignoringOtherApps: true)
                }
        }
    }
}
