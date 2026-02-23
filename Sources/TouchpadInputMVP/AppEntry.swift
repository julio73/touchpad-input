import AppKit
import SwiftUI

#if canImport(SwiftUI)
@available(macOS 11.0, *)
@main
struct TouchpadInputMVPApp: App {
    var body: some Scene {
        WindowGroup("Touchpad Input MVP") {
            ContentView()
                .frame(minWidth: 900, minHeight: 560)
                .onAppear {
                    NSApplication.shared.activate(ignoringOtherApps: true)
                }
        }
    }
}
#endif
