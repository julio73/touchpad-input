import SwiftUI
import TouchpadInputCore

struct ContentView: View {
    @StateObject private var session = TouchInputSession()
    @StateObject private var calibSession = CalibrationSession()
    @State private var showSettings = false
    @State private var showCalibration = false
    @AppStorage("hasCompletedCalibration") private var hasCompletedCalibration = false

    var body: some View {
        VStack(spacing: 0) {
            header
            if showSettings {
                Divider()
                SettingsPanel(session: session, onRecalibrate: {
                    calibSession.reset()
                    showCalibration = true
                })
            }
            if !session.completions.isEmpty {
                Divider()
                AutocompleteBar(completions: session.completions) { word in
                    session.acceptCompletion(word)
                }
            }
            Divider()
            HStack(spacing: 0) {
                TrackpadSurface(
                    fingers: session.liveFingers,
                    isActive: session.isActive,
                    zones: KeyGrid.default.zones,
                    activeModifiers: session.activeModifiers
                )
                    .padding(16)
                Divider()
                FingerTablePanel(fingers: session.liveFingers)
                    .frame(width: 340)
            }
            Divider()
            OutputBufferPanel(text: session.outputBuffer, activeModifiers: session.activeModifiers)
            Divider()
            EventLogPanel(entries: session.eventLog)
        }
        .onAppear {
            MultitouchCapture.shared.setupDoubleControlToggle(for: session)
            if !hasCompletedCalibration { showCalibration = true }
        }
        .onDisappear { MultitouchCapture.shared.teardownDoubleControlToggle() }
        .sheet(isPresented: $showCalibration) {
            CalibrationModal(
                session: calibSession,
                diagnosticSession: session,
                onComplete: { cal in
                    session.applyCalibration(cal)
                    hasCompletedCalibration = true
                    showCalibration = false
                },
                onSkip: {
                    hasCompletedCalibration = true
                    showCalibration = false
                }
            )
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Text("Touchpad Diagnostics")
                .font(.system(size: 18, weight: .semibold))
            modePill
            Spacer()
            Button(action: { showSettings.toggle() }) {
                Image(systemName: "slider.horizontal.3")
                    .foregroundColor(showSettings ? .accentColor : .secondary)
            }
            .buttonStyle(.borderless)
            .help("Toggle stability settings")
            Button("Clear") { session.clearAll() }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var modePill: some View {
        Group {
            if session.isActive {
                Text("● CAPTURING  —  double ctrl to stop")
                    .foregroundColor(.white)
                    .background(Color.green)
            } else {
                Text("○ OFF  —  double ctrl to start")
                    .foregroundColor(.secondary)
                    .background(Color.secondary.opacity(0.12))
            }
        }
        .font(.system(size: 11, weight: .medium, design: .monospaced))
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}
