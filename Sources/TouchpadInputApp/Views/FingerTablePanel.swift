import SwiftUI
import TouchpadInputCore

struct FingerTablePanel: View {
    let fingers: [FingerState]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Live Fingers")
                .font(.headline)
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 10)

            columnHeaders
            Divider()
            fingerRows
            Spacer()
        }
    }

    private var columnHeaders: some View {
        HStack(spacing: 0) {
            Text("ID")   .frame(width: 36,  alignment: .leading)
            Text("X")    .frame(width: 88,  alignment: .trailing)
            Text("Y")    .frame(width: 88,  alignment: .trailing)
            Text("P")    .frame(width: 52,  alignment: .trailing)
            Text("Phase").frame(width: 72,  alignment: .leading).padding(.leading, 12)
        }
        .font(.system(size: 11, weight: .semibold, design: .monospaced))
        .foregroundColor(.secondary)
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private var fingerRows: some View {
        if fingers.isEmpty {
            Text("— no active touches")
                .font(.system(size: 13, design: .monospaced))
                .foregroundColor(.secondary)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
        } else {
            ForEach(fingers) { f in
                HStack(spacing: 0) {
                    Text(f.label)
                        .frame(width: 36, alignment: .leading)
                    Text(String(format: "%.5f", f.x))
                        .frame(width: 88, alignment: .trailing)
                    Text(String(format: "%.5f", f.y))
                        .frame(width: 88, alignment: .trailing)
                    Text(String(format: "%.2f", f.pressure))
                        .frame(width: 52, alignment: .trailing)
                    Text(f.phase)
                        .frame(width: 72, alignment: .leading)
                        .padding(.leading, 12)
                        .foregroundColor(phaseColor(f.phase))
                }
                .font(.system(size: 12, design: .monospaced))
                .padding(.horizontal, 16)
                .padding(.vertical, 4)
            }
        }
    }

    private func phaseColor(_ phase: String) -> Color {
        switch phase {
        case "began": return .green
        case "ended": return .red
        case "moved": return .blue
        default:      return .primary
        }
    }
}
