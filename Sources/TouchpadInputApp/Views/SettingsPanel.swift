import SwiftUI
import TouchpadInputCore

struct SettingsPanel: View {
    @ObservedObject var session: TouchInputSession
    var onRecalibrate: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Stability Settings")
                .font(.headline)
            settingRow(label: "Pressure floor",
                       value: String(format: "%.2f", session.pressureFloor)) {
                Slider(value: $session.pressureFloor, in: 0.05...0.50, step: 0.05)
            }
            settingRow(label: "Min contact size",
                       value: String(format: "%.2f", session.minContactSize)) {
                Slider(value: $session.minContactSize, in: 0.0...1.0, step: 0.05)
            }
            settingRow(label: "Zone cooldown",
                       value: "\(Int(session.zoneCooldownMs))ms") {
                Slider(value: $session.zoneCooldownMs, in: 0...300, step: 20)
            }
            HStack(spacing: 8) {
                Button("Recalibrate layout…") { onRecalibrate() }
                    .buttonStyle(.bordered)
                Button("Reset to default grid") { session.resetCalibration() }
                    .buttonStyle(.bordered)
                    .foregroundColor(.red)
            }
            .padding(.top, 4)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(NSColor.controlBackgroundColor))
    }

    @ViewBuilder
    private func settingRow<S: View>(label: String, value: String, @ViewBuilder slider: () -> S) -> some View {
        HStack(spacing: 10) {
            Text(label)
                .frame(width: 140, alignment: .leading)
                .font(.system(size: 12))
            slider()
            Text(value)
                .frame(width: 44, alignment: .trailing)
                .font(.system(size: 12, design: .monospaced))
        }
    }
}
