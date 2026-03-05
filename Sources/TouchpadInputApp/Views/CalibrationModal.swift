import SwiftUI
import TouchpadInputCore

struct CalibrationModal: View {
    @ObservedObject var session: CalibrationSession
    let diagnosticSession: TouchInputSession
    let onComplete: (UserCalibration) -> Void
    let onSkip: () -> Void

    @State private var isStarted = false

    var body: some View {
        VStack(spacing: 20) {
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

                // Live tap-dot visualization — shows where taps actually landed
                CalibrationSurface(session: session)
                    .frame(height: 180)
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                VStack(spacing: 6) {
                    ProgressView(value: session.progress)
                        .progressViewStyle(.linear)
                        .frame(width: 360)
                    Text("\(session.currentIndex) / \(session.targets.count)")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
            }

            Button("Skip") { onSkip() }
                .buttonStyle(.bordered)
        }
        .padding(40)
        .frame(width: 460)
        .onDisappear {
            diagnosticSession.activeCalibrationSession = nil
        }
        .onChange(of: session.isComplete) { complete in
            if complete { onComplete(session.buildCalibration()) }
        }
    }
}

// MARK: - CalibrationSurface

/// Mini trackpad that renders the key grid, highlights the current target zone,
/// and draws a dot for every tap already recorded during calibration.
private struct CalibrationSurface: View {
    @ObservedObject var session: CalibrationSession

    private let gridZones = KeyGrid.default.zones.filter { $0.character != " " }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(NSColor.windowBackgroundColor))
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.secondary.opacity(0.25), lineWidth: 1)

                // Key zone cells
                ForEach(gridZones, id: \.character) { zone in
                    zoneCell(zone: zone, geo: geo)
                }

                // Recorded tap dots (most recent in green)
                ForEach(Array(session.samples.enumerated()), id: \.offset) { idx, sample in
                    let isRecent = idx == session.samples.count - 1
                    Circle()
                        .fill(isRecent ? Color.green.opacity(0.9) : Color.blue.opacity(0.55))
                        .frame(width: isRecent ? 8 : 5, height: isRecent ? 8 : 5)
                        .position(
                            x: CGFloat(sample.x) * geo.size.width,
                            y: (1.0 - CGFloat(sample.y)) * geo.size.height
                        )
                }
            }
        }
    }

    @ViewBuilder
    private func zoneCell(zone: KeyZone, geo: GeometryProxy) -> some View {
        let isTarget = zone.character == session.currentTarget
        let w = CGFloat(zone.xMax - zone.xMin) * geo.size.width
        let h = CGFloat(zone.yMax - zone.yMin) * geo.size.height
        let cx = CGFloat(zone.xMin + zone.xMax) / 2 * geo.size.width
        let cy = (1.0 - CGFloat(zone.yMin + zone.yMax) / 2) * geo.size.height

        ZStack {
            RoundedRectangle(cornerRadius: 2)
                .fill(isTarget ? Color.accentColor.opacity(0.25) : Color.secondary.opacity(0.06))
            RoundedRectangle(cornerRadius: 2)
                .stroke(
                    isTarget ? Color.accentColor.opacity(0.85) : Color.secondary.opacity(0.2),
                    lineWidth: isTarget ? 1.5 : 0.5
                )
            Text(String(zone.character).uppercased())
                .font(.system(size: max(7, geo.size.width * 0.02),
                              weight: isTarget ? .bold : .regular))
                .foregroundColor(isTarget ? .accentColor : .secondary.opacity(0.7))
        }
        .frame(width: w, height: h)
        .position(x: cx, y: cy)
    }
}
