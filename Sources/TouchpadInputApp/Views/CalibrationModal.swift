import SwiftUI
import TouchpadInputCore

struct CalibrationModal: View {
    @ObservedObject var session: CalibrationSession
    let diagnosticSession: TouchInputSession
    let onComplete: (UserCalibration) -> Void
    let onSkip: () -> Void

    @State private var isStarted = false

    var body: some View {
        VStack(spacing: 24) {
            Text("Welcome to Touchpad Input")
                .font(.title2).fontWeight(.semibold)

            Text("Type this sentence at your natural pace.\nWe'll learn where your keys are.")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)

            Text("\"\(CalibrationSession.sentence)\"")
                .font(.system(size: 15, design: .monospaced))
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            if !isStarted {
                Button("Start Calibration") {
                    isStarted = true
                    diagnosticSession.activeCalibrationSession = session
                    MultitouchCapture.shared.start(session: diagnosticSession)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            } else {
                if let target = session.currentTarget {
                    HStack(spacing: 12) {
                        Text("Next key:")
                            .foregroundColor(.secondary)
                        Text(String(target).uppercased())
                            .font(.system(size: 32, weight: .bold, design: .monospaced))
                            .frame(width: 56, height: 56)
                            .background(Color.accentColor.opacity(0.15),
                                        in: RoundedRectangle(cornerRadius: 10))
                    }
                } else {
                    Text("All done!")
                        .font(.title3)
                        .foregroundColor(.green)
                }

                VStack(spacing: 6) {
                    ProgressView(value: session.progress)
                        .progressViewStyle(.linear)
                        .frame(width: 300)
                    Text("\(session.currentIndex) / \(session.targets.count)")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
            }

            Button("Skip") { onSkip() }
                .buttonStyle(.bordered)
        }
        .padding(40)
        .frame(width: 440)
        .onDisappear {
            diagnosticSession.activeCalibrationSession = nil
        }
        .onChange(of: session.isComplete) { complete in
            if complete { onComplete(session.buildCalibration()) }
        }
    }
}
