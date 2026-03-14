import SwiftUI
import TouchpadInputCore

private enum AppMode: String, CaseIterable {
    case keyboard = "Keyboard"
    case drawing  = "Drawing"
}

struct ContentView: View {
    @StateObject private var session = TouchInputSession()
    @StateObject private var drawSession = DrawingSession()
    @StateObject private var calibSession = CalibrationSession()
    @State private var appMode: AppMode = .keyboard
    @State private var showSettings = false
    @State private var showCalibration = false
    @AppStorage("hasCompletedCalibration") private var hasCompletedCalibration = false

    var body: some View {
        VStack(spacing: 0) {
            header
            if appMode == .keyboard {
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
                HStack(spacing: 0) {
                    TrackpadSurface(
                        fingers: session.liveFingers,
                        isActive: session.isActive,
                        zones: KeyGrid.default.zones,
                        activeModifiers: session.activeModifiers
                    )
                        .padding(16)
                    Divider()
                    OutputBufferPanel(text: session.outputBuffer, activeModifiers: session.activeModifiers)
                    Divider()
                    EventLogPanel(entries: session.eventLog)
                }
            } else {
                DrawingCanvasView(session: drawSession)
            }
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
            Divider().frame(height: 18)
            Picker("Mode", selection: $appMode) {
                ForEach(AppMode.allCases, id: \.self) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 160)
            .onChange(of: appMode) { mode in
                let activeSession: any TouchEventReceiver = mode == .keyboard ? session : drawSession
                MultitouchCapture.shared.session = activeSession
            }
            Spacer()
            if appMode == .keyboard {
                Button(action: { showSettings.toggle() }) {
                    Image(systemName: "slider.horizontal.3")
                        .foregroundColor(showSettings ? .accentColor : .secondary)
                }
                .buttonStyle(.borderless)
                .help("Toggle stability settings")
                Button("Clear") { session.clearAll() }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var modePill: some View {
        let isActive = appMode == .keyboard ? session.isActive : drawSession.isActive
        return Group {
            if isActive {
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
