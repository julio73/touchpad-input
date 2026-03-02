import AppKit
import SwiftUI

#if canImport(SwiftUI)
@available(macOS 11.0, *)
@main
struct TouchpadInputMVPApp: App {
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
#endif
