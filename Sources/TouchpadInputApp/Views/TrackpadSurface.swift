import SwiftUI
import TouchpadInputCore

struct TrackpadSurface: View {
    let fingers: [FingerState]
    let isActive: Bool
    var activeModifiers: Set<AnyModifierKind> = []

    var body: some View {
        GeometryReader { geo in
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(NSColor.controlBackgroundColor))
                RoundedRectangle(cornerRadius: 12)
                    .stroke(
                        isActive ? Color.green.opacity(0.4) : Color.secondary.opacity(0.25),
                        lineWidth: isActive ? 1.5 : 1
                    )

                KeyGridOverlay(activeModifiers: activeModifiers)

                if !isActive {
                    Text("Double-tap ctrl to start")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                        .padding(8)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
                }

                ForEach(fingers) { finger in
                    let x = finger.x * geo.size.width
                    let y = (1.0 - finger.y) * geo.size.height
                    ZStack {
                        Circle()
                            .fill(dotColor(finger.phase).opacity(0.75))
                            .frame(width: 38, height: 38)
                        Text(finger.label)
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundColor(.white)
                    }
                    .position(x: x, y: y)
                }
            }
        }
    }

    private func dotColor(_ phase: String) -> Color {
        switch phase {
        case "began": return .green
        case "ended": return .red
        default:      return .blue
        }
    }
}
